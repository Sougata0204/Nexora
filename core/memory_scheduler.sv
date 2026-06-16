// memory_scheduler
`timescale 1ns / 1ps
module memory_scheduler (
    input  logic clk,
    input  logic rst_n,

    input  nexora_x3_pkg::mem_req_t [3:0] qc_req,
    output nexora_x3_pkg::mem_resp_t [3:0] qc_resp,

    output nexora_x3_pkg::mem_req_t  main_mem_req,
    input  nexora_x3_pkg::mem_resp_t main_mem_resp
);

    logic [1:0] rr_ptr = '0;
    logic [1:0] selected;
    logic active_request;

    nexora_x3_pkg::mem_req_t tmp_qc_req;
    logic qc_read_en [3:0];
    logic qc_write_en [3:0];

    always_comb begin
        for (int i = 0; i < 4; i++) begin
            tmp_qc_req = qc_req[i];
            qc_read_en[i]  = tmp_qc_req.read_en;
            qc_write_en[i] = tmp_qc_req.write_en;
        end
    end

    always_comb begin
        selected = rr_ptr;
        active_request = 1'b0;

        for (int i = 0; i < 4; i++) begin
            if ((qc_read_en[(rr_ptr + i) % 4] || qc_write_en[(rr_ptr + i) % 4]) && !active_request) begin
                selected = (rr_ptr + i) % 4;
                active_request = 1'b1;
            end
        end
    end

    always_comb begin
        main_mem_req = '0;
        if (active_request) begin
            main_mem_req = qc_req[selected];
        end
    end

    always_comb begin
        for (int i = 0; i < 4; i++) begin
            if (main_mem_resp.ready && active_request && (i == selected)) begin
                qc_resp[i] = main_mem_resp;
            end else begin
                qc_resp[i] = '0;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rr_ptr <= '0;
        end else if (main_mem_resp.ready && active_request) begin
            rr_ptr <= (selected + 1) % 4;
        end
    end

endmodule
