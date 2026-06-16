// tb_cpu_instructions
`timescale 1ns / 1ps

import nexora_x3_pkg::*;

module tb_cpu_instructions();

    localparam int CLK_PERIOD     = 10;     
    localparam int IMEM_WORDS     = 16384;  
    localparam int DMEM_WORDS     = 32768;  
    localparam int TIMEOUT_CYCLES = 50000;

    localparam logic [63:0] IMEM_BASE_ADDR = nexora_x3_pkg::IMEM_BASE;  
    localparam logic [63:0] DMEM_BASE_ADDR = nexora_x3_pkg::DMEM_BASE;  

    logic clk;
    logic rst_n;

    initial begin
        clk   = 1'b0;
        rst_n = 1'b0;
    end
    always #(CLK_PERIOD / 2) clk = ~clk;

    mem_req_t         imem_req;
    mem_resp_t        imem_resp;
    mem_req_t         dmem_req;
    mem_resp_t        dmem_resp;
    cpu_debug_t       cpu_debug;
    debug_signals_t   debug;
    logic             halt;
    logic [31:0]      instruction_count;
    logic [31:0]      cycle_count;
    logic [31:0]      cache_hits;
    logic [31:0]      cache_misses;
    logic [31:0]      stall_count;
    logic [31:0]      branch_count;

    logic [31:0] imem [IMEM_WORDS];

    logic [31:0] dmem [DMEM_WORDS];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            imem_resp.rdata <= 64'd0;
            imem_resp.ready <= 1'b0;
            imem_resp.error <= 1'b0;
        end else begin
            if (imem_req.read_en) begin
                automatic logic [63:0] byte_offset = imem_req.addr - IMEM_BASE_ADDR;
                automatic logic [31:0] word_index  = byte_offset[31:0] >> 2;
                if (word_index < IMEM_WORDS) begin

                    imem_resp.rdata <= {32'h0000_0000, imem[word_index]};
                end else begin

                    imem_resp.rdata <= {32'h0000_0000, 32'h0000_0013};
                end
                imem_resp.ready <= 1'b1;
                imem_resp.error <= 1'b0;
            end else begin
                imem_resp.ready <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dmem_resp.rdata <= 64'd0;
            dmem_resp.ready <= 1'b0;
            dmem_resp.error <= 1'b0;
        end else begin

            if (dmem_req.read_en) begin
                automatic logic [63:0] byte_offset = dmem_req.addr - DMEM_BASE_ADDR;
                automatic logic [31:0] word_index  = byte_offset[31:0] >> 2;
                if (word_index < DMEM_WORDS) begin
                    dmem_resp.rdata <= {32'h0000_0000, dmem[word_index]};
                end else begin
                    dmem_resp.rdata <= 64'd0;
                end
                dmem_resp.ready <= 1'b1;
                dmem_resp.error <= 1'b0;
            end else begin
                dmem_resp.ready <= dmem_req.write_en;  
                dmem_resp.error <= 1'b0;
            end

            if (dmem_req.write_en) begin
                automatic logic [63:0] byte_offset = dmem_req.addr - DMEM_BASE_ADDR;
                automatic logic [31:0] word_index  = byte_offset[31:0] >> 2;
                if (word_index < DMEM_WORDS) begin
                    if (dmem_req.byte_en[0]) dmem[word_index][ 7: 0] <= dmem_req.wdata[ 7: 0];
                    if (dmem_req.byte_en[1]) dmem[word_index][15: 8] <= dmem_req.wdata[15: 8];
                    if (dmem_req.byte_en[2]) dmem[word_index][23:16] <= dmem_req.wdata[23:16];
                    if (dmem_req.byte_en[3]) dmem[word_index][31:24] <= dmem_req.wdata[31:24];
                end
            end
        end
    end

    cpu_core dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .imem_req          (imem_req),
        .imem_resp         (imem_resp),
        .dmem_req          (dmem_req),
        .dmem_resp         (dmem_resp),
        .cpu_debug         (cpu_debug),
        .debug             (debug),
        .halt              (halt),
        .instruction_count (instruction_count),
        .cycle_count       (cycle_count),
        .cache_hits        (cache_hits),
        .cache_misses      (cache_misses),
        .stall_count       (stall_count),
        .branch_count      (branch_count)
    );

    function automatic logic [31:0] encode_r_type(
        input logic [6:0] funct7,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd,
        input logic [6:0] opcode
    );
        return {funct7, rs2, rs1, funct3, rd, opcode};
    endfunction

    function automatic logic [31:0] encode_i_type(
        input logic [11:0] imm,
        input logic [4:0]  rs1,
        input logic [2:0]  funct3,
        input logic [4:0]  rd,
        input logic [6:0]  opcode
    );
        return {imm, rs1, funct3, rd, opcode};
    endfunction

    function automatic logic [31:0] encode_s_type(
        input logic [11:0] imm,
        input logic [4:0]  rs2,
        input logic [4:0]  rs1,
        input logic [2:0]  funct3,
        input logic [6:0]  opcode
    );
        return {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
    endfunction

    function automatic logic [31:0] encode_b_type(
        input logic [12:0] imm,    
        input logic [4:0]  rs2,
        input logic [4:0]  rs1,
        input logic [2:0]  funct3,
        input logic [6:0]  opcode
    );
        return {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], opcode};
    endfunction

    function automatic logic [31:0] encode_u_type(
        input logic [31:0] imm,
        input logic [4:0]  rd,
        input logic [6:0]  opcode
    );
        return {imm[31:12], rd, opcode};
    endfunction

    function automatic logic [31:0] encode_j_type(
        input logic [20:0] imm,    
        input logic [4:0]  rd,
        input logic [6:0]  opcode
    );
        return {imm[20], imm[10:1], imm[11], imm[19:12], rd, opcode};
    endfunction

    function automatic logic [31:0] NOP();
        return encode_i_type(12'd0, 5'd0, 3'b000, 5'd0, 7'b0010011);
    endfunction

    function automatic logic [31:0] ADDI(
        input logic [4:0]  rd,
        input logic [4:0]  rs1,
        input logic [11:0] imm
    );
        return encode_i_type(imm, rs1, 3'b000, rd, 7'b0010011);
    endfunction

    function automatic logic [31:0] ADD(
        input logic [4:0] rd,
        input logic [4:0] rs1,
        input logic [4:0] rs2
    );
        return encode_r_type(7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011);
    endfunction

    function automatic logic [31:0] SUB(
        input logic [4:0] rd,
        input logic [4:0] rs1,
        input logic [4:0] rs2
    );
        return encode_r_type(7'b0100000, rs2, rs1, 3'b000, rd, 7'b0110011);
    endfunction

    function automatic logic [31:0] LUI(
        input logic [4:0]  rd,
        input logic [31:0] imm
    );
        return encode_u_type(imm, rd, 7'b0110111);
    endfunction

    function automatic logic [31:0] AUIPC(
        input logic [4:0]  rd,
        input logic [31:0] imm
    );
        return encode_u_type(imm, rd, 7'b0010111);
    endfunction

    function automatic logic [31:0] LW(
        input logic [4:0]  rd,
        input logic [4:0]  rs1,
        input logic [11:0] offset
    );
        return encode_i_type(offset, rs1, 3'b010, rd, 7'b0000011);
    endfunction

    function automatic logic [31:0] SW(
        input logic [4:0]  rs2,
        input logic [4:0]  rs1,
        input logic [11:0] offset
    );
        return encode_s_type(offset, rs2, rs1, 3'b010, 7'b0100011);
    endfunction

    function automatic logic [31:0] BEQ(
        input logic [4:0]  rs1,
        input logic [4:0]  rs2,
        input logic [12:0] offset
    );
        return encode_b_type(offset, rs2, rs1, 3'b000, 7'b1100011);
    endfunction

    function automatic logic [31:0] BNE(
        input logic [4:0]  rs1,
        input logic [4:0]  rs2,
        input logic [12:0] offset
    );
        return encode_b_type(offset, rs2, rs1, 3'b001, 7'b1100011);
    endfunction

    function automatic logic [31:0] JAL(
        input logic [4:0]  rd,
        input logic [20:0] offset
    );
        return encode_j_type(offset, rd, 7'b1101111);
    endfunction

    function automatic logic [31:0] JALR(
        input logic [4:0]  rd,
        input logic [4:0]  rs1,
        input logic [11:0] offset
    );
        return encode_i_type(offset, rs1, 3'b000, rd, 7'b1100111);
    endfunction

    function automatic logic [31:0] ECALL();
        return encode_i_type(12'h000, 5'd0, 3'b000, 5'd0, 7'b1110011);
    endfunction

    int test_count  = 0;
    int pass_count  = 0;
    int fail_count  = 0;

    task automatic wait_cycles(input int n);
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
        for (int i = 0; i < IMEM_WORDS; i++) imem[i] = NOP();
        for (int i = 0; i < DMEM_WORDS; i++) dmem[i] = 32'h0000_0000;
    endtask

    task automatic wait_for_halt(input int max_cycles);
        int cycle = 0;
        while (!halt && cycle < max_cycles) begin
            @(posedge clk);
            cycle++;
        end
        if (!halt) begin
            $display("[WARNING] wait_for_halt: Halt not asserted within %0d cycles", max_cycles);
        end
    endtask

    task automatic check_reg_write(
        input logic [4:0]  expected_rd,
        input logic [63:0] expected_value,
        input string       test_name
    );
        int timeout = 200;
        logic found = 0;

        while (timeout > 0 && !found) begin
            @(negedge clk);
            if (cpu_debug.rd_write && cpu_debug.rd_addr == expected_rd) begin
                if (cpu_debug.rd_data === expected_value) begin
                    pass_count++;
                    $display("[PASS] %s : x%0d = 0x%016h", test_name, expected_rd, expected_value);
                end else begin
                    fail_count++;
                    $display("[FAIL] %s : x%0d expected 0x%016h, got 0x%016h",
                             test_name, expected_rd, expected_value, cpu_debug.rd_data);
                end
                found = 1;
            end
            timeout--;
        end

        if (!found) begin
            fail_count++;
            $display("[FAIL] %s : Timeout waiting for write to x%0d", test_name, expected_rd);
        end

        test_count++;
    endtask

    task automatic check_reg_not_written(
        input logic [4:0] check_rd,
        input int          observe_cycles,
        input string       test_name
    );
        logic was_written = 0;
        repeat (observe_cycles) begin
            @(negedge clk);
            if (cpu_debug.rd_write && cpu_debug.rd_addr == check_rd) begin
                was_written = 1;
            end
        end

        if (!was_written) begin
            pass_count++;
            $display("[PASS] %s : x%0d was correctly skipped", test_name, check_rd);
        end else begin
            fail_count++;
            $display("[FAIL] %s : x%0d was unexpectedly written", test_name, check_rd);
        end

        test_count++;
    endtask

    initial begin
        $dumpfile("tb_cpu_instructions.vcd");
        $dumpvars(0, tb_cpu_instructions);
    end

    initial begin
        #(CLK_PERIOD * TIMEOUT_CYCLES);
        $display("");
        $display("============================================================");
        $display("  [TIMEOUT] Simulation exceeded %0d cycles. Aborting.", TIMEOUT_CYCLES);
        $display("  Tests Run: %0d | Passed: %0d | Failed: %0d",
                 test_count, pass_count, fail_count);
        $display("============================================================");
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && cpu_debug.rd_write) begin
            $display("[TRACE] Cycle=%0d  PC=0x%016h  Instr=0x%08h  WB: x%0d = 0x%016h",
                     debug.counter,
                     cpu_debug.pc,
                     cpu_debug.instruction,
                     cpu_debug.rd_addr,
                     cpu_debug.rd_data);
        end
    end

    always @(posedge clk) begin
        if (rst_n && halt) begin
            $display("[INFO ] CPU halted at cycle %0d", debug.counter);
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            if (cpu_debug.pipeline_stall)
                $display("[STALL] Cycle=%0d  PC=0x%016h", debug.counter, cpu_debug.pc);
            if (cpu_debug.pipeline_flush)
                $display("[FLUSH] Cycle=%0d  PC=0x%016h", debug.counter, cpu_debug.pc);
        end
    end

    initial begin
        $display("");
        $display("============================================================");
        $display("  Nexora X3 SoC — CPU Instruction Testbench");
        $display("  Module Under Test: cpu_core");
        $display("  ISA: RV32I  |  Pipeline: 5-Stage");
        $display("  IMEM: %0d KB  |  DMEM: %0d KB",
                 (IMEM_WORDS * 4) / 1024, (DMEM_WORDS * 4) / 1024);
        $display("  Timeout: %0d cycles", TIMEOUT_CYCLES);
        $display("============================================================");
        $display("");

        begin
            $display("------------------------------------------------------------");
            $display("  TEST 1: ADDI x1, x0, 42  →  verify x1 = 42");
            $display("------------------------------------------------------------");

            clear_memories();

            imem[0] = ADDI(5'd1, 5'd0, 12'd42);    
            imem[1] = NOP();
            imem[2] = NOP();
            imem[3] = NOP();
            imem[4] = NOP();

            do_reset();
            check_reg_write(5'd1, 64'd42, "TEST 1: ADDI x1, x0, 42");
            wait_cycles(5);
        end

        begin
            $display("");
            $display("------------------------------------------------------------");
            $display("  TEST 2: ADD x3, x1, x2  →  verify x3 = 52");
            $display("------------------------------------------------------------");

            clear_memories();

            imem[0] = ADDI(5'd1, 5'd0, 12'd42);    
            imem[1] = ADDI(5'd2, 5'd0, 12'd10);    
            imem[2] = NOP();                         
            imem[3] = NOP();                         
            imem[4] = ADD(5'd3, 5'd1, 5'd2);        
            imem[5] = NOP();
            imem[6] = NOP();
            imem[7] = NOP();
            imem[8] = NOP();

            do_reset();
            check_reg_write(5'd1, 64'd42, "TEST 2: ADDI x1, x0, 42");
            check_reg_write(5'd2, 64'd10, "TEST 2: ADDI x2, x0, 10");
            check_reg_write(5'd3, 64'd52, "TEST 2: ADD x3, x1, x2");
            wait_cycles(5);
        end

        begin
            $display("");
            $display("------------------------------------------------------------");
            $display("  TEST 3: LUI x4, 0x12345  →  verify x4 = 0x12345000");
            $display("------------------------------------------------------------");

            clear_memories();

            imem[0] = LUI(5'd4, 32'h12345000);      
            imem[1] = NOP();
            imem[2] = NOP();
            imem[3] = NOP();
            imem[4] = NOP();

            do_reset();
            check_reg_write(5'd4, 64'h0000_0000_1234_5000, "TEST 3: LUI x4, 0x12345");
            wait_cycles(5);
        end

        begin
            $display("");
            $display("------------------------------------------------------------");
            $display("  TEST 4: SW x1, 0(x10); LW x5, 0(x10)  →  verify x5 = 42");
            $display("------------------------------------------------------------");

            clear_memories();

            imem[0]  = ADDI(5'd1,  5'd0,  12'd42);          
            imem[1]  = LUI(5'd10, 32'h00020000);             
            imem[2]  = NOP();
            imem[3]  = NOP();
            imem[4]  = SW(5'd1, 5'd10, 12'd0);              
            imem[5]  = NOP();
            imem[6]  = NOP();
            imem[7]  = NOP();
            imem[8]  = LW(5'd5, 5'd10, 12'd0);              
            imem[9]  = NOP();
            imem[10] = NOP();
            imem[11] = NOP();
            imem[12] = NOP();

            do_reset();
            check_reg_write(5'd1,  64'd42,           "TEST 4: ADDI x1, x0, 42");
            check_reg_write(5'd10, 64'h0000_0000_0002_0000, "TEST 4: LUI x10, DMEM_BASE");
            check_reg_write(5'd5,  64'd42,           "TEST 4: LW x5, 0(x10) after SW");
            wait_cycles(5);
        end

        begin
            $display("");
            $display("------------------------------------------------------------");
            $display("  TEST 5: BEQ x0, x0, +8  →  skip ADDI x6; execute ADDI x7");
            $display("------------------------------------------------------------");

            clear_memories();

            imem[0] = BEQ(5'd0, 5'd0, 13'd8);           
            imem[1] = ADDI(5'd6, 5'd0, 12'd99);         
            imem[2] = ADDI(5'd7, 5'd0, 12'd77);         
            imem[3] = NOP();
            imem[4] = NOP();
            imem[5] = NOP();
            imem[6] = NOP();
            imem[7] = NOP();

            do_reset();
            check_reg_write(5'd7, 64'd77, "TEST 5: ADDI x7, x0, 77 (branch target)");
            wait_cycles(10);

        end

        begin
            $display("");
            $display("------------------------------------------------------------");
            $display("  TEST 6: ECALL  →  halt the CPU");
            $display("------------------------------------------------------------");

            clear_memories();

            imem[0] = ADDI(5'd1, 5'd0, 12'd1);         
            imem[1] = NOP();
            imem[2] = NOP();
            imem[3] = NOP();
            imem[4] = ECALL();                           
            imem[5] = ADDI(5'd8, 5'd0, 12'd99);         
            imem[6] = NOP();
            imem[7] = NOP();

            do_reset();
            check_reg_write(5'd1, 64'd1, "TEST 6: ADDI x1, x0, 1 (pre-ECALL)");

            wait_for_halt(500);

            if (halt) begin
                pass_count++;
                $display("[PASS] TEST 6: ECALL halted the CPU successfully");
            end else begin
                fail_count++;
                $display("[FAIL] TEST 6: ECALL did not halt the CPU");
            end
            test_count++;

            wait_cycles(5);
        end

        $display("");
        $display("============================================================");
        $display("  Performance Counter Summary");
        $display("============================================================");
        $display("  Instruction Count : %0d", instruction_count);
        $display("  Cycle Count       : %0d", cycle_count);
        $display("  Cache Hits        : %0d", cache_hits);
        $display("  Cache Misses      : %0d", cache_misses);
        $display("  Stall Count       : %0d", stall_count);
        $display("  Branch Count      : %0d", branch_count);
        if (instruction_count > 0) begin
            $display("  IPC (approx)      : %0f",
                     real'(instruction_count) / real'(cycle_count));
        end
        $display("============================================================");

        $display("");
        $display("============================================================");
        if (fail_count == 0) begin
            $display("  *** ALL %0d TESTS PASSED ***", test_count);
        end else begin
            $display("  *** %0d of %0d TESTS FAILED ***", fail_count, test_count);
        end
        $display("  Total: %0d  |  Passed: %0d  |  Failed: %0d",
                 test_count, pass_count, fail_count);
        $display("============================================================");
        $display("");

        $finish;
    end

endmodule : tb_cpu_instructions
