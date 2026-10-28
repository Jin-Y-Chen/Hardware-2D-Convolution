import param::*;
import mac_pipe::*;
import input_mems::*;
import fifo_out::*;

module Conv #(
    parameter WIDTH = param::WIDTH,
    parameter R = param::R,
    parameter C = param::C,
    parameter K = param::K,
    localparam X_ADDR_BITS = $clog2(R*C),
    localparam W_ADDR_BITS = $clog2(K*K),
    localparam MAXS = ((R > C) ? R : C) - K + 1,
    localparam S_BITS = $clog2(MAXS+1),
    localparam ACCW = $clog2(K*K*(128'd1 << (2*WIDTH-2)) + (1<<(WIDTH-1)))+1;
    localparam DEPTH = C - K + 1;
) (
    input clk, reset,
    //AXI-stream input
    input [WIDTH-1:0] AXIS_TDATA,
    input AXIS_TVALID,
    input [S_BITS+7:0] AXIS_TUSER,
    input OUTPUT_TREADY,

    //FIFO-queue output
    output INPUT_TREADY,
    output [WIDTH-1:0] OUTPUT_TDATA,
    output OUTPUT_TVALID
);
    //interconnects (input_mems -> mac_pipe)
    logic inputs_loaded, compute_finished, 
    logic [W_ADDR_BITS-1:0] W_read_addr,
    logic [X_ADDR_BITS-1:0] X_read_addr,
    logic [S_BITS-1:0] S,
    logic signed [WIDTH-1:0] B, X_data, W_data,
    logic [6:0] Q,

    //interconnects (mac_pipe -> FIFO_out)
    logic signed [WIDTH-1:0] out

    input_mems #(
        .WIDTH(WIDTH), .R(R), .C(C), .K(K)
    ) axis_in (
        .clk(clk), .reset(reset),
        .AXIS_TDATA(AXIS_TDATA),
        .AXIS_TVALID(AXIS_TVALID),
        .AXIS_TUSER(AXIS_TUSER),
        .compute_finished(compute_finished),

        .AXIS_TREADY(AXIS_TREADY),
        .input_loaded(input_loaded),
        .S(S), .B(B), .Q(Q),
        .X_read_addr(X_read_addr), .X_data(X_data),
        .W_read_addr(W_read_addr), .W_data(W_data)
    );

    mac_pipe #(

    ) mac_unit (
        .clk(clk), .reset(reset),
        .init_acc(), .input_vaild(), .Q(Q),
        .input0(), input1(), init_value(),
        .out(out)
    );

    fifo_out #(
        .WIDTH(WIDTH), .DEPTH(DEPTH)
    ) axis_out(
        .clk(clk), .reset(reset),
        .IN_AXIS_TDATA(out),
        .IN_AXIS_TVALID(),
        .IN_AXIS_TREADY(),
        .OUT_AXIS_TDATA(),

        .IN_AXIS_TREADY(INPUT_TREADY),
        .OUT_AXIS_TDATA(OUTPUT_TDATA), 
        .OUT_AXIS_TVALID(OUTPUT_TVALID)
    );


endmodule