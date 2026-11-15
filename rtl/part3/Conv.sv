module Conv #(
    parameter WIDTH = 16,
    parameter R = 16,
    parameter C = 16,
    parameter K = 3,
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

    control #(
        .WIDTH(WIDTH),
        .R(R),
        .C(C),
        .K(K)
    ) FSM_ctrl(
        .clk(clk), .reset(reset), 
        .en(input_loaded), .stall_bar(stall_bar),
        .S(S),
        .init_acc(init_acc),    //state flag 
        .X_read_addr(X_read_addr),
        .W_read_addr(W_read_addr),
        .input_valid(input_valid),
        .memory_fetched(memory_fetched),
        .y_valid(y_valid)
    );

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

    // input_valid1 waits for registered X_data/W_data. The two MAC stages
    // then put the finished sum on y_valid3, and B loads on that same cycle.
    logic input_valid1, init_acc1, init_acc2;
    logic y_valid1, y_valid2, y_valid3;

    always_ff @(posedge clk) begin
        if (reset) begin
            input_valid1 <= 0;
            init_acc1 <= 0;
            init_acc2 <= 0;
            y_valid1 <= 0;
            y_valid2 <= 0;
            y_valid3 <= 0;
            compute_finished <= 0;
        end else begin
            compute_finished <= memory_fetched; //last entries from memory is fetch, next cycle new entry are read
            input_valid1 <= input_valid;        //move with data read from memory to pre_accum register
            init_acc1 <= init_acc;             
            init_acc2 <= init_acc1;             //move with product-sum from pre_accum to accum_post register
            y_valid1 <= y_valid;
            y_valid2 <= y_valid1;
            y_valid3 <= y_valid2;               //move with output from accum-post to fifo-out
        end
    end

    mac_pipe #(
        .WIDTH(WIDTH), .ACCW(ACCW)
    ) mac_unit (
        //shared control
        .clk(clk), .reset(reset),
        //intermediate input
        .init_acc(init_acc2), .input_valid(input_valid1), .Q(Q),
        .input0(X_data), .input1(W_data), .init_value(B),
        //intermediate ouput
        .out(out)
    );
    
   

    fifo_out #(
        .WIDTH(WIDTH), .DEPTH(DEPTH)
    ) axis_out (
        //shared control
        .clk(clk), .reset(reset),
        //intermediate input
        .IN_AXIS_TDATA(out),
        .IN_AXIS_TVALID(y_valid3),          // finished sum, aligned with out

        //intermediate output
        .IN_AXIS_TREADY(stall_bar),         // stall is asserted low or IN_AXIS_TREADY = stall_bar

        //external output
        .OUT_AXIS_TDATA(OUTPUT_TDATA),
        .OUT_AXIS_TVALID(OUTPUT_TVALID),
        //external input
        .OUT_AXIS_TREADY(OUTPUT_TREADY)
    );

endmodule