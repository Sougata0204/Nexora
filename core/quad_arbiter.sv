// quad_arbiter
`timescale 1ns / 1ps
module quad_arbiter (
    input  logic clk,
    input  logic rst_n,

    input  nexora_x3_pkg::mem_req_t [7:0] core_req,
    output nexora_x3_pkg::mem_resp_t [7:0] core_resp,

    output nexora_x3_pkg::mem_req_t  l2_req,
    input  nexora_x3_pkg::mem_resp_t l2_resp
);

    logic [2:0] rr_ptr;
    logic [2:0] selected;
    logic active_request;
    logic busy;
    logic [2:0] latched_sel;
    nexora_x3_pkg::mem_req_t   latched_req;

    nexora_x3_pkg::mem_req_t tmp_arb_req;
    logic core_read_en [7:0];
    logic core_write_en [7:0];

    always_comb begin
        for (int i = 0; i < 8; i++) begin
            tmp_arb_req = core_req[i];
            core_read_en[i]  = tmp_arb_req.read_en;
            core_write_en[i] = tmp_arb_req.write_en;
        end
    end

    always_comb begin
        selected = rr_ptr;
        active_request = 1'b0;

        for (int i = 0; i < 8; i++) begin
            if ((core_read_en[(rr_ptr + i) % 8] || core_write_en[(rr_ptr + i) % 8]) && !active_request) begin
                selected = (rr_ptr + i) % 8;
                active_request = 1'b1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rr_ptr      <= '0;
            busy        <= 1'b0;
            latched_sel <= '0;
            latched_req <= '0;
        end else begin
            if (!busy && active_request) begin
                busy        <= 1'b1;
                latched_sel <= selected;
                latched_req <= core_req[selected];
            end
            if (busy && l2_resp.ready) begin
                busy        <= 1'b0;
                rr_ptr      <= (latched_sel + 1) % 8;
                latched_req <= '0;
            end
        end
    end

    always_comb begin
        if (busy) begin
            l2_req = latched_req;
        end else begin
            l2_req = '0;
        end
    end

    always_comb begin
        for (int i = 0; i < 8; i++) begin
            if (busy && l2_resp.ready && (i[2:0] == latched_sel)) begin
                core_resp[i] = l2_resp;
            end else begin
                core_resp[i] = '0;
            end
        end
    end

endmodule
