// dsp_cluster
`timescale 1ns / 1ps
module dsp_cluster (
    input  logic clk,
    input  logic rst_n,

    output nexora_x3_pkg::mem_req_t  mem_req,
    input  nexora_x3_pkg::mem_resp_t mem_resp
);

    always_comb begin
        mem_req.addr     = '0;
        mem_req.wdata    = '0;
        mem_req.read_en  = 1'b0;
        mem_req.write_en = 1'b0;
        mem_req.byte_en  = 8'h00;
    end

endmodule
