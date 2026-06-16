// control_unit
`timescale 1ns / 1ps
module control_unit #(
    parameter int REG_ADDR_WIDTH = nexora_x3_pkg::REG_ADDR_WIDTH
)(
    input  logic                       clk,
    input  logic                       rst_n,

    input  logic [REG_ADDR_WIDTH-1:0]  id_ex_rs1_addr,
    input  logic [REG_ADDR_WIDTH-1:0]  id_ex_rs2_addr,
    input  logic                       id_ex_valid,

    input  logic [REG_ADDR_WIDTH-1:0]  if_id_rs1_addr,
    input  logic [REG_ADDR_WIDTH-1:0]  if_id_rs2_addr,

    input  logic [REG_ADDR_WIDTH-1:0]  ex_mem_rd_addr,
    input  logic                       ex_mem_reg_write,
    input  logic                       ex_mem_mem_read,
    input  logic                       ex_mem_valid,

    input  logic [REG_ADDR_WIDTH-1:0]  mem_wb_rd_addr,
    input  logic                       mem_wb_reg_write,
    input  logic                       mem_wb_valid,

    input  logic                       branch_taken,

    input  logic                       id_ex_mem_read,
    input  logic [REG_ADDR_WIDTH-1:0]  id_ex_rd_addr,

    output logic [1:0]                 forward_a,
    output logic [1:0]                 forward_b,

    output logic                       stall_pipeline,   
    output logic                       flush_if_id,      
    output logic                       flush_id_ex,      

    output nexora_x3_pkg::debug_signals_t             debug
);

    logic [31:0] stall_count;
    logic [31:0] forward_count;
    logic        load_use_hazard;

    always_comb begin
        forward_a = 2'b00;  
        forward_b = 2'b00;

        if (ex_mem_reg_write && ex_mem_valid &&
            (ex_mem_rd_addr != '0) &&
            (ex_mem_rd_addr == id_ex_rs1_addr)) begin
            forward_a = 2'b01;  
        end else if (mem_wb_reg_write && mem_wb_valid &&
                     (mem_wb_rd_addr != '0) &&
                     (mem_wb_rd_addr == id_ex_rs1_addr)) begin
            forward_a = 2'b10;  
        end

        if (ex_mem_reg_write && ex_mem_valid &&
            (ex_mem_rd_addr != '0) &&
            (ex_mem_rd_addr == id_ex_rs2_addr)) begin
            forward_b = 2'b01;  
        end else if (mem_wb_reg_write && mem_wb_valid &&
                     (mem_wb_rd_addr != '0) &&
                     (mem_wb_rd_addr == id_ex_rs2_addr)) begin
            forward_b = 2'b10;  
        end
    end

    always_comb begin
        load_use_hazard = 1'b0;

        if (id_ex_mem_read && id_ex_valid && (id_ex_rd_addr != '0)) begin
            if ((id_ex_rd_addr == if_id_rs1_addr) ||
                (id_ex_rd_addr == if_id_rs2_addr)) begin
                load_use_hazard = 1'b1;
            end
        end
    end

    assign stall_pipeline = load_use_hazard;
    assign flush_if_id    = branch_taken;          
    assign flush_id_ex    = branch_taken || load_use_hazard;  

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stall_count   <= '0;
            forward_count <= '0;
        end else begin
            if (stall_pipeline) begin
                stall_count <= stall_count + 1;
            end
            if (forward_a != 2'b00 || forward_b != 2'b00) begin
                forward_count <= forward_count + 1;
            end
        end
    end

    assign debug.state   = {stall_pipeline, flush_if_id, flush_id_ex, load_use_hazard};
    assign debug.counter = stall_count;
    assign debug.valid   = 1'b1;
    assign debug.error   = 1'b0;

    assert_no_xz_forward_a: assert property (
        @(posedge clk) disable iff (!rst_n)
        !$isunknown(forward_a)
    ) else $error("[CTRL] ASSERT FAIL: X/Z on forward_a");

    assert_no_xz_forward_b: assert property (
        @(posedge clk) disable iff (!rst_n)
        !$isunknown(forward_b)
    ) else $error("[CTRL] ASSERT FAIL: X/Z on forward_b");

    assert_no_forward_from_x0_a: assert property (
        @(posedge clk) disable iff (!rst_n)
        (forward_a != 2'b00) |-> (id_ex_rs1_addr != '0)
    ) else $error("[CTRL] ASSERT FAIL: Forwarding to x0 source (rs1)");

    assert_no_forward_from_x0_b: assert property (
        @(posedge clk) disable iff (!rst_n)
        (forward_b != 2'b00) |-> (id_ex_rs2_addr != '0)
    ) else $error("[CTRL] ASSERT FAIL: Forwarding to x0 source (rs2)");

endmodule : control_unit
