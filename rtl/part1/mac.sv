import param_pkg::*;

module mac #(
    parameter WIDTH = 16,
    parameter ACCW = 48
)(
    input logic signed [WIDTH-1:0] input0, input1, init_value,
    input [6:0] Q,
    output logic signed [WIDTH-1:0] out,
    input clk, reset, init_acc, input_valid
);
    reg signed [ACCW-1:0] acc;

    always_comb begin : pre_acc
        if (reset)
            acc = 0;
        else if (init_acc)
            acc = init_value;
        else if (input_valid)
            acc = acc + (input0 * input1);
        else 
            acc = acc;


    end 

    always_ff @(negedge clk) begin
        logic signed [ACCW-WIDTH-1 : 0] sat_window;
        //out is quantized of acc
        if ((init_acc || input_valid)) begin
            sat_window = acc[(ACCW-WIDTH-1) : WIDTH] >>> (Q % ACCW);
        
            ///out is quantized + saturate of acc
            if (sat_window > 0)
                out <= MAXOUT[WIDTH-1:0];
            else if (sat_window < 0)
                out <= MINOUT[WIDTH-1:0];
            else 
                out <= acc >>> (Q % ACCW);
        end else
            out <= acc >>> (Q % ACCW);
    end 

endmodule