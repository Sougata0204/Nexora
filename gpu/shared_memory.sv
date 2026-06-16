// shared_memory
`timescale 1ns / 1ps
module shared_memory #(
    parameter int MEM_DEPTH = 16384   
)(
    input  logic        clk,
    input  logic        rst_n,

    input  logic [$clog2(MEM_DEPTH)-1:0] addr,  
    input  logic [31:0] wdata,
    output logic [31:0] rdata,
    input  logic        read_en,
    input  logic        write_en
);

    (* ram_style = "block" *) logic [31:0] mem_array [MEM_DEPTH-1:0];

    always_ff @(posedge clk) begin : smem_write
        if (write_en) begin
            mem_array[addr] <= wdata;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin : smem_read
        if (!rst_n) begin
            rdata <= 32'd0;
        end else begin
            if (read_en) begin
                rdata <= mem_array[addr];
            end
        end
    end

endmodule : shared_memory
