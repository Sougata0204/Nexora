// debug_controller
`timescale 1ns / 1ps
module debug_controller (
    input  logic clk,
    input  logic rst_n,

    input logic [15:0][31:0] core_instr_count,
    input logic [15:0][31:0] core_cycle_count,
    input logic [15:0][31:0] core_cache_hits,
    input logic [15:0][31:0] core_cache_misses,
    input logic [15:0][31:0] core_stall_count,
    input logic [15:0][31:0] core_branch_count,

    output logic [63:0] total_instr_count,
    output logic [63:0] total_cycle_count,
    output logic [63:0] total_cache_hits,
    output logic [63:0] total_cache_misses
);

    always_comb begin
        total_instr_count = '0;
        total_cycle_count = '0;
        total_cache_hits = '0;
        total_cache_misses = '0;

        for (int i = 0; i < 16; i++) begin
            total_instr_count += core_instr_count[i];
            total_cycle_count += core_cycle_count[i];
            total_cache_hits += core_cache_hits[i];
            total_cache_misses += core_cache_misses[i];
        end
    end

endmodule
