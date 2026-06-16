// gpu_cluster
// SIMT GPU cluster with per-lane parallel datapath, scoreboard hazard
// interlock, speculative fetch PC, load/LDS writeback, and barrier sync.
`timescale 1ns / 1ps
module gpu_cluster #(
    parameter int CLUSTER_ID = 0
)(
    input  logic        clk,
    input  logic        rst_n,

    output nexora_x3_pkg::mem_req_t    mem_req,
    input  nexora_x3_pkg::mem_resp_t   mem_resp,

    output logic        pim_cmd_valid,
    input  logic        pim_cmd_ready,
    output logic [2:0]  pim_cmd_op,
    output logic [63:0] pim_cmd_addr_a,
    output logic [63:0] pim_cmd_addr_b,
    output logic [63:0] pim_cmd_addr_dst
);

    // ---------------------------------------------------------------
    // Parameters
    // ---------------------------------------------------------------
    localparam int REG_COUNT   = nexora_x3_pkg::REG_COUNT;
    localparam int IMEM_DEPTH  = 256;
    localparam int NUM_WARPS   = nexora_x3_pkg::WARP_COUNT;
    localparam int NUM_THREADS = nexora_x3_pkg::THREADS_PER_WARP;
    localparam int NUM_REGS    = nexora_x3_pkg::GPU_REG_COUNT;
    localparam int WARP_IDX_W  = (NUM_WARPS > 1) ? $clog2(NUM_WARPS) : 1;
    localparam int THREAD_IDX_W = $clog2(NUM_THREADS);

    // ---------------------------------------------------------------
    // Warp state arrays
    // ---------------------------------------------------------------
    logic [NUM_WARPS-1:0][1:0]  warp_state_state;
    logic [NUM_WARPS-1:0][31:0] warp_state_pc;
    logic [NUM_WARPS-1:0][31:0] warp_state_active_mask;

    // Pack into warp_state_reg for scheduler
    logic [NUM_WARPS-1:0][65:0] warp_state_reg;
    always_comb begin : pack_warp_states
        for (int i = 0; i < NUM_WARPS; i++) begin
            warp_state_reg[i] = {warp_state_state[i], warp_state_pc[i], warp_state_active_mask[i]};
        end
    end

    // ---------------------------------------------------------------
    // Instruction memory (simulation/FPGA ROM via initial)
    // ---------------------------------------------------------------
    logic [31:0] imem [0:IMEM_DEPTH-1];

    function automatic logic [31:0] encode_instr(
        input logic [3:0] op,
        input logic [4:0] rd,
        input logic [4:0] rs1,
        input logic [4:0] rs2,
        input logic [11:0] imm,
        input logic valid
    );
        encode_instr = {op, rd, rs1, rs2, imm, valid};
    endfunction

    initial begin : imem_init
        for (int i = 0; i < IMEM_DEPTH; i++) begin
            imem[i] = encode_instr(nexora_x3_pkg::GPU_NOP, 5'd0, 5'd0, 5'd0, 12'd0, 1'b1);
        end

        imem[0] = encode_instr(nexora_x3_pkg::GPU_IADD, 5'd1, 5'd2, 5'd3, 12'd0, 1'b1);
        imem[1] = encode_instr(nexora_x3_pkg::GPU_IMUL, 5'd4, 5'd1, 5'd2, 12'd0, 1'b1);
        imem[2] = encode_instr(nexora_x3_pkg::GPU_LDS,  5'd5, 5'd0, 5'd0, 12'd0, 1'b1);
        imem[3] = encode_instr(nexora_x3_pkg::GPU_STS,  5'd0, 5'd0, 5'd5, 12'd0, 1'b1);
        imem[4] = encode_instr(nexora_x3_pkg::GPU_FADD, 5'd6, 5'd1, 5'd4, 12'd0, 1'b1);
        imem[5] = encode_instr(nexora_x3_pkg::GPU_FMUL, 5'd7, 5'd6, 5'd1, 12'd0, 1'b1);
        imem[6] = encode_instr(nexora_x3_pkg::GPU_BAR,  5'd0, 5'd0, 5'd0, 12'd0, 1'b1);
        imem[7] = encode_instr(nexora_x3_pkg::GPU_EXIT, 5'd0, 5'd0, 5'd0, 12'd0, 1'b1);
    end

    // ---------------------------------------------------------------
    // Scheduler signals
    // ---------------------------------------------------------------
    logic [WARP_IDX_W-1:0] sched_warp;
    logic        sched_valid;
    logic        exec_stall;

    // ---------------------------------------------------------------
    // Speculative fetch PC — per-warp (C5 fix)
    // Advances at fetch time; redirected on branch/exit at decode.
    // ---------------------------------------------------------------
    logic [NUM_WARPS-1:0][31:0] fetch_pc_spec;

    // ---------------------------------------------------------------
    // Fetch stage signals
    // ---------------------------------------------------------------
    logic [31:0]  fetch_pc;
    logic [31:0]  fetch_instr;
    logic         fetch_valid;
    logic [WARP_IDX_W-1:0] fetch_warp;

    // ---------------------------------------------------------------
    // Decode stage signals
    // ---------------------------------------------------------------
    typedef struct packed {
        logic [3:0] op;
        logic [4:0] rd;
        logic [4:0] rs1;
        logic [4:0] rs2;
        logic [11:0] imm;
        logic valid;
    } local_gpu_instr_t;

    local_gpu_instr_t dec_instr;
    logic [WARP_IDX_W-1:0] dec_warp;
    logic [31:0]  dec_pc;
    logic         dec_valid;

    // ---------------------------------------------------------------
    // Per-thread data arrays
    // ---------------------------------------------------------------
    logic [NUM_THREADS-1:0][31:0] rs1_data_all;
    logic [NUM_THREADS-1:0][31:0] rs2_data_all;
    logic [NUM_THREADS-1:0][31:0] alu_result;
    logic [NUM_THREADS-1:0]       alu_valid_out;

    // ---------------------------------------------------------------
    // Shared memory signals
    // ---------------------------------------------------------------
    localparam int SMEM_ADDR_W = $clog2(nexora_x3_pkg::GPU_SHARED_MEM_WORDS);
    logic [SMEM_ADDR_W-1:0] smem_addr;
    logic [31:0] smem_wdata;
    logic [31:0] smem_rdata;
    logic        smem_read_en;
    logic        smem_write_en;

    // ---------------------------------------------------------------
    // Performance counters (M1: warps_active width fix)
    // ---------------------------------------------------------------
    logic [$clog2(NUM_WARPS+1)-1:0] warps_active;
    logic [31:0] total_instructions;

    // ---------------------------------------------------------------
    // Memory FSM
    // ---------------------------------------------------------------
    typedef enum logic [2:0] {
        MEM_IDLE  = 3'd0,
        MEM_LOAD  = 3'd1,
        MEM_STORE = 3'd2,
        MEM_WAIT  = 3'd3,
        MEM_PIM   = 3'd4
    } mem_state_t;

    mem_state_t mem_state;
    logic [31:0] mem_pending_addr;
    logic [31:0] mem_pending_data;
    logic [WARP_IDX_W-1:0] mem_pending_warp;
    logic [4:0]  mem_pending_rd;

    // --- C3 fix: load writeback registers ---
    logic [31:0] mem_load_data;
    logic        mem_wb_valid;       // pulse: global load data ready for writeback
    logic [WARP_IDX_W-1:0] mem_wb_warp;
    logic [4:0]  mem_wb_rd;

    // --- C3 fix: shared load writeback registers ---
    logic        smem_wb_valid;      // 1-cycle delayed smem_read_en
    logic [WARP_IDX_W-1:0] smem_wb_warp;
    logic [4:0]  smem_wb_rd;

    // --- PIM latched command registers (C6 fix) ---
    logic [2:0]  pim_cmd_op_r;
    logic [63:0] pim_cmd_addr_a_r;
    logic [63:0] pim_cmd_addr_b_r;
    logic [63:0] pim_cmd_addr_dst_r;

    // ---------------------------------------------------------------
    // Scoreboard — per-(warp, register) (C4 fix)
    // Set on issue, clear on writeback. Stall if rs1 or rs2 is pending.
    // ---------------------------------------------------------------
    logic [NUM_WARPS-1:0][NUM_REGS-1:0] scoreboard;
    logic hazard_stall;

    // ---------------------------------------------------------------
    // ALU writeback iteration — iterate threads through single write port
    // ---------------------------------------------------------------
    logic [THREAD_IDX_W-1:0] wb_thread_ctr;
    logic        wb_active;                 // writeback iteration in progress
    logic [WARP_IDX_W-1:0] wb_warp;
    logic [4:0]  wb_rd;
    logic [31:0] wb_active_mask;

    // ---------------------------------------------------------------
    // Barrier logic (H2 fix)
    // ---------------------------------------------------------------
    logic [NUM_WARPS-1:0] barrier_pending;
    logic all_at_barrier;

    // ---------------------------------------------------------------
    // Pipeline flush on branch
    // ---------------------------------------------------------------
    logic branch_redirect;
    logic [WARP_IDX_W-1:0] branch_redirect_warp;

    // ---------------------------------------------------------------
    // Warp scheduler
    // ---------------------------------------------------------------
    warp_scheduler #(
        .WARP_COUNT(NUM_WARPS)
    ) u_warp_scheduler (
        .clk          (clk),
        .rst_n        (rst_n),
        .warp_states  (warp_state_reg),
        .selected_warp(sched_warp),
        .issue_valid  (sched_valid),
        .stall        (exec_stall)
    );

    // ---------------------------------------------------------------
    // Regfile — per-thread parallel reads, single-thread write
    // ---------------------------------------------------------------
    logic        rf_write_en;
    logic [4:0]  rf_rd_addr;
    logic [31:0] rf_rd_data;
    logic [WARP_IDX_W-1:0]  rf_wr_warp;
    logic [THREAD_IDX_W-1:0] rf_wr_thread;

    simt_regfile #(
        .WARP_COUNT(NUM_WARPS),
        .THREADS   (NUM_THREADS),
        .REG_COUNT (NUM_REGS),
        .DATA_WIDTH(32)
    ) u_regfile (
        .clk          (clk),
        .rst_n        (rst_n),
        // Read ports — parallel for all threads of the decode warp
        .rd_warp_id   (dec_warp),
        .rs1_addr     (dec_instr.rs1),
        .rs2_addr     (dec_instr.rs2),
        .rs1_data_all (rs1_data_all),
        .rs2_data_all (rs2_data_all),
        // Write port — single thread
        .wr_warp_id   (rf_wr_warp),
        .wr_thread_id (rf_wr_thread),
        .rd_addr      (rf_rd_addr),
        .rd_data      (rf_rd_data),
        .rd_write_en  (rf_write_en)
    );

    // ---------------------------------------------------------------
    // ALU array — one per thread, each with its own operands (C1 fix)
    // ---------------------------------------------------------------
    logic [NUM_THREADS-1:0][31:0] alu_res_32;
    generate
        genvar t;
        for (t = 0; t < NUM_THREADS; t++) begin : gen_alu
            simt_alu u_alu (
                .clk       (clk),
                .rst_n     (rst_n),
                .op        (dec_instr.op),
                .operand_a (rs1_data_all[t]),   // per-lane operand (C1 fix)
                .operand_b (rs2_data_all[t]),   // per-lane operand (C1 fix)
                .valid_in  (dec_valid && !hazard_stall),
                .result    (alu_res_32[t]),
                .valid_out (alu_valid_out[t]),
                .stall_out ()
            );
            assign alu_result[t] = alu_res_32[t];
        end
    endgenerate

    // ---------------------------------------------------------------
    // Shared memory
    // ---------------------------------------------------------------
    shared_memory #(
        .MEM_DEPTH(nexora_x3_pkg::GPU_SHARED_MEM_WORDS)
    ) u_shared_mem (
        .clk      (clk),
        .rst_n    (rst_n),
        .addr     (smem_addr),
        .wdata    (smem_wdata),
        .rdata    (smem_rdata),
        .read_en  (smem_read_en),
        .write_en (smem_write_en)
    );

    // ---------------------------------------------------------------
    // Determine if an op writes to rd (used by scoreboard + writeback)
    // ---------------------------------------------------------------
    function automatic logic op_writes_rd(input logic [3:0] op);
        case (op)
            nexora_x3_pkg::GPU_IADD,
            nexora_x3_pkg::GPU_IMUL,
            nexora_x3_pkg::GPU_FADD,
            nexora_x3_pkg::GPU_FMUL,
            nexora_x3_pkg::GPU_LD,
            nexora_x3_pkg::GPU_LDS:  op_writes_rd = 1'b1;
            default:                  op_writes_rd = 1'b0;
        endcase
    endfunction

    // Is this an ALU-writeback op? (excludes load/LDS which have separate paths)
    function automatic logic is_alu_wb_op(input logic [3:0] op);
        case (op)
            nexora_x3_pkg::GPU_IADD,
            nexora_x3_pkg::GPU_IMUL,
            nexora_x3_pkg::GPU_FADD,
            nexora_x3_pkg::GPU_FMUL:  is_alu_wb_op = 1'b1;
            default:                   is_alu_wb_op = 1'b0;
        endcase
    endfunction

    // ---------------------------------------------------------------
    // Hazard detection — scoreboard check (C4 fix)
    // Stall if decode instruction reads a register with a pending write
    // ---------------------------------------------------------------
    always_comb begin : hazard_check
        hazard_stall = 1'b0;
        if (dec_valid) begin
            if ((dec_instr.rs1 != 5'd0) && scoreboard[dec_warp][dec_instr.rs1])
                hazard_stall = 1'b1;
            if ((dec_instr.rs2 != 5'd0) && scoreboard[dec_warp][dec_instr.rs2])
                hazard_stall = 1'b1;
        end
    end

    // ---------------------------------------------------------------
    // Combined stall logic
    // ---------------------------------------------------------------
    always_comb begin : stall_logic
        exec_stall = (mem_state == MEM_LOAD)  ||
                     (mem_state == MEM_STORE) ||
                     (mem_state == MEM_WAIT)  ||
                     (mem_state == MEM_PIM)   ||
                     hazard_stall             ||
                     wb_active;    // stall while iterating writeback threads
    end

    // ---------------------------------------------------------------
    // FETCH STAGE — speculative PC (C5 fix)
    // ---------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin : fetch_stage
        if (!rst_n) begin
            fetch_pc    <= 32'd0;
            fetch_instr <= 32'd0;
            fetch_valid <= 1'b0;
            fetch_warp  <= '0;
            for (int w = 0; w < NUM_WARPS; w++) begin
                fetch_pc_spec[w] <= 32'd0;
            end
        end else begin
            // Branch redirect — flush fetch if redirecting the same warp
            if (branch_redirect) begin
                // If the fetched instruction was from the redirected warp, invalidate it
                if (fetch_valid && (fetch_warp == branch_redirect_warp)) begin
                    fetch_valid <= 1'b0;
                end
            end

            if (sched_valid && !exec_stall) begin
                fetch_pc    <= fetch_pc_spec[sched_warp];
                fetch_instr <= imem[fetch_pc_spec[sched_warp][7:0]];
                fetch_valid <= 1'b1;
                fetch_warp  <= sched_warp;

                // Advance speculative PC immediately (C5 fix)
                fetch_pc_spec[sched_warp] <= fetch_pc_spec[sched_warp] + 32'd1;
            end else begin
                fetch_valid <= 1'b0;
            end

            // Branch redirect updates speculative PC
            if (branch_redirect) begin
                // The new target is written to fetch_pc_spec in the warp_fsm section
                // via the branch_redirect signals below
            end
        end
    end

    // ---------------------------------------------------------------
    // DECODE STAGE — (M2 fix: imm width)
    // ---------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin : decode_stage
        if (!rst_n) begin
            dec_instr.op    <= nexora_x3_pkg::GPU_NOP;
            dec_instr.rd    <= '0;
            dec_instr.rs1   <= '0;
            dec_instr.rs2   <= '0;
            dec_instr.imm   <= '0;
            dec_instr.valid <= 1'b0;
            dec_warp  <= '0;
            dec_pc    <= 32'd0;
            dec_valid <= 1'b0;
        end else begin
            if (fetch_valid && !exec_stall) begin
                dec_instr.op    <= fetch_instr[31:28];
                dec_instr.rd    <= fetch_instr[27:23];
                dec_instr.rs1   <= fetch_instr[22:18];
                dec_instr.rs2   <= fetch_instr[17:13];
                dec_instr.imm   <= fetch_instr[12:1];   // M2 fix: no {4'b0,...} concat
                dec_instr.valid <= fetch_instr[0];
                dec_warp        <= fetch_warp;
                dec_pc          <= fetch_pc;
                dec_valid       <= 1'b1;
            end else begin
                dec_instr.op    <= nexora_x3_pkg::GPU_NOP;
                dec_instr.rd    <= '0;
                dec_instr.rs1   <= '0;
                dec_instr.rs2   <= '0;
                dec_instr.imm   <= '0;
                dec_instr.valid <= 1'b0;
                dec_warp  <= '0;
                dec_pc    <= 32'd0;
                dec_valid <= 1'b0;
            end
        end
    end

    // ---------------------------------------------------------------
    // Shared memory control
    // ---------------------------------------------------------------
    logic [31:0] imm_ext;
    always_comb begin : smem_ctrl
        imm_ext       = {20'd0, dec_instr.imm};
        smem_addr     = imm_ext[SMEM_ADDR_W-1:0] + rs1_data_all[0][SMEM_ADDR_W-1:0];
        smem_wdata    = rs2_data_all[0];
        smem_read_en  = dec_valid && !hazard_stall && (dec_instr.op == nexora_x3_pkg::GPU_LDS);
        smem_write_en = dec_valid && !hazard_stall && (dec_instr.op == nexora_x3_pkg::GPU_STS);
    end

    // ---------------------------------------------------------------
    // Shared memory load writeback tracking (C3 fix)
    // smem has 1-cycle read latency → delay the valid + capture rd/warp
    // ---------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin : smem_wb_track
        if (!rst_n) begin
            smem_wb_valid <= 1'b0;
            smem_wb_warp  <= '0;
            smem_wb_rd    <= 5'd0;
        end else begin
            smem_wb_valid <= smem_read_en;
            if (smem_read_en) begin
                smem_wb_warp <= dec_warp;
                smem_wb_rd   <= dec_instr.rd;
            end
        end
    end

    // ---------------------------------------------------------------
    // ALU writeback iteration — iterate wb_thread_ctr through all
    // threads for the single regfile write port (C1/C2 fix)
    // ---------------------------------------------------------------
    // Pipeline registers to capture the decode-stage info when ALU fires
    logic [WARP_IDX_W-1:0] alu_wb_warp_r;
    logic [4:0]            alu_wb_rd_r;
    logic [3:0]            alu_wb_op_r;
    logic [31:0]           alu_wb_active_mask_r;

    always_ff @(posedge clk or negedge rst_n) begin : alu_wb_pipeline
        if (!rst_n) begin
            alu_wb_warp_r        <= '0;
            alu_wb_rd_r          <= 5'd0;
            alu_wb_op_r          <= nexora_x3_pkg::GPU_NOP;
            alu_wb_active_mask_r <= 32'd0;
        end else if (dec_valid && !exec_stall && is_alu_wb_op(dec_instr.op)) begin
            alu_wb_warp_r        <= dec_warp;
            alu_wb_rd_r          <= dec_instr.rd;
            alu_wb_op_r          <= dec_instr.op;
            alu_wb_active_mask_r <= warp_state_active_mask[dec_warp];
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin : wb_thread_iter
        if (!rst_n) begin
            wb_thread_ctr <= '0;
            wb_active     <= 1'b0;
            wb_warp       <= '0;
            wb_rd         <= 5'd0;
            wb_active_mask <= 32'd0;
        end else begin
            if (!wb_active && alu_valid_out[0] && is_alu_wb_op(alu_wb_op_r)) begin
                // Start writeback iteration
                wb_active      <= 1'b1;
                wb_thread_ctr  <= '0;
                wb_warp        <= alu_wb_warp_r;
                wb_rd          <= alu_wb_rd_r;
                wb_active_mask <= alu_wb_active_mask_r;
            end else if (wb_active) begin
                if (wb_thread_ctr == THREAD_IDX_W'(NUM_THREADS - 1)) begin
                    wb_active     <= 1'b0;
                    wb_thread_ctr <= '0;
                end else begin
                    wb_thread_ctr <= wb_thread_ctr + 1'b1;
                end
            end
        end
    end

    // ---------------------------------------------------------------
    // Writeback MUX (C3 fix: load/LDS writeback + H3: active mask)
    // Priority: mem_load > smem_load > ALU iteration
    // ---------------------------------------------------------------
    always_comb begin : rf_writeback_mux
        rf_write_en  = 1'b0;
        rf_rd_addr   = 5'd0;
        rf_rd_data   = 32'd0;
        rf_wr_warp   = '0;
        rf_wr_thread = '0;

        if (mem_wb_valid) begin
            // Global load writeback — write to thread 0 (scalar load for now)
            rf_write_en  = 1'b1;
            rf_rd_addr   = mem_wb_rd;
            rf_rd_data   = mem_load_data;
            rf_wr_warp   = mem_wb_warp;
            rf_wr_thread = '0;
        end else if (smem_wb_valid) begin
            // Shared load writeback — write to thread 0 (scalar load for now)
            rf_write_en  = 1'b1;
            rf_rd_addr   = smem_wb_rd;
            rf_rd_data   = smem_rdata;
            rf_wr_warp   = smem_wb_warp;
            rf_wr_thread = '0;
        end else if (wb_active) begin
            // ALU writeback — iterate through all threads
            // H3 fix: respect active_mask
            rf_write_en  = wb_active_mask[wb_thread_ctr] && (wb_rd != 5'd0);
            rf_rd_addr   = wb_rd;
            rf_rd_data   = alu_result[wb_thread_ctr];
            rf_wr_warp   = wb_warp;
            rf_wr_thread = wb_thread_ctr;
        end
    end

    // ---------------------------------------------------------------
    // Scoreboard management (C4 fix)
    // ---------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin : scoreboard_mgmt
        if (!rst_n) begin
            for (int w = 0; w < NUM_WARPS; w++)
                scoreboard[w] <= '0;
        end else begin
            // SET on issue: mark rd as pending
            if (dec_valid && !exec_stall && op_writes_rd(dec_instr.op) && (dec_instr.rd != 5'd0)) begin
                scoreboard[dec_warp][dec_instr.rd] <= 1'b1;
            end

            // CLEAR on writeback completion
            // Global load: single-cycle writeback
            if (mem_wb_valid && (mem_wb_rd != 5'd0)) begin
                scoreboard[mem_wb_warp][mem_wb_rd] <= 1'b0;
            end
            // Shared load: single-cycle writeback
            if (smem_wb_valid && (smem_wb_rd != 5'd0)) begin
                scoreboard[smem_wb_warp][smem_wb_rd] <= 1'b0;
            end
            // ALU: clear after last thread written back
            if (wb_active && (wb_thread_ctr == THREAD_IDX_W'(NUM_THREADS - 1)) && (wb_rd != 5'd0)) begin
                scoreboard[wb_warp][wb_rd] <= 1'b0;
            end
        end
    end

    // ---------------------------------------------------------------
    // Barrier logic (H2 fix)
    // All non-DONE warps must reach barrier before any proceeds.
    // ---------------------------------------------------------------
    always_comb begin : barrier_check
        all_at_barrier = |barrier_pending; // at least one warp hit barrier
        for (int w = 0; w < NUM_WARPS; w++) begin
            // A running (non-barrier, non-done) warp blocks the barrier
            if ((warp_state_state[w] == nexora_x3_pkg::WARP_RUNNING) && !barrier_pending[w])
                all_at_barrier = 1'b0;
        end
    end

    // ---------------------------------------------------------------
    // Branch redirect signal
    // ---------------------------------------------------------------
    always_comb begin : branch_redirect_logic
        branch_redirect      = 1'b0;
        branch_redirect_warp = '0;
        if (dec_valid && !exec_stall) begin
            if (dec_instr.op == nexora_x3_pkg::GPU_BRA ||
                dec_instr.op == nexora_x3_pkg::GPU_EXIT) begin
                branch_redirect      = 1'b1;
                branch_redirect_warp = dec_warp;
            end
        end
    end

    // ---------------------------------------------------------------
    // WARP FSM — state machine, PC update, barrier, branch (H1/H2/H4)
    // ---------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin : warp_fsm
        if (!rst_n) begin
            for (int w = 0; w < NUM_WARPS; w++) begin
                warp_state_state[w]       <= nexora_x3_pkg::WARP_IDLE;
                warp_state_pc[w]          <= 32'd0;
                warp_state_active_mask[w] <= 32'hFFFF_FFFF;
            end
            barrier_pending <= '0;

        end else begin

            // H1 fix: start ALL warps, not just warp 0
            for (int w = 0; w < NUM_WARPS; w++) begin
                if (warp_state_state[w] == nexora_x3_pkg::WARP_IDLE) begin
                    warp_state_state[w] <= nexora_x3_pkg::WARP_RUNNING;
                end
            end

            // H2 fix: barrier release — when all non-DONE warps have arrived
            if (all_at_barrier) begin
                for (int w = 0; w < NUM_WARPS; w++) begin
                    if (barrier_pending[w]) begin
                        warp_state_state[w] <= nexora_x3_pkg::WARP_RUNNING;
                        barrier_pending[w]  <= 1'b0;
                    end
                end
            end

            if (dec_valid && !exec_stall && !hazard_stall) begin
                case (dec_instr.op)
                    nexora_x3_pkg::GPU_EXIT: begin
                        warp_state_state[dec_warp] <= nexora_x3_pkg::WARP_DONE;
                    end

                    nexora_x3_pkg::GPU_BAR: begin
                        // H2 fix: real barrier — stall warp until all arrive
                        warp_state_state[dec_warp] <= nexora_x3_pkg::WARP_STALLED;
                        warp_state_pc[dec_warp]    <= dec_pc + 32'd1;
                        barrier_pending[dec_warp]  <= 1'b1;
                        // Also update speculative fetch PC
                        fetch_pc_spec[dec_warp]    <= dec_pc + 32'd1;
                    end

                    nexora_x3_pkg::GPU_BRA: begin
                        // H4 fix: use imm[11] for sign-extension, produce 32-bit offset
                        warp_state_pc[dec_warp] <=
                            dec_pc + {{20{dec_instr.imm[11]}}, dec_instr.imm};
                        // Redirect speculative fetch PC to branch target
                        fetch_pc_spec[dec_warp] <=
                            dec_pc + {{20{dec_instr.imm[11]}}, dec_instr.imm};
                    end

                    nexora_x3_pkg::GPU_LD, nexora_x3_pkg::GPU_ST: begin
                        warp_state_state[dec_warp] <= nexora_x3_pkg::WARP_STALLED;
                        warp_state_pc[dec_warp]    <= dec_pc + 32'd1;
                        fetch_pc_spec[dec_warp]    <= dec_pc + 32'd1;
                    end

                    nexora_x3_pkg::GPU_PIM: begin
                        warp_state_state[dec_warp] <= nexora_x3_pkg::WARP_STALLED;
                        warp_state_pc[dec_warp]    <= dec_pc + 32'd1;
                        fetch_pc_spec[dec_warp]    <= dec_pc + 32'd1;
                    end

                    default: begin
                        // Normal ALU/LDS/STS — architectural PC advances
                        warp_state_pc[dec_warp] <=
                            (dec_pc < (IMEM_DEPTH - 1)) ? (dec_pc + 32'd1) : dec_pc;
                    end
                endcase
            end

            // Un-stall warp after memory completes
            if (mem_wb_valid) begin
                warp_state_state[mem_wb_warp] <= nexora_x3_pkg::WARP_RUNNING;
            end

            // Un-stall warp after PIM completes (C6)
            if ((mem_state == MEM_PIM) && pim_cmd_ready) begin
                warp_state_state[mem_pending_warp] <= nexora_x3_pkg::WARP_RUNNING;
            end
        end
    end

    // ---------------------------------------------------------------
    // MEMORY FSM (C3: capture load data, C6: explicit MEM_PIM state)
    // ---------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin : mem_fsm
        if (!rst_n) begin
            mem_state        <= MEM_IDLE;
            mem_pending_addr <= 32'd0;
            mem_pending_data <= 32'd0;
            mem_pending_warp <= '0;
            mem_pending_rd   <= 5'd0;
            mem_req.addr     <= '0;
            mem_req.wdata    <= '0;
            mem_req.read_en  <= 1'b0;
            mem_req.write_en <= 1'b0;
            mem_req.byte_en  <= 8'hFF;
            mem_load_data    <= 32'd0;
            mem_wb_valid     <= 1'b0;
            mem_wb_warp      <= '0;
            mem_wb_rd        <= 5'd0;
            // PIM latched regs (C6)
            pim_cmd_op_r       <= 3'd0;
            pim_cmd_addr_a_r   <= 64'd0;
            pim_cmd_addr_b_r   <= 64'd0;
            pim_cmd_addr_dst_r <= 64'd0;
        end else begin
            // Default: clear single-cycle writeback pulses
            mem_wb_valid <= 1'b0;

            case (mem_state)
                MEM_IDLE: begin
                    mem_req.read_en  <= 1'b0;
                    mem_req.write_en <= 1'b0;

                    if (dec_valid && !hazard_stall && (dec_instr.op == nexora_x3_pkg::GPU_LD)) begin
                        mem_pending_addr <= nexora_x3_pkg::GPU_SMEM_BASE[31:0]
                                          + rs1_data_all[0]
                                          + {{20{dec_instr.imm[11]}}, dec_instr.imm};
                        mem_pending_warp <= dec_warp;
                        mem_pending_rd   <= dec_instr.rd;
                        mem_state        <= MEM_LOAD;
                    end else if (dec_valid && !hazard_stall && (dec_instr.op == nexora_x3_pkg::GPU_ST)) begin
                        mem_pending_addr <= nexora_x3_pkg::GPU_SMEM_BASE[31:0]
                                          + rs1_data_all[0]
                                          + {{20{dec_instr.imm[11]}}, dec_instr.imm};
                        mem_pending_data <= rs2_data_all[0];
                        mem_pending_warp <= dec_warp;
                        mem_state        <= MEM_STORE;
                    end else if (dec_valid && !hazard_stall && (dec_instr.op == nexora_x3_pkg::GPU_PIM) && (mem_state == MEM_IDLE)) begin
                        mem_state        <= MEM_PIM;
                        mem_pending_warp <= dec_warp;
                        // C6 fix: latch PIM command fields so they remain stable
                        pim_cmd_op_r       <= dec_instr.imm[2:0];
                        pim_cmd_addr_a_r   <= {32'd0, rs1_data_all[0]};
                        pim_cmd_addr_b_r   <= {32'd0, rs2_data_all[0]};
                        // M3 fix: explicit 64-bit width for pim_cmd_addr_dst
                        pim_cmd_addr_dst_r <= nexora_x3_pkg::GPU_SMEM_BASE + {52'd0, dec_instr.imm};
                    end
                end

                MEM_LOAD: begin
                    mem_req.addr     <= {{32{1'b0}}, mem_pending_addr};
                    mem_req.wdata    <= 32'd0;
                    mem_req.read_en  <= 1'b1;
                    mem_req.write_en <= 1'b0;
                    mem_req.byte_en  <= 8'hFF;
                    mem_state        <= MEM_WAIT;
                end

                MEM_STORE: begin
                    mem_req.addr     <= {{32{1'b0}}, mem_pending_addr};
                    mem_req.wdata    <= mem_pending_data;
                    mem_req.read_en  <= 1'b0;
                    mem_req.write_en <= 1'b1;
                    mem_req.byte_en  <= 8'hFF;
                    mem_state        <= MEM_WAIT;
                end

                MEM_WAIT: begin
                    if (mem_resp.ready) begin
                        mem_req.read_en  <= 1'b0;
                        mem_req.write_en <= 1'b0;
                        // C3 fix: capture load data for writeback
                        mem_load_data    <= mem_resp.rdata[31:0];
                        mem_wb_valid     <= 1'b1;
                        mem_wb_warp      <= mem_pending_warp;
                        mem_wb_rd        <= mem_pending_rd;
                        mem_state        <= MEM_IDLE;
                    end
                end

                // C6 fix: explicit MEM_PIM state — hold until handshake
                MEM_PIM: begin
                    if (pim_cmd_ready) begin
                        mem_state <= MEM_IDLE;
                    end
                    // else stay in MEM_PIM; pim_cmd_valid remains asserted
                end

                default: begin
                    mem_state <= MEM_IDLE;
                end
            endcase
        end
    end

    // ---------------------------------------------------------------
    // PIM command outputs — driven from latched registers (C6 fix)
    // ---------------------------------------------------------------
    always_comb begin : pim_dispatch
        pim_cmd_valid    = (mem_state == MEM_PIM);
        pim_cmd_op       = pim_cmd_op_r;
        pim_cmd_addr_a   = pim_cmd_addr_a_r;
        pim_cmd_addr_b   = pim_cmd_addr_b_r;
        pim_cmd_addr_dst = pim_cmd_addr_dst_r;
    end

    // ---------------------------------------------------------------
    // Performance counters (M1: warps_active width fix)
    // ---------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin : perf_counters
        if (!rst_n) begin
            warps_active        <= '0;
            total_instructions  <= 32'd0;
        end else begin

            begin : count_warps
                logic [$clog2(NUM_WARPS+1)-1:0] cnt;
                cnt = '0;
                for (int w = 0; w < NUM_WARPS; w++) begin
                    if (warp_state_state[w] == nexora_x3_pkg::WARP_RUNNING) begin
                        cnt = cnt + 1'b1;
                    end
                end
                warps_active <= cnt;
            end

            if (dec_valid && !exec_stall && (dec_instr.op != nexora_x3_pkg::GPU_NOP)) begin
                total_instructions <= total_instructions + 32'd1;
            end
        end
    end

endmodule : gpu_cluster
