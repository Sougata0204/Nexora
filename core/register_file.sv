// register_file
`timescale 1ns / 1ps
module register_file #(
    parameter int DATA_WIDTH     = nexora_x3_pkg::DATA_WIDTH,
    parameter int REG_ADDR_WIDTH = nexora_x3_pkg::REG_ADDR_WIDTH,
    parameter int REG_COUNT      = nexora_x3_pkg::REG_COUNT
)(
    input  logic                       clk,
    input  logic                       rst_n,

    input  logic [REG_ADDR_WIDTH-1:0]  rs1_addr,
    output logic [DATA_WIDTH-1:0]      rs1_data,

    input  logic [REG_ADDR_WIDTH-1:0]  rs2_addr,
    output logic [DATA_WIDTH-1:0]      rs2_data,

    input  logic [REG_ADDR_WIDTH-1:0]  rd_addr,
    input  logic [DATA_WIDTH-1:0]      rd_data,
    input  logic                       rd_write_en,

    output nexora_x3_pkg::debug_signals_t             debug
);

    logic [DATA_WIDTH-1:0] registers [REG_COUNT];

    logic [31:0] write_count;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < REG_COUNT; i++) begin
                registers[i] <= '0;
            end
            write_count <= '0;
        end else begin
            if (rd_write_en && (rd_addr != '0)) begin
                registers[rd_addr] <= rd_data;
                write_count <= write_count + 1;
            end
        end
    end

    always_comb begin

        if (rs1_addr == '0) begin
            rs1_data = '0;
        end else if (rd_write_en && (rs1_addr == rd_addr)) begin
            rs1_data = rd_data;  
        end else begin
            rs1_data = registers[rs1_addr];
        end

        if (rs2_addr == '0) begin
            rs2_data = '0;
        end else if (rd_write_en && (rs2_addr == rd_addr)) begin
            rs2_data = rd_data;  
        end else begin
            rs2_data = registers[rs2_addr];
        end
    end

    assign debug.state   = 4'b0000;        
    assign debug.counter = write_count;
    assign debug.valid   = rd_write_en && (rd_addr != '0);
    assign debug.error   = 1'b0;           

    assert_x0_zero: assert property (
        @(posedge clk) disable iff (!rst_n)
        registers[0] == '0
    ) else $error("[REG_FILE] ASSERT FAIL: x0 is not zero! Value = %h", registers[0]);

    assert_no_write_in_reset: assert property (
        @(posedge clk)
        (!rst_n) |-> (!rd_write_en)
    ) else $warning("[REG_FILE] WARN: Write enable active during reset");

    assert_no_xz_rs1: assert property (
        @(posedge clk) disable iff (!rst_n)
        !$isunknown(rs1_data)
    ) else $error("[REG_FILE] ASSERT FAIL: X/Z detected on rs1_data");

    assert_no_xz_rs2: assert property (
        @(posedge clk) disable iff (!rst_n)
        !$isunknown(rs2_data)
    ) else $error("[REG_FILE] ASSERT FAIL: X/Z detected on rs2_data");

endmodule : register_file
