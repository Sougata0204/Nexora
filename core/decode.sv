// decode
`timescale 1ns / 1ps
module decode #(
    parameter int DATA_WIDTH     = nexora_x3_pkg::DATA_WIDTH,
    parameter int INSTR_WIDTH    = nexora_x3_pkg::INSTR_WIDTH,
    parameter int REG_ADDR_WIDTH = nexora_x3_pkg::REG_ADDR_WIDTH
)(
    input  logic                      clk,
    input  logic                      rst_n,

    input  nexora_x3_pkg::if_id_reg_t                if_id_in,

    input  logic                      stall,
    input  logic                      flush,

    output logic [REG_ADDR_WIDTH-1:0] rs1_addr,
    output logic [REG_ADDR_WIDTH-1:0] rs2_addr,
    input  logic [DATA_WIDTH-1:0]     rs1_data,
    input  logic [DATA_WIDTH-1:0]     rs2_data,

    output nexora_x3_pkg::id_ex_reg_t                id_ex_out,

    output logic                      illegal_instr,

    output nexora_x3_pkg::debug_signals_t            debug
);

    logic [6:0]  opcode;
    logic [4:0]  rd;
    logic [2:0]  funct3;
    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [6:0]  funct7;

    assign opcode = if_id_in.instruction[6:0];
    assign rd     = if_id_in.instruction[11:7];
    assign funct3 = if_id_in.instruction[14:12];
    assign rs1    = if_id_in.instruction[19:15];
    assign rs2    = if_id_in.instruction[24:20];
    assign funct7 = if_id_in.instruction[31:25];

    assign rs1_addr = rs1;
    assign rs2_addr = rs2;

    logic [DATA_WIDTH-1:0] imm_i, imm_s, imm_b, imm_u, imm_j;
    logic [DATA_WIDTH-1:0] immediate;

    assign imm_i = {{ (DATA_WIDTH-12){if_id_in.instruction[31]} }, if_id_in.instruction[31:20]};

    assign imm_s = {{ (DATA_WIDTH-12){if_id_in.instruction[31]} },
                    if_id_in.instruction[31:25],
                    if_id_in.instruction[11:7]};

    assign imm_b = {{ (DATA_WIDTH-13){if_id_in.instruction[31]} },
                    if_id_in.instruction[31],
                    if_id_in.instruction[7],
                    if_id_in.instruction[30:25],
                    if_id_in.instruction[11:8],
                    1'b0};

    assign imm_u = {{ (DATA_WIDTH-32){if_id_in.instruction[31]} }, if_id_in.instruction[31:12], 12'b0};

    assign imm_j = {{ (DATA_WIDTH-21){if_id_in.instruction[31]} },
                    if_id_in.instruction[31],
                    if_id_in.instruction[19:12],
                    if_id_in.instruction[20],
                    if_id_in.instruction[30:21],
                    1'b0};

    nexora_x3_pkg::alu_op_t    alu_op_decoded;
    logic       alu_src_decoded;    
    logic       mem_read_decoded;
    logic       mem_write_decoded;
    logic       reg_write_decoded;
    logic       branch_decoded;
    logic       jump_decoded;
    logic       is_jalr_decoded;
    logic       illegal;

    logic       is_auipc;  

    logic [31:0] decode_count;

    always_comb begin

        alu_op_decoded    = nexora_x3_pkg::ALU_NOP;
        alu_src_decoded   = 1'b0;
        mem_read_decoded  = 1'b0;
        mem_write_decoded = 1'b0;
        reg_write_decoded = 1'b0;
        branch_decoded    = 1'b0;
        jump_decoded      = 1'b0;
        is_jalr_decoded   = 1'b0;
        immediate         = '0;
        illegal           = 1'b0;
        is_auipc          = 1'b0;

        case (opcode)
            nexora_x3_pkg::OP_R_TYPE: begin
                reg_write_decoded = 1'b1;
                alu_src_decoded   = 1'b0;  
                immediate         = '0;
                case (funct3)
                    nexora_x3_pkg::F3_ADD_SUB: alu_op_decoded = (funct7[5]) ? nexora_x3_pkg::ALU_SUB : nexora_x3_pkg::ALU_ADD;
                    nexora_x3_pkg::F3_SLL:     alu_op_decoded = nexora_x3_pkg::ALU_SLL;
                    nexora_x3_pkg::F3_SLT:     alu_op_decoded = nexora_x3_pkg::ALU_SLT;
                    nexora_x3_pkg::F3_SLTU:    alu_op_decoded = nexora_x3_pkg::ALU_SLTU;
                    nexora_x3_pkg::F3_XOR:     alu_op_decoded = nexora_x3_pkg::ALU_XOR;
                    nexora_x3_pkg::F3_SRL_SRA: alu_op_decoded = (funct7[5]) ? nexora_x3_pkg::ALU_SRA : nexora_x3_pkg::ALU_SRL;
                    nexora_x3_pkg::F3_OR:      alu_op_decoded = nexora_x3_pkg::ALU_OR;
                    nexora_x3_pkg::F3_AND:     alu_op_decoded = nexora_x3_pkg::ALU_AND;
                    default:    illegal = 1'b1;
                endcase
            end

            nexora_x3_pkg::OP_I_TYPE: begin
                reg_write_decoded = 1'b1;
                alu_src_decoded   = 1'b1;  
                immediate         = imm_i;
                case (funct3)
                    nexora_x3_pkg::F3_ADD_SUB: alu_op_decoded = nexora_x3_pkg::ALU_ADD;  
                    nexora_x3_pkg::F3_SLL:     alu_op_decoded = nexora_x3_pkg::ALU_SLL;  
                    nexora_x3_pkg::F3_SLT:     alu_op_decoded = nexora_x3_pkg::ALU_SLT;  
                    nexora_x3_pkg::F3_SLTU:    alu_op_decoded = nexora_x3_pkg::ALU_SLTU; 
                    nexora_x3_pkg::F3_XOR:     alu_op_decoded = nexora_x3_pkg::ALU_XOR;  
                    nexora_x3_pkg::F3_SRL_SRA: alu_op_decoded = (funct7[5]) ? nexora_x3_pkg::ALU_SRA : nexora_x3_pkg::ALU_SRL; 
                    nexora_x3_pkg::F3_OR:      alu_op_decoded = nexora_x3_pkg::ALU_OR;   
                    nexora_x3_pkg::F3_AND:     alu_op_decoded = nexora_x3_pkg::ALU_AND;  
                    default:    illegal = 1'b1;
                endcase
            end

            nexora_x3_pkg::OP_LOAD: begin
                reg_write_decoded = 1'b1;
                mem_read_decoded  = 1'b1;
                alu_src_decoded   = 1'b1;  
                alu_op_decoded    = nexora_x3_pkg::ALU_ADD;
                immediate         = imm_i;
                case (funct3)
                    nexora_x3_pkg::F3_LB, nexora_x3_pkg::F3_LH, nexora_x3_pkg::F3_LW, nexora_x3_pkg::F3_LBU, nexora_x3_pkg::F3_LHU: ;  
                    default: illegal = 1'b1;
                endcase
            end

            nexora_x3_pkg::OP_STORE: begin
                mem_write_decoded = 1'b1;
                alu_src_decoded   = 1'b1;  
                alu_op_decoded    = nexora_x3_pkg::ALU_ADD;
                immediate         = imm_s;
                case (funct3)
                    nexora_x3_pkg::F3_SB, nexora_x3_pkg::F3_SH, nexora_x3_pkg::F3_SW: ;  
                    default: illegal = 1'b1;
                endcase
            end

            nexora_x3_pkg::OP_BRANCH: begin
                branch_decoded  = 1'b1;
                alu_src_decoded = 1'b0;    
                alu_op_decoded  = nexora_x3_pkg::ALU_SUB; 
                immediate       = imm_b;
                case (funct3)
                    nexora_x3_pkg::F3_BEQ, nexora_x3_pkg::F3_BNE, nexora_x3_pkg::F3_BLT, nexora_x3_pkg::F3_BGE, nexora_x3_pkg::F3_BLTU, nexora_x3_pkg::F3_BGEU: ;  
                    default: illegal = 1'b1;
                endcase
            end

            nexora_x3_pkg::OP_LUI: begin
                reg_write_decoded = 1'b1;
                alu_src_decoded   = 1'b1;
                alu_op_decoded    = nexora_x3_pkg::ALU_PASS_B;  
                immediate         = imm_u;
            end

            nexora_x3_pkg::OP_AUIPC: begin
                reg_write_decoded = 1'b1;
                alu_src_decoded   = 1'b1;
                alu_op_decoded    = nexora_x3_pkg::ALU_ADD;     
                immediate         = imm_u;
                is_auipc          = 1'b1;        
            end

            nexora_x3_pkg::OP_JAL: begin
                reg_write_decoded = 1'b1;  
                jump_decoded      = 1'b1;
                alu_op_decoded    = nexora_x3_pkg::ALU_ADD;
                alu_src_decoded   = 1'b1;
                immediate         = imm_j;
            end

            nexora_x3_pkg::OP_JALR: begin
                reg_write_decoded = 1'b1;  
                jump_decoded      = 1'b1;
                is_jalr_decoded   = 1'b1;
                alu_op_decoded    = nexora_x3_pkg::ALU_ADD;
                alu_src_decoded   = 1'b1;
                immediate         = imm_i;
            end

            nexora_x3_pkg::OP_SYSTEM: begin

                alu_op_decoded = nexora_x3_pkg::ALU_NOP;
            end

            nexora_x3_pkg::OP_FENCE: begin

                alu_op_decoded = nexora_x3_pkg::ALU_NOP;
            end

            default: begin
                illegal = 1'b1;
            end
        endcase
    end

    assign illegal_instr = illegal && if_id_in.valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_ex_out <= '0;
        end else if (flush) begin
            id_ex_out <= '0;  
        end else if (!stall) begin
            id_ex_out.pc          <= if_id_in.pc;
            id_ex_out.instruction <= if_id_in.instruction;
            id_ex_out.rs1_data    <= is_auipc ? if_id_in.pc : rs1_data;
            id_ex_out.rs2_data  <= rs2_data;
            id_ex_out.rs1_addr  <= rs1;
            id_ex_out.rs2_addr  <= rs2;
            id_ex_out.rd_addr   <= rd;
            id_ex_out.imm       <= immediate;
            id_ex_out.alu_op    <= alu_op_decoded;
            id_ex_out.alu_src   <= alu_src_decoded;
            id_ex_out.mem_read  <= mem_read_decoded;
            id_ex_out.mem_write <= mem_write_decoded;
            id_ex_out.reg_write <= reg_write_decoded;
            id_ex_out.branch    <= branch_decoded;
            id_ex_out.jump      <= jump_decoded;
            id_ex_out.is_jalr   <= is_jalr_decoded;
            id_ex_out.funct3    <= funct3;
            id_ex_out.valid     <= if_id_in.valid && !illegal;
        end

    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            decode_count <= '0;
        end else if (if_id_in.valid && !stall && !flush) begin
            decode_count <= decode_count + 1;
        end
    end

    assign debug.state   = opcode[3:0];  
    assign debug.counter = decode_count;
    assign debug.valid   = if_id_in.valid && !illegal;
    assign debug.error   = illegal_instr;

    assert_no_illegal_instruction: assert property (
        @(posedge clk) disable iff (!rst_n)
        if_id_in.valid |-> !illegal
    ) else $warning("[DECODE] WARN: Illegal instruction detected: %h at PC=%h",
                     if_id_in.instruction, if_id_in.pc);

    assert_valid_rd: assert property (
        @(posedge clk) disable iff (!rst_n)
        (if_id_in.valid && reg_write_decoded) |-> !$isunknown(rd)
    ) else $error("[DECODE] ASSERT FAIL: X/Z on rd address");

    assert_valid_imm: assert property (
        @(posedge clk) disable iff (!rst_n)
        (if_id_in.valid && alu_src_decoded) |-> !$isunknown(immediate)
    ) else $error("[DECODE] ASSERT FAIL: X/Z on immediate value");

endmodule : decode
