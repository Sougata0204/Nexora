// instruction_queue
`timescale 1ns / 1ps
module instruction_queue #(
    parameter int QUEUE_DEPTH = 16,
    parameter int ISSUE_WIDTH = 4
)(
    input  logic clk,
    input  logic rst_n,

    input  logic enqueue_valid,
    input  nexora_x3_pkg::id_ex_reg_t enqueue_data,
    output logic enqueue_ready,

    output logic [ISSUE_WIDTH-1:0] dequeue_valid,
    output nexora_x3_pkg::id_ex_reg_t [ISSUE_WIDTH-1:0] dequeue_data,
    input  logic [ISSUE_WIDTH-1:0] dequeue_ack, 

    input  logic flush,

    output logic [3:0] debug_state,
    output logic [31:0] debug_counter,
    output logic debug_valid,
    output logic debug_error
);

    nexora_x3_pkg::id_ex_reg_t [QUEUE_DEPTH-1:0] queue;

    logic [$clog2(QUEUE_DEPTH)-1:0] head_ptr;
    logic [$clog2(QUEUE_DEPTH)-1:0] tail_ptr;
    logic [$clog2(QUEUE_DEPTH):0] count;

    assign enqueue_ready = (count < QUEUE_DEPTH);

    logic [$clog2(ISSUE_WIDTH+1)-1:0] ack_count;
    always_comb begin
        ack_count = '0;
        for (int i = 0; i < ISSUE_WIDTH; i++) begin
            if (dequeue_ack[i]) ack_count++;
        end
    end

    always_comb begin
        for (int i = 0; i < ISSUE_WIDTH; i++) begin
            logic [$clog2(QUEUE_DEPTH)-1:0] read_idx;
            read_idx = (head_ptr + i) % QUEUE_DEPTH;

            if (i < count) begin
                dequeue_valid[i] = 1'b1;
                dequeue_data[i] = queue[read_idx];
            end else begin
                dequeue_valid[i] = 1'b0;
                dequeue_data[i] = '0;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head_ptr <= '0;
            tail_ptr <= '0;
            count <= '0;
            debug_counter <= '0;
            for (int j = 0; j < QUEUE_DEPTH; j++) begin
                queue[j] <= '0;
            end
        end else if (flush) begin
            head_ptr <= '0;
            tail_ptr <= '0;
            count <= '0;
            debug_counter <= debug_counter + 1;
        end else begin
            debug_counter <= debug_counter + 1;

            if (enqueue_valid && enqueue_ready) begin
                queue[tail_ptr] <= enqueue_data;
                tail_ptr <= (tail_ptr + 1) % QUEUE_DEPTH;
            end

            if (ack_count > 0) begin
                head_ptr <= (head_ptr + ack_count) % QUEUE_DEPTH;
            end

            count <= count + (enqueue_valid && enqueue_ready) - ack_count;
        end
    end

    assign debug_state = {enqueue_ready, count != 0, 2'b00};
    assign debug_valid = (count > 0);
    assign debug_error = (enqueue_valid && !enqueue_ready);

endmodule
