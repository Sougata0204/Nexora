// cpu_core
`timescale 1ns / 1ps
module cpu_core #(
    parameter int DATA_WIDTH = nexora_x3_pkg::DATA_WIDTH,
    parameter int ADDR_WIDTH = nexora_x3_pkg::ADDR_WIDTH,
    parameter int INSTR_WIDTH = nexora_x3_pkg::INSTR_WIDTH
)(
    input  logic clk,
    input  logic rst_n,

    output nexora_x3_pkg::mem_req_t  imem_req,
    input  nexora_x3_pkg::mem_resp_t imem_resp,

    output nexora_x3_pkg::mem_req_t  dmem_req,
    input  nexora_x3_pkg::mem_resp_t dmem_resp,

    output nexora_x3_pkg::cpu_debug_t   cpu_debug,
    output nexora_x3_pkg::debug_signals_t debug,

    output logic         halt,

    output logic [31:0]  instruction_count,
    output logic [31:0]  cycle_count,
    output logic [31:0]  cache_hits,
    output logic [31:0]  cache_misses,
    output logic [31:0]  stall_count,
    output logic [31:0]  branch_count
);

    localparam int REG_ADDR_WIDTH = nexora_x3_pkg::REG_ADDR_WIDTH;
    localparam int ISSUE_WIDTH    = nexora_x3_pkg::ISSUE_WIDTH;
    localparam int ALU_COUNT      = nexora_x3_pkg::ALU_COUNT;
    localparam int QUEUE_DEPTH    = nexora_x3_pkg::QUEUE_DEPTH;

    nexora_x3_pkg::if_id_reg_t  if_id;
    nexora_x3_pkg::id_ex_reg_t  id_ex;
    nexora_x3_pkg::ex_mem_reg_t ex_mem;
    nexora_x3_pkg::mem_wb_reg_t mem_wb;

    logic        stall_pipeline;
    logic        flush_if_id;
    logic        flush_id_ex;

    logic [4:0]  rs1_addr, rs2_addr;
    logic        illegal_instr;

    logic [4:0]  rf_rd_addr;
    logic [DATA_WIDTH-1:0] rf_rd_data;
    logic        rf_rd_write;
    logic [DATA_WIDTH-1:0] rf_rs1_data, rf_rs2_data;

    logic [DATA_WIDTH-1:0] alu_result;
    logic        alu_zero, alu_overflow;
    logic        branch_taken;
    logic [ADDR_WIDTH-1:0] branch_target;
    logic        branch_flush;
    logic        load_use_hazard;
    logic        halt_reg;

    nexora_x3_pkg::debug_signals_t fetch_debug;
    nexora_x3_pkg::debug_signals_t decode_debug;
    nexora_x3_pkg::debug_signals_t alu_debug;
    nexora_x3_pkg::debug_signals_t regfile_debug;
    nexora_x3_pkg::debug_signals_t branch_debug;
    nexora_x3_pkg::debug_signals_t lsu_debug;

    logic [DATA_WIDTH-1:0] fetch_debug_pc;

    logic icache_hit, icache_miss;
    logic dcache_hit, dcache_miss;

    nexora_x3_pkg::mem_req_t  core_imem_req;
    nexora_x3_pkg::mem_resp_t core_imem_resp;
    nexora_x3_pkg::mem_req_t  core_dmem_req;
    nexora_x3_pkg::mem_resp_t core_dmem_resp;

    l1_cache #(
        .CACHE_SIZE(16 * 1024)  // Reduced for Vivado RTL lint (ASIC: restore to 128KB)
    ) u_l1_icache (
        .clk(clk),
        .rst_n(rst_n),
        .core_req(core_imem_req),
        .core_resp(core_imem_resp),
        .l2_req(imem_req),
        .l2_resp(imem_resp),
        .hit(icache_hit),
        .miss(icache_miss)
    );

    l1_cache #(
        .CACHE_SIZE(16 * 1024)  // Reduced for Vivado RTL lint (ASIC: restore to 128KB)
    ) u_l1_dcache (
        .clk(clk),
        .rst_n(rst_n),
        .core_req(core_dmem_req),
        .core_resp(core_dmem_resp),
        .l2_req(dmem_req),
        .l2_resp(dmem_resp),
        .hit(dcache_hit),
        .miss(dcache_miss)
    );

    fetch #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_fetch (
        .clk          (clk),
        .rst_n        (rst_n),
        .stall        (stall_pipeline),
        .flush        (flush_if_id || branch_taken),
        .branch_taken (branch_taken),
        .branch_target(branch_target),
        .jump_taken   (1'b0),
        .jump_target  ('0),
        .imem_req     (core_imem_req),
        .imem_resp    (core_imem_resp),
        .if_id_out    (if_id),
        .debug        (fetch_debug),
        .debug_pc     (fetch_debug_pc)
    );

    decode #(
        .DATA_WIDTH(DATA_WIDTH),
        .INSTR_WIDTH(INSTR_WIDTH)
    ) u_decode (
        .clk          (clk),
        .rst_n        (rst_n),
        .if_id_in     (if_id),
        .stall        (stall_pipeline),
        .flush        (flush_if_id || branch_taken),
        .rs1_addr     (rs1_addr),
        .rs2_addr     (rs2_addr),
        .rs1_data     (rf_rs1_data),
        .rs2_data     (rf_rs2_data),
        .id_ex_out    (id_ex),
        .illegal_instr(illegal_instr),
        .debug        (decode_debug)
    );

    register_file #(
        .DATA_WIDTH    (DATA_WIDTH),
        .REG_ADDR_WIDTH(5),
        .REG_COUNT     (32)
    ) u_regfile (
        .clk         (clk),
        .rst_n       (rst_n),
        .rs1_addr    (rs1_addr),
        .rs2_addr    (rs2_addr),
        .rd_addr     (rf_rd_addr),
        .rd_data     (rf_rd_data),
        .rd_write_en (rf_rd_write),
        .rs1_data    (rf_rs1_data),
        .rs2_data    (rf_rs2_data),
        .debug       (regfile_debug)
    );

    logic [ISSUE_WIDTH-1:0] iq_valid;
    nexora_x3_pkg::id_ex_reg_t [ISSUE_WIDTH-1:0] iq_data;
    logic [ISSUE_WIDTH-1:0] iq_ack;
    logic iq_ready;
    nexora_x3_pkg::debug_signals_t iq_debug;

    instruction_queue #(
        .QUEUE_DEPTH(QUEUE_DEPTH),
        .ISSUE_WIDTH(ISSUE_WIDTH)
    ) u_iq (
        .clk(clk),
        .rst_n(rst_n),
        .enqueue_valid(id_ex.valid && !stall_pipeline), 
        .enqueue_data(id_ex),
        .enqueue_ready(iq_ready),
        .dequeue_valid(iq_valid),
        .dequeue_data(iq_data),
        .dequeue_ack(iq_ack),
        .flush(flush_if_id || branch_taken), 
        .debug_state(iq_debug.state),
        .debug_counter(iq_debug.counter),
        .debug_valid(iq_debug.valid),
        .debug_error(iq_debug.error)
    );

    logic [ISSUE_WIDTH-1:0] sched_valid;
    nexora_x3_pkg::dispatch_packet_t [ISSUE_WIDTH-1:0] sched_data;
    logic [4:0] sched_ready_count;

    logic non_alu_valid;
    nexora_x3_pkg::id_ex_reg_t non_alu_data;
    logic non_alu_ready;
    assign non_alu_ready = 1'b1; 

    logic sched_wb_valid;
    logic [4:0] sched_wb_rd;
    logic [DATA_WIDTH-1:0] sched_wb_data;

    nexora_x3_pkg::debug_signals_t dispatch_debug;

    dispatch_unit #(
        .ISSUE_WIDTH(ISSUE_WIDTH),
        .ALU_COUNT(ALU_COUNT)
    ) u_dispatch (
        .clk(clk),
        .rst_n(rst_n),
        .iq_valid(iq_valid),
        .iq_data(iq_data),
        .iq_ack(iq_ack),
        .sched_valid(sched_valid),
        .sched_data(sched_data),
        .sched_ready_count(sched_ready_count),
        .non_alu_valid(non_alu_valid),
        .non_alu_data(non_alu_data),
        .non_alu_ready(non_alu_ready),
        .sched_wb_valid(sched_wb_valid),
        .sched_wb_rd(sched_wb_rd),
        .sched_wb_data(sched_wb_data),
        .mem_wb_valid(mem_wb.valid),
        .mem_wb_rd(mem_wb.rd_addr),
        .mem_wb_data(rf_rd_data),
        .flush(flush_if_id || branch_taken),
        .debug_state(dispatch_debug.state),
        .debug_counter(dispatch_debug.counter),
        .debug_valid(dispatch_debug.valid),
        .debug_error(dispatch_debug.error)
    );

    logic [ALU_COUNT-1:0] alu_valid;
    nexora_x3_pkg::dispatch_packet_t [ALU_COUNT-1:0] alu_data;
    logic [ALU_COUNT-1:0] alu_done;
    logic [ALU_COUNT-1:0] [DATA_WIDTH-1:0] cluster_result;
    logic [ALU_COUNT-1:0] [4:0] cluster_rd;
    logic [ALU_COUNT-1:0] cluster_reg_write;

    nexora_x3_pkg::debug_signals_t sched_debug;

    scheduler #(
        .ISSUE_WIDTH(ISSUE_WIDTH),
        .ALU_COUNT(ALU_COUNT)
    ) u_scheduler (
        .clk(clk),
        .rst_n(rst_n),
        .sched_valid(sched_valid),
        .sched_data(sched_data),
        .sched_ready_count(sched_ready_count),
        .alu_valid(alu_valid),
        .alu_data(alu_data),
        .alu_done(alu_done),
        .alu_result(cluster_result),
        .alu_rd(cluster_rd),
        .alu_reg_write(cluster_reg_write),
        .wb_valid(sched_wb_valid),
        .wb_rd(sched_wb_rd),
        .wb_data(sched_wb_data),
        .flush(flush_if_id || branch_taken),
        .debug_state(sched_debug.state),
        .debug_counter(sched_debug.counter),
        .debug_valid(sched_debug.valid),
        .debug_error(sched_debug.error)
    );

    nexora_x3_pkg::debug_signals_t cluster_debug;

    execution_cluster #(
        .ALU_COUNT(ALU_COUNT)
    ) u_cluster (
        .clk(clk),
        .rst_n(rst_n),
        .alu_valid(alu_valid),
        .alu_data(alu_data),
        .alu_done(alu_done),
        .alu_result(cluster_result),
        .alu_rd(cluster_rd),
        .alu_reg_write(cluster_reg_write),
        .flush(flush_if_id || branch_taken),
        .debug_state(cluster_debug.state),
        .debug_counter(cluster_debug.counter),
        .debug_valid(cluster_debug.valid),
        .debug_error(cluster_debug.error)
    );

    control_unit #(
        .REG_ADDR_WIDTH(5)
    ) u_control (
        .clk              (clk),
        .rst_n            (rst_n),
        .if_id_rs1_addr   (rs1_addr),
        .if_id_rs2_addr   (rs2_addr),
        .id_ex_mem_read   (1'b0), 
        .id_ex_rd_addr    (5'd0),
        .ex_mem_rd_addr   (5'd0),
        .ex_mem_reg_write (1'b0),
        .ex_mem_mem_read  (1'b0),
        .ex_mem_valid     (1'b0),
        .mem_wb_rd_addr   (5'd0),
        .mem_wb_reg_write (1'b0),
        .mem_wb_valid     (1'b0),
        .branch_taken     (branch_taken),
        .forward_a        (),
        .forward_b        (),
        .stall_pipeline   (load_use_hazard), 
        .flush_if_id      (flush_if_id),
        .flush_id_ex      (flush_id_ex)
    );

    assign stall_pipeline = !iq_ready;

    logic [DATA_WIDTH-1:0] alu_operand_a;
    logic [DATA_WIDTH-1:0] alu_operand_b;

    assign alu_operand_a = (non_alu_data.instruction[6:0] == nexora_x3_pkg::OP_AUIPC) ? non_alu_data.pc : non_alu_data.rs1_data;
    assign alu_operand_b = non_alu_data.alu_src ? non_alu_data.imm : non_alu_data.rs2_data;

    alu #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_alu_address (
        .clk          (clk),
        .rst_n        (rst_n),
        .operand_a    (alu_operand_a),
        .operand_b    (alu_operand_b),
        .alu_op       (non_alu_valid ? non_alu_data.alu_op : nexora_x3_pkg::ALU_NOP),
        .result       (alu_result),
        .zero_flag    (alu_zero),
        .overflow_flag(alu_overflow),
        .debug        (alu_debug)
    );

    branch_unit #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_branch (
        .clk            (clk),
        .rst_n          (rst_n),
        .branch_en      (non_alu_data.branch && non_alu_valid),
        .jump_en        (non_alu_data.jump && non_alu_valid),
        .is_jalr        (non_alu_data.is_jalr),
        .funct3         (non_alu_data.funct3),
        .rs1_data       (non_alu_data.rs1_data),
        .rs2_data       (non_alu_data.rs2_data),
        .pc             (non_alu_data.pc),
        .immediate      (non_alu_data.imm),
        .branch_taken   (branch_taken),
        .target_addr    (branch_target),
        .flush_pipeline (branch_flush),
        .debug          (branch_debug)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem.alu_result <= '0;
            ex_mem.rs2_data   <= '0;
            ex_mem.rd_addr    <= '0;
            ex_mem.mem_read   <= '0;
            ex_mem.mem_write  <= '0;
            ex_mem.reg_write  <= '0;
            ex_mem.funct3     <= '0;
            ex_mem.pc_plus4   <= '0;
            ex_mem.is_jump    <= '0;
            ex_mem.valid      <= '0;
        end else begin
            ex_mem.alu_result <= alu_result;
            ex_mem.rs2_data   <= non_alu_data.rs2_data;  
            ex_mem.rd_addr    <= non_alu_data.rd_addr;
            ex_mem.mem_read   <= non_alu_data.mem_read;
            ex_mem.mem_write  <= non_alu_data.mem_write;
            ex_mem.reg_write  <= non_alu_data.reg_write;
            ex_mem.funct3     <= non_alu_data.funct3;
            ex_mem.pc_plus4   <= non_alu_data.pc + 32'd4;
            ex_mem.is_jump    <= non_alu_data.jump;
            ex_mem.valid      <= non_alu_valid && (!branch_taken || non_alu_data.jump);
        end
    end

    load_store_unit #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_lsu (
        .clk       (clk),
        .rst_n     (rst_n),
        .ex_mem_in (ex_mem),
        .dmem_req  (core_dmem_req),
        .dmem_resp (core_dmem_resp),
        .mem_wb_out(mem_wb),
        .debug     (lsu_debug)
    );

    logic [DATA_WIDTH-1:0] wb_data;
    assign wb_data = mem_wb.is_jump ? mem_wb.pc_plus4 : (mem_wb.mem_read ? mem_wb.mem_data : mem_wb.alu_result);

    assign rf_rd_addr  = sched_wb_valid ? sched_wb_rd : mem_wb.rd_addr;
    assign rf_rd_write = sched_wb_valid ? 1'b1 : (mem_wb.reg_write && mem_wb.valid);
    assign rf_rd_data  = sched_wb_valid ? sched_wb_data : wb_data;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            halt_reg <= 1'b0;
        end else begin

            if (non_alu_valid && (non_alu_data.instruction[6:0] == nexora_x3_pkg::OP_SYSTEM) && (non_alu_data.instruction[31:20] == 12'h000)) begin
                halt_reg <= 1'b1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            instruction_count <= '0;
            cycle_count <= '0;
            cache_hits <= '0;
            cache_misses <= '0;
            stall_count <= '0;
            branch_count <= '0;
        end else begin
            if (!halt_reg) begin
                cycle_count <= cycle_count + 1;

                if (mem_wb.valid || sched_wb_valid) begin
                    instruction_count <= instruction_count + 1;
                end

                if (stall_pipeline) begin
                    stall_count <= stall_count + 1;
                end

                if (branch_taken) begin
                    branch_count <= branch_count + 1;
                end

                if (icache_hit || dcache_hit) cache_hits <= cache_hits + 1;
                if (icache_miss || dcache_miss) cache_misses <= cache_misses + 1;
            end
        end
    end

    assign halt = halt_reg;

    assign debug.state   = rst_n ? {halt_reg, stall_pipeline, branch_taken, illegal_instr} : 4'b0000;
    assign debug.counter = cycle_count;
    assign debug.valid   = rst_n ? (sched_wb_valid || mem_wb.valid) : 1'b0;
    assign debug.error   = rst_n ? illegal_instr : 1'b0;

    assign cpu_debug.pc             = fetch_debug_pc;
    assign cpu_debug.instruction    = if_id.instruction; 
    assign cpu_debug.pipeline_stall = stall_pipeline;
    assign cpu_debug.pipeline_flush = flush_if_id;
    assign cpu_debug.branch_taken   = branch_taken;
    assign cpu_debug.illegal_instr  = illegal_instr;
    assign cpu_debug.rd_write       = rf_rd_write;
    assign cpu_debug.rd_addr        = rf_rd_addr;
    assign cpu_debug.rd_data        = rf_rd_data;

    assert_valid_pc: assert property (
        @(posedge clk) disable iff (!rst_n)
        !$isunknown(fetch_debug_pc)
    ) else $error("[CPU] ASSERT FAIL: valid_pc - PC is X/Z: %h", fetch_debug_pc);

endmodule : cpu_core
