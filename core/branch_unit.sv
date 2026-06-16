// branch_unit
`timescale 1ns / 1ps
module branch_unit #(
    parameter int DATA_WIDTH = nexora_x3_pkg::DATA_WIDTH,
    parameter int ADDR_WIDTH = nexora_x3_pkg::ADDR_WIDTH
)(
    input  logic                  clk,
    input  logic                  rst_n,

    input  logic                  branch_en,     
    input  logic                  jump_en,       
    input  logic                  is_jalr,       
    input  logic [2:0]            funct3,        

    input  logic [DATA_WIDTH-1:0] rs1_data,      
    input  logic [DATA_WIDTH-1:0] rs2_data,      
    input  logic [DATA_WIDTH-1:0] pc,            
    input  logic [DATA_WIDTH-1:0] immediate,     

    output logic                  branch_taken,  
    output logic [ADDR_WIDTH-1:0] target_addr,   
    output logic                  flush_pipeline, 

    output nexora_x3_pkg::debug_signals_t        debug
);

    logic condition_met;
    logic signed [DATA_WIDTH-1:0] rs1_signed, rs2_signed;

    assign rs1_signed = $signed(rs1_data);
    assign rs2_signed = $signed(rs2_data);

    always_comb begin
        condition_met = 1'b0;

        if (branch_en) begin
            case (funct3)
                nexora_x3_pkg::F3_BEQ:  condition_met = (rs1_data == rs2_data);
                nexora_x3_pkg::F3_BNE:  condition_met = (rs1_data != rs2_data);
                nexora_x3_pkg::F3_BLT:  condition_met = (rs1_signed < rs2_signed);
                nexora_x3_pkg::F3_BGE:  condition_met = (rs1_signed >= rs2_signed);
                nexora_x3_pkg::F3_BLTU: condition_met = (rs1_data < rs2_data);
                nexora_x3_pkg::F3_BGEU: condition_met = (rs1_data >= rs2_data);
                default: condition_met = 1'b0;
            endcase
        end
    end

    logic [ADDR_WIDTH-1:0] branch_target;
    logic [ADDR_WIDTH-1:0] jal_target;
    logic [ADDR_WIDTH-1:0] jalr_target;

    assign branch_target = pc + immediate;                    
    assign jal_target    = pc + immediate;                    
    assign jalr_target   = (rs1_data + immediate) & ~32'd1;  

    always_comb begin
        if (jump_en) begin
            branch_taken = 1'b1;
            target_addr  = is_jalr ? jalr_target : jal_target;
        end else if (branch_en && condition_met) begin
            branch_taken = 1'b1;
            target_addr  = branch_target;
        end else begin
            branch_taken = 1'b0;
            target_addr  = '0;
        end
    end

    assign flush_pipeline = branch_taken;

    logic [31:0] branch_count;
    logic [31:0] taken_count;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            branch_count <= '0;
            taken_count  <= '0;
        end else begin
            if (branch_en || jump_en) begin
                branch_count <= branch_count + 1;
            end
            if (branch_taken) begin
                taken_count <= taken_count + 1;
            end
        end
    end

    assign debug.state   = {branch_en, jump_en, is_jalr, condition_met};
    assign debug.counter = branch_count;
    assign debug.valid   = branch_taken;
    assign debug.error   = 1'b0;

    assert_aligned_target: assert property (
        @(posedge clk) disable iff (!rst_n)
        (branch_taken) |-> (target_addr[1:0] == 2'b00)
    ) else $error("[BRANCH] ASSERT FAIL: Misaligned branch target: %h", target_addr);

    assert_no_xz_target: assert property (
        @(posedge clk) disable iff (!rst_n)
        (branch_taken) |-> !$isunknown(target_addr)
    ) else $error("[BRANCH] ASSERT FAIL: X/Z detected on target address");

    assert_jalr_aligned: assert property (
        @(posedge clk) disable iff (!rst_n)
        (jump_en && is_jalr && branch_taken) |-> (target_addr[0] == 1'b0)
    ) else $error("[BRANCH] ASSERT FAIL: JALR target bit[0] not cleared");

endmodule : branch_unit
