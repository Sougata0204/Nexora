// execution_cluster
`timescale 1ns / 1ps
module execution_cluster #(
    parameter int ALU_COUNT = 16,
    parameter int DATA_WIDTH = nexora_x3_pkg::DATA_WIDTH
)(
    input  logic clk,
    input  logic rst_n,

    input  logic [ALU_COUNT-1:0] alu_valid,
    input  nexora_x3_pkg::dispatch_packet_t [ALU_COUNT-1:0] alu_data,

    output logic [ALU_COUNT-1:0] alu_done,
    output logic [ALU_COUNT-1:0] [DATA_WIDTH-1:0] alu_result,
    output logic [ALU_COUNT-1:0] [4:0] alu_rd,
    output logic [ALU_COUNT-1:0] alu_reg_write,

    input  logic flush,

    output logic [3:0] debug_state,
    output logic [31:0] debug_counter,
    output logic debug_valid,
    output logic debug_error
);

    logic [ALU_COUNT-1:0] exec_valid;
    nexora_x3_pkg::dispatch_packet_t [ALU_COUNT-1:0] exec_data;

    logic [ALU_COUNT-1:0] [DATA_WIDTH-1:0] comb_result;

    nexora_x3_pkg::dispatch_packet_t tmp_exec;
    logic [DATA_WIDTH-1:0] exec_op_a [ALU_COUNT-1:0];
    logic [DATA_WIDTH-1:0] exec_op_b [ALU_COUNT-1:0];
    nexora_x3_pkg::alu_op_t exec_alu_op [ALU_COUNT-1:0];
    logic [4:0] exec_rd [ALU_COUNT-1:0];
    logic exec_reg_write [ALU_COUNT-1:0];

    always_comb begin
        for (int j = 0; j < ALU_COUNT; j++) begin
            tmp_exec = exec_data[j];
            exec_op_a[j] = tmp_exec.op_a;
            exec_op_b[j] = tmp_exec.op_b;
            exec_alu_op[j] = tmp_exec.alu_op;
            exec_rd[j] = tmp_exec.rd_addr;
            exec_reg_write[j] = tmp_exec.reg_write;
        end
    end

    genvar i;
    generate
        for (i = 0; i < ALU_COUNT; i++) begin : alu_insts
            logic [DATA_WIDTH-1:0] alu_op_a;
            logic [DATA_WIDTH-1:0] alu_op_b;
            nexora_x3_pkg::alu_op_t alu_operation;

            assign alu_op_a = exec_op_a[i];
            assign alu_op_b = exec_op_b[i];
            assign alu_operation = exec_valid[i] ? exec_alu_op[i] : nexora_x3_pkg::ALU_NOP;

            alu #(
                .DATA_WIDTH(DATA_WIDTH)
            ) u_alu (
                .clk       (clk),
                .rst_n     (rst_n),
                .operand_a (alu_op_a),
                .operand_b (alu_op_b),
                .alu_op    (alu_operation),
                .result    (comb_result[i])
            );

            assign alu_done[i] = exec_valid[i];
            assign alu_result[i] = comb_result[i];
            assign alu_rd[i] = exec_rd[i];
            assign alu_reg_write[i] = exec_reg_write[i];
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            exec_valid <= '0;
            debug_counter <= '0;
            for (int k = 0; k < ALU_COUNT; k++) begin
                exec_data[k] <= '0;
            end
        end else if (flush) begin
            exec_valid <= '0;
            debug_counter <= debug_counter + 1;
            for (int k = 0; k < ALU_COUNT; k++) begin
                exec_data[k] <= '0;
            end
        end else begin
            debug_counter <= debug_counter + 1;
            exec_valid <= alu_valid;
            for (int j = 0; j < ALU_COUNT; j++) begin
                if (alu_valid[j]) begin
                    exec_data[j] <= alu_data[j];
                end else begin
                    exec_data[j] <= '0;
                end
            end
        end
    end

    assign debug_state = {exec_valid[0], 3'b000};
    assign debug_valid = (exec_valid != 0);
    assign debug_error = 1'b0;

endmodule
