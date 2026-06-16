// warp_scheduler
`timescale 1ns / 1ps
module warp_scheduler #(
    parameter int WARP_COUNT = 4
)(
    input  logic                         clk,
    input  logic                         rst_n,

    input  nexora_x3_pkg::warp_t [WARP_COUNT-1:0] warp_states,

    output logic [(WARP_COUNT > 1 ? $clog2(WARP_COUNT) : 1)-1:0] selected_warp,  
    output logic                          issue_valid,

    input  logic                          stall
);

    localparam int WARP_IDX_W = (WARP_COUNT > 1) ? $clog2(WARP_COUNT) : 1;

    logic [WARP_IDX_W-1:0] rr_ptr;        

    logic [WARP_IDX_W-1:0] next_warp_comb;
    logic                          found_comb;

    nexora_x3_pkg::warp_state_t warp_states_state [WARP_COUNT-1:0];
    nexora_x3_pkg::warp_t tmp_warp;
    always_comb begin
        for (int i = 0; i < WARP_COUNT; i++) begin
            tmp_warp = warp_states[i];
            warp_states_state[i] = tmp_warp.state;
        end
    end

    always_comb begin : scheduler_select
        int idx;

        next_warp_comb = rr_ptr;
        found_comb     = 1'b0;

        for (int i = 0; i < WARP_COUNT; i++) begin
            idx = (rr_ptr + i) % WARP_COUNT;
            if (!found_comb && (warp_states_state[idx] == nexora_x3_pkg::WARP_RUNNING)) begin
                next_warp_comb = idx[WARP_IDX_W-1:0];
                found_comb     = 1'b1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin : scheduler_reg
        if (!rst_n) begin
            selected_warp <= '0;
            issue_valid   <= 1'b0;
            rr_ptr        <= '0;
        end else begin
            if (!stall) begin

                selected_warp <= next_warp_comb;
                issue_valid   <= found_comb;

                if (found_comb) begin
                    rr_ptr <= (next_warp_comb + 1'b1) % WARP_COUNT;
                end
            end

        end
    end

endmodule : warp_scheduler
