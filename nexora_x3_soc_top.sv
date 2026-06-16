// nexora_x3_soc_top
`timescale 1ns / 1ps
module nexora_x3_soc_top (
    input  logic clk,
    input  logic rst_n,

    input  logic tck,
    input  logic tms,
    input  logic tdi,
    output logic tdo,

    output logic [nexora_x3_pkg::AXI_ID_WIDTH-1:0]   m_axi_hbm_awid,
    output logic [nexora_x3_pkg::AXI_ADDR_WIDTH-1:0] m_axi_hbm_awaddr,
    output logic [7:0]                               m_axi_hbm_awlen,
    output logic [2:0]                               m_axi_hbm_awsize,
    output logic [1:0]                               m_axi_hbm_awburst,
    output logic                                     m_axi_hbm_awvalid,
    input  logic                                     m_axi_hbm_awready,

    output logic [nexora_x3_pkg::AXI_DATA_WIDTH-1:0]   m_axi_hbm_wdata,
    output logic [(nexora_x3_pkg::AXI_DATA_WIDTH/8)-1:0] m_axi_hbm_wstrb,
    output logic                                       m_axi_hbm_wlast,
    output logic                                       m_axi_hbm_wvalid,
    input  logic                                       m_axi_hbm_wready,

    input  logic [nexora_x3_pkg::AXI_ID_WIDTH-1:0]     m_axi_hbm_bid,
    input  logic [1:0]                                 m_axi_hbm_bresp,
    input  logic                                       m_axi_hbm_bvalid,
    output logic                                       m_axi_hbm_bready,

    output logic [nexora_x3_pkg::AXI_ID_WIDTH-1:0]   m_axi_hbm_arid,
    output logic [nexora_x3_pkg::AXI_ADDR_WIDTH-1:0] m_axi_hbm_araddr,
    output logic [7:0]                               m_axi_hbm_arlen,
    output logic [2:0]                               m_axi_hbm_arsize,
    output logic [1:0]                               m_axi_hbm_arburst,
    output logic                                     m_axi_hbm_arvalid,
    input  logic                                     m_axi_hbm_arready,

    input  logic [nexora_x3_pkg::AXI_ID_WIDTH-1:0]   m_axi_hbm_rid,
    input  logic [nexora_x3_pkg::AXI_DATA_WIDTH-1:0] m_axi_hbm_rdata,
    input  logic [1:0]                               m_axi_hbm_rresp,
    input  logic                                     m_axi_hbm_rlast,
    input  logic                                     m_axi_hbm_rvalid,
    output logic                                     m_axi_hbm_rready,

    output logic uart_tx,
    input  logic uart_rx,

    output logic status_alive,       
    output logic status_cpu_halt,    
    output logic status_gpu_active,  
    output logic status_tensor_busy  
);


    localparam int NUM_CPU_CLUSTERS    = 4;
    localparam int NUM_GPU_CLUSTERS    = 8;
    localparam int NUM_TENSOR_CLUSTERS = 4;

    nexora_x3_pkg::mem_req_t [NUM_CPU_CLUSTERS-1:0] cpu_req;
    nexora_x3_pkg::mem_resp_t [NUM_CPU_CLUSTERS-1:0] cpu_resp;
    logic [NUM_CPU_CLUSTERS-1:0] cpu_system_halt;

    nexora_x3_pkg::mem_req_t [NUM_GPU_CLUSTERS-1:0] gpu_req;
    nexora_x3_pkg::mem_resp_t [NUM_GPU_CLUSTERS-1:0] gpu_resp;

    nexora_x3_pkg::mem_req_t [NUM_TENSOR_CLUSTERS-1:0] tensor_req;
    nexora_x3_pkg::mem_resp_t [NUM_TENSOR_CLUSTERS-1:0] tensor_resp;

    nexora_x3_pkg::mem_req_t  dsp_req;
    nexora_x3_pkg::mem_resp_t dsp_resp;

    nexora_x3_pkg::mem_req_t  dma_req;
    nexora_x3_pkg::mem_resp_t dma_resp;

    nexora_x3_pkg::mem_req_t [7:0] noc_to_mem_req;
    nexora_x3_pkg::mem_resp_t [7:0] noc_to_mem_resp;

    logic cpu_domain_en;
    logic gpu_domain_en;
    logic tensor_domain_en;
    logic dsp_domain_en;

    logic cpu_rst_n;
    logic gpu_rst_n;
    logic tensor_rst_n;
    logic dsp_rst_n;
    assign cpu_rst_n    = rst_n & cpu_domain_en;
    assign gpu_rst_n    = rst_n & gpu_domain_en;
    assign tensor_rst_n = rst_n & tensor_domain_en;
    assign dsp_rst_n    = rst_n & dsp_domain_en;

    nexora_x3_pkg::mem_req_t  phy_mem_req;
    nexora_x3_pkg::mem_resp_t phy_mem_resp;

    genvar i;

    logic [NUM_GPU_CLUSTERS-1:0]        gpu_pim_cmd_valid;
    logic [NUM_GPU_CLUSTERS-1:0]        gpu_pim_cmd_ready;
    logic [NUM_GPU_CLUSTERS-1:0] [2:0]  gpu_pim_cmd_op;
    logic [NUM_GPU_CLUSTERS-1:0] [63:0] gpu_pim_cmd_addr_a;
    logic [NUM_GPU_CLUSTERS-1:0] [63:0] gpu_pim_cmd_addr_b;
    logic [NUM_GPU_CLUSTERS-1:0] [63:0] gpu_pim_cmd_addr_dst;

    logic        hbm_pim_cmd_valid;
    logic        hbm_pim_cmd_ready;
    logic [2:0]  hbm_pim_cmd_op;
    logic [63:0] hbm_pim_cmd_addr_a;
    logic [63:0] hbm_pim_cmd_addr_b;
    logic [63:0] hbm_pim_cmd_addr_dst;
    logic        hbm_pim_busy;
    logic        hbm_pim_done;

    assign hbm_pim_cmd_valid    = gpu_pim_cmd_valid[0];
    assign gpu_pim_cmd_ready[0] = hbm_pim_cmd_ready;
    assign hbm_pim_cmd_op       = gpu_pim_cmd_op[0];
    assign hbm_pim_cmd_addr_a   = gpu_pim_cmd_addr_a[0];
    assign hbm_pim_cmd_addr_b   = gpu_pim_cmd_addr_b[0];
    assign hbm_pim_cmd_addr_dst = gpu_pim_cmd_addr_dst[0];

    generate
    for (i = 1; i < NUM_GPU_CLUSTERS; i++) begin : gen_pim_tie_off
            assign gpu_pim_cmd_ready[i] = 1'b0;
        end
    endgenerate

    hbm_controller u_hbm_controller (
        .clk(clk),
        .rst_n(rst_n),
        .soc_req(phy_mem_req),
        .soc_resp(phy_mem_resp),
        .m_axi_hbm_awid(m_axi_hbm_awid),
        .m_axi_hbm_awaddr(m_axi_hbm_awaddr),
        .m_axi_hbm_awlen(m_axi_hbm_awlen),
        .m_axi_hbm_awsize(m_axi_hbm_awsize),
        .m_axi_hbm_awburst(m_axi_hbm_awburst),
        .m_axi_hbm_awvalid(m_axi_hbm_awvalid),
        .m_axi_hbm_awready(m_axi_hbm_awready),
        .m_axi_hbm_wdata(m_axi_hbm_wdata),
        .m_axi_hbm_wstrb(m_axi_hbm_wstrb),
        .m_axi_hbm_wlast(m_axi_hbm_wlast),
        .m_axi_hbm_wvalid(m_axi_hbm_wvalid),
        .m_axi_hbm_wready(m_axi_hbm_wready),
        .m_axi_hbm_bid(m_axi_hbm_bid),
        .m_axi_hbm_bresp(m_axi_hbm_bresp),
        .m_axi_hbm_bvalid(m_axi_hbm_bvalid),
        .m_axi_hbm_bready(m_axi_hbm_bready),
        .m_axi_hbm_arid(m_axi_hbm_arid),
        .m_axi_hbm_araddr(m_axi_hbm_araddr),
        .m_axi_hbm_arlen(m_axi_hbm_arlen),
        .m_axi_hbm_arsize(m_axi_hbm_arsize),
        .m_axi_hbm_arburst(m_axi_hbm_arburst),
        .m_axi_hbm_arvalid(m_axi_hbm_arvalid),
        .m_axi_hbm_arready(m_axi_hbm_arready),
        .m_axi_hbm_rid(m_axi_hbm_rid),
        .m_axi_hbm_rdata(m_axi_hbm_rdata),
        .m_axi_hbm_rresp(m_axi_hbm_rresp),
        .m_axi_hbm_rlast(m_axi_hbm_rlast),
        .m_axi_hbm_rvalid(m_axi_hbm_rvalid),
        .m_axi_hbm_rready(m_axi_hbm_rready),

        .pim_cmd_valid(hbm_pim_cmd_valid),
        .pim_cmd_ready(hbm_pim_cmd_ready),
        .pim_cmd_op(hbm_pim_cmd_op),
        .pim_cmd_addr_a(hbm_pim_cmd_addr_a),
        .pim_cmd_addr_b(hbm_pim_cmd_addr_b),
        .pim_cmd_addr_dst(hbm_pim_cmd_addr_dst),
        .pim_busy(hbm_pim_busy),
        .pim_done(hbm_pim_done)
    );

    generate
    for (i = 0; i < 4; i++) begin : cpu_clusters
            if (i < NUM_CPU_CLUSTERS) begin : gen_active
                cpu_cluster u_cpu_cluster (
                    .clk(clk),
                    .rst_n(cpu_rst_n),
                    .main_mem_req(cpu_req[i]),
                    .main_mem_resp(cpu_resp[i]),
                    .system_halt(cpu_system_halt[i])
                );
            end else begin : gen_tie_off
                assign cpu_req[i].addr     = '0;
                assign cpu_req[i].wdata    = '0;
                assign cpu_req[i].read_en  = 1'b0;
                assign cpu_req[i].write_en = 1'b0;
                assign cpu_req[i].byte_en  = 8'h00;
                assign cpu_system_halt[i] = 1'b0;
            end
        end
    endgenerate

    generate
    for (i = 0; i < NUM_GPU_CLUSTERS; i++) begin : gpu_clusters
                gpu_cluster #(
                    .CLUSTER_ID(i)
                ) u_gpu_cluster (
                    .clk(clk),
                    .rst_n(gpu_rst_n),
                    .mem_req(gpu_req[i]),
                    .mem_resp(gpu_resp[i]),
                    .pim_cmd_valid(gpu_pim_cmd_valid[i]),
                    .pim_cmd_ready(gpu_pim_cmd_ready[i]),
                    .pim_cmd_op(gpu_pim_cmd_op[i]),
                    .pim_cmd_addr_a(gpu_pim_cmd_addr_a[i]),
                    .pim_cmd_addr_b(gpu_pim_cmd_addr_b[i]),
                    .pim_cmd_addr_dst(gpu_pim_cmd_addr_dst[i])
                );
        end
    endgenerate

    generate
    for (i = 0; i < NUM_TENSOR_CLUSTERS; i++) begin : tensor_clusters
                tensor_cluster #(
                    .CLUSTER_ID(i)
                ) u_tensor_cluster (
                    .clk(clk),
                    .rst_n(tensor_rst_n),
                    .mem_req(tensor_req[i]),
                    .mem_resp(tensor_resp[i])
                );
        end
    endgenerate

    dsp_cluster u_dsp_cluster (
        .clk(clk),
        .rst_n(dsp_rst_n),
        .mem_req(dsp_req),
        .mem_resp(dsp_resp)
    );

    dma_engine u_dma_engine (
        .clk(clk),
        .rst_n(rst_n),
        .mem_req(dma_req),
        .mem_resp(dma_resp)
    );

    noc #(
        .NUM_CPU_CLUSTERS    (NUM_CPU_CLUSTERS),
        .NUM_GPU_CLUSTERS    (NUM_GPU_CLUSTERS),
        .NUM_TENSOR_CLUSTERS (NUM_TENSOR_CLUSTERS)
    ) u_noc (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_req(cpu_req),
        .cpu_resp(cpu_resp),
        .gpu_req(gpu_req),
        .gpu_resp(gpu_resp),
        .tensor_req(tensor_req),
        .tensor_resp(tensor_resp),
        .dsp_req(dsp_req),
        .dsp_resp(dsp_resp),
        .dma_req(dma_req),
        .dma_resp(dma_resp),
        .mem_req(noc_to_mem_req),
        .mem_resp(noc_to_mem_resp)
    );

    nexora_x3_pkg::mem_req_t [7:0] l2_to_mem_req;
    nexora_x3_pkg::mem_resp_t [7:0] l2_to_mem_resp;

    cache_subsystem u_cache_subsystem (
        .clk(clk),
        .rst_n(rst_n),
        .sys_req(noc_to_mem_req),
        .sys_resp(noc_to_mem_resp),
        .l2_req(l2_to_mem_req),
        .l2_resp(l2_to_mem_resp)
    );

    memory_fabric u_memory_fabric (
        .clk(clk),
        .rst_n(rst_n),
        .noc_req(l2_to_mem_req),
        .noc_resp(l2_to_mem_resp),
        .phy_req(phy_mem_req),
        .phy_resp(phy_mem_resp)
    );

    power_controller u_power_controller (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_domain_en(cpu_domain_en),
        .gpu_domain_en(gpu_domain_en),
        .tensor_domain_en(tensor_domain_en),
        .dsp_domain_en(dsp_domain_en)
    );

    debug_subsystem u_debug_subsystem (
        .clk(clk),
        .rst_n(rst_n),
        .tck(tck),
        .tms(tms),
        .tdi(tdi),
        .tdo(tdo)
    );

    logic [20:0] heartbeat_cnt;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            heartbeat_cnt <= 21'd0;
        else
            heartbeat_cnt <= heartbeat_cnt + 1;
    end
    assign status_alive = heartbeat_cnt[20];

    assign status_cpu_halt = cpu_system_halt[0];

    assign status_gpu_active = gpu_rst_n; 

    assign status_tensor_busy = tensor_rst_n; 

    assign uart_tx = 1'b1; 

endmodule
