// l2_cache_shared
`timescale 1ns / 1ps
module l2_cache_shared #(
    parameter int CACHE_SIZE = 64 * 1024,  // Reduced for Vivado RTL lint (ASIC: restore to 4MB)
    parameter int LINE_SIZE  = 128,
    parameter int DATA_WIDTH = nexora_x3_pkg::DATA_WIDTH,
    parameter int ADDR_WIDTH = nexora_x3_pkg::ADDR_WIDTH
)(
    input  logic clk,
    input  logic rst_n,

    input  nexora_x3_pkg::mem_req_t  arb_req,
    output nexora_x3_pkg::mem_resp_t arb_resp,

    output nexora_x3_pkg::mem_req_t  mem_req,
    input  nexora_x3_pkg::mem_resp_t mem_resp
);

    localparam int NUM_LINES = CACHE_SIZE / LINE_SIZE;
    localparam int INDEX_BITS = $clog2(NUM_LINES);
    localparam int TAG_BITS   = ADDR_WIDTH - INDEX_BITS - 7;

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

    assign index = arb_req.addr[INDEX_BITS+6:7];
    assign tag   = arb_req.addr[ADDR_WIDTH-1:INDEX_BITS+7];
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
                    if (arb_req.read_en || arb_req.write_en) begin
                        latched_req <= arb_req;
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
                    cache[index].dirty <= arb_req.write_en;
                    if (arb_req.read_en) begin
                        cache[index].data <= mem_resp.rdata;
                    end else if (arb_req.write_en) begin
                        cache[index].data <= arb_req.wdata;
                    end
                end

                WAIT_MEM: begin
                    if (mem_resp.ready) begin
                        if (!latched_req.write_en) begin
                            cache[index].data <= mem_resp.rdata;
                        end
                        cache[index].dirty <= latched_req.write_en;
                    end
                end
            endcase
        end
    end

    always_comb begin
        next_state = state;
        arb_resp.rdata = '0;
        arb_resp.error = '0;
        arb_resp.ready = 1'b0;
        mem_req.addr = '0;
        mem_req.wdata = '0;
        mem_req.byte_en = '0;
        mem_req.read_en = 1'b0;
        mem_req.write_en = 1'b0;

        case (state)
            IDLE: begin
                if (arb_req.read_en || arb_req.write_en) begin
                    next_state = CHECK_TAG;
                end
            end

            CHECK_TAG: begin
                if (line_valid && tag_match) begin
                    arb_resp.ready = 1'b1;
                    arb_resp.rdata = cache[index].data[DATA_WIDTH-1:0];
                    if (arb_req.write_en) begin
                        next_state = ALLOCATE_LINE;
                    end else begin
                        next_state = IDLE;
                    end
                end else begin
                    if (line_valid && cache[index].dirty) begin
                        next_state = WRITEBACK;
                    end else begin
                        next_state = ALLOCATE_LINE;
                    end
                end
            end

            ALLOCATE_LINE: begin
                mem_req = latched_req;
                if (mem_resp.ready) begin
                    arb_resp = mem_resp;
                    next_state = IDLE;
                end
            end

            WRITEBACK: begin
                mem_req.addr     = {victim_tag, victim_index, 7'b0};
                mem_req.wdata    = writeback_data;
                mem_req.read_en  = 1'b0;
                mem_req.write_en = 1'b1;
                mem_req.byte_en  = 16'hFFFF;
                if (mem_resp.ready) begin
                    next_state = ALLOCATE_LINE;
                end
            end

            WAIT_MEM: begin
                mem_req = latched_req;
                if (mem_resp.ready) begin
                    arb_resp = mem_resp;
                    next_state = IDLE;
                end
            end
        endcase
    end

endmodule