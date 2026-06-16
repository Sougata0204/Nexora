// quad_cluster
`timescale 1ns / 1ps
module quad_cluster #(
    parameter int CLUSTER_ID = 0
)(
    input  logic clk,
    input  logic rst_n,

    output nexora_x3_pkg::mem_req_t  mem_req,
    input  nexora_x3_pkg::mem_resp_t mem_resp,

    output logic [3:0] halt_cores,

    output logic [3:0][31:0] core_instr_count,
    output logic [3:0][31:0] core_cycle_count,
    output logic [3:0][31:0] core_cache_hits,
    output logic [3:0][31:0] core_cache_misses,
    output logic [3:0][31:0] core_stall_count,
    output logic [3:0][31:0] core_branch_count
);

    nexora_x3_pkg::mem_req_t [7:0] core_req;
    nexora_x3_pkg::mem_resp_t [7:0] core_resp;

    generate
        genvar i;
    for (i = 0; i < 4; i++) begin : cores
            cpu_core u_core (
                .clk(clk),
                .rst_n(rst_n),
                .imem_req(core_req[i*2]),
                .imem_resp(core_resp[i*2]),
                .dmem_req(core_req[i*2 + 1]),
                .dmem_resp(core_resp[i*2 + 1]),

                .cpu_debug(),
                .debug(),
                .halt(halt_cores[i]),

                .instruction_count(core_instr_count[i]),
                .cycle_count(core_cycle_count[i]),
                .cache_hits(core_cache_hits[i]),
                .cache_misses(core_cache_misses[i]),
                .stall_count(core_stall_count[i]),
                .branch_count(core_branch_count[i])
            );
        end
    endgenerate

    nexora_x3_pkg::mem_req_t  l2_req;
    nexora_x3_pkg::mem_resp_t l2_resp;

    quad_arbiter u_arbiter (
        .clk(clk),
        .rst_n(rst_n),
        .core_req(core_req),
        .core_resp(core_resp),
        .l2_req(l2_req),
        .l2_resp(l2_resp)
    );

    l2_cache_shared u_l2_cache (
        .clk(clk),
        .rst_n(rst_n),
        .arb_req(l2_req),
        .arb_resp(l2_resp),
        .mem_req(mem_req),
        .mem_resp(mem_resp)
    );

endmodule
