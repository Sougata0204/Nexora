// fetch
`timescale 1ns / 1ps
module fetch #(
    parameter int DATA_WIDTH  = nexora_x3_pkg::DATA_WIDTH,
    parameter int ADDR_WIDTH  = nexora_x3_pkg::ADDR_WIDTH,
    parameter int INSTR_WIDTH = nexora_x3_pkg::INSTR_WIDTH,
    parameter logic [ADDR_WIDTH-1:0] PC_RESET = nexora_x3_pkg::PC_RESET_VAL
)(
    input  logic                  clk,
    input  logic                  rst_n,

    input  logic                  stall,           
    input  logic                  flush,           

    input  logic                  branch_taken,    
    input  logic [ADDR_WIDTH-1:0] branch_target,   
    input  logic                  jump_taken,      
    input  logic [ADDR_WIDTH-1:0] jump_target,     

    output nexora_x3_pkg::mem_req_t              imem_req,        
    input  nexora_x3_pkg::mem_resp_t             imem_resp,       

    output nexora_x3_pkg::if_id_reg_t            if_id_out,

    output nexora_x3_pkg::debug_signals_t        debug,
    output logic [DATA_WIDTH-1:0] debug_pc
);

    logic [ADDR_WIDTH-1:0] pc_reg;
    logic [ADDR_WIDTH-1:0] pc_next;

    logic [31:0] fetch_count;

    always_comb begin
        if (jump_taken) begin
            pc_next = jump_target;
        end else if (branch_taken) begin
            pc_next = branch_target;
        end else if (stall || !imem_resp.ready) begin
            pc_next = pc_reg;          
        end else begin
            pc_next = pc_reg + 4;  
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_reg <= PC_RESET[ADDR_WIDTH-1:0];
        end else begin
            pc_reg <= pc_next;
        end
    end

    assign imem_req.addr     = {pc_reg[ADDR_WIDTH-1:3], 3'b000}; 
    assign imem_req.wdata    = '0;            
    assign imem_req.read_en  = !stall;        
    assign imem_req.write_en = 1'b0;
    assign imem_req.byte_en  = 8'hFF;         

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_out.pc          <= PC_RESET[DATA_WIDTH-1:0];
            if_id_out.instruction <= 32'h0000_0013;  
            if_id_out.valid       <= 1'b0;
        end else if (flush) begin

            if_id_out.pc          <= pc_reg;
            if_id_out.instruction <= 32'h0000_0013;  
            if_id_out.valid       <= 1'b0;
        end else if (!stall) begin
            if (imem_resp.ready) begin
                if_id_out.pc          <= pc_reg;
                if_id_out.instruction <= pc_reg[2] ? imem_resp.rdata[63:32] : imem_resp.rdata[31:0];
                if_id_out.valid       <= 1'b1;
            end else begin

                if_id_out.valid       <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fetch_count <= '0;
        end else if (!stall && !flush) begin
            fetch_count <= fetch_count + 1;
        end
    end

    assign debug.state   = {flush, stall, branch_taken, jump_taken};
    assign debug.counter = fetch_count;
    assign debug.valid   = if_id_out.valid;
    assign debug.error   = 1'b0;
    assign debug_pc      = pc_reg;

    assert_valid_pc: assert property (
        @(posedge clk) disable iff (!rst_n)
        pc_reg[1:0] == 2'b00
    ) else $error("[FETCH] ASSERT FAIL: PC is not word-aligned! PC = %h", pc_reg);

    assert_no_xz_pc: assert property (
        @(posedge clk) disable iff (!rst_n)
        !$isunknown(pc_reg)
    ) else $error("[FETCH] ASSERT FAIL: X/Z detected on PC");

    assert_no_xz_instr: assert property (
        @(posedge clk) disable iff (!rst_n)
        (if_id_out.valid) |-> !$isunknown(if_id_out.instruction)
    ) else $error("[FETCH] ASSERT FAIL: X/Z detected on instruction");

endmodule : fetch
