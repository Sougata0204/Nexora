// simt_regfile
// Per-thread parallel read ports, single-thread write port.
// Combinational reads (LUTRAM) — suitable for LITE_BUILD (8 threads).
`timescale 1ns / 1ps
module simt_regfile #(
    parameter int WARP_COUNT = 4,
    parameter int THREADS    = 32,
    parameter int REG_COUNT  = 32,
    parameter int DATA_WIDTH = nexora_x3_pkg::DATA_WIDTH
)(
    input  logic        clk,
    input  logic        rst_n,

    // --- Read ports (parallel, all threads) ---
    input  logic [$clog2(WARP_COUNT)-1:0] rd_warp_id,
    input  logic [4:0]  rs1_addr,
    input  logic [4:0]  rs2_addr,
    output logic [THREADS-1:0][DATA_WIDTH-1:0] rs1_data_all,
    output logic [THREADS-1:0][DATA_WIDTH-1:0] rs2_data_all,

    // --- Write port (single thread) ---
    input  logic [$clog2(WARP_COUNT)-1:0] wr_warp_id,
    input  logic [$clog2(THREADS)-1:0]    wr_thread_id,
    input  logic [4:0]  rd_addr,
    input  logic [DATA_WIDTH-1:0] rd_data,
    input  logic        rd_write_en
);

    // Register storage: [warp][thread][register]
    logic [DATA_WIDTH-1:0] regfile [WARP_COUNT-1:0][THREADS-1:0][REG_COUNT-1:0];

    // --- Write: single thread per cycle ---
    always_ff @(posedge clk) begin : rf_write
        if (rd_write_en && (rd_addr != 5'd0)) begin
            regfile[wr_warp_id][wr_thread_id][rd_addr] <= rd_data;
        end
    end

    // --- Read: all threads in parallel, combinational ---
    always_comb begin : rf_read
        for (int t = 0; t < THREADS; t++) begin
            rs1_data_all[t] = (rs1_addr == 5'd0) ? {DATA_WIDTH{1'b0}}
                                                  : regfile[rd_warp_id][t][rs1_addr];
            rs2_data_all[t] = (rs2_addr == 5'd0) ? {DATA_WIDTH{1'b0}}
                                                  : regfile[rd_warp_id][t][rs2_addr];
        end
    end

endmodule : simt_regfile
