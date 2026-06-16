// tensor_cluster
`timescale 1ns / 1ps
module tensor_cluster #(
    parameter int CLUSTER_ID = 0
)(
    input  logic clk,
    input  logic rst_n,

    output nexora_x3_pkg::mem_req_t  mem_req,
    input  nexora_x3_pkg::mem_resp_t mem_resp,

    output logic [31:0] compute_cycles
);

    localparam int DIM = nexora_x3_pkg::TENSOR_DIM; 

    logic [2:0] state, next_state;

    logic [7:0] weight_buf [DIM-1:0][DIM-1:0];
    logic [7:0] act_buf    [DIM-1:0][DIM-1:0];
    logic [31:0] result_buf [DIM-1:0][DIM-1:0];

    logic [3:0] row_cnt;
    logic [3:0] col_cnt;

    logic [DIM-1:0] [7:0] w_col_in;
    logic [DIM-1:0] [7:0] a_row_in;
    logic        weight_load;
    logic        act_valid;
    logic        compute_en;
    logic [DIM-1:0][DIM-1:0][31:0] acc_out;
    logic        array_done;

    systolic_array #(.DIM(DIM)) u_systolic (
        .clk            (clk),
        .rst_n          (rst_n),
        .weight_col_in  (w_col_in),
        .weight_load    (weight_load),
        .act_row_in     (a_row_in),
        .act_valid      (act_valid),
        .compute_en     (compute_en),
        .acc_out        (acc_out),
        .done           (array_done)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= nexora_x3_pkg::TENS_FSM_IDLE;
        end else begin
            state <= next_state;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            compute_cycles <= 32'h0;
        end else if (state == nexora_x3_pkg::TENS_FSM_COMPUTE) begin
            compute_cycles <= compute_cycles + 1;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_cnt <= 4'h0;
            col_cnt <= 4'h0;
        end else begin
            case (state)
                nexora_x3_pkg::TENS_FSM_LOAD_W: begin
                    if (mem_resp.ready) begin
                        col_cnt <= col_cnt + 1;
                        if (col_cnt == DIM - 1) begin
                            col_cnt <= 4'h0;
                            row_cnt <= row_cnt + 1;
                        end
                    end
                end
                nexora_x3_pkg::TENS_FSM_LOAD_ACT: begin
                    if (mem_resp.ready) begin
                        col_cnt <= col_cnt + 1;
                        if (col_cnt == DIM - 1) begin
                            col_cnt <= 4'h0;
                            row_cnt <= row_cnt + 1;
                        end
                    end
                end
                nexora_x3_pkg::TENS_FSM_STORE: begin
                    if (mem_resp.ready) begin
                        col_cnt <= col_cnt + 1;
                        if (col_cnt == DIM - 1) begin
                            col_cnt <= 4'h0;
                            row_cnt <= row_cnt + 1;
                        end
                    end
                end
                default: begin
                    row_cnt <= 4'h0;
                    col_cnt <= 4'h0;
                end
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int r = 0; r < DIM; r++) begin
                for (int c = 0; c < DIM; c++) begin
                    weight_buf[r][c] <= 8'h0;
                    act_buf[r][c]    <= 8'h0;
                    result_buf[r][c] <= 32'h0;
                end
            end
        end else begin

            if (state == nexora_x3_pkg::TENS_FSM_LOAD_W && mem_resp.ready) begin
                weight_buf[row_cnt][col_cnt] <= mem_resp.rdata[7:0];
            end

            if (state == nexora_x3_pkg::TENS_FSM_LOAD_ACT && mem_resp.ready) begin
                act_buf[row_cnt][col_cnt] <= mem_resp.rdata[7:0];
            end

            if (state == nexora_x3_pkg::TENS_FSM_RELU) begin
                for (int r = 0; r < DIM; r++) begin
                    for (int c = 0; c < DIM; c++) begin

                        result_buf[r][c] <= acc_out[r][c][31] ? 32'h0 : acc_out[r][c];
                    end
                end
            end
        end
    end

    always_comb begin

        next_state       = state;
        mem_req.addr     = '0;
        mem_req.wdata    = '0;
        mem_req.read_en  = 1'b0;
        mem_req.write_en = 1'b0;
        mem_req.byte_en  = 8'h00;
        weight_load      = 1'b0;
        act_valid   = 1'b0;
        compute_en  = 1'b0;

        for (int r = 0; r < DIM; r++) begin
            w_col_in[r] = weight_buf[r][0];  
            a_row_in[r] = act_buf[0][r];     
        end

        case (state)
            nexora_x3_pkg::TENS_FSM_IDLE: begin

                next_state = nexora_x3_pkg::TENS_FSM_LOAD_W;
            end

            nexora_x3_pkg::TENS_FSM_LOAD_W: begin

                mem_req.read_en  = 1'b1;
                mem_req.write_en = 1'b0;
                mem_req.addr     = nexora_x3_pkg::TENSOR_BUF_BASE + (CLUSTER_ID * 512) + (row_cnt * DIM) + col_cnt;
                mem_req.byte_en  = 8'hFF;
                mem_req.wdata    = '0;

                if (mem_resp.ready) begin
                    weight_load = 1'b1;
                    for (int r = 0; r < DIM; r++) begin
                        w_col_in[r] = weight_buf[r][col_cnt];
                    end
                end

                if (row_cnt == DIM && col_cnt == 0) begin
                    next_state = nexora_x3_pkg::TENS_FSM_LOAD_ACT;
                end
            end

            nexora_x3_pkg::TENS_FSM_LOAD_ACT: begin

                mem_req.read_en  = 1'b1;
                mem_req.write_en = 1'b0;
                mem_req.addr     = nexora_x3_pkg::TENSOR_BUF_BASE + (CLUSTER_ID * 512) + 256 + (row_cnt * DIM) + col_cnt;
                mem_req.byte_en  = 8'hFF;
                mem_req.wdata    = '0;

                if (mem_resp.ready) begin
                    act_valid = 1'b1;
                    for (int c = 0; c < DIM; c++) begin
                        a_row_in[c] = act_buf[row_cnt][c];
                    end
                end

                if (row_cnt == DIM && col_cnt == 0) begin
                    next_state = nexora_x3_pkg::TENS_FSM_COMPUTE;
                end
            end

            nexora_x3_pkg::TENS_FSM_COMPUTE: begin
                compute_en = 1'b1;
                if (array_done) begin
                    next_state = nexora_x3_pkg::TENS_FSM_RELU;
                end
            end

            nexora_x3_pkg::TENS_FSM_RELU: begin

                next_state = nexora_x3_pkg::TENS_FSM_STORE;
            end

            nexora_x3_pkg::TENS_FSM_STORE: begin

                mem_req.read_en  = 1'b0;
                mem_req.write_en = 1'b1;
                mem_req.addr     = nexora_x3_pkg::TENSOR_BUF_BASE + (CLUSTER_ID * 512) + 384 + (row_cnt * DIM * 4) + (col_cnt * 4);
                mem_req.wdata    = {32'h0, result_buf[row_cnt][col_cnt]};
                mem_req.byte_en  = 8'hFF;

                if (row_cnt == DIM && col_cnt == 0) begin
                    next_state = nexora_x3_pkg::TENS_FSM_DRAIN;
                end
            end

            nexora_x3_pkg::TENS_FSM_DRAIN: begin

                next_state = nexora_x3_pkg::TENS_FSM_IDLE;
            end

            default: begin
                next_state = nexora_x3_pkg::TENS_FSM_IDLE;
            end
        endcase
    end

endmodule : tensor_cluster
