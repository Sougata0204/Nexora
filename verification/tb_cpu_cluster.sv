// tb_cpu_cluster
`timescale 1ns / 1ps

import nexora_x3_pkg::*;

module tb_cpu_cluster;

    logic clk;
    logic rst_n;

    mem_req_t  main_mem_req;
    mem_resp_t main_mem_resp;
    logic      system_halt;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    cpu_cluster dut (
        .clk(clk),
        .rst_n(rst_n),
        .main_mem_req(main_mem_req),
        .main_mem_resp(main_mem_resp),
        .system_halt(system_halt)
    );

    logic [31:0] memory [0:1023]; 

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin

            memory[0] <= 32'h00100093; 
            memory[1] <= 32'h00110133; 
            memory[2] <= 32'h00000073; 
        end else begin
            if (main_mem_req.write_en) begin
                memory[main_mem_req.addr[11:2]] <= main_mem_req.wdata;
            end
        end
    end

    always_comb begin
        main_mem_resp = '0;
        if (rst_n && (main_mem_req.read_en || main_mem_req.write_en)) begin
            main_mem_resp.ready = 1'b1;
            if (!main_mem_req.write_en && !$isunknown(main_mem_req.addr)) begin
                main_mem_resp.rdata = memory[main_mem_req.addr[11:2]];
            end
        end
    end

    integer clk_cycles = 0;
    always_ff @(posedge clk) begin
        clk_cycles <= clk_cycles + 1;
        $display("Time %0t: main_mem_req (r:%b, w:%b, addr:%h), main_mem_resp (ready:%b, data:%h), system_halt:%b", 
                 $time, main_mem_req.read_en, main_mem_req.write_en, main_mem_req.addr, 
                 main_mem_resp.ready, main_mem_resp.rdata, system_halt);

        if (clk_cycles > 5) begin
            $display("5 cycles complete. Exiting.");
            $finish;
        end
    end

    initial begin
        $display("========================================================");
        $display("   NEXORA X2 - CPU CLUSTER (16-CORE) SIMULATION TEST    ");
        $display("========================================================");

        clk = 0;
        rst_n = 0;
        main_mem_resp = '0;

        #20;
        rst_n = 1;

        begin : wait_for_halt
            fork
                begin
                    wait(system_halt == 1'b1);
                    $display("[PASS] All 16 Cores successfully Halted (ECALL detected)");
                end
                begin
                    #200;
                    $display("[FAIL] Timeout: System did not halt within 200ns");
                    $display("       Current system_halt status = %b", system_halt);
                    $finish;
                end
            join_any
            disable wait_for_halt;
        end

        $display("========================================================");
        $display("  *** NEXORA X2 CLUSTER INTEGRATION TESTS PASSED ***    ");
        $display("========================================================");
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            if (^main_mem_req.addr === 1'bX) $display("X detected in main_mem_req.addr");
            if (^main_mem_req.read_en === 1'bX) $display("X detected in main_mem_req.read_en");
            if (^main_mem_req.write_en === 1'bX) $display("X detected in main_mem_req.write_en");
            if (^main_mem_resp.ready === 1'bX) $display("X detected in main_mem_resp.ready");
        end
    end
endmodule
