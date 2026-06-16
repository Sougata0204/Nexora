// tb_hbm_transfers
`timescale 1ns / 1ps

module tb_hbm_transfers;

    import nexora_x3_pkg::*;

    localparam int AXI_ID_W   = nexora_x3_pkg::AXI_ID_WIDTH;   
    localparam int AXI_ADDR_W = nexora_x3_pkg::AXI_ADDR_WIDTH; 
    localparam int AXI_DATA_W = nexora_x3_pkg::AXI_DATA_WIDTH; 

    localparam int CLK_PERIOD   = 2;    
    localparam int TIMEOUT_CYC  = 100_000;
    localparam int MEM_BYTES    = 1 << 20;  
    localparam int MEM_WORDS    = MEM_BYTES / (AXI_DATA_W / 8); 

    localparam logic [2:0] PIM_VEC_ADD = 3'd0;
    localparam logic [2:0] PIM_VEC_MUL = 3'd1;
    localparam logic [2:0] PIM_RELU    = 3'd2;
    localparam logic [2:0] PIM_RED_SUM = 3'd3;
    localparam logic [2:0] PIM_VEC_MAC = 3'd4;

    logic clk;
    logic rst_n;

    mem_req_t  soc_req;
    mem_resp_t soc_resp;

    logic        pim_cmd_valid;
    logic        pim_cmd_ready;
    logic [2:0]  pim_cmd_op;
    logic [63:0] pim_cmd_addr_a;
    logic [63:0] pim_cmd_addr_b;
    logic [63:0] pim_cmd_addr_dst;
    logic        pim_busy;
    logic        pim_done;

    logic [3:0]  m_axi_hbm_awid;
    logic [63:0] m_axi_hbm_awaddr;
    logic [7:0]  m_axi_hbm_awlen;
    logic [2:0]  m_axi_hbm_awsize;
    logic [1:0]  m_axi_hbm_awburst;
    logic        m_axi_hbm_awvalid;
    logic        m_axi_hbm_awready;

    logic [127:0] m_axi_hbm_wdata;
    logic [15:0]  m_axi_hbm_wstrb;
    logic         m_axi_hbm_wlast;
    logic         m_axi_hbm_wvalid;
    logic         m_axi_hbm_wready;

    logic [3:0]  m_axi_hbm_bid;
    logic [1:0]  m_axi_hbm_bresp;
    logic        m_axi_hbm_bvalid;
    logic        m_axi_hbm_bready;

    logic [3:0]  m_axi_hbm_arid;
    logic [63:0] m_axi_hbm_araddr;
    logic [7:0]  m_axi_hbm_arlen;
    logic [2:0]  m_axi_hbm_arsize;
    logic [1:0]  m_axi_hbm_arburst;
    logic        m_axi_hbm_arvalid;
    logic        m_axi_hbm_arready;

    logic [3:0]   m_axi_hbm_rid;
    logic [127:0] m_axi_hbm_rdata;
    logic [1:0]   m_axi_hbm_rresp;
    logic         m_axi_hbm_rlast;
    logic         m_axi_hbm_rvalid;
    logic         m_axi_hbm_rready;

    int test_count  = 0;
    int pass_count  = 0;
    int fail_count  = 0;
    int cycle_count = 0;

    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    always @(posedge clk) cycle_count <= cycle_count + 1;

    initial begin
        $dumpfile("tb_hbm_transfers.vcd");
        $dumpvars(0, tb_hbm_transfers);
    end

    initial begin
        repeat (TIMEOUT_CYC) @(posedge clk);
        $display("\n[TIMEOUT] Simulation exceeded %0d cycles — aborting.", TIMEOUT_CYC);
        report_summary();
        $finish;
    end

    hbm_controller #(
        .AXI_ID_W   (AXI_ID_W),
        .AXI_ADDR_W (AXI_ADDR_W),
        .AXI_DATA_W (AXI_DATA_W)
    ) u_dut (
        .clk                (clk),
        .rst_n              (rst_n),

        .soc_req            (soc_req),
        .soc_resp           (soc_resp),

        .pim_cmd_valid      (pim_cmd_valid),
        .pim_cmd_ready      (pim_cmd_ready),
        .pim_cmd_op         (pim_cmd_op),
        .pim_cmd_addr_a     (pim_cmd_addr_a),
        .pim_cmd_addr_b     (pim_cmd_addr_b),
        .pim_cmd_addr_dst   (pim_cmd_addr_dst),
        .pim_busy           (pim_busy),
        .pim_done           (pim_done),

        .m_axi_hbm_awid     (m_axi_hbm_awid),
        .m_axi_hbm_awaddr   (m_axi_hbm_awaddr),
        .m_axi_hbm_awlen    (m_axi_hbm_awlen),
        .m_axi_hbm_awsize   (m_axi_hbm_awsize),
        .m_axi_hbm_awburst  (m_axi_hbm_awburst),
        .m_axi_hbm_awvalid  (m_axi_hbm_awvalid),
        .m_axi_hbm_awready  (m_axi_hbm_awready),

        .m_axi_hbm_wdata    (m_axi_hbm_wdata),
        .m_axi_hbm_wstrb    (m_axi_hbm_wstrb),
        .m_axi_hbm_wlast    (m_axi_hbm_wlast),
        .m_axi_hbm_wvalid   (m_axi_hbm_wvalid),
        .m_axi_hbm_wready   (m_axi_hbm_wready),

        .m_axi_hbm_bid      (m_axi_hbm_bid),
        .m_axi_hbm_bresp    (m_axi_hbm_bresp),
        .m_axi_hbm_bvalid   (m_axi_hbm_bvalid),
        .m_axi_hbm_bready   (m_axi_hbm_bready),

        .m_axi_hbm_arid     (m_axi_hbm_arid),
        .m_axi_hbm_araddr   (m_axi_hbm_araddr),
        .m_axi_hbm_arlen    (m_axi_hbm_arlen),
        .m_axi_hbm_arsize   (m_axi_hbm_arsize),
        .m_axi_hbm_arburst  (m_axi_hbm_arburst),
        .m_axi_hbm_arvalid  (m_axi_hbm_arvalid),
        .m_axi_hbm_arready  (m_axi_hbm_arready),

        .m_axi_hbm_rid      (m_axi_hbm_rid),
        .m_axi_hbm_rdata    (m_axi_hbm_rdata),
        .m_axi_hbm_rresp    (m_axi_hbm_rresp),
        .m_axi_hbm_rlast    (m_axi_hbm_rlast),
        .m_axi_hbm_rvalid   (m_axi_hbm_rvalid),
        .m_axi_hbm_rready   (m_axi_hbm_rready)
    );

    logic [127:0] axi_mem [0:MEM_WORDS-1];

    logic        ar_pending;
    logic [63:0] ar_captured_addr;
    logic [3:0]  ar_captured_id;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_hbm_arready <= 1'b1;
            m_axi_hbm_rvalid  <= 1'b0;
            m_axi_hbm_rdata   <= '0;
            m_axi_hbm_rid     <= '0;
            m_axi_hbm_rresp   <= 2'b00;
            m_axi_hbm_rlast   <= 1'b0;
            ar_pending         <= 1'b0;
        end else begin

            if (m_axi_hbm_rvalid && m_axi_hbm_rready) begin
                m_axi_hbm_rvalid <= 1'b0;
                m_axi_hbm_rlast  <= 1'b0;
                m_axi_hbm_arready <= 1'b1;
                ar_pending <= 1'b0;
            end

            if (m_axi_hbm_arvalid && m_axi_hbm_arready) begin
                ar_captured_addr  <= m_axi_hbm_araddr;
                ar_captured_id    <= m_axi_hbm_arid;
                ar_pending        <= 1'b1;
                m_axi_hbm_arready <= 1'b0; 
            end

            if (ar_pending && !m_axi_hbm_rvalid) begin
                m_axi_hbm_rdata  <= axi_mem[addr_to_word_idx(ar_captured_addr)];
                m_axi_hbm_rid    <= ar_captured_id;
                m_axi_hbm_rresp  <= 2'b00; 
                m_axi_hbm_rlast  <= 1'b1;  
                m_axi_hbm_rvalid <= 1'b1;
                $display("[AXI-RD ] t=%0t  addr=0x%016h  data=0x%032h  id=%0d",
                         $time, ar_captured_addr,
                         axi_mem[addr_to_word_idx(ar_captured_addr)],
                         ar_captured_id);
            end
        end
    end

    logic        aw_pending;
    logic [63:0] aw_captured_addr;
    logic [3:0]  aw_captured_id;
    logic        b_pending;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_hbm_awready <= 1'b1;
            m_axi_hbm_wready  <= 1'b1;
            m_axi_hbm_bvalid  <= 1'b0;
            m_axi_hbm_bid     <= '0;
            m_axi_hbm_bresp   <= 2'b00;
            aw_pending         <= 1'b0;
            b_pending          <= 1'b0;
        end else begin

            if (m_axi_hbm_bvalid && m_axi_hbm_bready) begin
                m_axi_hbm_bvalid  <= 1'b0;
                m_axi_hbm_awready <= 1'b1;
                m_axi_hbm_wready  <= 1'b1;
                b_pending          <= 1'b0;
            end

            if (m_axi_hbm_awvalid && m_axi_hbm_awready) begin
                aw_captured_addr  <= m_axi_hbm_awaddr;
                aw_captured_id    <= m_axi_hbm_awid;
                aw_pending        <= 1'b1;
                m_axi_hbm_awready <= 1'b0;
            end

            if (aw_pending && m_axi_hbm_wvalid && m_axi_hbm_wready) begin

                for (int b = 0; b < 16; b++) begin
                    if (m_axi_hbm_wstrb[b])
                        axi_mem[addr_to_word_idx(aw_captured_addr)][b*8 +: 8]
                            <= m_axi_hbm_wdata[b*8 +: 8];
                end
                $display("[AXI-WR ] t=%0t  addr=0x%016h  data=0x%032h  strb=0x%04h",
                         $time, aw_captured_addr, m_axi_hbm_wdata, m_axi_hbm_wstrb);
                aw_pending        <= 1'b0;
                m_axi_hbm_wready  <= 1'b0;
                b_pending          <= 1'b1;
            end

            if (b_pending && !m_axi_hbm_bvalid) begin
                m_axi_hbm_bvalid <= 1'b1;
                m_axi_hbm_bid    <= aw_captured_id;
                m_axi_hbm_bresp  <= 2'b00; 
                $display("[AXI-BRP] t=%0t  Write response OKAY  id=%0d",
                         $time, aw_captured_id);
            end
        end
    end

    function automatic int addr_to_word_idx(input logic [63:0] addr);
        return int'((addr & (MEM_BYTES - 1)) >> 4);
    endfunction

    always @(posedge clk) begin
        if (m_axi_hbm_arvalid && m_axi_hbm_arready)
            $display("[MON-AR ] t=%0t  Read  addr request  addr=0x%016h  len=%0d  id=%0d",
                     $time, m_axi_hbm_araddr, m_axi_hbm_arlen, m_axi_hbm_arid);

        if (m_axi_hbm_awvalid && m_axi_hbm_awready)
            $display("[MON-AW ] t=%0t  Write addr request  addr=0x%016h  len=%0d  id=%0d",
                     $time, m_axi_hbm_awaddr, m_axi_hbm_awlen, m_axi_hbm_awid);

        if (m_axi_hbm_rvalid && m_axi_hbm_rready)
            $display("[MON-R  ] t=%0t  Read  data beat     data=0x%032h  last=%0b  id=%0d",
                     $time, m_axi_hbm_rdata, m_axi_hbm_rlast, m_axi_hbm_rid);

        if (m_axi_hbm_wvalid && m_axi_hbm_wready)
            $display("[MON-W  ] t=%0t  Write data beat     data=0x%032h  last=%0b  strb=0x%04h",
                     $time, m_axi_hbm_wdata, m_axi_hbm_wlast, m_axi_hbm_wstrb);

        if (m_axi_hbm_bvalid && m_axi_hbm_bready)
            $display("[MON-B  ] t=%0t  Write response      resp=%0d  id=%0d",
                     $time, m_axi_hbm_bresp, m_axi_hbm_bid);
    end

    initial begin
        $display("============================================================");
        $display(" tb_hbm_transfers — Nexora X3 HBM Controller Testbench");
        $display("============================================================");

        init_signals();

        apply_reset();

        populate_memory();

        test_soc_read();

        test_soc_write();

        test_sequential_reads();

        test_pim_vec_add();

        test_pim_relu();

        report_summary();
        $finish;
    end

    task automatic init_signals();
        rst_n           = 1'b0;
        soc_req         = '0;
        pim_cmd_valid   = 1'b0;
        pim_cmd_op      = 3'd0;
        pim_cmd_addr_a  = 64'd0;
        pim_cmd_addr_b  = 64'd0;
        pim_cmd_addr_dst = 64'd0;
    endtask

    task automatic apply_reset();
        $display("\n[RESET ] t=%0t  Asserting reset...", $time);
        rst_n = 1'b0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        $display("[RESET ] t=%0t  Reset released.\n", $time);
    endtask

    task automatic populate_memory();
        $display("[MEM-INIT] Populating AXI slave memory...");

        for (int i = 0; i < MEM_WORDS; i++)
            axi_mem[i] = '0;

        axi_mem[addr_to_word_idx(64'h0000_0000_0000_1000)] = 128'hCAFE_BABE_0000_1111_2222_3333_4444_5555;

        axi_mem[addr_to_word_idx(64'h0000_0000_0000_2000)] = 128'h0;

        axi_mem[addr_to_word_idx(64'h0000_0000_0000_1000)] = 128'hAAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AA00;
        axi_mem[addr_to_word_idx(64'h0000_0000_0000_1010)] = 128'hBBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BB11;
        axi_mem[addr_to_word_idx(64'h0000_0000_0000_1020)] = 128'hCCCC_CCCC_CCCC_CCCC_CCCC_CCCC_CCCC_CC22;
        axi_mem[addr_to_word_idx(64'h0000_0000_0000_1030)] = 128'hDDDD_DDDD_DDDD_DDDD_DDDD_DDDD_DDDD_DD33;

        for (int i = 0; i < 8; i++) begin
            logic [63:0] elem_lo, elem_hi;
            elem_lo = 64'(i * 2 + 1);   
            elem_hi = 64'(i * 2 + 2);   
            axi_mem[addr_to_word_idx(64'h3000 + i * 16)] = {elem_hi, elem_lo};
        end

        for (int i = 0; i < 8; i++) begin
            logic [63:0] elem_lo, elem_hi;
            elem_lo = 64'((i * 2 + 1) * 10);  
            elem_hi = 64'((i * 2 + 2) * 10);  
            axi_mem[addr_to_word_idx(64'h4000 + i * 16)] = {elem_hi, elem_lo};
        end

        axi_mem[addr_to_word_idx(64'h6000)] = {64'hFFFF_FFFF_FFFF_FFF6,  
                                                 64'h0000_0000_0000_000A}; 
        axi_mem[addr_to_word_idx(64'h6010)] = {64'h0000_0000_0000_0014,   
                                                 64'hFFFF_FFFF_FFFF_FFEC}; 
        axi_mem[addr_to_word_idx(64'h6020)] = {64'hFFFF_FFFF_FFFF_FFCE,   
                                                 64'h0000_0000_0000_0032}; 
        axi_mem[addr_to_word_idx(64'h6030)] = {64'h0000_0000_0000_0000,   
                                                 64'hFFFF_FFFF_FFFF_FF9C}; 

        $display("[MEM-INIT] Memory population complete.\n");
    endtask

    task automatic soc_read(
        input  logic [63:0] addr,
        output logic [63:0] rdata,
        output logic        error
    );
        @(posedge clk);
        soc_req.addr    <= addr;
        soc_req.read_en <= 1'b1;
        soc_req.write_en <= 1'b0;
        soc_req.wdata   <= '0;
        soc_req.byte_en <= 8'hFF;
        @(posedge clk);
        soc_req.read_en <= 1'b0;

        fork
            begin
                repeat (500) @(posedge clk);
                $display("[ERROR  ] soc_read timeout — addr=0x%016h", addr);
                error = 1'b1;
                rdata = '0;
            end
            begin
                wait (soc_resp.ready);
                @(posedge clk);
                rdata = soc_resp.rdata;
                error = soc_resp.error;
            end
        join_any
        disable fork;
        soc_req <= '0;
    endtask

    task automatic soc_write(
        input  logic [63:0] addr,
        input  logic [63:0] wdata,
        input  logic [7:0]  byte_en,
        output logic        error
    );
        @(posedge clk);
        soc_req.addr     <= addr;
        soc_req.wdata    <= wdata;
        soc_req.write_en <= 1'b1;
        soc_req.read_en  <= 1'b0;
        soc_req.byte_en  <= byte_en;
        @(posedge clk);
        soc_req.write_en <= 1'b0;

        fork
            begin
                repeat (500) @(posedge clk);
                $display("[ERROR  ] soc_write timeout — addr=0x%016h", addr);
                error = 1'b1;
            end
            begin
                wait (soc_resp.ready);
                @(posedge clk);
                error = soc_resp.error;
            end
        join_any
        disable fork;
        soc_req <= '0;
    endtask

    task automatic check_result(
        input string test_name,
        input logic [127:0] actual,
        input logic [127:0] expected
    );
        test_count++;
        if (actual === expected) begin
            pass_count++;
            $display("[PASS   ] %s — got 0x%032h", test_name, actual);
        end else begin
            fail_count++;
            $display("[FAIL   ] %s — expected 0x%032h, got 0x%032h",
                     test_name, expected, actual);
        end
    endtask

    task automatic check_flag(
        input string test_name,
        input logic  actual,
        input logic  expected
    );
        test_count++;
        if (actual === expected) begin
            pass_count++;
            $display("[PASS   ] %s — flag=%0b", test_name, actual);
        end else begin
            fail_count++;
            $display("[FAIL   ] %s — expected %0b, got %0b", test_name, expected, actual);
        end
    endtask

    task automatic report_summary();
        $display("\n============================================================");
        $display(" TEST SUMMARY");
        $display("------------------------------------------------------------");
        $display("  Total : %0d", test_count);
        $display("  Pass  : %0d", pass_count);
        $display("  Fail  : %0d", fail_count);
        $display("------------------------------------------------------------");
        if (fail_count == 0)
            $display("  *** ALL TESTS PASSED ***");
        else
            $display("  *** %0d TEST(S) FAILED ***", fail_count);
        $display("============================================================\n");
    endtask

    task automatic test_soc_read();
        logic [63:0] rdata;
        logic        err;
        logic [127:0] expected_word;

        $display("------------------------------------------------------------");
        $display(" TEST 1 : SoC Read — addr=0x1000");
        $display("------------------------------------------------------------");

        expected_word = axi_mem[addr_to_word_idx(64'h1000)];

        soc_read(64'h0000_0000_0000_1000, rdata, err);

        check_flag("TEST1 — soc_resp.error", err, 1'b0);

        check_result("TEST1 — soc_read data (lo64)",
                     {64'd0, rdata}, {64'd0, expected_word[63:0]});

        repeat (5) @(posedge clk);
        $display("");
    endtask

    task automatic test_soc_write();
        logic [63:0] rdata;
        logic        err;

        $display("------------------------------------------------------------");
        $display(" TEST 2 : SoC Write — addr=0x2000, data=0xDEADBEEF");
        $display("------------------------------------------------------------");

        soc_write(64'h0000_0000_0000_2000, 64'h0000_0000_DEAD_BEEF, 8'hFF, err);
        check_flag("TEST2 — soc_write error", err, 1'b0);

        repeat (5) @(posedge clk);

        soc_read(64'h0000_0000_0000_2000, rdata, err);
        check_flag("TEST2 — soc_read_back error", err, 1'b0);
        check_result("TEST2 — read-back data",
                     {64'd0, rdata}, {64'd0, 64'h0000_0000_DEAD_BEEF});

        repeat (5) @(posedge clk);
        $display("");
    endtask

    task automatic test_sequential_reads();
        logic [63:0] rdata;
        logic        err;
        logic [63:0] addrs [4];
        logic [127:0] expected [4];

        $display("------------------------------------------------------------");
        $display(" TEST 3 : Sequential Reads — 4 addresses from 0x1000");
        $display("------------------------------------------------------------");

        addrs[0] = 64'h0000_0000_0000_1000;
        addrs[1] = 64'h0000_0000_0000_1010;
        addrs[2] = 64'h0000_0000_0000_1020;
        addrs[3] = 64'h0000_0000_0000_1030;

        for (int i = 0; i < 4; i++)
            expected[i] = axi_mem[addr_to_word_idx(addrs[i])];

        for (int i = 0; i < 4; i++) begin
            soc_read(addrs[i], rdata, err);
            check_flag($sformatf("TEST3[%0d] — error", i), err, 1'b0);
            check_result($sformatf("TEST3[%0d] — data (lo64)", i),
                         {64'd0, rdata}, {64'd0, expected[i][63:0]});
            repeat (2) @(posedge clk);
        end

        repeat (5) @(posedge clk);
        $display("");
    endtask

    task automatic test_pim_vec_add();
        logic [63:0] rdata;
        logic        err;

        $display("------------------------------------------------------------");
        $display(" TEST 4 : PIM Vector Add — A + B → dst");
        $display("------------------------------------------------------------");

        @(posedge clk);
        pim_cmd_valid    <= 1'b1;
        pim_cmd_op       <= PIM_VEC_ADD;
        pim_cmd_addr_a   <= 64'h0000_0000_0000_3000;
        pim_cmd_addr_b   <= 64'h0000_0000_0000_4000;
        pim_cmd_addr_dst <= 64'h0000_0000_0000_5000;

        fork
            begin
                repeat (500) @(posedge clk);
                $display("[ERROR  ] PIM cmd_ready timeout");
            end
            begin
                wait (pim_cmd_ready);
                @(posedge clk);
            end
        join_any
        disable fork;

        pim_cmd_valid <= 1'b0;

        repeat (2) @(posedge clk);
        $display("[PIM    ] pim_busy=%0b", pim_busy);

        fork
            begin
                repeat (5000) @(posedge clk);
                $display("[ERROR  ] PIM done timeout");
            end
            begin
                wait (pim_done);
                @(posedge clk);
            end
        join_any
        disable fork;

        check_flag("TEST4 — pim_done asserted", pim_done, 1'b1);
        $display("[PIM    ] PIM Vector Add complete at t=%0t", $time);

        repeat (5) @(posedge clk);

        for (int i = 0; i < 8; i++) begin
            logic [63:0] a_lo, a_hi, b_lo, b_hi;
            logic [127:0] expected_word;

            a_lo = 64'(i * 2 + 1);
            a_hi = 64'(i * 2 + 2);
            b_lo = 64'((i * 2 + 1) * 10);
            b_hi = 64'((i * 2 + 2) * 10);
            expected_word = {(a_hi + b_hi), (a_lo + b_lo)};

            soc_read(64'h5000 + i * 16, rdata, err);
            check_result($sformatf("TEST4 — dst[%0d] (lo64)", i),
                         {64'd0, rdata}, {64'd0, expected_word[63:0]});
        end

        repeat (5) @(posedge clk);
        $display("");
    endtask

    task automatic test_pim_relu();
        logic [63:0] rdata;
        logic        err;

        $display("------------------------------------------------------------");
        $display(" TEST 5 : PIM ReLU — max(0, x) on signed vector");
        $display("------------------------------------------------------------");

        @(posedge clk);
        pim_cmd_valid    <= 1'b1;
        pim_cmd_op       <= PIM_RELU;
        pim_cmd_addr_a   <= 64'h0000_0000_0000_6000;
        pim_cmd_addr_b   <= 64'h0;  
        pim_cmd_addr_dst <= 64'h0000_0000_0000_7000;

        fork
            begin
                repeat (500) @(posedge clk);
                $display("[ERROR  ] PIM ReLU cmd_ready timeout");
            end
            begin
                wait (pim_cmd_ready);
                @(posedge clk);
            end
        join_any
        disable fork;

        pim_cmd_valid <= 1'b0;

        fork
            begin
                repeat (5000) @(posedge clk);
                $display("[ERROR  ] PIM ReLU done timeout");
            end
            begin
                wait (pim_done);
                @(posedge clk);
            end
        join_any
        disable fork;

        check_flag("TEST5 — pim_done asserted", pim_done, 1'b1);
        $display("[PIM    ] PIM ReLU complete at t=%0t", $time);

        repeat (5) @(posedge clk);

        soc_read(64'h7000, rdata, err);
        check_result("TEST5 — relu[0] lo64 (expect +10)",
                     {64'd0, rdata}, {64'd0, 64'h0000_0000_0000_000A});

        soc_read(64'h7010, rdata, err);
        check_result("TEST5 — relu[1] lo64 (expect 0)",
                     {64'd0, rdata}, {64'd0, 64'h0000_0000_0000_0000});

        soc_read(64'h7020, rdata, err);
        check_result("TEST5 — relu[2] lo64 (expect +50)",
                     {64'd0, rdata}, {64'd0, 64'h0000_0000_0000_0032});

        soc_read(64'h7030, rdata, err);
        check_result("TEST5 — relu[3] lo64 (expect 0)",
                     {64'd0, rdata}, {64'd0, 64'h0000_0000_0000_0000});

        repeat (5) @(posedge clk);
        $display("");
    endtask

endmodule
