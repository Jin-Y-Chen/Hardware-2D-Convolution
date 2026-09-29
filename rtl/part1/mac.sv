import param_pkg::*;

/*
 the accumulator register ACCW bits wide and let it wrap around naturally.

the accumulator is the only register on the datapath, so everything from the input ports
through the multiplier and adder is combinational. This gives the design a latency of one clock cycle: a
set of inputs presented before a positive clock edge affects out immediately after that edge.

the register’s init_acc signal can be connected directly to the module’s init_acc input, and the register’s
en signal can be connected directly to the module’s input_valid input: the product of a valid input pair
reaches the accumulator’s D input on the very same cycle that input_valid is asserted

Q arrives alongside the input values it applies to, but the actual shifting by Q happens on the other side of the
accumulator register. This means that Q cannot be wired directly to the shifter’s input without a delay

We interpret this as saying
“multiply 1 times 2, add the product to whatever is stored in the accumulator, and then shift that value
by Q=0 places.”

The init_acc signal does not affect Q. Your Q register(s) should be enabled by input_valid (and its
delayed copies) alone. If init_acc and input_valid are both asserted on the same clock edge, the
accumulator is initialized, and the Q from that cycle is still captured and applied to the newly initialized
value.
*/

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
    logic [6:0] Q_reg;

    always_ff @(posedge clk) begin : acc_reg
        if (reset)
            acc <= '0;
        else if (init_acc)
            acc <= init_value;
        else if (input_valid)
            acc <= acc + (input0 * input1); //D
    end

    // Q is enabled by input_valid only; init_acc does not affect it
    always_ff @(posedge clk) begin : q_reg
        if (reset)
            Q_reg <= '0;
        else if (input_valid)
            Q_reg <= Q;
    end 

    always_comb begin : com_output
        if (acc >>> Q_reg > MAXOUT)
            out = signed'(MAXOUT[WIDTH-1:0]);
        else if (acc >>> Q_reg < MINOUT) 
            out = signed'(MINOUT[WIDTH-1:0]);
        else
            out = acc >>> Q_reg;
    end

endmodule

/*
 synthesize your unpipelined design with WIDTH=16 and ACCW=48 and
determine the fastest clock frequency your design can reach. 

 synthesis output file with a name (synth_mac.txt)
that includes the parameters you set and the clock period you are targeting.

*/
