// coherence_dir
`timescale 1ns / 1ps
module coherence_dir #(
    parameter int NUM_CACHES  = 16,
    parameter int DIR_ENTRIES = 256
)(
    input  logic clk,
    input  logic rst_n,

    input  nexora_x3_pkg::coh_req_t [NUM_CACHES-1:0] coh_req,
    input  logic [NUM_CACHES-1:0] coh_req_valid,
    output nexora_x3_pkg::coh_resp_t [NUM_CACHES-1:0] coh_resp,
    output logic [NUM_CACHES-1:0] coh_resp_valid,

    output nexora_x3_pkg::mem_req_t  mem_req,
    input  nexora_x3_pkg::mem_resp_t mem_resp
);

    localparam int DATA_WIDTH = nexora_x3_pkg::DATA_WIDTH;

    nexora_x3_pkg::mesi_state_t [DIR_ENTRIES-1:0] dir_state;
    logic [DIR_ENTRIES-1:0] [NUM_CACHES-1:0] sharers_map;
    logic [DIR_ENTRIES-1:0] [3:0] owner;

    typedef enum logic [2:0] {
        DIR_IDLE     = 3'd0,
        DIR_LOOKUP   = 3'd1,
        DIR_SNOOP    = 3'd2,
        DIR_WAIT_MEM = 3'd3,
        DIR_WAIT_ACK = 3'd4,
        DIR_RESPOND  = 3'd5
    } dir_fsm_t;

    dir_fsm_t state, next_state;

    logic [3:0]            active_req_id;
    nexora_x3_pkg::coh_req_t              active_req;
    logic [7:0]            dir_idx;        
    logic [DATA_WIDTH-1:0]           data_from_mem;

    logic [NUM_CACHES-1:0] snoop_pending;  
    logic [NUM_CACHES-1:0] snoop_ack_recv; 

    nexora_x3_pkg::coh_msg_t coh_req_msg_type [NUM_CACHES-1:0];
    nexora_x3_pkg::coh_req_t tmp_coh_req;
    always_comb begin
        for (int i = 0; i < NUM_CACHES; i++) begin
            tmp_coh_req = coh_req[i];
            coh_req_msg_type[i] = tmp_coh_req.msg_type;
        end
    end

    nexora_x3_pkg::coh_resp_t             resp_to_send;
    logic                  sending_resp;
    logic [3:0]            resp_target;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= DIR_IDLE;
        end else begin
            state <= next_state;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < DIR_ENTRIES; i++) begin
                dir_state[i]    <= nexora_x3_pkg::MESI_INVALID;
                sharers_map[i]  <= '0;
                owner[i]        <= 4'h0;
            end
            active_req_id   <= 4'h0;
            active_req      <= '0;
            dir_idx         <= 8'h0;
            data_from_mem   <= {DATA_WIDTH{1'b0}};
            snoop_pending   <= '0;
            snoop_ack_recv  <= '0;
            resp_to_send    <= '0;
            sending_resp    <= 1'b0;
            resp_target     <= 4'h0;
        end else begin
            case (state)
                DIR_IDLE: begin

                    for (int i = NUM_CACHES-1; i >= 0; i--) begin
                        if (coh_req_valid[i]) begin
                            active_req_id <= i[3:0];
                            active_req    <= coh_req[i];
                        end
                    end
                end

                DIR_LOOKUP: begin
                    dir_idx <= active_req.addr[9:2];
                end

                DIR_SNOOP: begin

                    snoop_pending  <= sharers_map[dir_idx] & ~(1 << active_req_id);
                    snoop_ack_recv <= '0;
                end

                DIR_WAIT_MEM: begin
                    if (mem_resp.ready) begin
                        data_from_mem <= mem_resp.rdata;

                        if (active_req.msg_type == nexora_x3_pkg::COH_READ) begin
                            dir_state[dir_idx]   <= nexora_x3_pkg::MESI_EXCLUSIVE;
                            owner[dir_idx]        <= active_req_id;
                            sharers_map[dir_idx] <= 1 << active_req_id;
                        end else if (active_req.msg_type == nexora_x3_pkg::COH_READ_EX) begin
                            dir_state[dir_idx]   <= nexora_x3_pkg::MESI_MODIFIED;
                            owner[dir_idx]        <= active_req_id;
                            sharers_map[dir_idx] <= 1 << active_req_id;
                        end else if (active_req.msg_type == nexora_x3_pkg::COH_WB_DATA) begin
                            dir_state[dir_idx]   <= nexora_x3_pkg::MESI_INVALID;
                            sharers_map[dir_idx] <= '0;
                        end
                    end
                end

                DIR_WAIT_ACK: begin

                    for (int i = 0; i < NUM_CACHES; i++) begin
                        if (coh_req_valid[i] && (coh_req_msg_type[i] == nexora_x3_pkg::COH_ACK)) begin
                            snoop_ack_recv[i] <= 1'b1;
                        end
                    end

                    if ((snoop_pending & ~snoop_ack_recv) == '0) begin
                        dir_state[dir_idx]   <= (active_req.msg_type == nexora_x3_pkg::COH_READ_EX) ? nexora_x3_pkg::MESI_MODIFIED : nexora_x3_pkg::MESI_EXCLUSIVE;
                        owner[dir_idx]        <= active_req_id;
                        sharers_map[dir_idx] <= 1 << active_req_id;
                    end
                end

                DIR_RESPOND: begin

                    resp_to_send.msg_type  <= nexora_x3_pkg::COH_DATA_RESP;
                    resp_to_send.data      <= data_from_mem;
                    resp_to_send.ack       <= 1'b1;
                    resp_to_send.ack_count <= 4'h0;
                    resp_target            <= active_req_id;
                    sending_resp           <= 1'b1;
                end

                default: begin end
            endcase

            if (sending_resp) begin
                sending_resp <= 1'b0;
            end
        end
    end

    always_comb begin
        next_state = state;
        mem_req    = '0;

        case (state)
            DIR_IDLE: begin

                for (int i = 0; i < NUM_CACHES; i++) begin
                    if (coh_req_valid[i]) begin
                        next_state = DIR_LOOKUP;
                    end
                end
            end

            DIR_LOOKUP: begin
                next_state = DIR_WAIT_MEM; 

                if (dir_state[dir_idx] == nexora_x3_pkg::MESI_EXCLUSIVE || dir_state[dir_idx] == nexora_x3_pkg::MESI_MODIFIED) begin
                    if (owner[dir_idx] != active_req_id) begin
                        next_state = DIR_SNOOP;
                    end
                end
            end

            DIR_SNOOP: begin

                next_state = DIR_WAIT_ACK;
                mem_req.read_en = 1'b1;
                mem_req.addr    = active_req.addr;
                mem_req.byte_en = 8'hFF;
            end

            DIR_WAIT_MEM: begin
                mem_req.read_en = (active_req.msg_type != nexora_x3_pkg::COH_WB_DATA);
                mem_req.write_en = (active_req.msg_type == nexora_x3_pkg::COH_WB_DATA);
                mem_req.addr    = active_req.addr;
                mem_req.wdata   = active_req.data;
                mem_req.byte_en = 8'hFF;
                if (mem_resp.ready) begin
                    next_state = DIR_RESPOND;
                end
            end

            DIR_WAIT_ACK: begin
                if ((snoop_pending & ~snoop_ack_recv) == '0 || snoop_pending == '0) begin
                    next_state = DIR_WAIT_MEM;
                end
            end

            DIR_RESPOND: begin
                next_state = DIR_IDLE;
            end

            default: next_state = DIR_IDLE;
        endcase
    end

    always_comb begin
        for (int i = 0; i < NUM_CACHES; i++) begin
            coh_resp[i] = {
                nexora_x3_pkg::COH_DATA_RESP,
                {DATA_WIDTH{1'b0}},
                1'b0,
                4'h0
            };
            coh_resp_valid[i] = 1'b0;
        end

        if (sending_resp) begin
            coh_resp[resp_target]       = resp_to_send;
            coh_resp_valid[resp_target] = 1'b1;
        end
    end

endmodule : coherence_dir
