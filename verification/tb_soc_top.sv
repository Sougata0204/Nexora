// tb_soc_top.sv
// Complete SystemVerilog Testbench for Nexora X3 Heterogeneous AI SoC
// Target: Vivado Simulator (xsim)
// Coverage: Full AXI4 memory model, CPU/GPU/Tensor monitoring,
//           JTAG stimulus, heartbeat tracking, self-checking pass/fail.
`timescale 1ns / 1ps

import nexora_x3_pkg::*;

module tb_soc_top;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam real   CLK_PERIOD_NS   = 10.0;          // 100 MHz
    localparam real   JTAG_PERIOD_NS  = 100.0;         // 10 MHz TCK
    localparam int    TIMEOUT_CYCLES  = 500_000;       // Simulation timeout
    localparam int    HBM_DEPTH       = 65536;         // 128-bit words
    localparam int    MEM_LOAD_OFFSET = 4096;          // fibonacci.mem load offset
    localparam string MEM_FILE        = "D:/verilog_practice/CPU/Nexora_X1_Vivado/verification/fibonacci.mem";

    // =========================================================================
    // Clock and Reset
    // =========================================================================
    logic clk;
    logic rst_n;

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS / 2.0) clk = ~clk;
    end

    // =========================================================================
    // JTAG Signals
    // =========================================================================
    logic tck;
    logic tms;
    logic tdi;
    logic tdo;

    initial tck = 1'b0;
    initial tms = 1'b0;
    initial tdi = 1'b0;

    // =========================================================================
    // AXI4 HBM Interface Signals
    // =========================================================================
    // Write Address Channel
    logic [nexora_x3_pkg::AXI_ID_WIDTH-1:0]   m_axi_hbm_awid;
    logic [nexora_x3_pkg::AXI_ADDR_WIDTH-1:0] m_axi_hbm_awaddr;
    logic [7:0]                               m_axi_hbm_awlen;
    logic [2:0]                               m_axi_hbm_awsize;
    logic [1:0]                               m_axi_hbm_awburst;
    logic                                     m_axi_hbm_awvalid;
    logic                                     m_axi_hbm_awready;

    // Write Data Channel
    logic [nexora_x3_pkg::AXI_DATA_WIDTH-1:0]     m_axi_hbm_wdata;
    logic [(nexora_x3_pkg::AXI_DATA_WIDTH/8)-1:0] m_axi_hbm_wstrb;
    logic                                         m_axi_hbm_wlast;
    logic                                         m_axi_hbm_wvalid;
    logic                                         m_axi_hbm_wready;

    // Write Response Channel
    logic [nexora_x3_pkg::AXI_ID_WIDTH-1:0]   m_axi_hbm_bid;
    logic [1:0]                               m_axi_hbm_bresp;
    logic                                     m_axi_hbm_bvalid;
    logic                                     m_axi_hbm_bready;

    // Read Address Channel
    logic [nexora_x3_pkg::AXI_ID_WIDTH-1:0]   m_axi_hbm_arid;
    logic [nexora_x3_pkg::AXI_ADDR_WIDTH-1:0] m_axi_hbm_araddr;
    logic [7:0]                               m_axi_hbm_arlen;
    logic [2:0]                               m_axi_hbm_arsize;
    logic [1:0]                               m_axi_hbm_arburst;
    logic                                     m_axi_hbm_arvalid;
    logic                                     m_axi_hbm_arready;

    // Read Data Channel
    logic [nexora_x3_pkg::AXI_ID_WIDTH-1:0]   m_axi_hbm_rid;
    logic [nexora_x3_pkg::AXI_DATA_WIDTH-1:0] m_axi_hbm_rdata;
    logic [1:0]                               m_axi_hbm_rresp;
    logic                                     m_axi_hbm_rlast;
    logic                                     m_axi_hbm_rvalid;
    logic                                     m_axi_hbm_rready;

    // =========================================================================
    // Peripheral Signals
    // =========================================================================
    logic uart_tx;
    logic uart_rx;
    logic status_alive;
    logic status_cpu_halt;
    logic status_gpu_active;
    logic status_tensor_busy;

    initial uart_rx = 1'b1; // UART idle state

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    nexora_x3_soc_top dut (
        .clk                (clk),
        .rst_n              (rst_n),
        // JTAG
        .tck                (tck),
        .tms                (tms),
        .tdi                (tdi),
        .tdo                (tdo),
        // AXI4 HBM - Write Address
        .m_axi_hbm_awid    (m_axi_hbm_awid),
        .m_axi_hbm_awaddr  (m_axi_hbm_awaddr),
        .m_axi_hbm_awlen   (m_axi_hbm_awlen),
        .m_axi_hbm_awsize  (m_axi_hbm_awsize),
        .m_axi_hbm_awburst (m_axi_hbm_awburst),
        .m_axi_hbm_awvalid (m_axi_hbm_awvalid),
        .m_axi_hbm_awready (m_axi_hbm_awready),
        // AXI4 HBM - Write Data
        .m_axi_hbm_wdata   (m_axi_hbm_wdata),
        .m_axi_hbm_wstrb   (m_axi_hbm_wstrb),
        .m_axi_hbm_wlast   (m_axi_hbm_wlast),
        .m_axi_hbm_wvalid  (m_axi_hbm_wvalid),
        .m_axi_hbm_wready  (m_axi_hbm_wready),
        // AXI4 HBM - Write Response
        .m_axi_hbm_bid     (m_axi_hbm_bid),
        .m_axi_hbm_bresp   (m_axi_hbm_bresp),
        .m_axi_hbm_bvalid  (m_axi_hbm_bvalid),
        .m_axi_hbm_bready  (m_axi_hbm_bready),
        // AXI4 HBM - Read Address
        .m_axi_hbm_arid    (m_axi_hbm_arid),
        .m_axi_hbm_araddr  (m_axi_hbm_araddr),
        .m_axi_hbm_arlen   (m_axi_hbm_arlen),
        .m_axi_hbm_arsize  (m_axi_hbm_arsize),
        .m_axi_hbm_arburst (m_axi_hbm_arburst),
        .m_axi_hbm_arvalid (m_axi_hbm_arvalid),
        .m_axi_hbm_arready (m_axi_hbm_arready),
        // AXI4 HBM - Read Data
        .m_axi_hbm_rid     (m_axi_hbm_rid),
        .m_axi_hbm_rdata   (m_axi_hbm_rdata),
        .m_axi_hbm_rresp   (m_axi_hbm_rresp),
        .m_axi_hbm_rlast   (m_axi_hbm_rlast),
        .m_axi_hbm_rvalid  (m_axi_hbm_rvalid),
        .m_axi_hbm_rready  (m_axi_hbm_rready),
        // Peripherals
        .uart_tx            (uart_tx),
        .uart_rx            (uart_rx),
        // Status
        .status_alive       (status_alive),
        .status_cpu_halt    (status_cpu_halt),
        .status_gpu_active  (status_gpu_active),
        .status_tensor_busy (status_tensor_busy)
    );

    // =========================================================================
    //  AXI4 SLAVE MEMORY MODEL
    //  - 128-bit wide, 64K-deep DRAM array
    //  - Full write-channel with WSTRB byte-lane masking
    //  - Full read-channel with burst support
    // =========================================================================
    logic [127:0] hbm_dram [0:HBM_DEPTH-1];

    // --- Statistics ---
    int unsigned axi_rd_txn_cnt;
    int unsigned axi_wr_txn_cnt;

    // --- Initialization: fill with NOP (addi x0,x0,0) and load fibonacci.mem ---
    initial begin
        for (int i = 0; i < HBM_DEPTH; i++) begin
            // Four packed RV32I NOP instructions per 128-bit word
            hbm_dram[i] = {32'h0000_0013, 32'h0000_0013, 32'h0000_0013, 32'h0000_0013};
        end
        $readmemh(MEM_FILE, hbm_dram, MEM_LOAD_OFFSET);
        $display("[TB MEM] Loaded %s at offset %0d (addr 0x%h)",
                 MEM_FILE, MEM_LOAD_OFFSET, MEM_LOAD_OFFSET * 16);
        axi_rd_txn_cnt = 0;
        axi_wr_txn_cnt = 0;
    end

    // ---- Write Address Channel: Latch AW info ----
    logic                                     aw_pending;
    logic [nexora_x3_pkg::AXI_ID_WIDTH-1:0]   aw_id_lat;
    logic [nexora_x3_pkg::AXI_ADDR_WIDTH-1:0] aw_addr_lat;
    logic [7:0]                               aw_len_lat;
    logic [2:0]                               aw_size_lat;
    logic [1:0]                               aw_burst_lat;
    logic [7:0]                               aw_beat_cnt;

    assign m_axi_hbm_awready = !aw_pending || (m_axi_hbm_wvalid && m_axi_hbm_wready && m_axi_hbm_wlast);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_pending   <= 1'b0;
            aw_id_lat    <= '0;
            aw_addr_lat  <= '0;
            aw_len_lat   <= 8'h0;
            aw_size_lat  <= 3'h0;
            aw_burst_lat <= 2'h0;
            aw_beat_cnt  <= 8'h0;
        end else begin
            if (m_axi_hbm_awvalid && m_axi_hbm_awready) begin
                aw_pending   <= 1'b1;
                aw_id_lat    <= m_axi_hbm_awid;
                aw_addr_lat  <= m_axi_hbm_awaddr;
                aw_len_lat   <= m_axi_hbm_awlen;
                aw_size_lat  <= m_axi_hbm_awsize;
                aw_burst_lat <= m_axi_hbm_awburst;
                aw_beat_cnt  <= 8'h0;
            end
            if (m_axi_hbm_wvalid && m_axi_hbm_wready && m_axi_hbm_wlast) begin
                aw_pending <= 1'b0;
            end
        end
    end

    // ---- Write Data Channel: Apply WSTRB byte-masking ----
    assign m_axi_hbm_wready = aw_pending;

    always_ff @(posedge clk) begin
        if (rst_n && m_axi_hbm_wvalid && m_axi_hbm_wready) begin
            automatic logic [nexora_x3_pkg::AXI_ADDR_WIDTH-1:0] beat_addr;
            automatic logic [19:0] mem_idx;
            automatic logic [127:0] old_data;
            automatic logic [127:0] new_data;

            // Compute beat address (INCR burst)
            beat_addr = aw_addr_lat + ({56'b0, aw_beat_cnt} << aw_size_lat);
            mem_idx   = beat_addr[19:4]; // 128-bit word index

            // Read-modify-write with byte-lane strobes
            old_data = hbm_dram[mem_idx];
            new_data = old_data;
            for (int b = 0; b < 16; b++) begin
                if (m_axi_hbm_wstrb[b])
                    new_data[b*8 +: 8] = m_axi_hbm_wdata[b*8 +: 8];
            end
            hbm_dram[mem_idx] = new_data;

            aw_beat_cnt <= aw_beat_cnt + 8'h1;
            axi_wr_txn_cnt = axi_wr_txn_cnt + 1;
        end
    end

    // ---- Write Response Channel ----
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_hbm_bvalid <= 1'b0;
            m_axi_hbm_bid    <= '0;
            m_axi_hbm_bresp  <= 2'b00;
        end else begin
            if (m_axi_hbm_wvalid && m_axi_hbm_wready && m_axi_hbm_wlast) begin
                m_axi_hbm_bvalid <= 1'b1;
                m_axi_hbm_bid    <= aw_id_lat;
                m_axi_hbm_bresp  <= 2'b00; // OKAY
            end else if (m_axi_hbm_bvalid && m_axi_hbm_bready) begin
                m_axi_hbm_bvalid <= 1'b0;
            end
        end
    end

    // ---- Read Address & Data Channel ----
    logic                                     rd_pending;
    logic [nexora_x3_pkg::AXI_ADDR_WIDTH-1:0] rd_addr_lat;
    logic [7:0]                               rd_len_lat;
    logic [2:0]                               rd_size_lat;
    logic [1:0]                               rd_burst_lat;
    logic [nexora_x3_pkg::AXI_ID_WIDTH-1:0]   rd_id_lat;
    logic [7:0]                               rd_beat_cnt;

    assign m_axi_hbm_arready = !rd_pending;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_pending       <= 1'b0;
            rd_addr_lat      <= '0;
            rd_len_lat       <= 8'h0;
            rd_size_lat      <= 3'h0;
            rd_burst_lat     <= 2'h0;
            rd_id_lat        <= '0;
            rd_beat_cnt      <= 8'h0;
            m_axi_hbm_rvalid <= 1'b0;
            m_axi_hbm_rdata  <= '0;
            m_axi_hbm_rlast  <= 1'b0;
            m_axi_hbm_rresp  <= 2'b00;
            m_axi_hbm_rid    <= '0;
        end else begin
            if (m_axi_hbm_arvalid && m_axi_hbm_arready) begin
                // Latch read request
                rd_pending   <= 1'b1;
                rd_addr_lat  <= m_axi_hbm_araddr;
                rd_len_lat   <= m_axi_hbm_arlen;
                rd_size_lat  <= m_axi_hbm_arsize;
                rd_burst_lat <= m_axi_hbm_arburst;
                rd_id_lat    <= m_axi_hbm_arid;
                rd_beat_cnt  <= 8'h0;

                // Immediately present first beat
                m_axi_hbm_rvalid <= 1'b1;
                m_axi_hbm_rid    <= m_axi_hbm_arid;
                m_axi_hbm_rresp  <= 2'b00;
                m_axi_hbm_rlast  <= (m_axi_hbm_arlen == 8'h0);
                m_axi_hbm_rdata  <= hbm_dram[m_axi_hbm_araddr[19:4]];
                axi_rd_txn_cnt    = axi_rd_txn_cnt + 1;

            end else if (m_axi_hbm_rvalid && m_axi_hbm_rready) begin
                if (m_axi_hbm_rlast) begin
                    // Transaction complete
                    m_axi_hbm_rvalid <= 1'b0;
                    rd_pending       <= 1'b0;
                end else begin
                    // Next beat
                    rd_beat_cnt <= rd_beat_cnt + 8'h1;
                    m_axi_hbm_rlast <= ((rd_beat_cnt + 8'h1) == rd_len_lat);
                    m_axi_hbm_rdata <= hbm_dram[rd_addr_lat[19:4] + {12'h0, rd_beat_cnt} + 20'h1];
                end
            end
        end
    end

    // =========================================================================
    //  JTAG STIMULUS DRIVER
    // =========================================================================
    task automatic jtag_tick();
        #(JTAG_PERIOD_NS / 2.0) tck = 1'b1;
        #(JTAG_PERIOD_NS / 2.0) tck = 1'b0;
    endtask

    task automatic jtag_reset();
        // Hold TMS high for 5 TCK cycles to enter Test-Logic-Reset
        tms = 1'b1;
        repeat (5) jtag_tick();
        // Go to Run-Test/Idle
        tms = 1'b0;
        jtag_tick();
        $display("[TB JTAG] @%0t: JTAG TAP reset complete, TDO=%b", $time, tdo);
    endtask

    task automatic jtag_shift_pattern(input int num_bits, input logic [31:0] pattern);
        $display("[TB JTAG] @%0t: Shifting %0d-bit pattern 0x%h", $time, num_bits, pattern);
        for (int i = 0; i < num_bits; i++) begin
            tdi = pattern[i];
            tms = (i == num_bits - 1) ? 1'b1 : 1'b0; // Exit on last bit
            jtag_tick();
        end
        // Return to Run-Test/Idle
        tms = 1'b1; jtag_tick(); // Update-DR/IR
        tms = 1'b0; jtag_tick(); // Run-Test/Idle
    endtask

    // =========================================================================
    //  UART TX MONITOR (watch for any non-idle transitions from DUT)
    // =========================================================================
    logic uart_tx_prev;
    int   uart_tx_toggle_cnt;

    initial uart_tx_toggle_cnt = 0;

    always_ff @(posedge clk) begin
        if (rst_n) begin
            uart_tx_prev <= uart_tx;
            if (uart_tx !== uart_tx_prev && uart_tx_prev !== 1'bx) begin
                uart_tx_toggle_cnt <= uart_tx_toggle_cnt + 1;
                if (uart_tx_toggle_cnt < 5) // Print first few only
                    $display("[TB UART TX] @%0t: uart_tx toggled to %b", $time, uart_tx);
            end
        end
    end

    // =========================================================================
    //  HEARTBEAT (status_alive) MONITOR
    // =========================================================================
    int heartbeat_cnt;

    initial heartbeat_cnt = 0;

    always @(posedge status_alive) begin
        heartbeat_cnt = heartbeat_cnt + 1;
        if (heartbeat_cnt <= 3)
            $display("[TB HEARTBEAT] @%0t: SoC alive pulse #%0d", $time, heartbeat_cnt);
    end

    // =========================================================================
    //  CPU CORE 0 EXECUTION MONITOR
    // =========================================================================
    logic [63:0] mon_last_pc;
    int          mon_pc_change_cnt;

    initial begin
        mon_last_pc       = 64'hFFFF_FFFF_FFFF_FFFF;
        mon_pc_change_cnt = 0;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            // Hierarchical probe into DUT core 0
            automatic logic [63:0] core0_pc      = dut.cpu_clusters[0].gen_active.u_cpu_cluster.quads[0].u_quad.cores[0].u_core.cpu_debug.pc;
            automatic logic [31:0] core0_instr   = dut.cpu_clusters[0].gen_active.u_cpu_cluster.quads[0].u_quad.cores[0].u_core.cpu_debug.instruction;
            automatic logic [31:0] core0_cycles  = dut.cpu_clusters[0].gen_active.u_cpu_cluster.quads[0].u_quad.cores[0].u_core.cycle_count;
            automatic logic [31:0] core0_retired = dut.cpu_clusters[0].gen_active.u_cpu_cluster.quads[0].u_quad.cores[0].u_core.instruction_count;
            automatic logic        core0_halt    = dut.cpu_clusters[0].gen_active.u_cpu_cluster.quads[0].u_quad.cores[0].u_core.halt;
            automatic logic [31:0] core0_chits   = dut.cpu_clusters[0].gen_active.u_cpu_cluster.quads[0].u_quad.cores[0].u_core.cache_hits;
            automatic logic [31:0] core0_cmiss   = dut.cpu_clusters[0].gen_active.u_cpu_cluster.quads[0].u_quad.cores[0].u_core.cache_misses;
            automatic logic [31:0] core0_stalls  = dut.cpu_clusters[0].gen_active.u_cpu_cluster.quads[0].u_quad.cores[0].u_core.stall_count;
            automatic logic [31:0] core0_branches= dut.cpu_clusters[0].gen_active.u_cpu_cluster.quads[0].u_quad.cores[0].u_core.branch_count;

            if (core0_pc !== mon_last_pc && !$isunknown(core0_pc)) begin
                mon_pc_change_cnt = mon_pc_change_cnt + 1;
                // Print first 50 and then every 100th
                if (mon_pc_change_cnt <= 50 || (mon_pc_change_cnt % 100 == 0))
                    $display("[CPU0] @%0t: PC=0x%h Instr=0x%h Cyc=%0d Ret=%0d Halt=%b",
                        $time, core0_pc, core0_instr, core0_cycles, core0_retired, core0_halt);
                mon_last_pc <= core0_pc;
            end

            // Print performance summary when core halts
            if (core0_halt && !$isunknown(core0_halt)) begin
                if (mon_last_pc !== 64'hDEAD_BEEF_DEAD_BEEF) begin
                    $display("=========================================================");
                    $display("[CPU0 HALT] @%0t: Core 0 halted (ECALL detected)", $time);
                    $display("  Cycle Count      : %0d", core0_cycles);
                    $display("  Instructions Ret : %0d", core0_retired);
                    $display("  Cache Hits       : %0d", core0_chits);
                    $display("  Cache Misses     : %0d", core0_cmiss);
                    $display("  Pipeline Stalls  : %0d", core0_stalls);
                    $display("  Branches Taken   : %0d", core0_branches);
                    if (core0_cycles > 0)
                        $display("  IPC              : %0f", real'(core0_retired) / real'(core0_cycles));
                    $display("=========================================================");
                    mon_last_pc <= 64'hDEAD_BEEF_DEAD_BEEF; // Sentinel to print only once
                end
            end
        end
    end

    // =========================================================================
    //  GPU STATUS MONITOR
    // =========================================================================
    logic gpu_active_prev;

    always_ff @(posedge clk) begin
        if (rst_n) begin
            gpu_active_prev <= status_gpu_active;
            if (status_gpu_active !== gpu_active_prev && gpu_active_prev !== 1'bx)
                $display("[GPU STATUS] @%0t: gpu_active = %b", $time, status_gpu_active);
        end
    end

    // =========================================================================
    //  TENSOR STATUS MONITOR
    // =========================================================================
    logic tensor_busy_prev;

    always_ff @(posedge clk) begin
        if (rst_n) begin
            tensor_busy_prev <= status_tensor_busy;
            if (status_tensor_busy !== tensor_busy_prev && tensor_busy_prev !== 1'bx)
                $display("[TENSOR STATUS] @%0t: tensor_busy = %b", $time, status_tensor_busy);
        end
    end

    // =========================================================================
    //  AXI TRANSACTION LOGGER
    // =========================================================================
    always @(posedge clk) begin
        if (rst_n) begin
            // Log AXI read address
            if (m_axi_hbm_arvalid && m_axi_hbm_arready) begin
                if (axi_rd_txn_cnt <= 30) // Limit output
                    $display("[AXI RD] @%0t: ARADDR=0x%h ARLEN=%0d ARSIZE=%0d ARBURST=%0d",
                        $time, m_axi_hbm_araddr, m_axi_hbm_arlen, m_axi_hbm_arsize, m_axi_hbm_arburst);
            end

            // Log AXI write address
            if (m_axi_hbm_awvalid && m_axi_hbm_awready) begin
                if (axi_wr_txn_cnt <= 30)
                    $display("[AXI WR] @%0t: AWADDR=0x%h AWLEN=%0d AWSIZE=%0d AWBURST=%0d",
                        $time, m_axi_hbm_awaddr, m_axi_hbm_awlen, m_axi_hbm_awsize, m_axi_hbm_awburst);
            end

            // Log AXI write data beats
            if (m_axi_hbm_wvalid && m_axi_hbm_wready) begin
                if (axi_wr_txn_cnt <= 10)
                    $display("[AXI WR DATA] @%0t: WDATA=0x%h WSTRB=0x%h WLAST=%b",
                        $time, m_axi_hbm_wdata, m_axi_hbm_wstrb, m_axi_hbm_wlast);
            end
        end
    end

    // =========================================================================
    //  NOC TRAFFIC MONITOR (channel 0)
    // =========================================================================
    int noc_req_cnt;
    initial noc_req_cnt = 0;

    always @(posedge clk) begin
        if (rst_n) begin
            if (dut.u_noc.mem_req[0].read_en || dut.u_noc.mem_req[0].write_en) begin
                noc_req_cnt = noc_req_cnt + 1;
                if (noc_req_cnt <= 20)
                    $display("[NOC CH0] @%0t: addr=0x%h rd=%b wr=%b",
                        $time, dut.u_noc.mem_req[0].addr,
                        dut.u_noc.mem_req[0].read_en,
                        dut.u_noc.mem_req[0].write_en);
            end
        end
    end

    // =========================================================================
    //  MAIN STIMULUS SEQUENCE
    // =========================================================================
    int          sim_cycle_cnt;
    logic        test_passed;
    logic        cpu_halt_seen;
    logic [31:0] halt_wait_timer;

    initial begin
        $display("=========================================================================");
        $display("   NEXORA X3 - HETEROGENEOUS AI PROCESSOR SoC TESTBENCH");
        $display("   Simulation started at %0t", $time);
        $display("   Timeout set to %0d clock cycles", TIMEOUT_CYCLES);
        $display("=========================================================================");

        // ---- Defaults ----
        test_passed    = 1'b0;
        cpu_halt_seen  = 1'b0;
        halt_wait_timer= 32'h0;
        sim_cycle_cnt  = 0;

        // ---- Reset ----
        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        $display("[TB] @%0t: Reset de-asserted", $time);

        // ---- Run JTAG sanity check ----
        repeat (10) @(posedge clk);
        jtag_reset();
        jtag_shift_pattern(8, 32'hA5); // Shift arbitrary IR pattern
        jtag_shift_pattern(16, 32'hCAFE); // Shift arbitrary DR pattern
        $display("[TB JTAG] @%0t: JTAG sanity stimulus complete", $time);

        // ---- Main simulation loop: wait for CPU halt or timeout ----
        forever begin
            @(posedge clk);
            sim_cycle_cnt = sim_cycle_cnt + 1;

            // Check for CPU halt
            if (status_cpu_halt && !cpu_halt_seen) begin
                cpu_halt_seen = 1'b1;
                $display("[TB] @%0t: CPU halt detected at cycle %0d", $time, sim_cycle_cnt);
                // Wait a few more cycles for pipeline to drain
                halt_wait_timer = 32'h0;
            end

            // After halt detected, wait 200 cycles then finish
            if (cpu_halt_seen) begin
                halt_wait_timer = halt_wait_timer + 1;
                if (halt_wait_timer >= 200) begin
                    test_passed = 1'b1;
                    break;
                end
            end

            // Timeout check
            if (sim_cycle_cnt >= TIMEOUT_CYCLES) begin
                $display("[TB TIMEOUT] @%0t: Simulation timed out after %0d cycles", $time, sim_cycle_cnt);
                test_passed = 1'b0;
                break;
            end
        end

        // ---- Final Report ----
        $display("");
        $display("=========================================================================");
        $display("   FINAL SIMULATION REPORT");
        $display("=========================================================================");
        $display("   Total Simulation Cycles : %0d", sim_cycle_cnt);
        $display("   AXI Read Transactions   : %0d", axi_rd_txn_cnt);
        $display("   AXI Write Transactions  : %0d", axi_wr_txn_cnt);
        $display("   NoC Channel 0 Requests  : %0d", noc_req_cnt);
        $display("   Heartbeat Pulses        : %0d", heartbeat_cnt);
        $display("   UART TX Toggles         : %0d", uart_tx_toggle_cnt);
        $display("   CPU Halt Detected       : %s", cpu_halt_seen ? "YES" : "NO");
        $display("   GPU Active (final)      : %b", status_gpu_active);
        $display("   Tensor Busy (final)     : %b", status_tensor_busy);
        $display("   Status Alive (final)    : %b", status_alive);

        // ---- Memory dump: check fibonacci result area ----
        $display("");
        $display("   --- HBM Memory Snapshot (Fibonacci region) ---");
        for (int i = MEM_LOAD_OFFSET; i < MEM_LOAD_OFFSET + 8; i++) begin
            $display("   hbm_dram[%0d] = 0x%032h", i, hbm_dram[i]);
        end

        // ---- Data memory region (store results) ----
        $display("");
        $display("   --- HBM Memory Snapshot (DMEM region: 0x20000) ---");
        for (int i = 8192; i < 8200; i++) begin // 0x20000 >> 4 = 0x2000 = 8192
            $display("   hbm_dram[%0d] = 0x%032h", i, hbm_dram[i]);
        end

        $display("");
        if (test_passed) begin
            $display("   *** SIMULATION RESULT: PASS ***");
        end else begin
            $display("   *** SIMULATION RESULT: FAIL (timeout or error) ***");
        end
        $display("=========================================================================");

        #100;
        $finish;
    end

    // =========================================================================
    //  CYCLE COUNTER WATCHDOG (fallback for hang detection)
    // =========================================================================
    int unsigned cycle_since_last_pc_change;

    always @(posedge clk) begin
        if (rst_n && !cpu_halt_seen) begin
            automatic logic [63:0] probe_pc = dut.cpu_clusters[0].gen_active.u_cpu_cluster.quads[0].u_quad.cores[0].u_core.cpu_debug.pc;
            if (probe_pc === mon_last_pc || $isunknown(probe_pc)) begin
                cycle_since_last_pc_change <= cycle_since_last_pc_change + 1;
            end else begin
                cycle_since_last_pc_change <= 0;
            end

            if (cycle_since_last_pc_change > 50000 && cycle_since_last_pc_change[0] == 1'b0) begin
                // Print only once near the threshold
                if (cycle_since_last_pc_change == 50002)
                    $display("[TB WARN] @%0t: PC stuck at 0x%h for >50000 cycles", $time, mon_last_pc);
            end
        end else begin
            cycle_since_last_pc_change <= 0;
        end
    end

endmodule : tb_soc_top
