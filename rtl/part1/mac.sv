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

    logic signed [ACCW-1:0] acc;

    always_ff @(posedge clk) begin : acc_reg
        if (reset)
            acc <= 0;
        else if (init_acc)
            acc <= init_value;
        else if (input_valid)
            acc <= acc + (input0 * input1);
    end 

    always_comb begin : com_output
        if (reset) begin
            out = 0;
        end
        else if (input_valid == 1) begin
            if (acc >>> Q > MAXOUT)
                out = signed'(MAXOUT[WIDTH-1:0]);
            else if (acc >>> Q < MINOUT) 
                out = signed'(MINOUT[WIDTH-1:0]);
            else
                out = acc >>> Q;
        end
    end

endmodule


/*
rst,    int_a,  inp_v,  accum,  output
0       0       0       mac     out
0       0       1       mac     mac + Q + sat
0       1       0       val     val + Q + sat
0       1       1       val     val + Q + sat
1       0       0       0       0




*/


