// dispatch_unit
`timescale 1ns / 1ps
module dispatch_unit #(
    parameter int ISSUE_WIDTH = 4,
    parameter int ALU_COUNT = 16,
    parameter int DATA_WIDTH = nexora_x3_pkg::DATA_WIDTH,
    parameter int REG_COUNT = nexora_x3_pkg::REG_COUNT
)(
    input  logic clk,
    input  logic rst_n,

    input  logic [ISSUE_WIDTH-1:0] iq_valid,
    input  nexora_x3_pkg::id_ex_reg_t [ISSUE_WIDTH-1:0] iq_data,
    output logic [ISSUE_WIDTH-1:0] iq_ack,

    output logic [ISSUE_WIDTH-1:0] sched_valid,
    output nexora_x3_pkg::dispatch_packet_t [ISSUE_WIDTH-1:0] sched_data,
    input  logic [$clog2(ALU_COUNT+1)-1:0] sched_ready_count,

    output logic non_alu_valid,
    output nexora_x3_pkg::id_ex_reg_t non_alu_data,
    input  logic non_alu_ready,

    input  logic sched_wb_valid,
    input  logic [4:0] sched_wb_rd,
    input  logic [DATA_WIDTH-1:0] sched_wb_data,

    input  logic mem_wb_valid,
    input  logic [4:0] mem_wb_rd,
    input  logic [DATA_WIDTH-1:0] mem_wb_data,

    input  logic flush,

    output logic [3:0] debug_state,
    output logic [31:0] debug_counter,
    output logic debug_valid,
    output logic debug_error
);

    logic [DATA_WIDTH-1:0] shadow_rf [REG_COUNT-1:0];
    logic [REG_COUNT-1:0] pending_bits; 

    logic [$clog2(ALU_COUNT+1)-1:0] alus_available;
    assign alus_available = sched_ready_count;

    nexora_x3_pkg::id_ex_reg_t tmp_is_alu;
    nexora_x3_pkg::id_ex_reg_t tmp_dispatch;

    logic [ISSUE_WIDTH-1:0] is_alu;
    logic [ISSUE_WIDTH-1:0] iq_reg_write;
    logic [nexora_x3_pkg::REG_ADDR_WIDTH-1:0] iq_rd_addr [ISSUE_WIDTH-1:0];
    always_comb begin
        for (int i = 0; i < ISSUE_WIDTH; i++) begin
            tmp_is_alu = iq_data[i];
            is_alu[i] = (tmp_is_alu.alu_op != nexora_x3_pkg::ALU_NOP) && !tmp_is_alu.branch && !tmp_is_alu.jump && !tmp_is_alu.mem_read && !tmp_is_alu.mem_write && (tmp_is_alu.instruction[6:0] != nexora_x3_pkg::OP_SYSTEM);
            iq_reg_write[i] = tmp_is_alu.reg_write;
            iq_rd_addr[i]   = tmp_is_alu.rd_addr;
        end
    end

    logic [ISSUE_WIDTH-1:0] local_iq_ack;
    logic [ISSUE_WIDTH-1:0] local_sched_valid;
    nexora_x3_pkg::dispatch_packet_t [ISSUE_WIDTH-1:0] local_sched_data;
    logic local_non_alu_valid;
    nexora_x3_pkg::id_ex_reg_t local_non_alu_data;

    logic [REG_COUNT-1:0] group_pending; 

    always_comb begin
        int alus_used;
        logic stop_issue;
        logic [4:0] rs1, rs2, rd;
        logic [DATA_WIDTH-1:0] val1, val2, op_a, op_b;
        logic raw_rs1, raw_rs2, uses_rs2, waw_rd, has_dep;

        rs1 = '0; rs2 = '0; rd = '0;
        val1 = '0; val2 = '0; op_a = '0; op_b = '0;
        raw_rs1 = 1'b0; raw_rs2 = 1'b0; uses_rs2 = 1'b0; waw_rd = 1'b0; has_dep = 1'b0;

        local_iq_ack = '0;
        local_sched_valid = '0;
        local_sched_data = '0;
        local_non_alu_valid = 1'b0;
        local_non_alu_data = '0;

        group_pending = pending_bits;

        alus_used = 0;
        stop_issue = 1'b0;

        for (int i = 0; i < ISSUE_WIDTH; i++) begin
            local_sched_data[i] = '0;
            tmp_dispatch = iq_data[i];
            if (iq_valid[i] && !stop_issue) begin
                rs1 = tmp_dispatch.rs1_addr;
                rs2 = tmp_dispatch.rs2_addr;
                rd  = tmp_dispatch.rd_addr;

                val1 = (rs1 == 0) ? 32'd0 : shadow_rf[rs1];
                val2 = (rs2 == 0) ? 32'd0 : shadow_rf[rs2];

                raw_rs1 = (rs1 != 0) && group_pending[rs1];

                uses_rs2 = (tmp_dispatch.instruction[6:0] == nexora_x3_pkg::OP_R_TYPE) || tmp_dispatch.branch || tmp_dispatch.mem_write;
                raw_rs2 = (rs2 != 0) && group_pending[rs2] && uses_rs2;

                waw_rd = (rd != 0) && group_pending[rd] && tmp_dispatch.reg_write;
                has_dep = raw_rs1 || raw_rs2 || waw_rd;

                if (is_alu[i]) begin

                    if (!has_dep && (alus_used < alus_available)) begin

                        local_iq_ack[i] = 1'b1;
                        local_sched_valid[i] = 1'b1;

                        if (tmp_dispatch.instruction[6:0] == nexora_x3_pkg::OP_AUIPC) begin
                            op_a = tmp_dispatch.pc;
                        end else begin
                            op_a = val1;
                        end

                        if (tmp_dispatch.alu_src) begin 
                            op_b = tmp_dispatch.imm;
                        end else begin
                            op_b = val2;
                        end

                        local_sched_data[i] = {
                            tmp_dispatch.pc,           
                            tmp_dispatch.instruction,  
                            op_a,                    
                            op_b,                    
                            rd,                      
                            tmp_dispatch.reg_write,    
                            tmp_dispatch.alu_op        
                        };

                        if (tmp_dispatch.reg_write && rd != 0) begin
                            group_pending[rd] = 1'b1;
                        end

                        alus_used++;
                    end else begin
                        stop_issue = 1'b1;
                    end
                end else begin

                    if (i == 0) begin 

                        if (group_pending == 0 && non_alu_ready) begin
                            local_iq_ack[i] = 1'b1;
                            local_non_alu_valid = 1'b1;

                            local_non_alu_data = {
                                tmp_dispatch.pc,
                                tmp_dispatch.instruction,
                                val1,                    
                                val2,                    
                                tmp_dispatch.rs1_addr,
                                tmp_dispatch.rs2_addr,
                                tmp_dispatch.rd_addr,
                                tmp_dispatch.imm,
                                tmp_dispatch.alu_op,
                                tmp_dispatch.alu_src,
                                tmp_dispatch.mem_read,
                                tmp_dispatch.mem_write,
                                tmp_dispatch.reg_write,
                                tmp_dispatch.branch,
                                tmp_dispatch.jump,
                                tmp_dispatch.is_jalr,
                                tmp_dispatch.funct3,
                                tmp_dispatch.valid
                            };

                            if (tmp_dispatch.reg_write && rd != 0) begin
                                group_pending[rd] = 1'b1;
                            end
                        end

                        stop_issue = 1'b1;
                    end else begin

                        stop_issue = 1'b1;
                    end
                end
            end else begin
                if (iq_valid[i]) stop_issue = 1'b1;
            end
        end
    end

    assign iq_ack = local_iq_ack;
    assign sched_valid = local_sched_valid;
    assign sched_data = local_sched_data;
    assign non_alu_valid = local_non_alu_valid;
    assign non_alu_data = local_non_alu_data;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_bits <= '0;
            for (int j = 0; j < REG_COUNT; j++) shadow_rf[j] <= '0;
            debug_counter <= '0;
        end else if (flush) begin
            pending_bits <= '0; 
            debug_counter <= debug_counter + 1;
        end else begin
            debug_counter <= debug_counter + 1;

            for (int i = 0; i < ISSUE_WIDTH; i++) begin
                if (local_iq_ack[i] && iq_reg_write[i] && iq_rd_addr[i] != 0) begin
                    pending_bits[iq_rd_addr[i]] <= 1'b1;
                end
            end

            if (sched_wb_valid && sched_wb_rd != 0) begin
                shadow_rf[sched_wb_rd] <= sched_wb_data;
                pending_bits[sched_wb_rd] <= 1'b0;
            end

            if (mem_wb_valid && mem_wb_rd != 0) begin
                shadow_rf[mem_wb_rd] <= mem_wb_data;
                pending_bits[mem_wb_rd] <= 1'b0;
            end
        end
    end

    assign debug_state = {sched_valid[0], non_alu_valid, 2'b00};
    assign debug_valid = (sched_valid != 0) || non_alu_valid;
    assign debug_error = 1'b0;

endmodule
