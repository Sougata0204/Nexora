// systolic_array
`timescale 1ns / 1ps
module systolic_array #(
    parameter int DIM = nexora_x3_pkg::TENSOR_DIM  
)(
    input  logic        clk,
    input  logic        rst_n,

    input  logic [DIM-1:0] [7:0] weight_col_in,
    input  logic        weight_load,                  

    input  logic [DIM-1:0] [7:0] act_row_in,
    input  logic        act_valid,                    

    input  logic        compute_en,

    output logic [DIM-1:0][DIM-1:0][31:0] acc_out, 
    output logic        done                          
);

    logic [7:0]  weight_h [DIM-1:0][DIM:0];

    logic [7:0]  act_v    [DIM:0][DIM-1:0];

    logic [31:0] psum     [DIM-1:0][DIM:0];

    logic        wv       [DIM-1:0][DIM-1:0];

    logic [4:0] compute_cnt;
    logic       computing;

    genvar r, c;
    generate
        for (r = 0; r < DIM; r++) begin : gen_row_input
            assign weight_h[r][0] = weight_col_in[r]; 
            assign psum[r][0]     = 32'h0;             
        end
        for (c = 0; c < DIM; c++) begin : gen_col_input
            assign act_v[0][c] = act_row_in[c];        
        end
    endgenerate

    generate
        for (r = 0; r < DIM; r++) begin : row_gen
            for (c = 0; c < DIM; c++) begin : col_gen
                systolic_pe u_pe (
                    .clk            (clk),
                    .rst_n          (rst_n),
                    .weight_in      (weight_h[r][c]),
                    .activation_in  (act_v[r][c]),
                    .partial_sum_in (psum[r][c]),
                    .weight_valid   (weight_load),
                    .weight_out     (weight_h[r][c+1]),
                    .activation_out (act_v[r+1][c]),
                    .partial_sum_out(psum[r][c+1])
                );
            end
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < DIM; i++) begin
                for (int j = 0; j < DIM; j++) begin
                    acc_out[i][j] <= 32'h0;
                end
            end
            compute_cnt <= 5'h0;
            computing   <= 1'b0;
            done        <= 1'b0;
        end else begin
            done <= 1'b0;
            if (compute_en && !computing) begin
                computing   <= 1'b1;
                compute_cnt <= 5'h0;
            end
            if (computing) begin
                compute_cnt <= compute_cnt + 1;

                if (compute_cnt == (DIM * 2 - 1)) begin
                    computing <= 1'b0;
                    done      <= 1'b1;
                    for (int i = 0; i < DIM; i++) begin
                        acc_out[i][DIM-1] <= psum[i][DIM]; 
                    end
                end
            end
        end
    end

endmodule : systolic_array
