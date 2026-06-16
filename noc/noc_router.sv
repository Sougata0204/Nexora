// noc_router
`timescale 1ns / 1ps
module noc_router #(
    parameter int ROUTER_X = 0,
    parameter int ROUTER_Y = 0
)(
    input  logic clk,
    input  logic rst_n,

    input  nexora_x3_pkg::noc_flit_t local_flit_in,
    input  logic      local_flit_in_valid,
    output logic      local_flit_in_ready,
    output nexora_x3_pkg::noc_flit_t local_flit_out,
    output logic      local_flit_out_valid,
    input  logic      local_flit_out_ready,

    input  nexora_x3_pkg::noc_flit_t north_flit_in,
    input  logic      north_flit_in_valid,
    output logic      north_flit_in_ready,
    output nexora_x3_pkg::noc_flit_t north_flit_out,
    output logic      north_flit_out_valid,
    input  logic      north_flit_out_ready,

    input  nexora_x3_pkg::noc_flit_t east_flit_in,
    input  logic      east_flit_in_valid,
    output logic      east_flit_in_ready,
    output nexora_x3_pkg::noc_flit_t east_flit_out,
    output logic      east_flit_out_valid,
    input  logic      east_flit_out_ready,

    input  nexora_x3_pkg::noc_flit_t south_flit_in,
    input  logic      south_flit_in_valid,
    output logic      south_flit_in_ready,
    output nexora_x3_pkg::noc_flit_t south_flit_out,
    output logic      south_flit_out_valid,
    input  logic      south_flit_out_ready,

    input  nexora_x3_pkg::noc_flit_t west_flit_in,
    input  logic      west_flit_in_valid,
    output logic      west_flit_in_ready,
    output nexora_x3_pkg::noc_flit_t west_flit_out,
    output logic      west_flit_out_valid,
    input  logic      west_flit_out_ready
);

    localparam int NUM_PORTS  = 5;
    localparam int FIFO_DEPTH = nexora_x3_pkg::NOC_BUFFER_DEPTH;

    localparam int PORT_LOCAL = 0;
    localparam int PORT_NORTH = 1;
    localparam int PORT_EAST  = 2;
    localparam int PORT_SOUTH = 3;
    localparam int PORT_WEST  = 4;

    nexora_x3_pkg::noc_flit_t [NUM_PORTS-1:0][FIFO_DEPTH-1:0] fifo_buf;
    logic [2:0] fifo_head [NUM_PORTS-1:0];
    logic [2:0] fifo_tail [NUM_PORTS-1:0];
    logic [2:0] fifo_count [NUM_PORTS-1:0];

    nexora_x3_pkg::noc_flit_t port_flit_in [NUM_PORTS-1:0];
    logic [NUM_PORTS-1:0] port_valid_in;
    logic [NUM_PORTS-1:0] port_ready_in;

    assign port_flit_in[PORT_LOCAL] = local_flit_in;
    assign port_flit_in[PORT_NORTH] = north_flit_in;
    assign port_flit_in[PORT_EAST]  = east_flit_in;
    assign port_flit_in[PORT_SOUTH] = south_flit_in;
    assign port_flit_in[PORT_WEST]  = west_flit_in;

    assign port_valid_in[PORT_LOCAL] = local_flit_in_valid;
    assign port_valid_in[PORT_NORTH] = north_flit_in_valid;
    assign port_valid_in[PORT_EAST]  = east_flit_in_valid;
    assign port_valid_in[PORT_SOUTH] = south_flit_in_valid;
    assign port_valid_in[PORT_WEST]  = west_flit_in_valid;

    assign local_flit_in_ready = port_ready_in[PORT_LOCAL];
    assign north_flit_in_ready = port_ready_in[PORT_NORTH];
    assign east_flit_in_ready  = port_ready_in[PORT_EAST];
    assign south_flit_in_ready = port_ready_in[PORT_SOUTH];
    assign west_flit_in_ready  = port_ready_in[PORT_WEST];

    genvar p;
    generate
        for (p = 0; p < NUM_PORTS; p++) begin : gen_fifo_ready
            assign port_ready_in[p] = (fifo_count[p] < FIFO_DEPTH);
        end
    endgenerate

    function logic [2:0] xy_route(
        input nexora_x3_pkg::noc_flit_t flit
    );
        if (flit.dst_x > ROUTER_X[nexora_x3_pkg::NOC_ADDR_X_BITS-1:0])
            xy_route = PORT_EAST;
        else if (flit.dst_x < ROUTER_X[nexora_x3_pkg::NOC_ADDR_X_BITS-1:0])
            xy_route = PORT_WEST;
        else if (flit.dst_y > ROUTER_Y[nexora_x3_pkg::NOC_ADDR_Y_BITS-1:0])
            xy_route = PORT_SOUTH;
        else if (flit.dst_y < ROUTER_Y[nexora_x3_pkg::NOC_ADDR_Y_BITS-1:0])
            xy_route = PORT_NORTH;
        else
            xy_route = PORT_LOCAL;
    endfunction

    logic [NUM_PORTS-1:0] [2:0] rr_ptr;

    nexora_x3_pkg::noc_flit_t out_flit [NUM_PORTS-1:0];
    logic [NUM_PORTS-1:0] out_valid;
    logic [NUM_PORTS-1:0] out_ready;

    assign out_ready[PORT_LOCAL] = local_flit_out_ready;
    assign out_ready[PORT_NORTH] = north_flit_out_ready;
    assign out_ready[PORT_EAST]  = east_flit_out_ready;
    assign out_ready[PORT_SOUTH] = south_flit_out_ready;
    assign out_ready[PORT_WEST]  = west_flit_out_ready;

    assign local_flit_out       = out_flit[PORT_LOCAL];
    assign local_flit_out_valid = out_valid[PORT_LOCAL];
    assign north_flit_out       = out_flit[PORT_NORTH];
    assign north_flit_out_valid = out_valid[PORT_NORTH];
    assign east_flit_out        = out_flit[PORT_EAST];
    assign east_flit_out_valid  = out_valid[PORT_EAST];
    assign south_flit_out       = out_flit[PORT_SOUTH];
    assign south_flit_out_valid = out_valid[PORT_SOUTH];
    assign west_flit_out        = out_flit[PORT_WEST];
    assign west_flit_out_valid  = out_valid[PORT_WEST];

    always_comb begin : arb_per_out
        int candidate;
        nexora_x3_pkg::noc_flit_t head_flit;
        logic [2:0] dest_port;

        candidate = 0;
        head_flit = '0;
        dest_port = '0;

        for (int op = 0; op < NUM_PORTS; op++) begin
            out_flit[op] = '0;
            out_valid[op] = 1'b0;
            for (int ip = 0; ip < NUM_PORTS; ip++) begin

                candidate = (rr_ptr[op] + ip) % NUM_PORTS;
                if (fifo_count[candidate] > 0) begin
                    head_flit = fifo_buf[candidate][fifo_head[candidate][1:0]];
                    dest_port = xy_route(head_flit);
                    if (dest_port == op[2:0] && !out_valid[op]) begin
                        out_flit[op]  = head_flit;
                        out_valid[op] = 1'b1;
                    end
                end
            end
        end
    end

    logic [NUM_PORTS-1:0] read_ack;
    logic [2:0] next_fifo_head [NUM_PORTS-1:0];
    logic [2:0] next_fifo_tail [NUM_PORTS-1:0];
    logic [2:0] next_fifo_count [NUM_PORTS-1:0];
    logic [2:0] next_rr_ptr [NUM_PORTS-1:0];

    always_comb begin : noc_router_comb
        int candidate;
        nexora_x3_pkg::noc_flit_t hf;
        logic write_en;
        logic read_en;

        candidate = 0;
        hf = '0;
        write_en = 1'b0;
        read_en = 1'b0;

        if (!rst_n) begin
            read_ack = '0;
            for (int i = 0; i < NUM_PORTS; i++) begin
                next_fifo_head[i]  = '0;
                next_fifo_tail[i]  = '0;
                next_fifo_count[i] = '0;
                next_rr_ptr[i]     = '0;
            end
        end else begin

            for (int i = 0; i < NUM_PORTS; i++) begin
                next_rr_ptr[i]     = rr_ptr[i];
                next_fifo_head[i]  = fifo_head[i];
                next_fifo_tail[i]  = fifo_tail[i];
                next_fifo_count[i] = fifo_count[i];
            end

            read_ack = '0;
            for (int op = 0; op < NUM_PORTS; op++) begin
                if (out_valid[op] && out_ready[op]) begin
                    for (int ip = 0; ip < NUM_PORTS; ip++) begin
                        candidate = (rr_ptr[op] + ip) % NUM_PORTS;
                        if (fifo_count[candidate] > 0) begin
                            hf = fifo_buf[candidate][fifo_head[candidate][1:0]];
                            if (xy_route(hf) == op[2:0]) begin
                                read_ack[candidate] = 1'b1;
                                next_rr_ptr[op] = (candidate + 1'b1) % NUM_PORTS;

                            end
                        end
                    end
                end
            end

            for (int i = 0; i < NUM_PORTS; i++) begin
                write_en = port_valid_in[i] && port_ready_in[i];
                read_en  = read_ack[i];

                next_fifo_tail[i]  = fifo_tail[i] + {2'b00, write_en};
                next_fifo_head[i]  = fifo_head[i] + {2'b00, read_en};
                next_fifo_count[i] = fifo_count[i] + {2'b00, (write_en && !read_en)} - {2'b00, (!write_en && read_en)};
            end
        end
    end

    always_ff @(posedge clk) begin : noc_router_fsm
        for (int i = 0; i < NUM_PORTS; i++) begin
            fifo_head[i]  <= next_fifo_head[i];
            fifo_tail[i]  <= next_fifo_tail[i];
            fifo_count[i] <= next_fifo_count[i];
            rr_ptr[i]     <= next_rr_ptr[i];

            if (port_valid_in[i] && port_ready_in[i]) begin
                fifo_buf[i][fifo_tail[i][1:0]] <= port_flit_in[i];
            end
        end
    end

endmodule : noc_router
