import com_pkg::*;

module mac #(
    parameter WIDTH = WIDTH,
    parameter ACCW = ACCW
)(
    input logic signed [WIDTH-1:0] input0, input1, init_value,
    input [6:0] Q,
    output logic signed [WIDTH-1:0] out,
    input clk, reset, init_acc, input_valid
);
    reg signed [ACCW-1:0] acc = 0;

    always_comb begin
        logic signed [ACCW-1:0] quant; 
        if (reset)
            acc = 0;
        else if (init_acc)
            acc = init_value;
        else if (input_valid)
            acc = acc + (input0 * input1);
        else 
            acc = acc;

        //perform quantization
        if (!reset && (Q > 0 && Q < ACCW))
                quant = acc >>> Q;

        //perform saturation
        if (quant > MAXOUT)
            out = MAXOUT[WIDTH-1:0];
        else if (quant < MINOUT)
            out = MINOUT[WIDTH-1:0];
        else 
            out = quant[WIDTH-1:0];
    end 

endmodule