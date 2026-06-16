// hbm_controller
`timescale 1ns / 1ps
module hbm_controller #(
    parameter int AXI_ID_W   = nexora_x3_pkg::AXI_ID_WIDTH,
    parameter int AXI_ADDR_W = nexora_x3_pkg::AXI_ADDR_WIDTH,
    parameter int AXI_DATA_W = nexora_x3_pkg::AXI_DATA_WIDTH
)(
    input  logic clk,
    input  logic rst_n,

    input  nexora_x3_pkg::mem_req_t  soc_req,
    output nexora_x3_pkg::mem_resp_t soc_resp,

    input  logic        pim_cmd_valid,
    output logic        pim_cmd_ready,
    input  logic [2:0]  pim_cmd_op,
    input  logic [63:0] pim_cmd_addr_a,
    input  logic [63:0] pim_cmd_addr_b,
    input  logic [63:0] pim_cmd_addr_dst,

    output logic        pim_busy,
    output logic        pim_done,

    output logic [AXI_ID_W-1:0]   m_axi_hbm_awid,
    output logic [AXI_ADDR_W-1:0] m_axi_hbm_awaddr,
    output logic [7:0]            m_axi_hbm_awlen,
    output logic [2:0]            m_axi_hbm_awsize,
    output logic [1:0]            m_axi_hbm_awburst,
    output logic                  m_axi_hbm_awvalid,
    input  logic                  m_axi_hbm_awready,

    output logic [AXI_DATA_W-1:0]   m_axi_hbm_wdata,
    output logic [(AXI_DATA_W/8)-1:0] m_axi_hbm_wstrb,
    output logic                    m_axi_hbm_wlast,
    output logic                    m_axi_hbm_wvalid,
    input  logic                    m_axi_hbm_wready,

    input  logic [AXI_ID_W-1:0]   m_axi_hbm_bid,
    input  logic [1:0]            m_axi_hbm_bresp,
    input  logic                  m_axi_hbm_bvalid,
    output logic                  m_axi_hbm_bready,

    output logic [AXI_ID_W-1:0]   m_axi_hbm_arid,
    output logic [AXI_ADDR_W-1:0] m_axi_hbm_araddr,
    output logic [7:0]            m_axi_hbm_arlen,
    output logic [2:0]            m_axi_hbm_arsize,
    output logic [1:0]            m_axi_hbm_arburst,
    output logic                  m_axi_hbm_arvalid,
    input  logic                  m_axi_hbm_arready,

    input  logic [AXI_ID_W-1:0]   m_axi_hbm_rid,
    input  logic [AXI_DATA_W-1:0] m_axi_hbm_rdata,
    input  logic [1:0]            m_axi_hbm_rresp,
    input  logic                  m_axi_hbm_rlast,
    input  logic                  m_axi_hbm_rvalid,
    output logic                  m_axi_hbm_rready
);

    localparam int LLC_TAG_W = AXI_ADDR_W - 8 - 4; 
    localparam int LLC_SETS  = 256;
    localparam int LLC_WAYS  = 4;
    localparam int PIM_VECTOR_DEPTH = 16;

    logic [LLC_TAG_W-1:0] llc_tag   [LLC_SETS-1:0][LLC_WAYS-1:0];
    logic                 llc_valid [LLC_SETS-1:0][LLC_WAYS-1:0];
    logic                 llc_dirty [LLC_SETS-1:0][LLC_WAYS-1:0];
    logic [127:0]         llc_data  [LLC_SETS-1:0][LLC_WAYS-1:0];
    logic [1:0]           llc_lru   [LLC_SETS-1:0][LLC_WAYS-1:0]; 

    logic [LLC_TAG_W-1:0] lookup_tag;
    logic [7:0]           lookup_index;
    logic                 llc_hit;
    logic [1:0]           llc_hit_way;
    logic [127:0]         llc_hit_data;
    logic [1:0]           llc_victim_way;

    assign lookup_tag   = soc_req.addr[AXI_ADDR_W-1:12];
    assign lookup_index = soc_req.addr[11:4];

    always_comb begin : llc_lookup
        llc_hit      = 1'b0;
        llc_hit_way  = 2'd0;
        llc_hit_data = 128'd0;

        for (int w = 0; w < LLC_WAYS; w++) begin
            if (llc_valid[lookup_index][w] && (llc_tag[lookup_index][w] == lookup_tag)) begin
                llc_hit      = 1'b1;
                llc_hit_way  = w[1:0];
                llc_hit_data = llc_data[lookup_index][w];
            end
        end
    end

    always_comb begin : llc_victim_sel
        logic [1:0] max_way;
        logic [1:0] max_lru;
        max_way = 2'd0;
        max_lru = llc_lru[lookup_index][0];
        for (int w = 1; w < LLC_WAYS; w++) begin
            if (llc_lru[lookup_index][w] > max_lru) begin
                max_way = w[1:0];
                max_lru = llc_lru[lookup_index][w];
            end
        end
        llc_victim_way = max_way;
    end

    typedef enum logic [3:0] {
        IDLE,
        LLC_HIT_RESP,
        WRITE_AW,
        WRITE_W,
        WRITE_RESP,
        READ_AR,
        READ_R,
        LLC_FILL,
        PIM_ACTIVE,
        PIM_WAIT
    } hbm_fsm_t;

    hbm_fsm_t state, next_state;

    assign m_axi_hbm_awid    = '0;
    assign m_axi_hbm_awlen   = 8'd0;
    assign m_axi_hbm_awsize  = 3'b011; 
    assign m_axi_hbm_awburst = 2'b01;  

    assign m_axi_hbm_arid    = '0;
    assign m_axi_hbm_arlen   = 8'd0;
    assign m_axi_hbm_arsize  = 3'b100; 
    assign m_axi_hbm_arburst = 2'b01;

    logic [AXI_ADDR_W-1:0] latched_addr;

    logic is_upper_half;
    assign is_upper_half = latched_addr[3];

    assign m_axi_hbm_wdata = soc_req.addr[3] ? {soc_req.wdata, 64'd0} : {64'd0, soc_req.wdata};
    assign m_axi_hbm_wstrb = soc_req.addr[3] ? {soc_req.byte_en, 8'd0} : {8'd0, soc_req.byte_en};
    assign m_axi_hbm_wlast = 1'b1;

    logic [63:0] extracted_rdata;
    assign extracted_rdata = is_upper_half ? m_axi_hbm_rdata[127:64] : m_axi_hbm_rdata[63:0];

    logic        pim_rd_req;
    logic [63:0] pim_rd_addr;
    logic [63:0] pim_rd_data;
    logic        pim_rd_valid;
    logic        pim_wr_req;
    logic [63:0] pim_wr_addr;
    logic [63:0] pim_wr_data;
    logic        pim_wr_ready;
    logic        pim_engine_busy;
    logic        pim_engine_done;
    logic [31:0] pim_perf_ops;

    pim_engine #(
        .VECTOR_DEPTH(PIM_VECTOR_DEPTH)
    ) u_pim_engine (
        .clk             (clk),
        .rst_n           (rst_n),
        .pim_cmd_valid   (pim_cmd_valid && (state == IDLE)),
        .pim_cmd_ready   (pim_cmd_ready),
        .pim_cmd_op      (pim_cmd_op),
        .pim_cmd_addr_a  (pim_cmd_addr_a),
        .pim_cmd_addr_b  (pim_cmd_addr_b),
        .pim_cmd_addr_dst(pim_cmd_addr_dst),
        .pim_rd_req      (pim_rd_req),
        .pim_rd_addr     (pim_rd_addr),
        .pim_rd_data     (pim_rd_data),
        .pim_rd_valid    (pim_rd_valid),
        .pim_wr_req      (pim_wr_req),
        .pim_wr_addr     (pim_wr_addr),
        .pim_wr_data     (pim_wr_data),
        .pim_wr_ready    (pim_wr_ready),
        .pim_busy        (pim_engine_busy),
        .pim_done        (pim_engine_done),
        .pim_perf_ops    (pim_perf_ops)
    );

    assign pim_busy = pim_engine_busy;
    assign pim_done = pim_engine_done;

    localparam int PIM_SPAD_DEPTH = 256; 
    (* ram_style = "block" *) logic [63:0] pim_spad [PIM_SPAD_DEPTH-1:0];

    always_ff @(posedge clk or negedge rst_n) begin : pim_spad_ctrl
        if (!rst_n) begin
            pim_rd_valid <= 1'b0;
            pim_rd_data  <= 64'd0;
            pim_wr_ready <= 1'b0;
        end else begin

            pim_rd_valid <= pim_rd_req;
            if (pim_rd_req) begin
                pim_rd_data <= pim_spad[pim_rd_addr[10:3]]; 
            end

            pim_wr_ready <= pim_wr_req;
            if (pim_wr_req) begin
                pim_spad[pim_wr_addr[10:3]] <= pim_wr_data;
            end
        end
    end

    always_comb begin
        next_state = state;

        m_axi_hbm_awvalid = 1'b0;
        m_axi_hbm_wvalid  = 1'b0;
        m_axi_hbm_bready  = 1'b0;

        m_axi_hbm_arvalid = 1'b0;
        m_axi_hbm_rready  = 1'b0;

        soc_resp.ready = 1'b0;
        soc_resp.error = 1'b0;
        soc_resp.rdata = '0;

        case (state)
            IDLE: begin
                if (pim_cmd_valid) begin

                    next_state = PIM_ACTIVE;
                end else if (soc_req.read_en && llc_hit) begin

                    next_state = LLC_HIT_RESP;
                end else if (soc_req.write_en) begin
                    next_state = WRITE_AW;
                end else if (soc_req.read_en) begin

                    next_state = READ_AR;
                end
            end

            LLC_HIT_RESP: begin
                soc_resp.ready = 1'b1;
                soc_resp.rdata = latched_addr[3] ? llc_hit_data[127:64] : llc_hit_data[63:0];
                soc_resp.error = 1'b0;
                next_state = IDLE;
            end

            WRITE_AW: begin
                m_axi_hbm_awvalid = 1'b1;
                if (m_axi_hbm_awready) begin
                    next_state = WRITE_W;
                end
            end

            WRITE_W: begin
                m_axi_hbm_wvalid = 1'b1;
                if (m_axi_hbm_wready) begin
                    next_state = WRITE_RESP;
                end
            end

            WRITE_RESP: begin
                m_axi_hbm_bready = 1'b1;
                if (m_axi_hbm_bvalid) begin
                    soc_resp.ready = 1'b1;
                    soc_resp.error = m_axi_hbm_bresp[1];
                    next_state = IDLE;
                end
            end

            READ_AR: begin
                m_axi_hbm_arvalid = 1'b1;
                if (m_axi_hbm_arready) begin
                    next_state = READ_R;
                end
            end

            READ_R: begin
                m_axi_hbm_rready = 1'b1;
                if (m_axi_hbm_rvalid) begin
                    soc_resp.ready = 1'b1;
                    soc_resp.rdata = extracted_rdata;
                    soc_resp.error = m_axi_hbm_rresp[1];
                    next_state = LLC_FILL;
                end
            end

            LLC_FILL: begin

                next_state = IDLE;
            end

            PIM_ACTIVE: begin

                if (pim_engine_done) begin
                    next_state = IDLE;
                end
            end

            PIM_WAIT: begin
                next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

    assign m_axi_hbm_awaddr = (state == IDLE) ? soc_req.addr : latched_addr;
    assign m_axi_hbm_araddr = (state == IDLE) ? {soc_req.addr[63:4], 4'b0000} : {latched_addr[63:4], 4'b0000};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            latched_addr <= '0;

            for (int s = 0; s < LLC_SETS; s++) begin
                for (int w = 0; w < LLC_WAYS; w++) begin
                    llc_valid[s][w] <= 1'b0;
                end
            end
        end else begin
            state <= next_state;

            if (state == IDLE && (soc_req.write_en || soc_req.read_en)) begin
                latched_addr <= soc_req.addr;
            end

            if (state == READ_R && m_axi_hbm_rvalid) begin

                llc_valid[lookup_index][llc_victim_way] <= 1'b1;
                llc_dirty[lookup_index][llc_victim_way] <= 1'b0;
                llc_tag[lookup_index][llc_victim_way]   <= latched_addr[AXI_ADDR_W-1:12];
                llc_data[lookup_index][llc_victim_way]  <= m_axi_hbm_rdata;

                for (int w = 0; w < LLC_WAYS; w++) begin
                    if (w[1:0] == llc_victim_way) begin
                        llc_lru[lookup_index][w] <= 2'd0;
                    end else begin
                        if (llc_lru[lookup_index][w] < 2'd3) begin
                            llc_lru[lookup_index][w] <= llc_lru[lookup_index][w] + 2'd1;
                        end
                    end
                end
            end

            if (state == LLC_HIT_RESP) begin
                for (int w = 0; w < LLC_WAYS; w++) begin
                    if (w[1:0] == llc_hit_way) begin
                        llc_lru[lookup_index][w] <= 2'd0;
                    end else begin
                        if (llc_lru[lookup_index][w] < 2'd3) begin
                            llc_lru[lookup_index][w] <= llc_lru[lookup_index][w] + 2'd1;
                        end
                    end
                end
            end

            if (soc_req.write_en) begin
                for (int w = 0; w < LLC_WAYS; w++) begin
                    if (llc_valid[lookup_index][w] && (llc_tag[lookup_index][w] == lookup_tag)) begin
                        llc_valid[lookup_index][w] <= 1'b0;
                    end
                end
            end
        end
    end

endmodule : hbm_controller
