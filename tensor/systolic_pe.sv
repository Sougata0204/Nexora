// systolic_pe
`timescale 1ns / 1ps
module systolic_pe (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [7:0]  weight_in,       
    input  logic [7:0]  activation_in,   
    input  logic [31:0] partial_sum_in,  
    input  logic        weight_valid,    

    output logic [7:0]  weight_out,      
    output logic [7:0]  activation_out,  
    output logic [31:0] partial_sum_out  
);

    logic [7:0]  w_reg;
    logic [7:0]  a_reg;
    logic [31:0] mac_result;

    always_comb begin
        mac_result = partial_sum_in + ({{24{1'b0}}, w_reg} * {{24{1'b0}}, a_reg});
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_reg           <= 8'h00;
            a_reg           <= 8'h00;
            weight_out      <= 8'h00;
            activation_out  <= 8'h00;
            partial_sum_out <= 32'h0;
        end else begin

            if (weight_valid) begin
                w_reg <= weight_in;
            end

            a_reg          <= activation_in;
            weight_out     <= w_reg;       
            activation_out <= a_reg;       
            partial_sum_out <= mac_result; 
        end
    end

endmodule : systolic_pe
