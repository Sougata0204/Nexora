// debug_subsystem
`timescale 1ns / 1ps
module debug_subsystem (
    input  logic clk,
    input  logic rst_n,

    input  logic tck,
    input  logic tms,
    input  logic tdi,
    output logic tdo
);

    always_comb begin
        tdo = 1'b0;
    end

endmodule
