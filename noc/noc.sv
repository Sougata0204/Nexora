// noc
`timescale 1ns / 1ps
module noc #(
    parameter int NUM_CPU_CLUSTERS    = nexora_x3_pkg::NUM_CPU_CLUSTERS,
    parameter int NUM_GPU_CLUSTERS    = nexora_x3_pkg::NUM_GPU_CLUSTERS,
    parameter int NUM_TENSOR_CLUSTERS = nexora_x3_pkg::NUM_TENSOR_CLUSTERS
)(
    input  logic clk,
    input  logic rst_n,

    input  nexora_x3_pkg::mem_req_t [NUM_CPU_CLUSTERS-1:0]     cpu_req,
    output nexora_x3_pkg::mem_resp_t [NUM_CPU_CLUSTERS-1:0]    cpu_resp,

    input  nexora_x3_pkg::mem_req_t [NUM_GPU_CLUSTERS-1:0]     gpu_req,
    output nexora_x3_pkg::mem_resp_t [NUM_GPU_CLUSTERS-1:0]    gpu_resp,

    input  nexora_x3_pkg::mem_req_t [NUM_TENSOR_CLUSTERS-1:0]  tensor_req,
    output nexora_x3_pkg::mem_resp_t [NUM_TENSOR_CLUSTERS-1:0] tensor_resp,

    input  nexora_x3_pkg::mem_req_t  dsp_req,
    output nexora_x3_pkg::mem_resp_t dsp_resp,

    input  nexora_x3_pkg::mem_req_t  dma_req,
    output nexora_x3_pkg::mem_resp_t dma_resp,

    output nexora_x3_pkg::mem_req_t [7:0] mem_req,
    input  nexora_x3_pkg::mem_resp_t [7:0] mem_resp
);

    nexora_x3_pkg::noc_flit_t [3:0][3:0] h_flit_ew; 
    logic      h_valid_ew [3:0][3:0];
    logic      h_ready_ew [3:0][3:0];

    nexora_x3_pkg::noc_flit_t [3:0][3:0] h_flit_we;
    logic      h_valid_we [3:0][3:0];
    logic      h_ready_we [3:0][3:0];

    nexora_x3_pkg::noc_flit_t [3:0][3:0] v_flit_ns;
    logic      v_valid_ns [3:0][3:0];
    logic      v_ready_ns [3:0][3:0];

    nexora_x3_pkg::noc_flit_t [3:0][3:0] v_flit_sn;
    logic      v_valid_sn [3:0][3:0];
    logic      v_ready_sn [3:0][3:0];

    nexora_x3_pkg::noc_flit_t [3:0][3:0] local_to_router;
    logic      local_to_router_valid [3:0][3:0];
    logic      local_to_router_ready [3:0][3:0];

    nexora_x3_pkg::noc_flit_t [3:0][3:0] router_to_local;
    logic      router_to_local_valid [3:0][3:0];
    logic      router_to_local_ready [3:0][3:0];

    nexora_x3_pkg::mem_req_t [3:0][3:0] ni_mem_req;
    nexora_x3_pkg::mem_resp_t [3:0][3:0] ni_mem_resp;

    always_comb begin
        // Initialize all to zero
        for (int x = 0; x < 4; x++) begin
            for (int y = 0; y < 4; y++) begin
                ni_mem_req[x][y] = '0;
            end
        end

        // Map CPU clusters to NI ports [x][0]
        for (int i = 0; i < NUM_CPU_CLUSTERS && i < 4; i++) begin
            ni_mem_req[i][0] = cpu_req[i];
            cpu_resp[i]      = ni_mem_resp[i][0];
        end

        // Map GPU clusters to NI ports [x][1] and [x][2]
        for (int i = 0; i < NUM_GPU_CLUSTERS && i < 4; i++) begin
            ni_mem_req[i][1] = gpu_req[i];
            gpu_resp[i]      = ni_mem_resp[i][1];
        end
        for (int i = 0; i < NUM_GPU_CLUSTERS - 4 && i < 4; i++) begin
            ni_mem_req[i][2] = gpu_req[i+4];
            gpu_resp[i+4]    = ni_mem_resp[i][2];
        end

        // Map Tensor clusters to NI ports [x][3]
        for (int i = 0; i < NUM_TENSOR_CLUSTERS && i < 4; i++) begin
            ni_mem_req[i][3] = tensor_req[i];
            tensor_resp[i]   = ni_mem_resp[i][3];
        end

        // DSP at [2][3]
        ni_mem_req[2][3] = dsp_req;
        dsp_resp         = ni_mem_resp[2][3];

        // Unused ports
        ni_mem_req[3][3] = '0;

        // Tie off any unused tensor resp
        for (int i = NUM_TENSOR_CLUSTERS; i < 4; i++) begin
            tensor_resp[i] = '0;
        end
        dma_resp = '0;
    end

    logic [7:0] [31:0] mc_pending_addr;
    logic [7:0] [3:0]  mc_msg_type;
    logic [7:0] [1:0]  mc_src_x;
    logic [7:0] [1:0]  mc_src_y;
    logic [7:0]        mc_pending;
    logic [7:0] [31:0] mc_rdata;
    logic [7:0]        mc_done;
    logic [2:0]  resp_rr_ptr;

    logic mc_resp_ready [7:0];
    logic [nexora_x3_pkg::DATA_WIDTH-1:0] mc_resp_rdata [7:0];
    nexora_x3_pkg::mem_resp_t tmp_mem_resp;
    always_comb begin
        for (int i = 0; i < 8; i++) begin
            tmp_mem_resp = mem_resp[i];
            mc_resp_ready[i] = tmp_mem_resp.ready;
            mc_resp_rdata[i] = tmp_mem_resp.rdata;
        end
    end

    nexora_x3_pkg::noc_flit_t mc_flit_in;
    logic      mc_flit_in_valid;
    logic      mc_flit_in_ready;

    nexora_x3_pkg::noc_flit_t mc_flit_out;
    logic      mc_flit_out_valid;
    logic      mc_flit_out_ready;

    assign mc_flit_in       = router_to_local[3][3];
    assign mc_flit_in_valid = router_to_local_valid[3][3];
    assign mc_flit_out_ready           = local_to_router_ready[3][3];

    logic [2:0] incoming_c;
    assign incoming_c = mc_flit_in.payload[5:3];

    assign mc_flit_in_ready = !mc_pending[incoming_c] && !mc_done[incoming_c];

    logic       resp_found;
    logic [2:0] selected_c;

    always_comb begin
        resp_found = 1'b0;
        selected_c = '0;
        for (int i = 0; i < 8; i++) begin
            logic [2:0] c;
            c = resp_rr_ptr + i;
            if (mc_done[c] && !resp_found) begin
                selected_c = c;
                resp_found = 1'b1;
            end
        end
    end

    always_comb begin
        mc_flit_out = '0;
        if (resp_found) begin
            mc_flit_out.flit_type = nexora_x3_pkg::FLIT_HEAD;
            mc_flit_out.dst_x     = mc_src_x[selected_c];
            mc_flit_out.dst_y     = mc_src_y[selected_c];
            mc_flit_out.src_x     = 2'd3;
            mc_flit_out.src_y     = 2'd3;
            mc_flit_out.vc_id     = 2'd0;
            mc_flit_out.msg_type  = (mc_msg_type[selected_c] == 4'h0) ? 4'h2 : 4'h3;
            mc_flit_out.payload   = mc_rdata[selected_c];
        end
    end

    assign mc_flit_out_valid = resp_found;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            resp_rr_ptr <= '0;
            for (int i = 0; i < 8; i++) begin
                mc_pending_addr[i]   <= '0;
                mc_msg_type[i]       <= '0;
                mc_src_x[i]          <= '0;
                mc_src_y[i]          <= '0;
                mc_pending[i]        <= 1'b0;
                mc_rdata[i]          <= '0;
                mc_done[i]           <= 1'b0;
                mem_req[i]           <= '0;
            end
        end else begin

            if (mc_flit_in_valid && mc_flit_in_ready) begin
                mc_pending[incoming_c]      <= 1'b1;
                mc_pending_addr[incoming_c] <= mc_flit_in.payload;
                mc_msg_type[incoming_c]     <= mc_flit_in.msg_type;
                mc_src_x[incoming_c]        <= mc_flit_in.src_x;
                mc_src_y[incoming_c]        <= mc_flit_in.src_y;

                if (mc_flit_in.msg_type == 4'h0) begin

                    mem_req[incoming_c] <= {mc_flit_in.payload, 64'd0, 1'b1, 1'b0, 8'hFF};
                end else if (mc_flit_in.msg_type == 4'h1) begin

                    mem_req[incoming_c] <= {mc_flit_in.payload, 64'd0, 1'b0, 1'b1, 8'hFF};
                end
            end

            for (int c = 0; c < 8; c++) begin
                if (mc_pending[c] && mc_resp_ready[c]) begin
                    mc_pending[c]       <= 1'b0;
                    mem_req[c]          <= '0; 
                    mc_rdata[c]    <= mc_resp_rdata[c];
                    mc_done[c]     <= 1'b1;
                end
            end

            if (resp_found && mc_flit_out_ready) begin
                mc_done[selected_c] <= 1'b0;
                resp_rr_ptr         <= selected_c + 1;
            end
        end
    end

    genvar gx, gy;
    generate
        for (gy = 0; gy < 4; gy++) begin : row_gen
            for (gx = 0; gx < 4; gx++) begin : col_gen

                if (!(gx == 3 && gy == 3)) begin : gen_ni
                    noc_ni #(
                        .NI_X     (gx),
                        .NI_Y     (gy),
                        .NI_ID    (gy * 4 + gx),
                        .MEM_DST_X(3),
                        .MEM_DST_Y(3)
                    ) u_ni (
                        .clk           (clk),
                        .rst_n         (rst_n),
                        .mem_req       (ni_mem_req[gx][gy]),
                        .mem_resp      (ni_mem_resp[gx][gy]),
                        .flit_out      (local_to_router[gx][gy]),
                        .flit_out_valid(local_to_router_valid[gx][gy]),
                        .flit_out_ready(local_to_router_ready[gx][gy]),
                        .flit_in       (router_to_local[gx][gy]),
                        .flit_in_valid (router_to_local_valid[gx][gy]),
                        .flit_in_ready (router_to_local_ready[gx][gy])
                    );
                end else begin : gen_mc_tieoff
                    // Memory controller position — no NI, tie off unused resp
                    assign ni_mem_resp[gx][gy] = '0;
                end

                nexora_x3_pkg::noc_flit_t north_in_flit;
                logic      north_in_valid;
                logic      north_in_ready;
                nexora_x3_pkg::noc_flit_t north_out_flit;
                logic      north_out_valid;
                logic      north_out_ready;

                nexora_x3_pkg::noc_flit_t south_in_flit;
                logic      south_in_valid;
                logic      south_in_ready;
                nexora_x3_pkg::noc_flit_t south_out_flit;
                logic      south_out_valid;
                logic      south_out_ready;

                nexora_x3_pkg::noc_flit_t east_in_flit;
                logic      east_in_valid;
                logic      east_in_ready;
                nexora_x3_pkg::noc_flit_t east_out_flit;
                logic      east_out_valid;
                logic      east_out_ready;

                nexora_x3_pkg::noc_flit_t west_in_flit;
                logic      west_in_valid;
                logic      west_in_ready;
                nexora_x3_pkg::noc_flit_t west_out_flit;
                logic      west_out_valid;
                logic      west_out_ready;

                if (gy > 0) begin
                    assign north_in_flit         = v_flit_ns[gx][gy-1];
                    assign north_in_valid        = v_valid_ns[gx][gy-1];
                    assign v_ready_ns[gx][gy-1]  = north_in_ready;
                    assign v_flit_sn[gx][gy-1]   = north_out_flit;
                    assign v_valid_sn[gx][gy-1]  = north_out_valid;
                    assign north_out_ready       = v_ready_sn[gx][gy-1];
                end else begin
                    assign north_in_flit         = '0;
                    assign north_in_valid        = 1'b0;
                    assign north_out_ready       = 1'b1;
                end

                if (gy < 3) begin
                    assign south_in_flit         = v_flit_sn[gx][gy];
                    assign south_in_valid        = v_valid_sn[gx][gy];
                    assign v_ready_sn[gx][gy]    = south_in_ready;
                    assign v_flit_ns[gx][gy]     = south_out_flit;
                    assign v_valid_ns[gx][gy]    = south_out_valid;
                    assign south_out_ready       = v_ready_ns[gx][gy];
                end else begin
                    assign south_in_flit         = '0;
                    assign south_in_valid        = 1'b0;
                    assign south_out_ready       = 1'b1;
                end

                if (gx < 3) begin
                    assign east_in_flit          = h_flit_we[gx][gy];
                    assign east_in_valid         = h_valid_we[gx][gy];
                    assign h_ready_we[gx][gy]    = east_in_ready;
                    assign h_flit_ew[gx][gy]     = east_out_flit;
                    assign h_valid_ew[gx][gy]    = east_out_valid;
                    assign east_out_ready        = h_ready_ew[gx][gy];
                end else begin
                    assign east_in_flit          = '0;
                    assign east_in_valid         = 1'b0;
                    assign east_out_ready        = 1'b1;
                end

                if (gx > 0) begin
                    assign west_in_flit          = h_flit_ew[gx-1][gy];
                    assign west_in_valid         = h_valid_ew[gx-1][gy];
                    assign h_ready_ew[gx-1][gy]  = west_in_ready;
                    assign h_flit_we[gx-1][gy]   = west_out_flit;
                    assign h_valid_we[gx-1][gy]  = west_out_valid;
                    assign west_out_ready        = h_ready_we[gx-1][gy];
                end else begin
                    assign west_in_flit          = '0;
                    assign west_in_valid         = 1'b0;
                    assign west_out_ready        = 1'b1;
                end

                noc_router #(
                    .ROUTER_X(gx),
                    .ROUTER_Y(gy)
                ) u_router (
                    .clk  (clk),
                    .rst_n(rst_n),

                    .local_flit_in        ( (gx==3 && gy==3) ? mc_flit_out : local_to_router[gx][gy] ),
                    .local_flit_in_valid  ( (gx==3 && gy==3) ? mc_flit_out_valid : local_to_router_valid[gx][gy] ),
                    .local_flit_in_ready  ( local_to_router_ready[gx][gy] ),
                    .local_flit_out       ( router_to_local[gx][gy] ),
                    .local_flit_out_valid ( router_to_local_valid[gx][gy] ),
                    .local_flit_out_ready ( (gx==3 && gy==3) ? mc_flit_in_ready : router_to_local_ready[gx][gy] ),

                    .north_flit_in        (north_in_flit),
                    .north_flit_in_valid  (north_in_valid),
                    .north_flit_in_ready  (north_in_ready),
                    .north_flit_out       (north_out_flit),
                    .north_flit_out_valid (north_out_valid),
                    .north_flit_out_ready (north_out_ready),

                    .east_flit_in         (east_in_flit),
                    .east_flit_in_valid   (east_in_valid),
                    .east_flit_in_ready   (east_in_ready),
                    .east_flit_out        (east_out_flit),
                    .east_flit_out_valid  (east_out_valid),
                    .east_flit_out_ready  (east_out_ready),

                    .south_flit_in        (south_in_flit),
                    .south_flit_in_valid  (south_in_valid),
                    .south_flit_in_ready  (south_in_ready),
                    .south_flit_out       (south_out_flit),
                    .south_flit_out_valid (south_out_valid),
                    .south_flit_out_ready (south_out_ready),

                    .west_flit_in         (west_in_flit),
                    .west_flit_in_valid   (west_in_valid),
                    .west_flit_in_ready   (west_in_ready),
                    .west_flit_out        (west_out_flit),
                    .west_flit_out_valid  (west_out_valid),
                    .west_flit_out_ready  (west_out_ready)
                );

            end
        end
    endgenerate

endmodule : noc
