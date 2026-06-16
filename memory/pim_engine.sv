// pim_engine
`timescale 1ns / 1ps
module pim_engine #(
    parameter int VECTOR_DEPTH = 16
)(
    input  logic        clk,
    input  logic        rst_n,

    input  logic        pim_cmd_valid,
    output logic        pim_cmd_ready,
    input  logic [2:0]  pim_cmd_op,
    input  logic [63:0] pim_cmd_addr_a,
    input  logic [63:0] pim_cmd_addr_b,
    input  logic [63:0] pim_cmd_addr_dst,

    output logic        pim_rd_req,
    output logic [63:0] pim_rd_addr,
    input  logic [63:0] pim_rd_data,
    input  logic        pim_rd_valid,

    output logic        pim_wr_req,
    output logic [63:0] pim_wr_addr,
    output logic [63:0] pim_wr_data,
    input  logic        pim_wr_ready,

    output logic        pim_busy,
    output logic        pim_done,
    output logic [31:0] pim_perf_ops
);

    typedef enum logic [2:0] {
        PIM_IDLE,
        PIM_LOAD_A,
        PIM_LOAD_B,
        PIM_LOAD_DST, 
        PIM_COMPUTE,
        PIM_STORE,
        PIM_DONE_STATE
    } pim_state_t;

    pim_state_t state, next_state;

    logic [VECTOR_DEPTH-1:0] [63:0] vec_a;
    logic [VECTOR_DEPTH-1:0] [63:0] vec_b;
    logic [VECTOR_DEPTH-1:0] [63:0] vec_r;

    logic [3:0]  elem_cnt;
    logic [63:0] accum;

    nexora_x3_pkg::pim_op_t     cmd_op_reg;
    logic [63:0] cmd_addr_a_reg;
    logic [63:0] cmd_addr_b_reg;
    logic [63:0] cmd_addr_dst_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pim_perf_ops <= 32'd0;
        end else if (state == PIM_DONE_STATE) begin
            pim_perf_ops <= pim_perf_ops + VECTOR_DEPTH;
        end
    end

    always_comb begin
        next_state    = state;
        pim_cmd_ready = 1'b0;
        pim_rd_req    = 1'b0;
        pim_rd_addr   = 64'd0;
        pim_wr_req    = 1'b0;
        pim_wr_addr   = 64'd0;
        pim_wr_data   = 64'd0;
        pim_busy      = (state != PIM_IDLE);
        pim_done      = (state == PIM_DONE_STATE);

        case (state)
            PIM_IDLE: begin
                pim_cmd_ready = 1'b1;
                if (pim_cmd_valid) begin
                    next_state = PIM_LOAD_A;
                end
            end

            PIM_LOAD_A: begin
                pim_rd_req  = 1'b1;

                pim_rd_addr = cmd_addr_a_reg + {56'd0, elem_cnt, 3'b000};
                if (pim_rd_valid && (elem_cnt == VECTOR_DEPTH - 1)) begin
                    if (cmd_op_reg == nexora_x3_pkg::PIM_RELU || cmd_op_reg == nexora_x3_pkg::PIM_RED_SUM) begin
                        next_state = PIM_COMPUTE; 
                    end else begin
                        next_state = PIM_LOAD_B;
                    end
                end
            end

            PIM_LOAD_B: begin
                pim_rd_req  = 1'b1;
                pim_rd_addr = cmd_addr_b_reg + {56'd0, elem_cnt, 3'b000};
                if (pim_rd_valid && (elem_cnt == VECTOR_DEPTH - 1)) begin
                    if (cmd_op_reg == nexora_x3_pkg::PIM_VEC_MAC) begin
                        next_state = PIM_LOAD_DST;
                    end else begin
                        next_state = PIM_COMPUTE;
                    end
                end
            end

            PIM_LOAD_DST: begin
                pim_rd_req  = 1'b1;
                pim_rd_addr = cmd_addr_dst_reg + {56'd0, elem_cnt, 3'b000};
                if (pim_rd_valid && (elem_cnt == VECTOR_DEPTH - 1)) begin
                    next_state = PIM_COMPUTE;
                end
            end

            PIM_COMPUTE: begin
                next_state = PIM_STORE;
            end

            PIM_STORE: begin
                pim_wr_req  = 1'b1;
                pim_wr_addr = cmd_addr_dst_reg + {56'd0, elem_cnt, 3'b000};
                pim_wr_data = vec_r[elem_cnt];

                if (pim_wr_ready && (elem_cnt == VECTOR_DEPTH - 1)) begin
                    next_state = PIM_DONE_STATE;
                end
            end

            PIM_DONE_STATE: begin
                next_state = PIM_IDLE;
            end

            default: next_state = PIM_IDLE;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= PIM_IDLE;
            elem_cnt         <= 4'd0;
            accum            <= 64'd0;
            cmd_op_reg       <= nexora_x3_pkg::PIM_VEC_ADD;
            cmd_addr_a_reg   <= 64'd0;
            cmd_addr_b_reg   <= 64'd0;
            cmd_addr_dst_reg <= 64'd0;

            for (int i=0; i<VECTOR_DEPTH; i++) begin
                vec_a[i] <= 64'd0;
                vec_b[i] <= 64'd0;
                vec_r[i] <= 64'd0;
            end
        end else begin
            state <= next_state;

            case (state)
                PIM_IDLE: begin
                    elem_cnt <= 4'd0;
                    accum    <= 64'd0;
                    if (pim_cmd_valid && pim_cmd_ready) begin
                        cmd_op_reg       <= nexora_x3_pkg::pim_op_t'(pim_cmd_op);
                        cmd_addr_a_reg   <= pim_cmd_addr_a;
                        cmd_addr_b_reg   <= pim_cmd_addr_b;
                        cmd_addr_dst_reg <= pim_cmd_addr_dst;
                    end
                end

                PIM_LOAD_A: begin
                    if (pim_rd_valid) begin
                        vec_a[elem_cnt] <= pim_rd_data;
                        if (elem_cnt == VECTOR_DEPTH - 1) begin
                            elem_cnt <= 4'd0;
                        end else begin
                            elem_cnt <= elem_cnt + 1;
                        end
                    end
                end

                PIM_LOAD_B: begin
                    if (pim_rd_valid) begin
                        vec_b[elem_cnt] <= pim_rd_data;
                        if (elem_cnt == VECTOR_DEPTH - 1) begin
                            elem_cnt <= 4'd0;
                        end else begin
                            elem_cnt <= elem_cnt + 1;
                        end
                    end
                end

                PIM_LOAD_DST: begin
                    if (pim_rd_valid) begin
                        vec_r[elem_cnt] <= pim_rd_data; 
                        if (elem_cnt == VECTOR_DEPTH - 1) begin
                            elem_cnt <= 4'd0;
                        end else begin
                            elem_cnt <= elem_cnt + 1;
                        end
                    end
                end

                PIM_COMPUTE: begin
                    elem_cnt <= 4'd0; 

                    for (int i = 0; i < VECTOR_DEPTH; i++) begin
                        case (cmd_op_reg)
                            nexora_x3_pkg::PIM_VEC_ADD: vec_r[i] <= vec_a[i] + vec_b[i];
                            nexora_x3_pkg::PIM_VEC_MUL: vec_r[i] <= vec_a[i] * vec_b[i];
                            nexora_x3_pkg::PIM_RELU:    vec_r[i] <= (vec_a[i][63]) ? 64'd0 : vec_a[i];
                            nexora_x3_pkg::PIM_VEC_MAC: vec_r[i] <= vec_r[i] + (vec_a[i] * vec_b[i]); 
                            default:     vec_r[i] <= 64'd0;
                        endcase
                    end

                    if (cmd_op_reg == nexora_x3_pkg::PIM_RED_SUM) begin
                        logic [63:0] temp_sum;
                        temp_sum = 64'd0;
                        for (int i = 0; i < VECTOR_DEPTH; i++) begin
                            temp_sum = temp_sum + vec_a[i];
                        end
                        vec_r[0] <= temp_sum;

                    end
                end

                PIM_STORE: begin
                    if (pim_wr_ready) begin
                        if (elem_cnt == VECTOR_DEPTH - 1 || (cmd_op_reg == nexora_x3_pkg::PIM_RED_SUM && elem_cnt == 0)) begin

                            elem_cnt <= 4'd0;
                        end else begin
                            elem_cnt <= elem_cnt + 1;
                        end
                    end
                end

                PIM_DONE_STATE: begin
                    elem_cnt <= 4'd0;
                end
            endcase

            if (state == PIM_STORE && cmd_op_reg == nexora_x3_pkg::PIM_RED_SUM && pim_wr_ready && elem_cnt == 0) begin
                state <= PIM_DONE_STATE; 
            end
        end
    end

endmodule : pim_engine
