// l1_cache
`timescale 1ns / 1ps
module l1_cache #(
    parameter int CACHE_SIZE = 16 * 1024,  // Reduced for Vivado RTL lint (ASIC: restore to 16KB)
    parameter int LINE_SIZE  = 32,
    parameter int DATA_WIDTH = nexora_x3_pkg::DATA_WIDTH,
    parameter int ADDR_WIDTH = nexora_x3_pkg::ADDR_WIDTH
)(
    input  logic clk,
    input  logic rst_n,

    input  nexora_x3_pkg::mem_req_t  core_req,
    output nexora_x3_pkg::mem_resp_t core_resp,

    output nexora_x3_pkg::mem_req_t  l2_req,
    input  nexora_x3_pkg::mem_resp_t l2_resp,

    output logic hit,
    output logic miss
);

    localparam int NUM_LINES = CACHE_SIZE / LINE_SIZE;
    localparam int INDEX_BITS = $clog2(NUM_LINES);
    localparam int TAG_BITS   = ADDR_WIDTH - INDEX_BITS - 5;

    typedef struct packed {
        logic [TAG_BITS-1:0] tag;
        logic [LINE_SIZE*8-1:0] data;
        logic valid;
        logic dirty;
    } cache_line_t;

    cache_line_t cache [NUM_LINES-1:0];

    logic [INDEX_BITS-1:0] index;
    logic [TAG_BITS-1:0]   tag;
    logic                  tag_match;
    logic                  line_valid;

    assign index = core_req.addr[INDEX_BITS+4:5];
    assign tag   = core_req.addr[ADDR_WIDTH-1:INDEX_BITS+5];
    assign tag_match = (cache[index].tag == tag);
    assign line_valid = cache[index].valid;

    typedef enum logic [2:0] {
        IDLE          = 3'd0,
        CHECK_TAG     = 3'd1,
        ALLOCATE_LINE = 3'd2,
        WRITEBACK     = 3'd3,
        WAIT_MEM      = 3'd4
    } state_t;

    state_t state, next_state;

    nexora_x3_pkg::mem_req_t latched_req;
    logic [LINE_SIZE*8-1:0] writeback_data;
    logic [INDEX_BITS-1:0]  victim_index;
    logic [TAG_BITS-1:0]    victim_tag;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            for (int i = 0; i < NUM_LINES; i++) begin
                cache[i].valid <= 1'b0;
                cache[i].dirty <= 1'b0;
                cache[i].tag   <= '0;
                cache[i].data  <= '0;
            end
        end else begin
            state <= next_state;

            case (state)
                CHECK_TAG: begin
                    if (core_req.read_en || core_req.write_en) begin
                        latched_req <= core_req;
                    end
                end

                ALLOCATE_LINE: begin
                    if (line_valid && cache[index].dirty) begin
                        victim_index <= index;
                        victim_tag   <= cache[index].tag;
                        writeback_data <= cache[index].data;
                    end
                    cache[index].tag   <= tag;
                    cache[index].valid <= 1'b1;
                    cache[index].dirty <= core_req.write_en;
                    if (core_req.read_en) begin
                        cache[index].data <= l2_resp.rdata;
                    end else if (core_req.write_en) begin
                        cache[index].data <= core_req.wdata;
                    end
                end

                WRITEBACK: begin
                end

                WAIT_MEM: begin
                    if (l2_resp.ready) begin
                        if (!latched_req.write_en) begin
                            cache[index].data <= l2_resp.rdata;
                        end
                        cache[index].dirty <= latched_req.write_en;
                    end
                end
            endcase
        end
    end

    always_comb begin
        next_state = state;
        l2_req.addr = '0;
        l2_req.wdata = '0;
        l2_req.read_en = '0;
        l2_req.write_en = '0;
        l2_req.byte_en = '0;
        miss = 1'b0;
        hit  = 1'b0;
        core_resp.rdata = '0;
        core_resp.ready = '0;
        core_resp.error = '0;

        case (state)
            IDLE: begin
                if (core_req.read_en || core_req.write_en) begin
                    next_state = CHECK_TAG;
                end
            end

            CHECK_TAG: begin
                if (line_valid && tag_match) begin
                    hit = 1'b1;
                    core_resp.ready = 1'b1;
                    core_resp.rdata = cache[index].data[DATA_WIDTH-1:0];
                    if (core_req.write_en) begin
                        next_state = ALLOCATE_LINE;
                    end else begin
                        next_state = IDLE;
                    end
                end else begin
                    miss = 1'b1;
                    if (line_valid && cache[index].dirty) begin
                        next_state = WRITEBACK;
                    end else begin
                        next_state = ALLOCATE_LINE;
                    end
                end
            end

            ALLOCATE_LINE: begin
                miss = 1'b1;
                l2_req = latched_req;
                if (l2_resp.ready) begin
                    hit = 1'b1;
                    core_resp = l2_resp;
                    next_state = IDLE;
                end
            end

            WRITEBACK: begin
                miss = 1'b1;
                l2_req.addr     = {victim_tag, victim_index, 5'b0};
                l2_req.wdata    = writeback_data;
                l2_req.read_en  = 1'b0;
                l2_req.write_en = 1'b1;
                l2_req.byte_en  = 8'hFF;
                if (l2_resp.ready) begin
                    next_state = ALLOCATE_LINE;
                end
            end

            WAIT_MEM: begin
                miss = 1'b1;
                l2_req = latched_req;
                if (l2_resp.ready) begin
                    hit = 1'b1;
                    core_resp = l2_resp;
                    next_state = IDLE;
                end
            end
        endcase
    end

endmodule