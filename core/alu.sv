// alu
`timescale 1ns / 1ps
module alu #(
    parameter DATA_WIDTH = nexora_x3_pkg::DATA_WIDTH
)(
    input  logic                   clk,
    input  logic                   rst_n,

    input  logic [DATA_WIDTH-1:0]  operand_a,
    input  logic [DATA_WIDTH-1:0]  operand_b,

    input  nexora_x3_pkg::alu_op_t alu_op,

    output logic [DATA_WIDTH-1:0]  result,
    output logic                   zero_flag,
    output logic                   overflow_flag,

    output nexora_x3_pkg::debug_signals_t debug
);

    logic [DATA_WIDTH-1:0] iso_operand_a;
    logic [DATA_WIDTH-1:0] iso_operand_b;

    assign iso_operand_a = (alu_op == nexora_x3_pkg::ALU_NOP) ? '0 : operand_a;
    assign iso_operand_b = (alu_op == nexora_x3_pkg::ALU_NOP) ? '0 : operand_b;

    logic [DATA_WIDTH-1:0] add_result;
    logic [DATA_WIDTH-1:0] sub_result;
    logic                  add_overflow;
    logic                  sub_overflow;
    logic [4:0]            shift_amount;

    logic [31:0] op_count;
    logic        result_valid;
    logic        result_error;

    assign shift_amount = iso_operand_b[4:0];

    assign add_result = iso_operand_a + iso_operand_b;
    assign sub_result = iso_operand_a - iso_operand_b;

    assign add_overflow = (iso_operand_a[DATA_WIDTH-1] == iso_operand_b[DATA_WIDTH-1]) &&
                          (add_result[DATA_WIDTH-1] != iso_operand_a[DATA_WIDTH-1]);
    assign sub_overflow = (iso_operand_a[DATA_WIDTH-1] != iso_operand_b[DATA_WIDTH-1]) &&
                          (sub_result[DATA_WIDTH-1] != iso_operand_a[DATA_WIDTH-1]);

    always_comb begin
        result        = '0;
        overflow_flag = 1'b0;
        result_valid  = 1'b1;
        result_error  = 1'b0;

        case (alu_op)
            nexora_x3_pkg::ALU_ADD: begin
                result        = add_result;
                overflow_flag = add_overflow;
            end

            nexora_x3_pkg::ALU_SUB: begin
                result        = sub_result;
                overflow_flag = sub_overflow;
            end

            nexora_x3_pkg::ALU_AND: begin
                result = iso_operand_a & iso_operand_b;
            end

            nexora_x3_pkg::ALU_OR: begin
                result = iso_operand_a | iso_operand_b;
            end

            nexora_x3_pkg::ALU_XOR: begin
                result = iso_operand_a ^ iso_operand_b;
            end

            nexora_x3_pkg::ALU_SLL: begin
                result = iso_operand_a << shift_amount;
            end

            nexora_x3_pkg::ALU_SRL: begin
                result = iso_operand_a >> shift_amount;
            end

            nexora_x3_pkg::ALU_SRA: begin
                result = $signed(iso_operand_a) >>> shift_amount;
            end

            nexora_x3_pkg::ALU_SLT: begin
                result = {{(DATA_WIDTH-1){1'b0}}, ($signed(iso_operand_a) < $signed(iso_operand_b))};
            end

            nexora_x3_pkg::ALU_SLTU: begin
                result = {{(DATA_WIDTH-1){1'b0}}, (iso_operand_a < iso_operand_b)};
            end

            nexora_x3_pkg::ALU_PASS_B: begin
                result = iso_operand_b;  
            end

            nexora_x3_pkg::ALU_NOP: begin
                result       = '0;
                result_valid = 1'b0;
            end

            default: begin
                result       = '0;
                result_error = 1'b1;
                result_valid = 1'b0;
            end
        endcase
    end

    assign zero_flag = (result == '0);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            op_count <= '0;
        end else if (result_valid) begin
            op_count <= op_count + 1;
        end
    end

    assign debug.state   = {1'b0, alu_op[2:0]};  
    assign debug.counter = op_count;
    assign debug.valid   = result_valid;
    assign debug.error   = result_error;

    assert_no_xz_result: assert property (
        @(posedge clk) disable iff (!rst_n)
        (result_valid) |-> !$isunknown(result)
    ) else $error("[ALU] ASSERT FAIL: X/Z detected on result for op=%s", alu_op.name());

    assert_add_commutative: assert property (
        @(posedge clk) disable iff (!rst_n)
        (alu_op == nexora_x3_pkg::ALU_ADD) |-> (iso_operand_a + iso_operand_b == iso_operand_b + iso_operand_a)
    ) else $error("[ALU] ASSERT FAIL: ADD is not commutative");

    assert_slt_binary: assert property (
        @(posedge clk) disable iff (!rst_n)
        (alu_op == nexora_x3_pkg::ALU_SLT || alu_op == nexora_x3_pkg::ALU_SLTU) |-> (result == '0 || result == 32'd1)
    ) else $error("[ALU] ASSERT FAIL: SLT/SLTU result is not 0 or 1");

endmodule : alu
