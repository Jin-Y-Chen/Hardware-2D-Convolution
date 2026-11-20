//R = 9, C = 8, K = 5: 10000 Convs in     2641020 cycles = 264.102 Conv per second
// vsyn writes these defines into sim/part3/params.sv from constraint/all_config.json.
`include "../../sim/part3/params.sv"
module Conv #(
    parameter WIDTH = `WIDTHVAL,
    parameter R = `RVAL,
    parameter C = `CVAL,
    parameter K = `KVAL,
    localparam X_ADDR_BITS = $clog2(R*C),
    localparam W_ADDR_BITS = $clog2(K*K),
    localparam MAXS = ((R > C) ? R : C) - K + 1,
    localparam S_BITS = $clog2(MAXS+1),
    localparam ACCW = $clog2(K*K*(128'd1 << (2*WIDTH-2)) + (1<<(WIDTH-1)))+1,
    localparam DEPTH = C - K + 1
) (
    input clk, reset,
    // AXI-stream input. Order matches Conv_tb's positional port list.
    input [WIDTH-1:0] INPUT_TDATA,
    input INPUT_TVALID,
    input [S_BITS+7:0] INPUT_TUSER,
    output logic INPUT_TREADY,

    // FIFO-queue output
    output logic [WIDTH-1:0] OUTPUT_TDATA,
    output logic OUTPUT_TVALID,
    input OUTPUT_TREADY
);
    // interconnects (input_mems -> mac_pipe)
    logic input_loaded, memory_fetched, compute_finished, stall_bar, input_valid, y_valid;
    logic init_acc;
    logic [W_ADDR_BITS-1:0] W_read_addr;
    logic [X_ADDR_BITS-1:0] X_read_addr;
    logic [S_BITS-1:0] S;
    logic signed [WIDTH-1:0] B, X_data, W_data;
    logic [6:0] Q;

    // interconnects (mac_pipe -> FIFO_out)
    logic signed [WIDTH-1:0] out;

    // input_valid1 waits for registered X_data/W_data. The two MAC stages
    // then put the finished sum on y_valid3, and B loads on that same cycle.
    logic input_valid2, input_valid1, init_acc1, init_acc2, init_acc3;
    logic y_valid1, y_valid2, y_valid3, y_valid4;
    logic signed [WIDTH-1:0] X_input0, W_input1, B1; 
    logic [6:0] Q1;

    control #(
        .WIDTH(WIDTH), .R(R), .C(C), .K(K)
    ) FSM_ctrl(
        .clk(clk), .reset(reset), 
        .en(input_loaded), .stall_bar(stall_bar),
        .S(S),
        .init_acc(init_acc),    //initate flag 
        .X_read_addr(X_read_addr),
        .W_read_addr(W_read_addr),
        .input_valid(input_valid),
        .memory_fetched(memory_fetched),
        .y_valid(y_valid)
    );

    always_ff @(posedge clk) begin //
        if (reset) begin
            init_acc1 <= 0;
            input_valid1 <= 0;
            y_valid1 <= 0;
            compute_finished <= 1;
        end 
        else begin
            init_acc1 <= init_acc;
            compute_finished <= memory_fetched; //last entries from memory is fetch, next cycle new entry are read
            input_valid1 <= input_valid;        //move with data read from memory to pre_accum register
            y_valid1 <= y_valid;
        end
    end 

    input_mems #(
        .WIDTH(WIDTH), .R(R), .C(C), .K(K)
    ) axis_in (
        //shared control
        .clk(clk), .reset(reset),
        //external input
        .AXIS_TDATA(INPUT_TDATA),
        .AXIS_TVALID(INPUT_TVALID),
        .AXIS_TUSER(INPUT_TUSER),
        .AXIS_TREADY(INPUT_TREADY),

        //intermediate output 
        .inputs_loaded(input_loaded),
        .S(S), .B(B), .Q(Q),
        .X_data(X_data),
        .W_data(W_data), 

        //intermediate input
        .compute_finished(compute_finished),
        .X_read_addr(X_read_addr), //drive X_data
        .W_read_addr(W_read_addr) //drive W_data
    );

    always_ff @(posedge clk) begin //intermeidate register MEM/MAC
        if (reset) begin
            init_acc2 <= 0;
            init_acc3 <= 0;
            X_input0 <= 0;
            W_input1 <= 0;
            input_valid2 <= 0;
            y_valid2 <= 0;
            B1 <= 0;
            Q1 <= 0;
        end 
        else begin
            init_acc2 <= init_acc1;
            init_acc3 <= init_acc2;
            X_input0 <= X_data;
            W_input1 <= W_data;
            B1 <= B;
            Q1 <= Q;
            input_valid2 <= input_valid1;
            y_valid2 <= y_valid1;
        end 
    end

    mac_pipe #(
        .WIDTH(WIDTH), .ACCW(ACCW)
    ) mac_unit (
        //shared control
        .clk(clk), .reset(reset),
        //intermediate input
        .init_acc(init_acc3), .input_valid(input_valid2), .Q(Q1),
        .input0(X_input0), .input1(W_input1), .init_value(B1),
        //intermediate ouput
        .out(out)
    );
    
    always_ff @(posedge clk) begin
        if (reset) begin
            y_valid3 <= 0;
            y_valid4 <= 0;
        end else begin
            y_valid3 <= y_valid2;
            y_valid4 <= y_valid3;               //move with output from accum-post to fifo-out
        end
    end

    fifo_out #(
        .WIDTH(WIDTH), .DEPTH(DEPTH)
    ) axis_out (
        //shared control
        .clk(clk), .reset(reset),
        //intermediate input
        .IN_AXIS_TDATA(out),
        .IN_AXIS_TVALID(y_valid4),          // finished sum, aligned with out

        //intermediate output
        .IN_AXIS_TREADY(stall_bar),         // stall is asserted low or IN_AXIS_TREADY = stall_bar

        //external output
        .OUT_AXIS_TDATA(OUTPUT_TDATA),
        .OUT_AXIS_TVALID(OUTPUT_TVALID),
        //external input
        .OUT_AXIS_TREADY(OUTPUT_TREADY)
    );

endmodule