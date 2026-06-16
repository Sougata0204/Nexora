// load_store_unit
`timescale 1ns / 1ps
module load_store_unit #(
    parameter int DATA_WIDTH = nexora_x3_pkg::DATA_WIDTH,
    parameter int ADDR_WIDTH = nexora_x3_pkg::ADDR_WIDTH
)(
    input  logic              clk,
    input  logic              rst_n,

    input  nexora_x3_pkg::ex_mem_reg_t       ex_mem_in,

    output nexora_x3_pkg::mem_req_t          dmem_req,
    input  nexora_x3_pkg::mem_resp_t         dmem_resp,

    output nexora_x3_pkg::mem_wb_reg_t       mem_wb_out,

    output nexora_x3_pkg::debug_signals_t    debug
);

    logic [1:0]            byte_offset;
    logic [DATA_WIDTH-1:0] load_data;
    logic [DATA_WIDTH-1:0] store_data;
    logic [7:0]            byte_enable;
    logic                  misaligned;

    logic [31:0] access_count;

    assign byte_offset = ex_mem_in.alu_result[1:0];

    always_comb begin
        byte_enable = 8'h00;
        store_data  = '0;
        misaligned  = 1'b0;

        if (ex_mem_in.mem_write && ex_mem_in.valid) begin
            case (ex_mem_in.funct3[1:0])
                2'b00: begin  
                    case (byte_offset)
                        2'b00: begin byte_enable = 8'h01; store_data = {24'b0, ex_mem_in.rs2_data[7:0]}; end
                        2'b01: begin byte_enable = 8'h02; store_data = {16'b0, ex_mem_in.rs2_data[7:0], 8'b0}; end
                        2'b10: begin byte_enable = 8'h04; store_data = {8'b0, ex_mem_in.rs2_data[7:0], 16'b0}; end
                        2'b11: begin byte_enable = 8'h08; store_data = {ex_mem_in.rs2_data[7:0], 24'b0}; end
                    endcase
                end
                2'b01: begin  
                    case (byte_offset)
                        2'b00: begin byte_enable = 8'h03; store_data = {16'b0, ex_mem_in.rs2_data[15:0]}; end
                        2'b10: begin byte_enable = 8'h0C; store_data = {ex_mem_in.rs2_data[15:0], 16'b0}; end
                        default: misaligned = 1'b1;
                    endcase
                end
                2'b10: begin  
                    if (byte_offset == 2'b00) begin
                        byte_enable = 8'hFF;
                        store_data  = ex_mem_in.rs2_data;
                    end else begin
                        misaligned = 1'b1;
                    end
                end
                default: ;  
            endcase
        end
    end

    assign dmem_req.addr     = {ex_mem_in.alu_result[ADDR_WIDTH-1:2], 2'b00};  
    assign dmem_req.wdata    = store_data;
    assign dmem_req.read_en  = ex_mem_in.mem_read  && ex_mem_in.valid;
    assign dmem_req.write_en = ex_mem_in.mem_write && ex_mem_in.valid && !misaligned;
    assign dmem_req.byte_en  = byte_enable;

    always_comb begin
        load_data = dmem_resp.rdata;  

        if (ex_mem_in.mem_read && ex_mem_in.valid) begin
            case (ex_mem_in.funct3)
                3'b000: begin  
                    case (byte_offset)
                        2'b00: load_data = {{24{dmem_resp.rdata[7]}},  dmem_resp.rdata[7:0]};
                        2'b01: load_data = {{24{dmem_resp.rdata[15]}}, dmem_resp.rdata[15:8]};
                        2'b10: load_data = {{24{dmem_resp.rdata[23]}}, dmem_resp.rdata[23:16]};
                        2'b11: load_data = {{24{dmem_resp.rdata[31]}}, dmem_resp.rdata[31:24]};
                    endcase
                end
                3'b001: begin  
                    case (byte_offset)
                        2'b00: load_data = {{16{dmem_resp.rdata[15]}}, dmem_resp.rdata[15:0]};
                        2'b10: load_data = {{16{dmem_resp.rdata[31]}}, dmem_resp.rdata[31:16]};
                        default: load_data = '0;  
                    endcase
                end
                3'b010: begin  
                    load_data = dmem_resp.rdata;
                end
                3'b100: begin  
                    case (byte_offset)
                        2'b00: load_data = {24'b0, dmem_resp.rdata[7:0]};
                        2'b01: load_data = {24'b0, dmem_resp.rdata[15:8]};
                        2'b10: load_data = {24'b0, dmem_resp.rdata[23:16]};
                        2'b11: load_data = {24'b0, dmem_resp.rdata[31:24]};
                    endcase
                end
                3'b101: begin  
                    case (byte_offset)
                        2'b00: load_data = {16'b0, dmem_resp.rdata[15:0]};
                        2'b10: load_data = {16'b0, dmem_resp.rdata[31:16]};
                        default: load_data = '0;  
                    endcase
                end
                default: load_data = dmem_resp.rdata;
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wb_out.alu_result <= '0;
            mem_wb_out.mem_data   <= '0;
            mem_wb_out.rd_addr    <= '0;
            mem_wb_out.reg_write  <= 1'b0;
            mem_wb_out.mem_read   <= 1'b0;
            mem_wb_out.is_jump    <= 1'b0;
            mem_wb_out.pc_plus4   <= '0;
            mem_wb_out.valid      <= 1'b0;
        end else begin
            mem_wb_out.alu_result <= ex_mem_in.alu_result;
            mem_wb_out.mem_data   <= load_data;
            mem_wb_out.rd_addr    <= ex_mem_in.rd_addr;
            mem_wb_out.reg_write  <= ex_mem_in.reg_write;
            mem_wb_out.mem_read   <= ex_mem_in.mem_read;
            mem_wb_out.is_jump    <= ex_mem_in.is_jump;
            mem_wb_out.pc_plus4   <= ex_mem_in.pc_plus4;
            mem_wb_out.valid      <= ex_mem_in.valid;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            access_count <= '0;
        end else if ((ex_mem_in.mem_read || ex_mem_in.mem_write) && ex_mem_in.valid) begin
            access_count <= access_count + 1;
        end
    end

    assign debug.state   = {ex_mem_in.mem_read, ex_mem_in.mem_write, misaligned, 1'b0};
    assign debug.counter = access_count;
    assign debug.valid   = (ex_mem_in.mem_read || ex_mem_in.mem_write) && ex_mem_in.valid;
    assign debug.error   = misaligned && ex_mem_in.valid;

    assert_valid_memory_address: assert property (
        @(posedge clk) disable iff (!rst_n)
        ((ex_mem_in.mem_read || ex_mem_in.mem_write) && ex_mem_in.valid) |->
        !$isunknown(ex_mem_in.alu_result)
    ) else $error("[LSU] ASSERT FAIL: X/Z on memory address: %h", ex_mem_in.alu_result);

    assert_no_simultaneous_read_write: assert property (
        @(posedge clk) disable iff (!rst_n)
        !(ex_mem_in.mem_read && ex_mem_in.mem_write && ex_mem_in.valid)
    ) else $error("[LSU] ASSERT FAIL: Simultaneous read and write");

    assert_word_aligned_lw: assert property (
        @(posedge clk) disable iff (!rst_n)
        (ex_mem_in.mem_read && ex_mem_in.valid && ex_mem_in.funct3 == 3'b010) |->
        (byte_offset == 2'b00)
    ) else $warning("[LSU] WARN: Misaligned word load at address %h", ex_mem_in.alu_result);

endmodule : load_store_unit
