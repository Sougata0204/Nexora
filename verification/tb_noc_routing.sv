// tb_noc_routing
`timescale 1ns / 1ps

module tb_noc_routing;

    import nexora_x3_pkg::*;

    localparam int ROUTER_X       = 1;
    localparam int ROUTER_Y       = 1;
    localparam int CLK_PERIOD     = 10;       
    localparam int TIMEOUT_CYCLES = 10_000;
    localparam int ROUTER_LATENCY = 4;        

    logic clk;
    logic rst_n;

    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    noc_flit_t local_flit_in;
    logic      local_flit_in_valid;
    logic      local_flit_in_ready;
    noc_flit_t local_flit_out;
    logic      local_flit_out_valid;
    logic      local_flit_out_ready;

    noc_flit_t north_flit_in;
    logic      north_flit_in_valid;
    logic      north_flit_in_ready;
    noc_flit_t north_flit_out;
    logic      north_flit_out_valid;
    logic      north_flit_out_ready;

    noc_flit_t east_flit_in;
    logic      east_flit_in_valid;
    logic      east_flit_in_ready;
    noc_flit_t east_flit_out;
    logic      east_flit_out_valid;
    logic      east_flit_out_ready;

    noc_flit_t south_flit_in;
    logic      south_flit_in_valid;
    logic      south_flit_in_ready;
    noc_flit_t south_flit_out;
    logic      south_flit_out_valid;
    logic      south_flit_out_ready;

    noc_flit_t west_flit_in;
    logic      west_flit_in_valid;
    logic      west_flit_in_ready;
    noc_flit_t west_flit_out;
    logic      west_flit_out_valid;
    logic      west_flit_out_ready;

    noc_router #(
        .ROUTER_X (ROUTER_X),
        .ROUTER_Y (ROUTER_Y)
    ) u_dut (
        .clk                 (clk),
        .rst_n               (rst_n),

        .local_flit_in       (local_flit_in),
        .local_flit_in_valid (local_flit_in_valid),
        .local_flit_in_ready (local_flit_in_ready),
        .local_flit_out      (local_flit_out),
        .local_flit_out_valid(local_flit_out_valid),
        .local_flit_out_ready(local_flit_out_ready),

        .north_flit_in       (north_flit_in),
        .north_flit_in_valid (north_flit_in_valid),
        .north_flit_in_ready (north_flit_in_ready),
        .north_flit_out      (north_flit_out),
        .north_flit_out_valid(north_flit_out_valid),
        .north_flit_out_ready(north_flit_out_ready),

        .east_flit_in        (east_flit_in),
        .east_flit_in_valid  (east_flit_in_valid),
        .east_flit_in_ready  (east_flit_in_ready),
        .east_flit_out       (east_flit_out),
        .east_flit_out_valid (east_flit_out_valid),
        .east_flit_out_ready (east_flit_out_ready),

        .south_flit_in       (south_flit_in),
        .south_flit_in_valid (south_flit_in_valid),
        .south_flit_in_ready (south_flit_in_ready),
        .south_flit_out      (south_flit_out),
        .south_flit_out_valid(south_flit_out_valid),
        .south_flit_out_ready(south_flit_out_ready),

        .west_flit_in        (west_flit_in),
        .west_flit_in_valid  (west_flit_in_valid),
        .west_flit_in_ready  (west_flit_in_ready),
        .west_flit_out       (west_flit_out),
        .west_flit_out_valid (west_flit_out_valid),
        .west_flit_out_ready (west_flit_out_ready)
    );

    int pass_count;
    int fail_count;
    int test_num;

    initial begin
        $dumpfile("tb_noc_routing.vcd");
        $dumpvars(0, tb_noc_routing);
    end

    initial begin
        repeat (TIMEOUT_CYCLES) @(posedge clk);
        $display("============================================================");
        $display("ERROR: Simulation timed out after %0d cycles!", TIMEOUT_CYCLES);
        $display("============================================================");
        $finish;
    end

    function automatic noc_flit_t build_head_flit(
        input logic [1:0] dst_x,
        input logic [1:0] dst_y,
        input logic [1:0] src_x,
        input logic [1:0] src_y,
        input logic [1:0] vc_id,
        input logic [3:0] msg_type,
        input logic [31:0] payload
    );
        noc_flit_t flit;
        flit.flit_type = FLIT_HEAD;     
        flit.dst_x     = dst_x;
        flit.dst_y     = dst_y;
        flit.src_x     = src_x;
        flit.src_y     = src_y;
        flit.vc_id     = vc_id;
        flit.msg_type  = msg_type;
        flit.payload   = payload;
        return flit;
    endfunction

    task automatic clear_all_inputs();
        local_flit_in       <= '0;
        local_flit_in_valid <= 1'b0;
        north_flit_in       <= '0;
        north_flit_in_valid <= 1'b0;
        east_flit_in        <= '0;
        east_flit_in_valid  <= 1'b0;
        south_flit_in       <= '0;
        south_flit_in_valid <= 1'b0;
        west_flit_in        <= '0;
        west_flit_in_valid  <= 1'b0;
    endtask

    task automatic inject_flit(
        input int          port_sel,
        input noc_flit_t   flit
    );
        @(posedge clk);
        case (port_sel)
            0: begin local_flit_in <= flit; local_flit_in_valid <= 1'b1; end
            1: begin north_flit_in <= flit; north_flit_in_valid <= 1'b1; end
            2: begin east_flit_in  <= flit; east_flit_in_valid  <= 1'b1; end
            3: begin south_flit_in <= flit; south_flit_in_valid <= 1'b1; end
            4: begin west_flit_in  <= flit; west_flit_in_valid  <= 1'b1; end
            default: $display("[TB] ERROR: Invalid port_sel=%0d", port_sel);
        endcase
        @(posedge clk);
        clear_all_inputs();
    endtask

    task automatic wait_for_output(
        input  int          port_sel,
        input  int          max_wait,
        output noc_flit_t   captured_flit,
        output logic        success
    );
        int i;
        success = 1'b0;
        for (i = 0; i < max_wait; i++) begin
            @(posedge clk);
            case (port_sel)
                0: if (local_flit_out_valid) begin captured_flit = local_flit_out; success = 1'b1; end
                1: if (north_flit_out_valid) begin captured_flit = north_flit_out; success = 1'b1; end
                2: if (east_flit_out_valid)  begin captured_flit = east_flit_out;  success = 1'b1; end
                3: if (south_flit_out_valid) begin captured_flit = south_flit_out; success = 1'b1; end
                4: if (west_flit_out_valid)  begin captured_flit = west_flit_out;  success = 1'b1; end
                default: ;
            endcase
            if (success) return;
        end
    endtask

    function automatic string port_name(input int sel);
        case (sel)
            0: return "LOCAL";
            1: return "NORTH";
            2: return "EAST";
            3: return "SOUTH";
            4: return "WEST";
            default: return "UNKNOWN";
        endcase
    endfunction

    task automatic test_single_route(
        input string       test_label,
        input int          inj_port,
        input int          exp_port,
        input logic [1:0]  dst_x,
        input logic [1:0]  dst_y,
        input logic [31:0] payload_tag
    );
        noc_flit_t flit_in;
        noc_flit_t flit_out;
        logic      ok;

        test_num++;
        $display("------------------------------------------------------------");
        $display("[TEST %0d] %s", test_num, test_label);
        $display("  Inject on %-5s → dst (%0d,%0d) → expect on %-5s",
                 port_name(inj_port), dst_x, dst_y, port_name(exp_port));

        flit_in = build_head_flit(
            .dst_x   (dst_x),
            .dst_y   (dst_y),
            .src_x   (2'(ROUTER_X)),
            .src_y   (2'(ROUTER_Y)),
            .vc_id   (2'b00),
            .msg_type(4'h0),         
            .payload (payload_tag)
        );

        inject_flit(inj_port, flit_in);

        wait_for_output(exp_port, ROUTER_LATENCY + 2, flit_out, ok);

        if (ok && flit_out.payload == payload_tag) begin
            $display("  PASS — Flit arrived on %s with correct payload 0x%08h",
                     port_name(exp_port), flit_out.payload);
            pass_count++;
        end else if (ok) begin
            $display("  FAIL — Flit arrived on %s but payload mismatch: expected 0x%08h, got 0x%08h",
                     port_name(exp_port), payload_tag, flit_out.payload);
            fail_count++;
        end else begin
            $display("  FAIL — No flit appeared on %s within %0d cycles",
                     port_name(exp_port), ROUTER_LATENCY + 2);
            fail_count++;
        end
    endtask

    initial begin
        $display("============================================================");
        $display(" tb_noc_routing — Nexora X3 NoC Router Verification");
        $display(" Router position: (%0d, %0d)", ROUTER_X, ROUTER_Y);
        $display(" Timestamp      : %0t", $time);
        $display("============================================================");

        pass_count = 0;
        fail_count = 0;
        test_num   = 0;

        local_flit_out_ready <= 1'b1;
        north_flit_out_ready <= 1'b1;
        east_flit_out_ready  <= 1'b1;
        south_flit_out_ready <= 1'b1;
        west_flit_out_ready  <= 1'b1;

        clear_all_inputs();

        rst_n <= 1'b0;
        repeat (5) @(posedge clk);
        rst_n <= 1'b1;
        repeat (3) @(posedge clk);
        $display("[TB] Reset released at time %0t", $time);

        test_single_route(
            .test_label  ("LOCAL → EAST routing"),
            .inj_port    (0),       
            .exp_port    (2),       
            .dst_x       (2'd3),
            .dst_y       (2'd1),
            .payload_tag (32'hDEAD_0001)
        );
        repeat (2) @(posedge clk);

        test_single_route(
            .test_label  ("LOCAL → WEST routing"),
            .inj_port    (0),       
            .exp_port    (4),       
            .dst_x       (2'd0),
            .dst_y       (2'd1),
            .payload_tag (32'hDEAD_0002)
        );
        repeat (2) @(posedge clk);

        test_single_route(
            .test_label  ("LOCAL → SOUTH routing"),
            .inj_port    (0),       
            .exp_port    (3),       
            .dst_x       (2'd1),
            .dst_y       (2'd3),
            .payload_tag (32'hDEAD_0003)
        );
        repeat (2) @(posedge clk);

        test_single_route(
            .test_label  ("LOCAL → NORTH routing"),
            .inj_port    (0),       
            .exp_port    (1),       
            .dst_x       (2'd1),
            .dst_y       (2'd0),
            .payload_tag (32'hDEAD_0004)
        );
        repeat (2) @(posedge clk);

        test_single_route(
            .test_label  ("LOCAL → LOCAL loopback"),
            .inj_port    (0),       
            .exp_port    (0),       
            .dst_x       (2'd1),
            .dst_y       (2'd1),
            .payload_tag (32'hDEAD_0005)
        );
        repeat (2) @(posedge clk);

        test_single_route(
            .test_label  ("NORTH → SOUTH transit"),
            .inj_port    (1),       
            .exp_port    (3),       
            .dst_x       (2'd1),
            .dst_y       (2'd3),
            .payload_tag (32'hDEAD_0006)
        );
        repeat (2) @(posedge clk);

        test_single_route(
            .test_label  ("EAST → WEST transit"),
            .inj_port    (2),       
            .exp_port    (4),       
            .dst_x       (2'd0),
            .dst_y       (2'd1),
            .payload_tag (32'hDEAD_0007)
        );
        repeat (2) @(posedge clk);

        begin
            noc_flit_t flit_local, flit_north;
            noc_flit_t cap_flit;
            logic      ok;
            int        east_count;

            test_num++;
            $display("------------------------------------------------------------");
            $display("[TEST %0d] Multi-port contention (LOCAL + NORTH → EAST)", test_num);

            flit_local = build_head_flit(
                .dst_x   (2'd3),
                .dst_y   (2'd1),
                .src_x   (2'd1),
                .src_y   (2'd1),
                .vc_id   (2'b00),
                .msg_type(4'h0),
                .payload (32'hCAFE_0008)
            );
            flit_north = build_head_flit(
                .dst_x   (2'd2),
                .dst_y   (2'd1),
                .src_x   (2'd1),
                .src_y   (2'd0),
                .vc_id   (2'b01),
                .msg_type(4'h1),
                .payload (32'hCAFE_0009)
            );

            @(posedge clk);
            local_flit_in       <= flit_local;
            local_flit_in_valid <= 1'b1;
            north_flit_in       <= flit_north;
            north_flit_in_valid <= 1'b1;
            @(posedge clk);
            clear_all_inputs();

            east_count = 0;
            for (int w = 0; w < (ROUTER_LATENCY + 6); w++) begin
                @(posedge clk);
                if (east_flit_out_valid) begin
                    $display("  Flit %0d on EAST: payload=0x%08h  (cycle %0d)",
                             east_count, east_flit_out.payload, w);
                    east_count++;
                end
            end

            if (east_count == 2) begin
                $display("  PASS — Both flits routed to EAST under contention");
                pass_count++;
            end else begin
                $display("  FAIL — Expected 2 flits on EAST, got %0d", east_count);
                fail_count++;
            end
        end
        repeat (4) @(posedge clk);

        test_single_route(
            .test_label  ("X-first routing: dst (3,3) → EAST (not SOUTH)"),
            .inj_port    (0),       
            .exp_port    (2),       
            .dst_x       (2'd3),
            .dst_y       (2'd3),
            .payload_tag (32'hBEEF_000A)
        );
        repeat (2) @(posedge clk);

        begin
            noc_flit_t bp_flit;
            logic      ready_dropped;
            int        inject_idx;

            test_num++;
            $display("------------------------------------------------------------");
            $display("[TEST %0d] Backpressure — 5 rapid flits (FIFO depth=4)", test_num);

            east_flit_out_ready <= 1'b0;

            repeat (2) @(posedge clk);

            ready_dropped = 1'b0;

            for (inject_idx = 0; inject_idx < 5; inject_idx++) begin
                bp_flit = build_head_flit(
                    .dst_x   (2'd3),
                    .dst_y   (2'd1),
                    .src_x   (2'd1),
                    .src_y   (2'd1),
                    .vc_id   (2'b00),
                    .msg_type(4'h0),
                    .payload (32'hF1F0_0000 + inject_idx[31:0])
                );
                @(posedge clk);
                local_flit_in       <= bp_flit;
                local_flit_in_valid <= 1'b1;

                @(posedge clk);
                if (!local_flit_in_ready) begin
                    $display("  Ready deasserted after injecting flit %0d", inject_idx);
                    ready_dropped = 1'b1;
                end
            end

            clear_all_inputs();

            if (ready_dropped) begin
                $display("  PASS — Backpressure correctly asserted (ready dropped)");
                pass_count++;
            end else begin
                $display("  FAIL — Ready never deasserted; backpressure not observed");
                fail_count++;
            end

            east_flit_out_ready <= 1'b1;

            repeat (ROUTER_LATENCY + 6) @(posedge clk);
        end

        $display("");
        $display("============================================================");
        $display(" TEST SUMMARY");
        $display("============================================================");
        $display("  Total : %0d", pass_count + fail_count);
        $display("  PASS  : %0d", pass_count);
        $display("  FAIL  : %0d", fail_count);
        $display("============================================================");
        if (fail_count == 0)
            $display(" >>> ALL TESTS PASSED <<<");
        else
            $display(" >>> SOME TESTS FAILED — review log above <<<");
        $display("============================================================");
        $finish;
    end

endmodule
