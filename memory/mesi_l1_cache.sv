// mesi_l1_cache
`timescale 1ns / 1ps
module mesi_l1_cache #(
    parameter int CACHE_LINES = 64,
    parameter int CACHE_ID    = 0
)(
    input  logic clk,
    input  logic rst_n,

    input  nexora_x3_pkg::mem_req_t  core_req,
    output nexora_x3_pkg::mem_resp_t core_resp,

    output nexora_x3_pkg::coh_req_t  coh_req,
    output logic      coh_req_valid,

    input  nexora_x3_pkg::coh_resp_t  coh_resp,
    input  logic       coh_resp_valid,

    input  nexora_x3_pkg::coh_req_t  snoop_req,
    input  logic      snoop_req_valid,
    output logic      snoop_ack,
    output logic [nexora_x3_pkg::DATA_WIDTH-1:0] snoop_data,

    output logic hit,
    output logic miss
);

    localparam int DATA_WIDTH = nexora_x3_pkg::DATA_WIDTH;

    localparam int IDX_BITS = 6;  
    localparam int TAG_BITS = 24; 

    logic [TAG_BITS-1:0] tags        [CACHE_LINES-1:0];
    logic [DATA_WIDTH-1:0]         data_array  [CACHE_LINES-1:0];
    nexora_x3_pkg::mesi_state_t [CACHE_LINES-1:0] state_array;
    logic                valid_array [CACHE_LINES-1:0];

    typedef enum logic [2:0] {
        L1_IDLE       = 3'd0,
        L1_ALLOC      = 3'd1,  
        L1_UPGRADE    = 3'd2,  
        L1_SNOOP_PROC = 3'd3,  
        L1_SNOOP_WB   = 3'd4   
    } l1_fsm_t;

    l1_fsm_t state, next_state;

    nexora_x3_pkg::mem_req_t  pending_req;
    logic [IDX_BITS-1:0] pending_idx;
    logic [TAG_BITS-1:0] pending_tag;

    logic [IDX_BITS-1:0] req_idx;
    logic [TAG_BITS-1:0] req_tag;
    logic                cache_hit;
    logic                cache_valid;

    assign req_idx    = core_req.addr[7:2];
    assign req_tag    = core_req.addr[31:8];
    assign cache_hit  = valid_array[req_idx] && (tags[req_idx] == req_tag) && (state_array[req_idx] != nexora_x3_pkg::MESI_INVALID);
    assign cache_valid = valid_array[req_idx];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= L1_IDLE;
        end else begin
            state <= next_state;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin : l1_fsm
        logic [IDX_BITS-1:0] sidx;
        logic [TAG_BITS-1:0] stag;

        if (!rst_n) begin
            for (int i = 0; i < CACHE_LINES; i++) begin
                state_array[i] <= nexora_x3_pkg::MESI_INVALID;
                valid_array[i] <= 1'b0;
            end
            pending_req <= '0;
            pending_idx <= '0;
            pending_tag <= '0;
            snoop_ack   <= 1'b0;
            snoop_data  <= {DATA_WIDTH{1'b0}};
        end else begin
            snoop_ack <= 1'b0; 

            case (state)
                L1_IDLE: begin
                    if ((core_req.read_en || core_req.write_en) && !cache_hit) begin

                        pending_req <= core_req;
                        pending_idx <= req_idx;
                        pending_tag <= req_tag;
                    end else if (core_req.write_en && cache_hit) begin

                        if (state_array[req_idx] == nexora_x3_pkg::MESI_SHARED) begin

                            pending_req <= core_req;
                            pending_idx <= req_idx;
                            pending_tag <= req_tag;
                        end else begin

                            data_array[req_idx]  <= core_req.wdata;
                            state_array[req_idx] <= nexora_x3_pkg::MESI_MODIFIED;
                        end
                    end
                end

                L1_ALLOC: begin

                    if (coh_resp_valid) begin
                        data_array[pending_idx]  <= coh_resp.data;
                        tags[pending_idx]         <= pending_tag;
                        valid_array[pending_idx]  <= 1'b1;

                        if (pending_req.write_en) begin
                            data_array[pending_idx] <= pending_req.wdata;
                            state_array[pending_idx] <= nexora_x3_pkg::MESI_MODIFIED;
                        end else begin
                            state_array[pending_idx] <= nexora_x3_pkg::MESI_EXCLUSIVE;
                        end
                    end
                end

                L1_UPGRADE: begin
                    if (coh_resp_valid && coh_resp.ack) begin
                        state_array[pending_idx] <= nexora_x3_pkg::MESI_EXCLUSIVE;
                        data_array[pending_idx]  <= pending_req.wdata;
                        state_array[pending_idx] <= nexora_x3_pkg::MESI_MODIFIED;
                    end
                end

                L1_SNOOP_PROC: begin
                    if (snoop_req_valid) begin
                        if (snoop_req.msg_type == nexora_x3_pkg::COH_INVALIDATE || snoop_req.msg_type == nexora_x3_pkg::COH_FETCH_INV) begin
                            sidx = snoop_req.addr[7:2];
                            stag = snoop_req.addr[31:8];
                            if (valid_array[sidx] && (tags[sidx] == stag)) begin
                                snoop_data <= data_array[sidx];
                                if (state_array[sidx] == nexora_x3_pkg::MESI_MODIFIED) begin

                                    state_array[sidx] <= nexora_x3_pkg::MESI_INVALID;
                                    valid_array[sidx] <= 1'b0;
                                end else begin
                                    state_array[sidx] <= nexora_x3_pkg::MESI_INVALID;
                                    valid_array[sidx] <= 1'b0;
                                    snoop_ack <= 1'b1;
                                end
                            end else begin
                                snoop_ack <= 1'b1; 
                            end
                        end
                    end
                end

                L1_SNOOP_WB: begin

                    snoop_ack <= 1'b1;
                end

                default: begin end
            endcase
        end
    end

    always_comb begin : next_state_logic
        logic [IDX_BITS-1:0] sidx;

        next_state     = state;
        core_resp      = '0;
        coh_req        = '0;
        coh_req_valid  = 1'b0;
        hit            = 1'b0;
        miss           = 1'b0;

        case (state)
            L1_IDLE: begin
                if (core_req.read_en) begin
                    if (cache_hit) begin

                        hit              = 1'b1;
                        core_resp.rdata  = data_array[req_idx];
                        core_resp.ready  = 1'b1;
                        core_resp.error  = 1'b0;
                    end else begin

                        miss              = 1'b1;
                        coh_req.msg_type  = nexora_x3_pkg::COH_READ;
                        coh_req.addr      = core_req.addr;
                        coh_req.data      = '0;
                        coh_req.requester_id = CACHE_ID[3:0];
                        coh_req_valid     = 1'b1;
                        next_state        = L1_ALLOC;
                    end
                end else if (core_req.write_en) begin
                    if (cache_hit) begin
                        if (state_array[req_idx] == nexora_x3_pkg::MESI_SHARED) begin

                            coh_req.msg_type  = nexora_x3_pkg::COH_UPGRADE;
                            coh_req.addr      = core_req.addr;
                            coh_req.data      = core_req.wdata;
                            coh_req.requester_id = CACHE_ID[3:0];
                            coh_req_valid     = 1'b1;
                            next_state        = L1_UPGRADE;
                        end else begin

                            hit             = 1'b1;
                            core_resp.ready = 1'b1;
                        end
                    end else begin

                        miss              = 1'b1;
                        coh_req.msg_type  = nexora_x3_pkg::COH_READ_EX;
                        coh_req.addr      = core_req.addr;
                        coh_req.data      = core_req.wdata;
                        coh_req.requester_id = CACHE_ID[3:0];
                        coh_req_valid     = 1'b1;
                        next_state        = L1_ALLOC;
                    end
                end

                if (snoop_req_valid) begin
                    next_state = L1_SNOOP_PROC;
                end
            end

            L1_ALLOC: begin
                if (coh_resp_valid) begin
                    core_resp.rdata = coh_resp.data;
                    core_resp.ready = 1'b1;
                    next_state      = L1_IDLE;
                end
            end

            L1_UPGRADE: begin
                if (coh_resp_valid && coh_resp.ack) begin
                    core_resp.ready = 1'b1;
                    next_state      = L1_IDLE;
                end
            end

            L1_SNOOP_PROC: begin
                next_state = L1_IDLE;

                if (snoop_req_valid) begin
                    sidx = snoop_req.addr[7:2];
                    if (valid_array[sidx] && state_array[sidx] == nexora_x3_pkg::MESI_MODIFIED) begin

                        coh_req.msg_type  = nexora_x3_pkg::COH_WB_DATA;
                        coh_req.addr      = snoop_req.addr;
                        coh_req.data      = data_array[sidx];
                        coh_req.requester_id = CACHE_ID[3:0];
                        coh_req_valid     = 1'b1;
                        next_state        = L1_SNOOP_WB;
                    end
                end
            end

            L1_SNOOP_WB: begin
                next_state = L1_IDLE;
            end

            default: next_state = L1_IDLE;
        endcase
    end

endmodule : mesi_l1_cache
