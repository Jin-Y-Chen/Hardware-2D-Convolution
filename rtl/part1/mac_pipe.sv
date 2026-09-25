import comm_pkg::*;

module mac_pipe #(
    parameter WIDTH = 16,
    parameter ACCW = 48
)(
    input signed [WIDTH-1:0] input0, input1, init_value,
    input [6:0] Q,
    output logic signed [WIDTH-1:0] out,
    input clk, reset, init_acc, input_valid
);
    signed [2*WIDTH-1:0] mult_add;
    signed [ACCW-1:0] next_value = 0;

    assign mult_add = input0 * input1 + next_value;

    always_ff @(posedge clk) begin
        if (rest)
            next_value = 0;
        else if (init_acc)
            next_value = init_value;
        else if (input_valid) 
            next_value = mult_add;
        else 
            next_value = next_value;
    end 

    always_comb begin
        signed [ACCW-1:0] quant,
        //perform quantization
        if (!rest && (Q > 0 && Q < ACCW))
            quant = (next_value >>> Q); 
        
        //perform saturation
        if quant > MAXOUT
            out = MAXOUT[WIDTH-1:0];
        else if quant < MINOUT
            out = MINOUT[WIDTH-1:0];
        else 
            out = quant[WDITH-1:0];
    end 

endmodule


