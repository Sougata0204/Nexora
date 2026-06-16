// memory_fabric
`timescale 1ns / 1ps
module memory_fabric (
    input  logic clk,
    input  logic rst_n,

    input  nexora_x3_pkg::mem_req_t [7:0] noc_req,
    output nexora_x3_pkg::mem_resp_t [7:0] noc_resp,

    output nexora_x3_pkg::mem_req_t  phy_req,
    input  nexora_x3_pkg::mem_resp_t phy_resp
);

    logic [2:0] rr_ptr;
    logic [2:0] active_ch;
    logic       has_req;
    logic       busy;

    logic noc_read_en [7:0];
    logic noc_write_en [7:0];
    nexora_x3_pkg::mem_req_t tmp_noc_req;
    always_comb begin
        for (int i = 0; i < 8; i++) begin
            tmp_noc_req = noc_req[i];
            noc_read_en[i]  = tmp_noc_req.read_en;
            noc_write_en[i] = tmp_noc_req.write_en;
        end
    end

    always_comb begin : next_ch_comb
        int idx;

        has_req   = 1'b0;
        active_ch = rr_ptr;
        for (int i = 0; i < 8; i++) begin
            idx = (rr_ptr + i) % 8;
            if (!has_req && (noc_read_en[idx] || noc_write_en[idx])) begin
                active_ch = idx[2:0];
                has_req   = 1'b1;
            end
        end
    end

    logic [2:0] latched_ch;
    nexora_x3_pkg::mem_req_t   latched_req;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rr_ptr     <= 3'd0;
            busy       <= 1'b0;
            latched_ch <= 3'd0;
            latched_req <= '0;
        end else begin
            if (!busy && has_req) begin
                busy        <= 1'b1;
                latched_ch  <= active_ch;
                latched_req <= noc_req[active_ch];
            end
            if (busy && phy_resp.ready) begin
                busy       <= 1'b0;
                rr_ptr     <= latched_ch + 1;
                latched_req <= '0;
            end
        end
    end

    always_comb begin
        if (busy) begin
            phy_req = latched_req;
        end else begin
            phy_req = '0;
        end
    end

    always_comb begin
        for (int i = 0; i < 8; i++) begin
            noc_resp[i] = '0;
        end
        if (busy && phy_resp.ready) begin
            noc_resp[latched_ch] = phy_resp;
        end
    end

endmodule
