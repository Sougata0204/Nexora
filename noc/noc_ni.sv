// noc_ni
`timescale 1ns / 1ps
module noc_ni #(
    parameter int NI_X  = 0,
    parameter int NI_Y  = 0,
    parameter int NI_ID = 0,

    parameter int MEM_DST_X = 3,
    parameter int MEM_DST_Y = 3
)(
    input  logic clk,
    input  logic rst_n,

    input  nexora_x3_pkg::mem_req_t  mem_req,
    output nexora_x3_pkg::mem_resp_t mem_resp,

    output nexora_x3_pkg::noc_flit_t flit_out,
    output logic      flit_out_valid,
    input  logic      flit_out_ready,

    input  nexora_x3_pkg::noc_flit_t flit_in,
    input  logic      flit_in_valid,
    output logic      flit_in_ready
);

    typedef enum logic [1:0] {
        NI_IDLE     = 2'd0,
        NI_SEND_HEAD = 2'd1,
        NI_SEND_TAIL = 2'd2,
        NI_WAIT_RESP = 2'd3
    } ni_fsm_t;

    ni_fsm_t state, next_state;

    nexora_x3_pkg::mem_req_t  pending_req;
    nexora_x3_pkg::noc_flit_t head_flit;
    nexora_x3_pkg::noc_flit_t tail_flit;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= NI_IDLE;
            pending_req <= '0;
            head_flit   <= '0;
            tail_flit   <= '0;
        end else begin
            state <= next_state;
            if (state == NI_IDLE && (mem_req.read_en || mem_req.write_en)) begin
                pending_req <= mem_req;

                head_flit.flit_type <= nexora_x3_pkg::FLIT_HEAD;
                head_flit.dst_x     <= MEM_DST_X[nexora_x3_pkg::NOC_ADDR_X_BITS-1:0];
                head_flit.dst_y     <= MEM_DST_Y[nexora_x3_pkg::NOC_ADDR_Y_BITS-1:0];
                head_flit.src_x     <= NI_X[nexora_x3_pkg::NOC_ADDR_X_BITS-1:0];
                head_flit.src_y     <= NI_Y[nexora_x3_pkg::NOC_ADDR_Y_BITS-1:0];
                head_flit.vc_id     <= 2'd0;
                head_flit.msg_type  <= mem_req.write_en ? 4'h1 : 4'h0; 
                head_flit.payload   <= mem_req.addr;

                tail_flit.flit_type <= nexora_x3_pkg::FLIT_TAIL;
                tail_flit.dst_x     <= MEM_DST_X[nexora_x3_pkg::NOC_ADDR_X_BITS-1:0];
                tail_flit.dst_y     <= MEM_DST_Y[nexora_x3_pkg::NOC_ADDR_Y_BITS-1:0];
                tail_flit.src_x     <= NI_X[nexora_x3_pkg::NOC_ADDR_X_BITS-1:0];
                tail_flit.src_y     <= NI_Y[nexora_x3_pkg::NOC_ADDR_Y_BITS-1:0];
                tail_flit.vc_id     <= 2'd0;
                tail_flit.msg_type  <= 4'h1;
                tail_flit.payload   <= mem_req.wdata;
            end
        end
    end

    always_comb begin
        next_state     = state;
        flit_out       = '0;
        flit_out_valid = 1'b0;
        flit_in_ready  = 1'b0;
        mem_resp       = '0;

        case (state)
            NI_IDLE: begin
                flit_in_ready = 1'b1; 
                if (mem_req.read_en || mem_req.write_en) begin
                    next_state = NI_SEND_HEAD;
                end

                if (flit_in_valid && flit_in.msg_type == 4'h2) begin
                    mem_resp.rdata = flit_in.payload;
                    mem_resp.ready = 1'b1;
                end
            end

            NI_SEND_HEAD: begin
                flit_out       = head_flit;
                flit_out_valid = 1'b1;
                if (flit_out_ready) begin
                    next_state = pending_req.write_en ? NI_SEND_TAIL : NI_WAIT_RESP;
                end
            end

            NI_SEND_TAIL: begin
                flit_out       = tail_flit;
                flit_out_valid = 1'b1;
                if (flit_out_ready) begin
                    next_state = NI_WAIT_RESP;
                end
            end

            NI_WAIT_RESP: begin
                flit_in_ready = 1'b1;
                if (flit_in_valid) begin
                    if (flit_in.msg_type == 4'h2) begin

                        mem_resp.rdata = flit_in.payload;
                        mem_resp.ready = 1'b1;
                    end else if (flit_in.msg_type == 4'h3) begin

                        mem_resp.ready = 1'b1;
                    end
                    next_state = NI_IDLE;
                end
            end

            default: next_state = NI_IDLE;
        endcase
    end

endmodule : noc_ni
