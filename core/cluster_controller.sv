// cluster_controller
`timescale 1ns / 1ps
module cluster_controller (
    input  logic clk,
    input  logic rst_n,

    input  logic [15:0] core_halts,
    output logic system_halt
);

    assign system_halt = &core_halts;

endmodule
