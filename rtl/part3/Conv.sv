import param::*;

module Conv #(
    parameter WIDTH = param::WIDTH,
    parameter R = param::R,
    parameter C = param::C,
    parameter K = param::K,
    localparam X_ADDR_BITS = $clog2(R*C),
    localparam W_ADDR_BITS = $clog2(K*K),
    localparam W_COLUMN_BITS = $clog2(K),
    //localparma ROUT = ((R - K)/S) + 1,
    //localparma COUT = ((C - K)/S) + 1,
    //localparma S_NEXT_ROW = C*S - COUT,

    /*rounds down to the next integer.
        Rout = [(R - K)/ S ] + 1
        Cout = [(C - K)/ S] + 1
    computing all of Y requires RoutCoutK2 multiplications
    and additions.

    C - Cout = the addition amount to the next row
    C*S - Cout = the addition amount to the next row by stride amount
    */
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
    logic input_loaded, compute_finished, reset_W_addr, reset_X_addr, init_acc, valid, ready;
    logic valid_pre_acc, valid_acc_pos;
    logic [W_ADDR_BITS-1:0] W_read_addr;
    logic [X_ADDR_BITS-1:0] X_read_addr, next_window, based_row;
    logic [S_BITS-1:0] S;
    logic signed [WIDTH-1:0] B, X_data, W_data;
    logic [6:0] Q;

    // interconnects (mac_pipe -> FIFO_out)
    logic signed [WIDTH-1:0] out;

    // Declared before the procedural blocks that read it.
    enum logic [1:0] {
        load_B,
        inc_col,
        inc_row
    } state, next_state;

    counter #(
        .SIZE(W_ADDR_BITS)
    ) w_ptr (
        .clk(clk), .reset((reset || reset_W_addr) && !input_loaded),
        .inc_en((state == inc_col) || ((state == inc_row) && ready)),
        .prev_count(W_read_addr),
        .new_count(W_read_addr)
    );

    // One register drives X_read_addr. The old x_ptr and the comb assigns were both drivers.
    always_ff @(posedge clk) begin
        if (reset || reset_X_addr)
            X_read_addr <= '0;
        else if (state == inc_col && ready)
            X_read_addr <= X_read_addr + 1'b1;
        else if (state == inc_row && ready) begin
            if (X_read_addr == R*C-1)
                X_read_addr <= '0;
            else if (W_read_addr == K*K-1)
                X_read_addr <= next_window;
            else
                X_read_addr <= X_read_addr + (C - K) + 1;
        end
    end

    input_mems #(
        .WIDTH(WIDTH), .R(R), .C(C), .K(K)
    ) axis_in (
        .clk(clk), .reset(reset),
        .AXIS_TDATA(INPUT_TDATA),
        .AXIS_TVALID(INPUT_TVALID),
        .AXIS_TUSER(INPUT_TUSER),
        .compute_finished(compute_finished),
        .AXIS_TREADY(INPUT_TREADY),
        .inputs_loaded(input_loaded),
        .S(S), .B(B), .Q(Q),
        .X_read_addr(X_read_addr), .X_data(X_data),
        .W_read_addr(W_read_addr), .W_data(W_data)
    );

    always_ff @(posedge clk) begin
        valid_pre_acc <= valid;
    end

    mac_pipe #(
        .WIDTH(WIDTH), .ACCW(ACCW)
    ) mac_unit (
        .clk(clk), .reset(reset),
        .init_acc(init_acc), .input_valid(valid), .Q(Q),
        .input0(X_data), .input1(W_data), .init_value(B),
        .out(out)
    );

    always_ff @(posedge clk) begin
        valid_acc_pos <= valid_pre_acc;
    end

    fifo_out #(
        .WIDTH(WIDTH), .DEPTH(DEPTH)
    ) axis_out (
        .clk(clk), .reset(reset),
        .IN_AXIS_TDATA(out),
        .IN_AXIS_TVALID(valid_acc_pos),
        .IN_AXIS_TREADY(ready),
        .OUT_AXIS_TDATA(OUTPUT_TDATA),
        .OUT_AXIS_TVALID(OUTPUT_TVALID),
        .OUT_AXIS_TREADY(OUTPUT_TREADY)
    );

    always_ff @(posedge clk) begin
        if (reset)
            state <= load_B;
        else
            state <= next_state;
    end

    always_ff @(posedge clk) begin
        if (reset || reset_X_addr) begin
            next_window <= S;
            based_row <= '0;
        end else if ((state == inc_row) && reset_W_addr) begin
            if (next_window + S > based_row + (C - K)) begin
                next_window <= based_row + C*S;
                based_row <= next_window;
            end else
                next_window <= next_window + S;
        end
    end

    always_comb begin
        reset_W_addr = 0;
        reset_X_addr = 0;
        compute_finished = 0;
        init_acc = 1;
        valid = 0;
        next_state = state;
        case (state)
            inc_col : begin
                valid = 1;
                init_acc = 0;
                if (W_read_addr[W_COLUMN_BITS-1:0] == K-1)
                    next_state = inc_row;
            end
            inc_row : begin
                valid = 1;
                next_state = inc_col;
                if (X_read_addr == R*C-1) begin
                    reset_W_addr = 1;
                    reset_X_addr = 1;
                    compute_finished = 1;
                end else if (W_read_addr == K*K-1) begin
                    reset_W_addr = 1;
                end else
                    init_acc = 0;
            end
            default : begin
                valid = 0;
                next_state = inc_col;
            end
        endcase
    end

endmodule

/*Then, your new Part 3 control logic will be responsible for reading the input data from the input
memories using the X_read_addr and W_read_addr signals and feeding the values of 𝑋, 𝑊, and
𝐵 into the MAC module.
*/

//read address counter
//row-major order, so you will need to map accesses like X[r*S+i][c*S+j] and W[i][j] to addresses.


//Your logic will need to control the MAC module’s control inputs (init_acc, init_value, Q, and input_valid).

/*interact with the FIFO’s IN_AXIS_TVALID and IN_AXIS_TREADY signals appropriately. If the FIFO’s
IN_AXIS_TREADY == 0, then the FIFO is full, and you cannot write data to it. In this case, your logic
would need to stall until the recently computed MAC output can be stored in the FIFO

*/

/*After your system is done computing the full convolution, the control logic should set
compute_finished (the input signal to the memory module) to 1 for one clock cycle. This will cause
the input_mems module to start reading in new inputs again, and the whole process can repeat.
*/


    /*

    X[r*S+1][c*S+j] = X[] (h, s), where h is 
    just a simple counter that iterated through the whole window of the 
    K by K of W-matrix. The simple counter is also the logic 
    for address elements by W[j][i].

    S is constant during this phase, but additional logic has to
    direct what S should drived (row or colume). 
    */