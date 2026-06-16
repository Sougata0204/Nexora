// cache_subsystem
`timescale 1ns / 1ps
module cache_subsystem (
    input  logic clk,
    input  logic rst_n,

    input  nexora_x3_pkg::mem_req_t [7:0] sys_req,
    output nexora_x3_pkg::mem_resp_t [7:0] sys_resp,

    output nexora_x3_pkg::mem_req_t [7:0] l2_req,
    input  nexora_x3_pkg::mem_resp_t [7:0] l2_resp
);

    always_comb begin
        for (int i = 0; i < 8; i++) begin
            l2_req[i]   = sys_req[i];
            sys_resp[i] = l2_resp[i];
        end
    end

endmodule
