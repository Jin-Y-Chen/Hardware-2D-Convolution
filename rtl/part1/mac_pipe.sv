import param::*;

module pre_accum_ff #(
    parameter WIDTH = param::WIDTH,
    parameter ACCW  = param::ACCW
)(
    input clk, reset, 

    input in_valid,
    input signed [2*WIDTH-1:0] in_product,
    input [6:0] in_Q,

    output logic out_valid,
    output logic signed [2*WIDTH-1:0] out_product,
    output logic [6:0] out_Q
);
    
    always_ff @(posedge clk) begin
        if (reset) begin
            out_product <= '0;
            out_valid <= 1'b0;
            out_Q <= '0;
        end else begin
            // valid must update every cycle so an idle cycle clears en
            out_valid <= in_valid;
            if (in_valid) begin
                out_product <= in_product;
                out_Q <= in_Q;
            end
        end
    end 

endmodule 

module accum_post_ff #(
    parameter WIDTH = param::WIDTH,
    parameter ACCW  = param::ACCW
) (
    input clk, reset, en, load_init,
    input [6:0] in_Q,
    input logic signed [WIDTH-1:0] init_value,
    input logic signed [ACCW-1:0] in_accum,

    output logic [6:0] out_Q,
    output logic signed [ACCW-1:0] out_accum
);

    always_ff @(posedge clk) begin
        if (reset)
            out_accum <= '0;
        else if (load_init)
            out_accum <= init_value;
        else if (en)
            out_accum <= in_accum;
    end 

    // Q is loaded aslong as input_vaild is asserted
    always_ff @(posedge clk) begin
        if (reset)
            out_Q <= '0;
        else if (en)
            out_Q <= in_Q;
    end


endmodule

/*
 When both init_acc and input_valid is asser, the product is discarded, though: the Q presented on that
cycle is still captured, since input_valid was 1, and it scales the newly initialized accumulator value.)
This is one rule (init_acc takes effect in one cycle and has priority over accumulation) producing two
different behaviors at two different latencies.

*/
module mac_pipe #(
    parameter WIDTH = param::WIDTH,
    parameter ACCW  = param::ACCW
)(
    input logic signed [WIDTH-1:0] input0, input1, init_value,
    input [6:0] Q,
    output logic signed [WIDTH-1:0] out,
    input clk, reset, init_acc, input_valid
);

    logic signed [2*WIDTH-1:0] product, out_product;
    logic out_valid;
    logic [6:0] out1_Q, out2_Q;

    logic signed [ACCW-1:0] post_accum, accum;

    //pre_accum stage
    assign product = input0 * input1;

    //intermediate register from pre -> accum
    pre_accum_ff #(.WIDTH(WIDTH), .ACCW(ACCW)) reg1 (
        .clk(clk),
        .reset(reset),
        .in_valid(input_valid),
        .in_product(product),
        .in_Q(Q),

        .out_valid(out_valid),
        .out_product(out_product),
        .out_Q(out1_Q)
    );
    //accum stage
    assign accum = out_product + post_accum;

    //intermediate register from accum -> post
    accum_post_ff #(.WIDTH(WIDTH), .ACCW(ACCW)) reg2 (
        .clk(clk),
        .reset(reset),
        .en(out_valid),
        .in_Q(out1_Q),
        .load_init(init_acc),
        .init_value(init_value),
        .in_accum(accum),

        .out_Q(out2_Q),
        .out_accum(post_accum)
    );

    //post_accum stage
    always_comb begin : com_output
        if (post_accum >>> out2_Q > MAXOUT)
            out = signed'(MAXOUT[WIDTH-1:0]);
        else if (post_accum >>> out2_Q < MINOUT)
            out = signed'(MINOUT[WIDTH-1:0]);
        else
            out = post_accum >>> out2_Q;
    end

endmodule
