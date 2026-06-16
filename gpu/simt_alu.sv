// simt_alu
`timescale 1ns / 1ps
module simt_alu #(
    parameter int DATA_WIDTH = 32
)(
    input  logic        clk,
    input  logic        rst_n,

    input  logic [3:0]  op,
    input  logic [DATA_WIDTH-1:0] operand_a,
    input  logic [DATA_WIDTH-1:0] operand_b,
    input  logic        valid_in,

    output logic [DATA_WIDTH-1:0] result,
    output logic        valid_out,
    output logic        stall_out     
);

    logic [DATA_WIDTH-1:0] result_comb;
    logic [(DATA_WIDTH*2)-1:0] mul_full;          

    always_comb begin : alu_compute
        mul_full = '0;
        result_comb = '0;

        case (op)
            nexora_x3_pkg::GPU_IADD  : result_comb = operand_a + operand_b;
            nexora_x3_pkg::GPU_IMUL  : begin
                            mul_full = operand_a * operand_b;
                            result_comb = mul_full[DATA_WIDTH-1:0];
                        end
            // TODO: Replace with IEEE-754 FP adder for real float semantics
            nexora_x3_pkg::GPU_FADD  : result_comb = operand_a + operand_b;   // integer stub
            // TODO: Replace with IEEE-754 FP multiplier for real float semantics
            nexora_x3_pkg::GPU_FMUL  : begin   // integer stub
                            mul_full = operand_a * operand_b;
                            result_comb = mul_full[DATA_WIDTH-1:0];
                        end
            nexora_x3_pkg::GPU_NOP   : result_comb = '0;
            default   : result_comb = '0;  
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin : alu_pipeline_reg
        if (!rst_n) begin
            result    <= 32'd0;
            valid_out <= 1'b0;
        end else begin
            result    <= result_comb;
            valid_out <= valid_in;
        end
    end

    assign stall_out = 1'b0;

endmodule : simt_alu
