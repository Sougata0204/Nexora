// tb_cpu
`timescale 1ns / 1ps

import nexora_x3_pkg::*;

module tb_cpu();

    parameter int CLK_PERIOD  = 10;  
    parameter int IMEM_DEPTH  = 1024;
    parameter int DMEM_DEPTH  = 1024;
    parameter int TIMEOUT_CYCLES = 5000;

    logic        clk;
    logic        rst_n;
    mem_req_t    imem_req;
    mem_resp_t   imem_resp;
    mem_req_t    dmem_req;
    mem_resp_t   dmem_resp;
    cpu_debug_t  cpu_debug;
    debug_signals_t debug;

    logic [31:0]  debug_pc;
    logic [31:0]  debug_instruction;
    logic [6:0]   debug_opcode;
    logic [4:0]   debug_rs1;
    logic [4:0]   debug_rs2;
    logic [4:0]   debug_rd;
    logic [31:0]  debug_alu_result;
    logic         debug_reg_write;
    logic         debug_branch_taken;
    logic         debug_stall;
    logic         debug_flush;

    logic [31:0]  if_id_pc;
    logic [31:0]  if_id_instr;
    logic [31:0]  id_ex_pc;
    logic [31:0]  id_ex_instruction;
    logic [31:0]  ex_mem_result;
    logic [31:0]  mem_wb_result;

    logic        halt;

    logic [31:0] imem [IMEM_DEPTH];
    logic [31:0] dmem [DMEM_DEPTH];

    always_comb begin

        automatic logic [31:0] word_addr = (imem_req.addr - IMEM_BASE) >> 2;
        if (word_addr < IMEM_DEPTH)
            imem_resp.rdata = imem[word_addr];
        else
            imem_resp.rdata = 32'h0000_0013;  
        imem_resp.ready = 1'b1;
        imem_resp.error = 1'b0;
    end

    always_comb begin
        automatic logic [31:0] word_addr = (dmem_req.addr - DMEM_BASE) >> 2;
        if (word_addr < DMEM_DEPTH)
            dmem_resp.rdata = dmem[word_addr];
        else
            dmem_resp.rdata = 32'h0000_0000;
        dmem_resp.ready = 1'b1;
        dmem_resp.error = 1'b0;
    end

    always_ff @(posedge clk) begin
        if (dmem_req.write_en) begin
            automatic logic [31:0] word_addr = (dmem_req.addr - DMEM_BASE) >> 2;
            if (word_addr < DMEM_DEPTH) begin

                if (dmem_req.byte_en[0]) dmem[word_addr][7:0]   <= dmem_req.wdata[7:0];
                if (dmem_req.byte_en[1]) dmem[word_addr][15:8]  <= dmem_req.wdata[15:8];
                if (dmem_req.byte_en[2]) dmem[word_addr][23:16] <= dmem_req.wdata[23:16];
                if (dmem_req.byte_en[3]) dmem[word_addr][31:24] <= dmem_req.wdata[31:24];
            end
        end
    end

    cpu_core #(
        .DATA_WIDTH (32),
        .ADDR_WIDTH (32),
        .INSTR_WIDTH(32)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .imem_req  (imem_req),
        .imem_resp (imem_resp),
        .dmem_req  (dmem_req),
        .dmem_resp (dmem_resp),
        .cpu_debug (cpu_debug),
        .debug     (debug),

        .debug_pc           (debug_pc),
        .debug_instruction  (debug_instruction),
        .debug_opcode       (debug_opcode),
        .debug_rs1          (debug_rs1),
        .debug_rs2          (debug_rs2),
        .debug_rd           (debug_rd),
        .debug_alu_result   (debug_alu_result),
        .debug_reg_write    (debug_reg_write),
        .debug_branch_taken (debug_branch_taken),
        .debug_stall        (debug_stall),
        .debug_flush        (debug_flush),

        .if_id_pc           (if_id_pc),
        .if_id_instr        (if_id_instr),
        .id_ex_pc           (id_ex_pc),
        .id_ex_instruction  (id_ex_instruction),
        .ex_mem_result      (ex_mem_result),
        .mem_wb_result      (mem_wb_result),

        .halt      (halt)
    );

    initial begin
        clk = 0;
        rst_n = 0;
    end
    always #(CLK_PERIOD/2) clk = ~clk;

    int test_count;
    int pass_count;
    int fail_count;
    int total_tests;
    string current_test_name;

    function automatic logic [31:0] rv32_r_type(
        input logic [6:0] funct7,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd,
        input logic [6:0] opcode
    );
        return {funct7, rs2, rs1, funct3, rd, opcode};
    endfunction

    function automatic logic [31:0] rv32_i_type(
        input logic [11:0] imm,
        input logic [4:0]  rs1,
        input logic [2:0]  funct3,
        input logic [4:0]  rd,
        input logic [6:0]  opcode
    );
        return {imm, rs1, funct3, rd, opcode};
    endfunction

    function automatic logic [31:0] rv32_s_type(
        input logic [11:0] imm,
        input logic [4:0]  rs2,
        input logic [4:0]  rs1,
        input logic [2:0]  funct3,
        input logic [6:0]  opcode
    );
        return {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
    endfunction

    function automatic logic [31:0] rv32_b_type(
        input logic [12:0] imm,   
        input logic [4:0]  rs2,
        input logic [4:0]  rs1,
        input logic [2:0]  funct3,
        input logic [6:0]  opcode
    );
        return {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], opcode};
    endfunction

    function automatic logic [31:0] rv32_u_type(
        input logic [31:0] imm,
        input logic [4:0]  rd,
        input logic [6:0]  opcode
    );
        return {imm[31:12], rd, opcode};
    endfunction

    function automatic logic [31:0] rv32_j_type(
        input logic [20:0] imm,   
        input logic [4:0]  rd,
        input logic [6:0]  opcode
    );
        return {imm[20], imm[10:1], imm[11], imm[19:12], rd, opcode};
    endfunction

    function automatic logic [31:0] NOP();
        return rv32_i_type(12'd0, 5'd0, 3'b000, 5'd0, 7'b0010011);  
    endfunction

    function automatic logic [31:0] ADD(input logic [4:0] rd, rs1, rs2);
        return rv32_r_type(7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011);
    endfunction

    function automatic logic [31:0] SUB(input logic [4:0] rd, rs1, rs2);
        return rv32_r_type(7'b0100000, rs2, rs1, 3'b000, rd, 7'b0110011);
    endfunction

    function automatic logic [31:0] AND_R(input logic [4:0] rd, rs1, rs2);
        return rv32_r_type(7'b0000000, rs2, rs1, 3'b111, rd, 7'b0110011);
    endfunction

    function automatic logic [31:0] OR_R(input logic [4:0] rd, rs1, rs2);
        return rv32_r_type(7'b0000000, rs2, rs1, 3'b110, rd, 7'b0110011);
    endfunction

    function automatic logic [31:0] XOR_R(input logic [4:0] rd, rs1, rs2);
        return rv32_r_type(7'b0000000, rs2, rs1, 3'b100, rd, 7'b0110011);
    endfunction

    function automatic logic [31:0] SLL_R(input logic [4:0] rd, rs1, rs2);
        return rv32_r_type(7'b0000000, rs2, rs1, 3'b001, rd, 7'b0110011);
    endfunction

    function automatic logic [31:0] SRL_R(input logic [4:0] rd, rs1, rs2);
        return rv32_r_type(7'b0000000, rs2, rs1, 3'b101, rd, 7'b0110011);
    endfunction

    function automatic logic [31:0] SRA_R(input logic [4:0] rd, rs1, rs2);
        return rv32_r_type(7'b0100000, rs2, rs1, 3'b101, rd, 7'b0110011);
    endfunction

    function automatic logic [31:0] SLT_R(input logic [4:0] rd, rs1, rs2);
        return rv32_r_type(7'b0000000, rs2, rs1, 3'b010, rd, 7'b0110011);
    endfunction

    function automatic logic [31:0] SLTU_R(input logic [4:0] rd, rs1, rs2);
        return rv32_r_type(7'b0000000, rs2, rs1, 3'b011, rd, 7'b0110011);
    endfunction

    function automatic logic [31:0] ADDI(input logic [4:0] rd, rs1, input logic [11:0] imm);
        return rv32_i_type(imm, rs1, 3'b000, rd, 7'b0010011);
    endfunction

    function automatic logic [31:0] ANDI(input logic [4:0] rd, rs1, input logic [11:0] imm);
        return rv32_i_type(imm, rs1, 3'b111, rd, 7'b0010011);
    endfunction

    function automatic logic [31:0] ORI(input logic [4:0] rd, rs1, input logic [11:0] imm);
        return rv32_i_type(imm, rs1, 3'b110, rd, 7'b0010011);
    endfunction

    function automatic logic [31:0] XORI(input logic [4:0] rd, rs1, input logic [11:0] imm);
        return rv32_i_type(imm, rs1, 3'b100, rd, 7'b0010011);
    endfunction

    function automatic logic [31:0] SLTI(input logic [4:0] rd, rs1, input logic [11:0] imm);
        return rv32_i_type(imm, rs1, 3'b010, rd, 7'b0010011);
    endfunction

    function automatic logic [31:0] SLTIU(input logic [4:0] rd, rs1, input logic [11:0] imm);
        return rv32_i_type(imm, rs1, 3'b011, rd, 7'b0010011);
    endfunction

    function automatic logic [31:0] SLLI(input logic [4:0] rd, rs1, shamt);
        return rv32_i_type({7'b0000000, shamt}, rs1, 3'b001, rd, 7'b0010011);
    endfunction

    function automatic logic [31:0] SRLI(input logic [4:0] rd, rs1, shamt);
        return rv32_i_type({7'b0000000, shamt}, rs1, 3'b101, rd, 7'b0010011);
    endfunction

    function automatic logic [31:0] SRAI(input logic [4:0] rd, rs1, shamt);
        return rv32_i_type({7'b0100000, shamt}, rs1, 3'b101, rd, 7'b0010011);
    endfunction

    function automatic logic [31:0] LUI(input logic [4:0] rd, input logic [31:0] imm);
        return rv32_u_type(imm, rd, 7'b0110111);
    endfunction

    function automatic logic [31:0] AUIPC(input logic [4:0] rd, input logic [31:0] imm);
        return rv32_u_type(imm, rd, 7'b0010111);
    endfunction

    function automatic logic [31:0] LW(input logic [4:0] rd, rs1, input logic [11:0] offset);
        return rv32_i_type(offset, rs1, 3'b010, rd, 7'b0000011);
    endfunction

    function automatic logic [31:0] LH(input logic [4:0] rd, rs1, input logic [11:0] offset);
        return rv32_i_type(offset, rs1, 3'b001, rd, 7'b0000011);
    endfunction

    function automatic logic [31:0] LB(input logic [4:0] rd, rs1, input logic [11:0] offset);
        return rv32_i_type(offset, rs1, 3'b000, rd, 7'b0000011);
    endfunction

    function automatic logic [31:0] LHU(input logic [4:0] rd, rs1, input logic [11:0] offset);
        return rv32_i_type(offset, rs1, 3'b101, rd, 7'b0000011);
    endfunction

    function automatic logic [31:0] LBU(input logic [4:0] rd, rs1, input logic [11:0] offset);
        return rv32_i_type(offset, rs1, 3'b100, rd, 7'b0000011);
    endfunction

    function automatic logic [31:0] SW(input logic [4:0] rs2, rs1, input logic [11:0] offset);
        return rv32_s_type(offset, rs2, rs1, 3'b010, 7'b0100011);
    endfunction

    function automatic logic [31:0] SH(input logic [4:0] rs2, rs1, input logic [11:0] offset);
        return rv32_s_type(offset, rs2, rs1, 3'b001, 7'b0100011);
    endfunction

    function automatic logic [31:0] SB(input logic [4:0] rs2, rs1, input logic [11:0] offset);
        return rv32_s_type(offset, rs2, rs1, 3'b000, 7'b0100011);
    endfunction

    function automatic logic [31:0] BEQ(input logic [4:0] rs1, rs2, input logic [12:0] offset);
        return rv32_b_type(offset, rs2, rs1, 3'b000, 7'b1100011);
    endfunction

    function automatic logic [31:0] BNE(input logic [4:0] rs1, rs2, input logic [12:0] offset);
        return rv32_b_type(offset, rs2, rs1, 3'b001, 7'b1100011);
    endfunction

    function automatic logic [31:0] BLT(input logic [4:0] rs1, rs2, input logic [12:0] offset);
        return rv32_b_type(offset, rs2, rs1, 3'b100, 7'b1100011);
    endfunction

    function automatic logic [31:0] BGE(input logic [4:0] rs1, rs2, input logic [12:0] offset);
        return rv32_b_type(offset, rs2, rs1, 3'b101, 7'b1100011);
    endfunction

    function automatic logic [31:0] BLTU(input logic [4:0] rs1, rs2, input logic [12:0] offset);
        return rv32_b_type(offset, rs2, rs1, 3'b110, 7'b1100011);
    endfunction

    function automatic logic [31:0] BGEU(input logic [4:0] rs1, rs2, input logic [12:0] offset);
        return rv32_b_type(offset, rs2, rs1, 3'b111, 7'b1100011);
    endfunction

    function automatic logic [31:0] JAL(input logic [4:0] rd, input logic [20:0] offset);
        return rv32_j_type(offset, rd, 7'b1101111);
    endfunction

    function automatic logic [31:0] JALR(input logic [4:0] rd, rs1, input logic [11:0] offset);
        return rv32_i_type(offset, rs1, 3'b000, rd, 7'b1100111);
    endfunction

    task automatic wait_pipe_drain(int extra_cycles = 0);
        repeat (5 + extra_cycles) @(posedge clk);
    endtask

    task automatic wait_cycles(int n);
        repeat (n) @(posedge clk);
    endtask

    task automatic do_reset();
        rst_n = 1'b0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
    endtask

    task automatic clear_memories();
        for (int i = 0; i < IMEM_DEPTH; i++) imem[i] = NOP();
        for (int i = 0; i < DMEM_DEPTH; i++) dmem[i] = 32'h0;
    endtask

    task automatic check_reg_write(
        input logic [4:0]  expected_rd,
        input logic [31:0] expected_value,
        input string       test_name
    );
        int timeout = 100;
        logic found = 0;

        while (timeout > 0 && !found) begin
            @(negedge clk);
            if (cpu_debug.rd_write && cpu_debug.rd_addr == expected_rd) begin
                if (cpu_debug.rd_data === expected_value) begin
                    pass_count++;
                    $display("[PASS] %s: x%0d = 0x%08h", test_name, expected_rd, expected_value);
                end else begin
                    fail_count++;
                    $display("[FAIL] %s: x%0d expected 0x%08h, got 0x%08h",
                             test_name, expected_rd, expected_value, cpu_debug.rd_data);
                end
                found = 1;
            end
            timeout--;
        end

        if (!found) begin
            fail_count++;
            $display("[FAIL] %s: Timeout waiting for write to x%0d", test_name, expected_rd);
        end
        test_count++;
    endtask

    initial begin
        $dumpfile("tb_cpu.vcd");
        $dumpvars(0, tb_cpu);
    end

    initial begin
        #(CLK_PERIOD * TIMEOUT_CYCLES);
        $display("\n[TIMEOUT] Simulation exceeded %0d cycles. Aborting.", TIMEOUT_CYCLES);
        $display("Tests run: %0d, Passed: %0d, Failed: %0d", test_count, pass_count, fail_count);
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && cpu_debug.rd_write) begin
            $display("Cycle:%0d\nPC:%08h\nInstruction:%08h\nOpcode:%b\nRD:x%0d\nResult:%08h\n",
                     debug.counter, cpu_debug.pc, cpu_debug.instruction, cpu_debug.instruction[6:0], cpu_debug.rd_addr, cpu_debug.rd_data);
        end
    end

    int xz_errors = 0;
    always @(posedge clk) begin
        if (rst_n) begin
            if (debug.valid && $isunknown(cpu_debug.pc)) begin
                $display("[XZ_ERROR] Cycle=%0d: X/Z on PC", debug.counter);
                xz_errors++;
            end
        end
    end

    initial begin
        $display("========================================================");
        $display("  Nexora X1 CPU Core - Milestone 1 Verification");
        $display("  RV32I Directed + Randomized Test Suite");
        $display("========================================================\n");

        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        begin
            $display("\n--- TEST 1: R-Type ALU Instructions ---");
            clear_memories();

            imem[0]  = ADDI(5'd1, 5'd0, 12'd10);
            imem[1]  = ADDI(5'd2, 5'd0, 12'd3);
            imem[2]  = NOP();
            imem[3]  = NOP();
            imem[4]  = ADD(5'd3, 5'd1, 5'd2);
            imem[5]  = SUB(5'd4, 5'd1, 5'd2);
            imem[6]  = AND_R(5'd5, 5'd1, 5'd2);
            imem[7]  = OR_R(5'd6, 5'd1, 5'd2);
            imem[8]  = XOR_R(5'd7, 5'd1, 5'd2);
            imem[9]  = SLL_R(5'd8, 5'd1, 5'd2);
            imem[10] = SRL_R(5'd9, 5'd1, 5'd2);
            imem[11] = SLT_R(5'd10, 5'd2, 5'd1);
            imem[12] = SLTU_R(5'd11, 5'd1, 5'd2);

            for (int i = 13; i < 30; i++) imem[i] = NOP();

            do_reset();

            check_reg_write(5'd1, 32'd10, "ADDI x1, x0, 10");
            check_reg_write(5'd2, 32'd3,  "ADDI x2, x0, 3");

            check_reg_write(5'd3, 32'd13, "ADD x3, x1, x2");
            check_reg_write(5'd4, 32'd7,  "SUB x4, x1, x2");
            check_reg_write(5'd5, 32'd2,  "AND x5, x1, x2");
            check_reg_write(5'd6, 32'd11, "OR x6, x1, x2");
            check_reg_write(5'd7, 32'd9,  "XOR x7, x1, x2");
            check_reg_write(5'd8, 32'd80, "SLL x8, x1, x2");
            check_reg_write(5'd9, 32'd1,  "SRL x9, x1, x2");
            check_reg_write(5'd10, 32'd1, "SLT x10, x2, x1");
            check_reg_write(5'd11, 32'd0, "SLTU x11, x1, x2");

            wait_pipe_drain(2);
        end

        begin
            $display("\n--- TEST 2: I-Type ALU Instructions ---");
            clear_memories();

            imem[0]  = ADDI(5'd1, 5'd0, 12'd100);
            imem[1]  = NOP();
            imem[2]  = NOP();
            imem[3]  = ADDI(5'd2, 5'd1, 12'hFCE);  
            imem[4]  = ANDI(5'd3, 5'd1, 12'h00F);
            imem[5]  = ORI(5'd4, 5'd1, 12'h00F);
            imem[6]  = XORI(5'd5, 5'd1, 12'h0FF);
            imem[7]  = SLTI(5'd6, 5'd1, 12'd200);
            imem[8]  = SLTIU(5'd7, 5'd1, 12'd200);
            imem[9]  = SLLI(5'd8, 5'd1, 5'd2);
            imem[10] = SRLI(5'd9, 5'd1, 5'd2);
            imem[11] = SRAI(5'd10, 5'd2, 5'd1);
            for (int i = 12; i < 30; i++) imem[i] = NOP();

            do_reset();

            check_reg_write(5'd1, 32'd100, "ADDI x1, x0, 100");

            check_reg_write(5'd2, 32'd50,  "ADDI x2, x1, -50");
            check_reg_write(5'd3, 32'd4,   "ANDI x3, x1, 0x0F");
            check_reg_write(5'd4, 32'd111, "ORI x4, x1, 0x0F");
            check_reg_write(5'd5, 32'd155, "XORI x5, x1, 0xFF");  
            check_reg_write(5'd6, 32'd1,   "SLTI x6, x1, 200");
            check_reg_write(5'd7, 32'd1,   "SLTIU x7, x1, 200");
            check_reg_write(5'd8, 32'd400, "SLLI x8, x1, 2");
            check_reg_write(5'd9, 32'd25,  "SRLI x9, x1, 2");
            check_reg_write(5'd10, 32'd25, "SRAI x10, x2, 1");

            wait_pipe_drain(2);
        end

        begin
            $display("\n--- TEST 3: LUI and AUIPC ---");
            clear_memories();

            imem[0] = LUI(5'd1, 32'h12345000);
            imem[1] = LUI(5'd2, 32'h00001000);
            imem[2] = AUIPC(5'd3, 32'h00000000);
            for (int i = 3; i < 20; i++) imem[i] = NOP();

            do_reset();

            check_reg_write(5'd1, 32'h12345000, "LUI x1, 0x12345");
            check_reg_write(5'd2, 32'h00001000, "LUI x2, 0x00001");
            check_reg_write(5'd3, 32'h00010008, "AUIPC x3, 0x00000 (should be PC)");

            wait_pipe_drain(2);
        end

        begin
            $display("\n--- TEST 4: Load/Store Instructions ---");
            clear_memories();

            dmem[0] = 32'hDEADBEEF;
            dmem[1] = 32'h12345678;

            imem[0]  = LUI(5'd1, 32'h00020000);    
            imem[1]  = NOP();
            imem[2]  = NOP();
            imem[3]  = LW(5'd2, 5'd1, 12'd0);      
            imem[4]  = LW(5'd3, 5'd1, 12'd4);      
            imem[5]  = ADDI(5'd4, 5'd0, 12'h042);  
            imem[6]  = NOP();
            imem[7]  = NOP();
            imem[8]  = SW(5'd4, 5'd1, 12'd8);      
            imem[9]  = NOP();
            imem[10] = NOP();
            imem[11] = NOP();
            imem[12] = LW(5'd5, 5'd1, 12'd8);      
            for (int i = 13; i < 30; i++) imem[i] = NOP();

            do_reset();

            check_reg_write(5'd1, 32'h00020000, "LUI x1, DMEM_BASE");

            check_reg_write(5'd2, 32'hDEADBEEF, "LW x2, 0(x1)");
            check_reg_write(5'd3, 32'h12345678, "LW x3, 4(x1)");
            check_reg_write(5'd4, 32'h00000042, "ADDI x4, x0, 0x42");

            check_reg_write(5'd5, 32'h00000042, "LW x5, 8(x1) after SW");

            wait_pipe_drain(2);
        end

        begin
            $display("\n--- TEST 5: Branch Instructions ---");
            clear_memories();

            imem[0] = ADDI(5'd1, 5'd0, 12'd5);
            imem[1] = ADDI(5'd2, 5'd0, 12'd5);
            imem[2] = NOP();
            imem[3] = NOP();
            imem[4] = BEQ(5'd1, 5'd2, 13'd12);      
            imem[5] = ADDI(5'd3, 5'd0, 12'd99);     
            imem[6] = ADDI(5'd3, 5'd0, 12'd99);     
            imem[7] = ADDI(5'd3, 5'd0, 12'd1);      
            for (int i = 8; i < 30; i++) imem[i] = NOP();

            do_reset();

            check_reg_write(5'd1, 32'd5, "ADDI x1=5");
            check_reg_write(5'd2, 32'd5, "ADDI x2=5");

            check_reg_write(5'd3, 32'd1, "BEQ taken: x3 should be 1, not 99");

            wait_pipe_drain(2);
        end

        begin
            $display("\n--- TEST 6: BNE Not-Taken ---");
            clear_memories();

            imem[0] = ADDI(5'd1, 5'd0, 12'd7);
            imem[1] = ADDI(5'd2, 5'd0, 12'd7);
            imem[2] = NOP();
            imem[3] = NOP();
            imem[4] = BNE(5'd1, 5'd2, 13'd12);
            imem[5] = ADDI(5'd3, 5'd0, 12'd42);
            for (int i = 6; i < 20; i++) imem[i] = NOP();

            do_reset();

            check_reg_write(5'd1, 32'd7,  "ADDI x1=7");
            check_reg_write(5'd2, 32'd7,  "ADDI x2=7");

            check_reg_write(5'd3, 32'd42, "BNE not-taken: x3 should be 42");

            wait_pipe_drain(2);
        end

        begin
            $display("\n--- TEST 7: JAL ---");
            clear_memories();

            imem[0] = JAL(5'd1, 21'd12);            
            imem[1] = ADDI(5'd2, 5'd0, 12'd99);     
            imem[2] = ADDI(5'd2, 5'd0, 12'd99);     
            imem[3] = ADDI(5'd2, 5'd0, 12'd1);      
            for (int i = 4; i < 20; i++) imem[i] = NOP();

            do_reset();

            check_reg_write(5'd1, 32'h00010004, "JAL x1: should be PC+4");
            check_reg_write(5'd2, 32'd1, "JAL target: x2 should be 1, not 99");

            wait_pipe_drain(2);
        end

        begin
            $display("\n--- TEST 8: Data Forwarding (EX-EX) ---");
            clear_memories();

            imem[0] = ADDI(5'd1, 5'd0, 12'd10);
            imem[1] = ADDI(5'd2, 5'd1, 12'd5);
            imem[2] = ADD(5'd3, 5'd1, 5'd2);
            for (int i = 3; i < 20; i++) imem[i] = NOP();

            do_reset();

            check_reg_write(5'd1, 32'd10, "FWD: ADDI x1=10");
            check_reg_write(5'd2, 32'd15, "FWD: ADDI x2=x1+5=15");
            check_reg_write(5'd3, 32'd25, "FWD: ADD x3=x1+x2=25");

            wait_pipe_drain(2);
        end

        begin
            $display("\n--- TEST 9: Load-Use Hazard ---");
            clear_memories();
            dmem[0] = 32'h00000020;  

            imem[0] = LUI(5'd1, 32'h00020000);
            imem[1] = NOP();
            imem[2] = NOP();
            imem[3] = LW(5'd2, 5'd1, 12'd0);
            imem[4] = ADDI(5'd3, 5'd2, 12'd1);     
            for (int i = 5; i < 20; i++) imem[i] = NOP();

            do_reset();

            check_reg_write(5'd1, 32'h00020000, "LOADUSE: LUI x1=DMEM_BASE");

            check_reg_write(5'd2, 32'd32, "LOADUSE: LW x2=32");
            check_reg_write(5'd3, 32'd33, "LOADUSE: ADDI x3=x2+1=33 (after stall)");

            wait_pipe_drain(2);
        end

        begin
            $display("\n--- TEST 10: x0 Hardwired Zero ---");
            clear_memories();

            imem[0] = ADDI(5'd0, 5'd0, 12'd100);
            imem[1] = NOP();
            imem[2] = NOP();
            imem[3] = NOP();
            imem[4] = ADD(5'd1, 5'd0, 5'd0);
            for (int i = 5; i < 20; i++) imem[i] = NOP();

            do_reset();

            check_reg_write(5'd1, 32'd0, "x0 hardwired: ADD x1=x0+x0 should be 0");

            wait_pipe_drain(2);
        end

        begin
            $display("\n--- TEST 11: Negative Numbers ---");
            clear_memories();

            imem[0] = ADDI(5'd1, 5'd0, 12'hFFF);   
            imem[1] = ADDI(5'd2, 5'd0, 12'd1);
            imem[2] = NOP();
            imem[3] = NOP();
            imem[4] = ADD(5'd3, 5'd1, 5'd2);
            imem[5] = SLT_R(5'd4, 5'd1, 5'd2);
            imem[6] = SLTU_R(5'd5, 5'd1, 5'd2);
            for (int i = 7; i < 20; i++) imem[i] = NOP();

            do_reset();

            check_reg_write(5'd1, 32'hFFFFFFFF, "NEG: ADDI x1=-1");
            check_reg_write(5'd2, 32'd1, "NEG: ADDI x2=1");

            check_reg_write(5'd3, 32'd0, "NEG: ADD x3=-1+1=0");
            check_reg_write(5'd4, 32'd1, "NEG: SLT x4=(-1<1)=1");
            check_reg_write(5'd5, 32'd0, "NEG: SLTU x5=(0xFFFFFFFF<1)=0");

            wait_pipe_drain(2);
        end

        begin
            $display("\n--- TEST 12: SRA with Negative Value ---");
            clear_memories();

            imem[0] = ADDI(5'd1, 5'd0, 12'hFF0);   
            imem[1] = ADDI(5'd2, 5'd0, 12'd2);
            imem[2] = NOP();
            imem[3] = NOP();
            imem[4] = SRA_R(5'd3, 5'd1, 5'd2);
            for (int i = 5; i < 20; i++) imem[i] = NOP();

            do_reset();

            check_reg_write(5'd1, 32'hFFFFFFF0, "SRA: x1=-16");
            check_reg_write(5'd2, 32'd2, "SRA: x2=2");

            check_reg_write(5'd3, 32'hFFFFFFFC, "SRA: x3=-16>>>2=-4");

            wait_pipe_drain(2);
        end

        begin
            $display("\n--- TEST 13: Byte and Halfword Loads ---");
            clear_memories();
            dmem[0] = 32'hABCD1234;

            imem[0] = LUI(5'd1, 32'h00020000);
            imem[1] = NOP();
            imem[2] = NOP();
            imem[3] = LBU(5'd2, 5'd1, 12'd0);
            imem[4] = LBU(5'd3, 5'd1, 12'd1);
            imem[5] = LHU(5'd4, 5'd1, 12'd0);
            imem[6] = LB(5'd5, 5'd1, 12'd3);
            for (int i = 7; i < 20; i++) imem[i] = NOP();

            do_reset();

            check_reg_write(5'd1, 32'h00020000, "LDSUBWORD: LUI x1");

            check_reg_write(5'd2, 32'h00000034, "LBU x2, byte[0]");
            check_reg_write(5'd3, 32'h00000012, "LBU x3, byte[1]");
            check_reg_write(5'd4, 32'h00001234, "LHU x4, half[0]");
            check_reg_write(5'd5, 32'hFFFFFFAB, "LB x5, byte[3] sign-ext");

            wait_pipe_drain(2);
        end

        begin
            $display("\n--- TEST 14: Byte and Halfword Stores ---");
            clear_memories();

            imem[0] = LUI(5'd1, 32'h00020000);
            imem[1] = ADDI(5'd2, 5'd0, 12'h0AB);
            imem[2] = NOP();
            imem[3] = NOP();
            imem[4] = SB(5'd2, 5'd1, 12'd0);
            imem[5] = NOP();
            imem[6] = NOP();
            imem[7] = NOP();
            imem[8] = LW(5'd3, 5'd1, 12'd0);
            for (int i = 9; i < 20; i++) imem[i] = NOP();

            do_reset();

            check_reg_write(5'd1, 32'h00020000, "SB_TEST: LUI x1");
            check_reg_write(5'd2, 32'h000000AB, "SB_TEST: ADDI x2=0xAB");
            check_reg_write(5'd3, 32'h000000AB, "SB_TEST: LW after SB");

            wait_pipe_drain(2);
        end

        begin
            $display("\n--- TEST 15: Forwarding Chain ---");
            clear_memories();

            imem[0] = ADDI(5'd1, 5'd0, 12'd1);
            imem[1] = ADDI(5'd2, 5'd1, 12'd1);
            imem[2] = ADDI(5'd3, 5'd2, 12'd1);
            imem[3] = ADDI(5'd4, 5'd3, 12'd1);
            imem[4] = ADDI(5'd5, 5'd4, 12'd1);
            for (int i = 5; i < 20; i++) imem[i] = NOP();

            do_reset();

            check_reg_write(5'd1, 32'd1, "CHAIN: x1=1");
            check_reg_write(5'd2, 32'd2, "CHAIN: x2=2");
            check_reg_write(5'd3, 32'd3, "CHAIN: x3=3");
            check_reg_write(5'd4, 32'd4, "CHAIN: x4=4");
            check_reg_write(5'd5, 32'd5, "CHAIN: x5=5");

            wait_pipe_drain(2);
        end

        begin
            $display("\n--- TEST 16: Branch Loop ---");
            clear_memories();

            imem[0] = ADDI(5'd1, 5'd0, 12'd0);
            imem[1] = ADDI(5'd2, 5'd0, 12'd4);

            imem[2] = ADDI(5'd1, 5'd1, 12'd1);     
            imem[3] = NOP();
            imem[4] = NOP();

            imem[5] = BNE(5'd1, 5'd2, 13'h1FF4);   
            imem[6] = ADDI(5'd3, 5'd1, 12'd0);     
            for (int i = 7; i < 30; i++) imem[i] = NOP();

            do_reset();

            check_reg_write(5'd3, 32'd4, "LOOP: x3 = counter after loop = 4");

            wait_pipe_drain(2);
        end

        begin
            int halt_timeout;
            logic halt_found;

            $display("\n--- TEST 17: HALT / ECALL Verification ---");
            clear_memories();

            imem[0] = 32'h00000073;  
            for (int i = 1; i < 20; i++) imem[i] = NOP();

            do_reset();

            halt_timeout = 20;
            halt_found = 0;

            while (halt_timeout > 0 && !halt_found) begin
                @(posedge clk);
                if (halt) begin
                    halt_found = 1;
                    pass_count++;
                    test_count++;
                    $display("[PASS] HALT / ECALL Verification: CPU halted successfully");
                end
                halt_timeout--;
            end

            if (!halt_found) begin
                fail_count++;
                test_count++;
                $display("[FAIL] HALT / ECALL Verification: CPU failed to halt");
            end
        end

        $display("\n========================================================");
        $display("  TEST SUMMARY");
        $display("========================================================");
        $display("  Total tests: %0d", test_count);
        $display("  Passed:      %0d", pass_count);
        $display("  Failed:      %0d", fail_count);
        $display("  X/Z Errors:  %0d", xz_errors);
        $display("========================================================");

        if (fail_count == 0 && xz_errors == 0 && halt) begin
            $display("  *** ALL TESTS PASSED — MILESTONE 1 GATE: PASS ***");
        end else begin
            $display("  *** TESTS FAILED — MILESTONE 1 GATE: FAIL ***");
        end

        $display("========================================================\n");
        $finish;
    end

endmodule : tb_cpu
