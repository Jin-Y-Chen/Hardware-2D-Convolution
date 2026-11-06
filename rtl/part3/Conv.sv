import param::*;

module Conv #(
    parameter WIDTH = param::WIDTH,
    parameter R = param::R,
    parameter C = param::C,
    parameter K = param::K,
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
    logic input_loaded, compute_finished, stall_bar, valid_read;
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
        .valid_read(valid_read),
        .compute_finished(compute_finished)
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

    mac_pipe #(
        .WIDTH(WIDTH), .ACCW(ACCW)
    ) mac_unit (
        //shared control
        .clk(clk), .reset(reset),
        //intermediate input
        .init_acc(init_acc), .input_valid(valid_read), .Q(Q),
        .input0(X_data), .input1(W_data), .init_value(B),
        //intermediate ouput
        .out(out)
    );
    
    logic valid_read1, valid_read2;

    always_ff @(posedge clk) begin
        valid_read1 <= valid_read;

        valid_read2 <= valid_read1;
    end

    fifo_out #(
        .WIDTH(WIDTH), .DEPTH(DEPTH)
    ) axis_out (
        .clk(clk), .reset(reset),
        .IN_AXIS_TDATA(out),
        .IN_AXIS_TVALID(valid_read2),          //input pipelined valid signal
        .IN_AXIS_TREADY(stall_bar),             //stall is asserted low or IN_AXIS_TREADY = stall_bar
        //
        .OUT_AXIS_TDATA(OUTPUT_TDATA),
        .OUT_AXIS_TVALID(OUTPUT_TVALID),
        .OUT_AXIS_TREADY(OUTPUT_TREADY)
    );

endmodule

   // always_ff @(posedge clk) begin
    //     if (reset || reset_X_addr) begin
    //         next_window <= S;
    //         based_row <= '0;
    //     end else if ((state == inc_row) && reset_W_addr) begin // ff -> comb -> ff
    //         if (next_window + S > based_row + (C - K)) begin    //C is adjust per row, base_row is the refered mulitpal of Row
    //             // next row, stride to the apporiate row, hummm
    //             // based_row + C << (S >> 1) + C (S mod 2);
    //             next_window <= based_row + C*S;
    //             based_row <= next_window;
    //         end else
    //             next_window <= next_window + S;
    //     end
    // end


    // always_comb begin
    //     reset_W_addr = 0;
    //     reset_X_addr = 0;
    //     compute_finished = 0;
    //     init_acc = 1;
    //     valid = 0;
    //     next_state = state;
    //     X_next_addr = X_read_addr;
    //     case (state)
    //         idle : begin
    //             reset_W_addr = 1;
    //             reset_X_addr = 1;
    //             base_column = 0;
    //             if (input_loaded)
    //                 next_state <= inc_col;
    //         end
    //         inc_col : begin
    //             valid = 1;
    //             init_acc = 0;
    //             if (ready) begin
    //                 if (X_read_addr == R*C-1) begin      //complete the last window's last row, complete
    //                     reset_W_addr = 1;
    //                     reset_X_addr = 1;
    //                     compute_finished = 1;
    //                 end else if (W_read_addr == K*K-1) begin //complete the last row in the window, move to next window
    //                     reset_W_addr = 1;
    //                     X_next_addr = next_window;
    //                 end else if (W_read_addr == base_column + K) begin
    //                     X_next_addr = X_read_addr + (C - K) + 1; //complete the last column in a row, move to next row
    //                 end
    //             end 
    //         end
    //         default : begin
    //             valid = 0;
    //             next_state = idle;
    //         end
    //     endcase
    // end