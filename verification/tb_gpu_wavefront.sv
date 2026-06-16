// tb_gpu_wavefront
`timescale 1ns / 1ps

module tb_gpu_wavefront;

    import nexora_x3_pkg::*;

    localparam int TIMEOUT_CYCLES  = 20_000;
    localparam int CLK_PERIOD_NS   = 10;
    localparam int MEM_RESP_DELAY  = 2;        
    localparam int NUM_WARPS       = 4;
    localparam int KERNEL_LENGTH   = 8;        

    localparam logic [3:0] GPU_NOP  = 4'h0;
    localparam logic [3:0] GPU_IADD = 4'h1;
    localparam logic [3:0] GPU_IMUL = 4'h2;
    localparam logic [3:0] GPU_FADD = 4'h3;
    localparam logic [3:0] GPU_FMUL = 4'h4;
    localparam logic [3:0] GPU_LD   = 4'h5;
    localparam logic [3:0] GPU_ST   = 4'h6;
    localparam logic [3:0] GPU_LDS  = 4'h7;
    localparam logic [3:0] GPU_STS  = 4'h8;
    localparam logic [3:0] GPU_BAR  = 4'h9;
    localparam logic [3:0] GPU_BRA  = 4'hA;
    localparam logic [3:0] GPU_EXIT = 4'hB;
    localparam logic [3:0] GPU_PIM  = 4'hC;

    localparam logic [1:0] WARP_IDLE    = 2'd0;
    localparam logic [1:0] WARP_RUNNING = 2'd1;
    localparam logic [1:0] WARP_STALLED = 2'd2;
    localparam logic [1:0] WARP_DONE    = 2'd3;

    logic clk;
    logic rst_n;

    initial clk = 1'b0;
    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    mem_req_t   mem_req;
    mem_resp_t  mem_resp;
    logic       pim_cmd_valid;
    logic       pim_cmd_ready;
    logic [2:0] pim_cmd_op;
    logic [63:0] pim_cmd_addr_a;
    logic [63:0] pim_cmd_addr_b;
    logic [63:0] pim_cmd_addr_dst;

    gpu_cluster #(
        .CLUSTER_ID (0)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .mem_req         (mem_req),
        .mem_resp        (mem_resp),
        .pim_cmd_valid   (pim_cmd_valid),
        .pim_cmd_ready   (pim_cmd_ready),
        .pim_cmd_op      (pim_cmd_op),
        .pim_cmd_addr_a  (pim_cmd_addr_a),
        .pim_cmd_addr_b  (pim_cmd_addr_b),
        .pim_cmd_addr_dst(pim_cmd_addr_dst)
    );

    assign pim_cmd_ready = 1'b0;

    logic [1:0] mem_delay_cnt;
    logic       mem_pending;
    logic [63:0] mem_saved_addr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_resp.ready  <= 1'b0;
            mem_resp.rdata  <= 64'h0;
            mem_resp.error  <= 1'b0;
            mem_delay_cnt   <= '0;
            mem_pending     <= 1'b0;
            mem_saved_addr  <= 64'h0;
        end else begin

            mem_resp.ready <= 1'b0;
            mem_resp.error <= 1'b0;

            if (mem_pending) begin
                if (mem_delay_cnt == MEM_RESP_DELAY[1:0] - 1) begin
                    mem_resp.ready <= 1'b1;
                    mem_resp.rdata <= mem_saved_addr ^ 64'hDEAD_BEEF_CAFE_0000;
                    mem_pending    <= 1'b0;
                    mem_delay_cnt  <= '0;
                end else begin
                    mem_delay_cnt <= mem_delay_cnt + 1;
                end
            end else if (mem_req.read_en || mem_req.write_en) begin
                mem_pending    <= 1'b1;
                mem_saved_addr <= mem_req.addr;
                mem_delay_cnt  <= '0;
            end
        end
    end

    initial begin
        $dumpfile("tb_gpu_wavefront.vcd");
        $dumpvars(0, tb_gpu_wavefront);
    end

    initial begin
        repeat (TIMEOUT_CYCLES) @(posedge clk);
        $display("\n[TIMEOUT] Simulation exceeded %0d cycles — aborting!", TIMEOUT_CYCLES);
        $display("[RESULT ] *** FAIL ***\n");
        $finish;
    end

    function automatic string opcode_name(logic [3:0] op);
        case (op)
            GPU_NOP:  return "NOP";
            GPU_IADD: return "IADD";
            GPU_IMUL: return "IMUL";
            GPU_FADD: return "FADD";
            GPU_FMUL: return "FMUL";
            GPU_LD:   return "LD";
            GPU_ST:   return "ST";
            GPU_LDS:  return "LDS";
            GPU_STS:  return "STS";
            GPU_BAR:  return "BAR";
            GPU_BRA:  return "BRA";
            GPU_EXIT: return "EXIT";
            GPU_PIM:  return "PIM";
            default:  return "UNKNOWN";
        endcase
    endfunction

    function automatic string warp_state_name(logic [1:0] st);
        case (st)
            WARP_IDLE:    return "IDLE";
            WARP_RUNNING: return "RUNNING";
            WARP_STALLED: return "STALLED";
            WARP_DONE:    return "DONE";
            default:      return "???";
        endcase
    endfunction

    always @(posedge clk) begin
        if (rst_n && dut.dec_valid) begin
            $display("[%0t] DECODE: warp=%0d  PC=0x%08h  op=%s (%0d)",
                     $time,
                     dut.sched_warp,
                     dut.warp_state_pc[dut.sched_warp],
                     opcode_name(dut.dec_instr.op),
                     dut.dec_instr.op);
        end
    end

    logic [1:0] prev_warp_state [NUM_WARPS];

    initial begin
        for (int i = 0; i < NUM_WARPS; i++)
            prev_warp_state[i] = WARP_IDLE;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            for (int w = 0; w < NUM_WARPS; w++) begin
                if (dut.warp_state_state[w] !== prev_warp_state[w]) begin
                    $display("[%0t] WARP %0d: %s -> %s",
                             $time, w,
                             warp_state_name(prev_warp_state[w]),
                             warp_state_name(dut.warp_state_state[w]));
                    prev_warp_state[w] <= dut.warp_state_state[w];
                end
            end
        end
    end

    int pass_count;
    int fail_count;
    int total_tests;

    task automatic check(string test_name, logic condition);
        total_tests++;
        if (condition) begin
            pass_count++;
            $display("[PASS] %s", test_name);
        end else begin
            fail_count++;
            $display("[FAIL] %s", test_name);
        end
    endtask

    initial begin

        pass_count  = 0;
        fail_count  = 0;
        total_tests = 0;

        $display("============================================================");
        $display(" tb_gpu_wavefront — GPU Wavefront Scheduling Testbench");
        $display(" Nexora X3 SoC Verification");
        $display("============================================================");
        $display("[%0t] Applying reset...", $time);

        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        $display("[%0t] Reset de-asserted.", $time);

        $display("\n--- TEST 1: Warp 0 IDLE -> RUNNING ---");
        repeat (2) @(posedge clk);
        check("TEST 1: Warp 0 is RUNNING after reset",
              dut.warp_state_state[0] == WARP_RUNNING);

        $display("\n--- TEST 2: Scheduler issues valid instruction ---");
        begin
            logic seen_valid;
            seen_valid = 1'b0;
            for (int cyc = 0; cyc < 50; cyc++) begin
                @(posedge clk);
                if (dut.sched_valid) begin
                    seen_valid = 1'b1;
                    $display("[%0t] Scheduler issued instruction on warp %0d",
                             $time, dut.sched_warp);
                    break;
                end
            end
            check("TEST 2: sched_valid asserted within 50 cycles", seen_valid);
        end

        $display("\n--- TEST 3: PC advancement through kernel ---");
        begin
            logic [31:0] max_pc_seen;
            max_pc_seen = 32'h0;

            for (int cyc = 0; cyc < 5000; cyc++) begin
                @(posedge clk);
                if (dut.warp_state_pc[0] > max_pc_seen)
                    max_pc_seen = dut.warp_state_pc[0];

                if (dut.warp_state_state[0] == WARP_DONE)
                    break;
            end
            $display("[%0t] Maximum PC observed for warp 0: %0d", $time, max_pc_seen);
            check("TEST 3: PC advanced to at least instruction 7",
                  max_pc_seen >= 32'd7);
        end

        $display("\n--- TEST 4: GPU_LDS (shared memory read) decoded ---");

        begin

            rst_n = 1'b0;
            repeat (5) @(posedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);

            logic lds_seen;
            lds_seen = 1'b0;
            for (int cyc = 0; cyc < 5000; cyc++) begin
                @(posedge clk);
                if (dut.dec_valid && dut.dec_instr.op == GPU_LDS) begin
                    lds_seen = 1'b1;
                    $display("[%0t] GPU_LDS decoded — shared memory read triggered", $time);
                    break;
                end
            end
            check("TEST 4: GPU_LDS (opcode 7) was decoded", lds_seen);
        end

        $display("\n--- TEST 5: GPU_STS (shared memory write) decoded ---");
        begin
            logic sts_seen;
            sts_seen = 1'b0;
            for (int cyc = 0; cyc < 5000; cyc++) begin
                @(posedge clk);
                if (dut.dec_valid && dut.dec_instr.op == GPU_STS) begin
                    sts_seen = 1'b1;
                    $display("[%0t] GPU_STS decoded — shared memory write triggered", $time);
                    break;
                end
            end
            check("TEST 5: GPU_STS (opcode 8) was decoded", sts_seen);
        end

        $display("\n--- TEST 6: GPU_BAR (barrier sync) decoded ---");
        begin
            logic bar_seen;
            logic warp_running_at_bar;
            bar_seen = 1'b0;
            warp_running_at_bar = 1'b0;
            for (int cyc = 0; cyc < 5000; cyc++) begin
                @(posedge clk);
                if (dut.dec_valid && dut.dec_instr.op == GPU_BAR) begin
                    bar_seen = 1'b1;
                    warp_running_at_bar =
                        (dut.warp_state_state[dut.sched_warp] == WARP_RUNNING);
                    $display("[%0t] GPU_BAR decoded on warp %0d, state=%s",
                             $time, dut.sched_warp,
                             warp_state_name(dut.warp_state_state[dut.sched_warp]));
                    break;
                end
            end
            check("TEST 6a: GPU_BAR (opcode 9) was decoded", bar_seen);
            check("TEST 6b: Warp remains RUNNING at barrier", warp_running_at_bar);
        end

        $display("\n--- TEST 7: GPU_EXIT decoded — warp → DONE ---");
        begin
            logic exit_seen;
            exit_seen = 1'b0;
            for (int cyc = 0; cyc < 5000; cyc++) begin
                @(posedge clk);
                if (dut.dec_valid && dut.dec_instr.op == GPU_EXIT) begin
                    exit_seen = 1'b1;
                    $display("[%0t] GPU_EXIT decoded on warp %0d", $time, dut.sched_warp);
                    break;
                end
            end
            check("TEST 7a: GPU_EXIT (opcode 0xB) was decoded", exit_seen);

            repeat (5) @(posedge clk);
            check("TEST 7b: Warp 0 transitioned to DONE after EXIT",
                  dut.warp_state_state[0] == WARP_DONE);
        end

        $display("\n--- TEST 8: Instruction counter after kernel completion ---");
        begin
            logic [31:0] instr_count;
            instr_count = dut.total_instructions;
            $display("[%0t] total_instructions = %0d", $time, instr_count);
            check("TEST 8: total_instructions > 0 after kernel execution",
                  instr_count > 0);
        end

        $display("\n--- TEST 9: warps_active drops to 0 ---");
        begin
            logic active_zero;
            active_zero = 1'b0;

            for (int cyc = 0; cyc < 100; cyc++) begin
                @(posedge clk);
                if (dut.warps_active == 2'd0) begin
                    active_zero = 1'b1;
                    break;
                end
            end
            $display("[%0t] warps_active = %0d", $time, dut.warps_active);
            check("TEST 9: warps_active == 0 after all warps exit", active_zero);
        end

        $display("\n============================================================");
        $display(" TEST SUMMARY");
        $display("============================================================");
        $display("  Total : %0d", total_tests);
        $display("  Passed: %0d", pass_count);
        $display("  Failed: %0d", fail_count);
        $display("------------------------------------------------------------");

        if (fail_count == 0) begin
            $display("[RESULT] *** PASS — All %0d tests passed ***", total_tests);
        end else begin
            $display("[RESULT] *** FAIL — %0d of %0d tests failed ***",
                     fail_count, total_tests);
        end

        $display("============================================================\n");
        $finish;
    end

endmodule
