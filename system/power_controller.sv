// power_controller
`timescale 1ns / 1ps
module power_controller (
    input  logic clk,
    input  logic rst_n,

    output logic cpu_domain_en,
    output logic gpu_domain_en,
    output logic tensor_domain_en,
    output logic dsp_domain_en
);

    always_comb begin
        cpu_domain_en = 1'b1;
        gpu_domain_en = 1'b1;
        tensor_domain_en = 1'b1;
        dsp_domain_en = 1'b1;
    end

endmodule
