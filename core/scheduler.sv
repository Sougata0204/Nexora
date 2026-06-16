// scheduler
`timescale 1ns / 1ps
module scheduler #(
    parameter int ISSUE_WIDTH = 4,
    parameter int ALU_COUNT = 16,
    parameter int DATA_WIDTH = nexora_x3_pkg::DATA_WIDTH
)(
    input  logic clk,
    input  logic rst_n,

    input  logic [ISSUE_WIDTH-1:0] sched_valid,
    input  nexora_x3_pkg::dispatch_packet_t [ISSUE_WIDTH-1:0] sched_data,
    output logic [$clog2(ALU_COUNT+1)-1:0] sched_ready_count,

    output logic [ALU_COUNT-1:0] alu_valid,
    output nexora_x3_pkg::dispatch_packet_t [ALU_COUNT-1:0] alu_data,
    input  logic [ALU_COUNT-1:0] alu_done,
    input  logic [ALU_COUNT-1:0] [DATA_WIDTH-1:0] alu_result,
    input  logic [ALU_COUNT-1:0] [4:0] alu_rd,
    input  logic [ALU_COUNT-1:0] alu_reg_write,

    output logic wb_valid,
    output logic [4:0] wb_rd,
    output logic [DATA_WIDTH-1:0] wb_data,

    input  logic flush,

    output logic [3:0] debug_state,
    output logic [31:0] debug_counter,
    output logic debug_valid,
    output logic debug_error
);

    logic [ALU_COUNT-1:0] alu_busy;
    logic [$clog2(ALU_COUNT)-1:0] rr_ptr;

    typedef struct packed {
        logic [4:0] rd;
        logic [DATA_WIDTH-1:0] data;
        logic reg_write;
    } wb_entry_t;

    wb_entry_t [ALU_COUNT-1:0] wb_buffer;
    logic [ALU_COUNT-1:0] wb_valid_bits;
    logic [$clog2(ALU_COUNT)-1:0] wb_head, wb_tail;
    logic [$clog2(ALU_COUNT+1)-1:0] wb_count;

    wb_entry_t current_wb;

    logic [$clog2(ALU_COUNT+1)-1:0] free_count;
    always_comb begin
        free_count = 0;
        for (int i = 0; i < ALU_COUNT; i++) begin
            if (!alu_busy[i]) free_count++;
        end
    end

    assign sched_ready_count = free_count;

    logic [ALU_COUNT-1:0] free_rot;
    logic [ALU_COUNT-1:0] [4:0] prefix_sum;
    logic [$clog2(ALU_COUNT)-1:0] next_rr_ptr;

    logic [ALU_COUNT-1:0] next_alu_busy;
    logic [ALU_COUNT-1:0] local_alu_valid;
    nexora_x3_pkg::dispatch_packet_t [ALU_COUNT-1:0] local_alu_data;

    always_comb begin

        for (int j = 0; j < ALU_COUNT; j++) begin
            free_rot[j] = !alu_busy[(rr_ptr + j) % ALU_COUNT];
        end

        prefix_sum[0] = free_rot[0] ? 5'd1 : 5'd0;
        for (int j = 1; j < ALU_COUNT; j++) begin
            prefix_sum[j] = prefix_sum[j-1] + (free_rot[j] ? 5'd1 : 5'd0);
        end

        next_alu_busy = alu_busy;
        local_alu_valid = '0;
        local_alu_data = '0;

        for (int j = 0; j < ALU_COUNT; j++) begin
            if (free_rot[j]) begin
                logic [4:0] rank;
                rank = prefix_sum[j] - 1;
                if (rank < ISSUE_WIDTH) begin
                    if (sched_valid[rank]) begin
                        logic [$clog2(ALU_COUNT)-1:0] k;
                        k = (rr_ptr + j) % ALU_COUNT;
                        local_alu_valid[k] = 1'b1;
                        local_alu_data[k]  = sched_data[rank];
                        next_alu_busy[k]   = 1'b1;
                    end
                end
            end
        end
    end

    always_comb begin
        logic [4:0] sched_valid_count;
        logic [4:0] issued_count;

        sched_valid_count = sched_valid[0] + sched_valid[1] + sched_valid[2] + sched_valid[3];
        issued_count = (prefix_sum[ALU_COUNT-1] < sched_valid_count) ? prefix_sum[ALU_COUNT-1] : sched_valid_count;

        next_rr_ptr = rr_ptr;
        if (issued_count > 0) begin
            for (int j = 0; j < ALU_COUNT; j++) begin
                if (free_rot[j] && (prefix_sum[j] == issued_count)) begin
                    next_rr_ptr = (rr_ptr + j + 1) % ALU_COUNT;
                end
            end
        end
    end

    assign alu_valid = local_alu_valid;
    assign alu_data = local_alu_data;

    always_comb begin
        current_wb = '0;

        wb_valid = 1'b0;
        wb_rd = '0;
        wb_data = '0;

        if (wb_count > 0) begin
            current_wb = wb_buffer[wb_head];
            if (current_wb.reg_write && current_wb.rd != 0) begin
                wb_valid = 1'b1;
                wb_rd = current_wb.rd;
                wb_data = current_wb.data;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alu_busy <= '0;
            rr_ptr <= '0;
            wb_head <= '0;
            wb_tail <= '0;
            wb_count <= '0;
            wb_valid_bits <= '0;
            debug_counter <= '0;
            for (int i = 0; i < ALU_COUNT; i++) begin
                wb_buffer[i] <= '0;
            end
        end else if (flush) begin
            alu_busy <= '0;
            rr_ptr <= '0;
            wb_head <= '0;
            wb_tail <= '0;
            wb_count <= '0;
            wb_valid_bits <= '0;
            debug_counter <= debug_counter + 1;
        end else begin
            logic [ALU_COUNT-1:0] temp_busy;
            logic [$clog2(ALU_COUNT)-1:0] next_tail;
            logic [$clog2(ALU_COUNT+1)-1:0] added;
            logic [$clog2(ALU_COUNT+1)-1:0] removed;

            debug_counter <= debug_counter + 1;

            temp_busy = next_alu_busy;
            for (int i = 0; i < ALU_COUNT; i++) begin
                if (alu_done[i]) begin
                    temp_busy[i] = 1'b0;
                end
            end
            alu_busy <= temp_busy;

            rr_ptr <= next_rr_ptr;

            next_tail = wb_tail;
            added = 0;

            for (int i = 0; i < ALU_COUNT; i++) begin
                if (alu_done[i]) begin
                    wb_buffer[next_tail] <= {alu_rd[i], alu_result[i], alu_reg_write[i]};
                    wb_valid_bits[next_tail] <= 1'b1;
                    next_tail = (next_tail + 1) % ALU_COUNT;
                    added++;
                end
            end
            wb_tail <= next_tail;

            removed = 0;
            if (wb_count > 0) begin
                wb_valid_bits[wb_head] <= 1'b0;
                wb_head <= (wb_head + 1) % ALU_COUNT;
                removed = 1;
            end

            wb_count <= wb_count + added - removed;
        end
    end

    assign debug_state = {wb_count != 0, alu_busy[0], 2'b00};
    assign debug_valid = (wb_count > 0) || (alu_busy != 0);
    assign debug_error = 1'b0;

endmodule
