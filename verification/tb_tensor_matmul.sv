// tb_tensor_matmul
`timescale 1ns / 1ps

module tb_tensor_matmul;

    import nexora_x3_pkg::*;

    localparam int DIM = nexora_x3_pkg::TENSOR_DIM;  

    localparam int unsigned CLUSTER_ID = 0;

    localparam logic [63:0] WEIGHT_BASE = 64'h2000_0000;                      
    localparam logic [63:0] ACT_BASE    = 64'h2000_0000 + 64'd256;            
    localparam logic [63:0] RESULT_BASE = 64'h2000_0000 + 64'd384;            

    localparam int TIMEOUT_CYCLES = 50_000;

    localparam logic [2:0] S_IDLE     = 3'd0;
    localparam logic [2:0] S_LOAD_W   = 3'd1;
    localparam logic [2:0] S_LOAD_ACT = 3'd2;
    localparam logic [2:0] S_COMPUTE  = 3'd3;
    localparam logic [2:0] S_RELU     = 3'd4;
    localparam logic [2:0] S_STORE    = 3'd5;
    localparam logic [2:0] S_DRAIN    = 3'd6;

    logic clk;
    logic rst_n;

    initial clk = 1'b0;
    always #5 clk = ~clk;  

    mem_req_t  mem_req;
    mem_resp_t mem_resp;
    logic [31:0] compute_cycles;

    tensor_cluster #(
        .CLUSTER_ID (CLUSTER_ID)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .mem_req        (mem_req),
        .mem_resp       (mem_resp),
        .compute_cycles (compute_cycles)
    );

    localparam int MEM_SIZE = 1024;
    logic [7:0] mem_model [0:MEM_SIZE-1];

    function automatic int addr_to_idx(logic [63:0] addr);
        return int'(addr - WEIGHT_BASE);
    endfunction

    task automatic populate_memory();
        int idx;

        for (int r = 0; r < DIM; r++) begin
            for (int c = 0; c < DIM; c++) begin
                idx = addr_to_idx(WEIGHT_BASE) + r * 8 + c;
                mem_model[idx] = 8'(r + 1);
            end
        end

        for (int r = 0; r < DIM; r++) begin
            for (int c = 0; c < DIM; c++) begin
                idx = addr_to_idx(ACT_BASE) + r * 8 + c;
                mem_model[idx] = 8'(c + 1);
            end
        end
        $display("[%0t] MEM : Weights and activations populated.", $time);
    endtask

    logic        resp_valid_q;
    logic [63:0] resp_data_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            resp_valid_q <= 1'b0;
            resp_data_q  <= 64'd0;
        end else begin
            resp_valid_q <= 1'b0;
            resp_data_q  <= 64'd0;

            if (mem_req.read_en) begin
                int base_idx;
                logic [63:0] rword;
                base_idx = addr_to_idx(mem_req.addr);
                rword    = 64'd0;
                for (int b = 0; b < 8; b++) begin
                    if (mem_req.byte_en[b]) begin
                        if ((base_idx + b) >= 0 && (base_idx + b) < MEM_SIZE)
                            rword[b*8 +: 8] = mem_model[base_idx + b];
                    end
                end
                resp_data_q  <= rword;
                resp_valid_q <= 1'b1;
            end

            if (mem_req.write_en) begin
                int base_idx;
                base_idx = addr_to_idx(mem_req.addr);
                for (int b = 0; b < 8; b++) begin
                    if (mem_req.byte_en[b]) begin
                        if ((base_idx + b) >= 0 && (base_idx + b) < MEM_SIZE)
                            mem_model[base_idx + b] = mem_req.wdata[b*8 +: 8];
                    end
                end
                resp_valid_q <= 1'b1;
            end
        end
    end

    assign mem_resp.rdata = resp_data_q;
    assign mem_resp.ready = resp_valid_q;
    assign mem_resp.error = 1'b0;

    logic [2:0] prev_state;

    function automatic string state_name(logic [2:0] s);
        case (s)
            S_IDLE:     return "IDLE";
            S_LOAD_W:   return "LOAD_W";
            S_LOAD_ACT: return "LOAD_ACT";
            S_COMPUTE:  return "COMPUTE";
            S_RELU:     return "RELU";
            S_STORE:    return "STORE";
            S_DRAIN:    return "DRAIN";
            default:    return "UNKNOWN";
        endcase
    endfunction

    always_ff @(posedge clk) begin
        if (rst_n) begin
            if (dut.state !== prev_state) begin
                $display("[%0t] FSM : %s -> %s",
                         $time, state_name(prev_state), state_name(dut.state));
            end
            prev_state <= dut.state;
        end else begin
            prev_state <= S_IDLE;
        end
    end

    function automatic int expected_result(int r, int c);

        return DIM * (r + 1) * (c + 1);
    endfunction

    int pass_count;
    int fail_count;
    int results_stored;

    task automatic check_results();
        int idx;
        int actual;
        int expect;

        results_stored = 0;
        pass_count     = 0;
        fail_count     = 0;

        $display("");
        
        $display("  RESULT VERIFICATION");
        for (int r = 0; r < DIM; r++) begin
            for (int c = 0; c < DIM; c++) begin
                idx = addr_to_idx(RESULT_BASE) + r * 32 + c * 4;

                actual = int'({mem_model[idx+3],
                               mem_model[idx+2],
                               mem_model[idx+1],
                               mem_model[idx+0]});
                expect = expected_result(r, c);

                if (actual !== 0 || expect !== 0)
                    results_stored++;

                if (actual === expect) begin
                    pass_count++;
                end else begin
                    fail_count++;
                    $display("[FAIL] C[%0d][%0d] = %0d  (expected %0d)",
                             r, c, actual, expect);
                end
            end
        end

        $display("  Checked %0d elements: %0d PASS, %0d FAIL",
                 DIM*DIM, pass_count, fail_count);
    endtask

    logic fsm_completed;

    initial begin : main_test
        int cycle_cnt;

        $dumpfile("tb_tensor_matmul.vcd");
        $dumpvars(0, tb_tensor_matmul);

        $display("");
        $display("  tb_tensor_matmul  –  Tensor Matrix Multiply Testbench");
        $display("  DIM = %0d   CLUSTER_ID = %0d", DIM, CLUSTER_ID);

        fsm_completed = 1'b0;
        rst_n         = 1'b0;

        for (int i = 0; i < MEM_SIZE; i++)
            mem_model[i] = 8'h00;

        populate_memory();

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        $display("[%0t] RST : Reset de-asserted.", $time);

        cycle_cnt = 0;
        fork

            begin : watchdog
                repeat (TIMEOUT_CYCLES) @(posedge clk);
                $display("");
                $display("[FATAL] Timeout after %0d cycles!", TIMEOUT_CYCLES);
                $display("        FSM state at timeout: %s", state_name(dut.state));
                $display("");
                $display("  OVERALL RESULT :  ** FAIL **");
                $finish;
            end

            begin : fsm_wait

                wait (dut.state != S_IDLE);
                $display("[%0t] INFO: FSM left IDLE, computation in progress...", $time);

                wait (dut.state == S_IDLE);
                $display("[%0t] INFO: FSM returned to IDLE.", $time);
                fsm_completed = 1'b1;

                repeat (10) @(posedge clk);

                disable watchdog;
            end
        join

        $display("");
        $display("  TEST RESULTS");

        if (fsm_completed) begin
            $display("  [PASS] TEST 1 : FSM completed full cycle (returned to IDLE)");
        end else begin
            $display("  [FAIL] TEST 1 : FSM did NOT complete full cycle");
        end

        if (dut.compute_cycles > 0) begin
            $display("  [PASS] TEST 2 : compute_cycles = %0d (> 0)", dut.compute_cycles);
        end else begin
            $display("  [FAIL] TEST 2 : compute_cycles = %0d (expected > 0)", dut.compute_cycles);
        end

        check_results();

        if (fail_count == 0) begin
            $display("  [PASS] TEST 3 : All result values match expected C[r][c] = %0d*(r+1)*(c+1)", DIM);
        end else begin
            $display("  [FAIL] TEST 3 : %0d result mismatches detected", fail_count);
        end

        if (results_stored == DIM * DIM) begin
            $display("  [PASS] TEST 4 : All %0d result elements stored", DIM * DIM);
        end else begin
            $display("  [FAIL] TEST 4 : Only %0d / %0d result elements stored",
                     results_stored, DIM * DIM);
        end

        $display("");
        if (fsm_completed && (dut.compute_cycles > 0) &&
            (fail_count == 0) && (results_stored == DIM * DIM)) begin
            $display("  OVERALL RESULT :  ** PASS **");
        end else begin
            $display("  OVERALL RESULT :  ** FAIL **");
        end
        $display("");

        $finish;
    end

endmodule
