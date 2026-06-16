// cpu_cluster
`timescale 1ns / 1ps
module cpu_cluster (
    input  logic clk,
    input  logic rst_n,

    output nexora_x3_pkg::mem_req_t  main_mem_req,
    input  nexora_x3_pkg::mem_resp_t main_mem_resp,

    output logic system_halt
);

    nexora_x3_pkg::mem_req_t [3:0] qc_mem_req;
    nexora_x3_pkg::mem_resp_t [3:0] qc_mem_resp;

    logic [15:0] flat_core_halts;

    logic [15:0][31:0] flat_instr_count;
    logic [15:0][31:0] flat_cycle_count;
    logic [15:0][31:0] flat_cache_hits;
    logic [15:0][31:0] flat_cache_misses;
    logic [15:0][31:0] flat_stall_count;
    logic [15:0][31:0] flat_branch_count;

    generate
        genvar i;
    for (i = 0; i < 4; i++) begin : quads
            quad_cluster #(
                .CLUSTER_ID(i)
            ) u_quad (
                .clk(clk),
                .rst_n(rst_n),
                .mem_req(qc_mem_req[i]),
                .mem_resp(qc_mem_resp[i]),
                .halt_cores(flat_core_halts[i*4 +: 4]),

                .core_instr_count(flat_instr_count[i*4 +: 4]),
                .core_cycle_count(flat_cycle_count[i*4 +: 4]),
                .core_cache_hits(flat_cache_hits[i*4 +: 4]),
                .core_cache_misses(flat_cache_misses[i*4 +: 4]),
                .core_stall_count(flat_stall_count[i*4 +: 4]),
                .core_branch_count(flat_branch_count[i*4 +: 4])
            );
        end
    endgenerate

    memory_scheduler u_mem_sched (
        .clk(clk),
        .rst_n(rst_n),
        .qc_req(qc_mem_req),
        .qc_resp(qc_mem_resp),
        .main_mem_req(main_mem_req),
        .main_mem_resp(main_mem_resp)
    );

    cluster_controller u_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        .core_halts(flat_core_halts),
        .system_halt(system_halt)
    );

    debug_controller u_debug (
        .clk(clk),
        .rst_n(rst_n),
        .core_instr_count(flat_instr_count),
        .core_cycle_count(flat_cycle_count),
        .core_cache_hits(flat_cache_hits),
        .core_cache_misses(flat_cache_misses),
        .core_stall_count(flat_stall_count),
        .core_branch_count(flat_branch_count),
        .total_instr_count(),
        .total_cycle_count(),
        .total_cache_hits(),
        .total_cache_misses()
    );

endmodule
