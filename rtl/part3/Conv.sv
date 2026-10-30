import param::*;
import mac_pipe::*;
import input_mems::*;
import fifo_out::*;

module counter #(
    parameter SIZE = 32
) (
    input clk, reset, inc_en,
    input [SIZE-1 : 0] prev_count,
    output logic [SIZE-1:0] new_count
);
    always_ff @(posedge clk) begin //same rising edge as the memory write
        if (reset)
        if (reset)
            new_count <= 0;
        else
            new_count <= prev_count + inc_en;
        else
            new_count <= prev_count + inc_en;
    end 

endmodule

module Conv #(
    parameter WIDTH = param::WIDTH,
    parameter R = param::R,
    parameter C = param::C,
    parameter K = param::K,
    localparam X_ADDR_BITS = $clog2(R*C),
    localparam X_COLUMN_BITS = $clog2(C),
    localparam X_ROW_BITS = $clog2(R),
    localparam X_COLUMN_BITS = $clog2(C),
    localparam X_ROW_BITS = $clog2(R),
    localparam W_ADDR_BITS = $clog2(K*K),
    localparam W_COLUMN_BITS = $clog2(K),
    localparam W_COLUMN_BITS = $clog2(K),
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
    output INPUT_TREADY,
    output INPUT_TREADY,

    //FIFO-queue output
    input OUTPUT_TREADY,
    input OUTPUT_TREADY,
    output [WIDTH-1:0] OUTPUT_TDATA,
    output OUTPUT_TVALID
);
    //interconnects (input_mems -> mac_pipe)
    logic input_loaded, compute_finished, valid_1, valid_2
    logic [W_ADDR_BITS-1:0] W_read_addr
    logic [X_ADDR_BITS-1:0] X_read_addr
    logic [S_BITS-1:0] S
    logic signed [WIDTH-1:0] B, X_data, W_data
    logic [6:0] Q

    //interconnects (mac_pipe -> FIFO_out)
    logic signed [WIDTH-1:0] out

    counter #(
        .SIZE(W_ADDR_BITS)
    ) w_ptr(
        .clk(clk), .reset(reset),
        .inc_en(input_loaded), 
        .prev_count(W_read_addr), 
        .new_count(W_read_addr)
    );

    counter #(
        .SIZE(X_ROW_BITS)
    ) X_row_ptr(
        .SIZE(X_ROW_BITS)
    ) X_row_ptr(
        .clk(clk), .reset(reset),
        .inc_en(input_loaded && en_row), 
        .prev_count(X_read_addr[X_ADDR_BITS-1:X_COLUMN_BITS]), 
        .new_count(X_read_addr[X_ADDR_BITS-1:X_COLUMN_BITS])
        .prev_count(X_read_addr[X_ADDR_BITS-1:X_COLUMN_BITS]), 
        .new_count(X_read_addr[X_ADDR_BITS-1:X_COLUMN_BITS])
    );

    counter #(
        .SIZE(X_COLUMN_BITS)
    ) X_col_ptr(
        .clk(clk), .reset(reset),
        .inc_en(input_loaded && en_col), 
        .prev_count(X_read_addr[X_COLUMN_BITS-1:0]), 
        .new_count(X_read_addr[X_COLUMN_BITS-1:0])
    )

    /* since w-matrix is always a saqure matrix (K by K),
    we need 2log(K) bit to address whole matrix, such that
    more significant bits of log(K) bits address the row, 
    and less significant bits of log(K) bits address the column.

    similar fashsion with X-matrix (R by C), such that
    log(R) + log(C) = log(RC)

    then for the expression
    accumulator_Reg = B
    ...
    accumulator_Reg += X[R*S+j][C*S+i] * W[j][i]


    column_window = X[log(C)-1:0]
    next_column_window = column + S
    column_i = (next_column_window) + K[log(k)-1:1

    *note S is only apply to column or row not both at the same time
    such that if next_column_window > C then S should be apply to 
    rows_Window instead and next_column_window = 0 again. 

    row_window = X[log(RC)-1:log(C)]
    next_row_window = row_window + S
    row_j : (next_row_window) + K[log(KK)-1:log(K)]

    X[r*S+1][c*S+j] = X[row_j concat column_i] (h, s), where h is 
    just (j concat i) of length log(KK), which could just be a 
    simple counter that iterated through the whole window of the 
    K by K of W-matrix. The simple counter is also the logic 
    for address elements by W[j][i].

    S is constant during this phase, but additional logic has to
    direct what S should drived (row or colume). 
    */

    input_mems #(
        .WIDTH(WIDTH), .R(R), .C(C), .K(K)
    ) axis_in (
        .clk(clk), .reset(reset),
        .AXIS_TDATA(AXIS_TDATA),
        .AXIS_TVALID(AXIS_TVALID),
        .AXIS_TUSER(AXIS_TUSER),
        .compute_finished(compute_finished),

        .AXIS_TREADY(INPUT_TREADY),
        .AXIS_TREADY(INPUT_TREADY),
        .input_loaded(input_loaded),
        .S(S), .B(B), .Q(Q),
        .X_read_addr(X_read_addr), .X_data(X_data),
        .W_read_addr(W_read_addr), .W_data(W_data)
    );
    
    W_read_addr[X_ADDR_BITS-1:X_COLUMN_BITS] += 1 
    
    W_read_addr[X_ADDR_BITS-1:X_COLUMN_BITS] += 1 

    alwasy_ff @(posedge clk) begin //extend the pre/acc mac_pipe
        if (reset)
            
        else 
            

    end 
    
    mac_pipe #(

    ) mac_unit (
        .clk(clk), .reset(reset),
        .init_acc(), .input_vaild(input_loaded), .Q(Q),
        .input0(X_data), .input1(W_data), .init_value(B),

        .out(out)
    );

    fifo_out #(
        .WIDTH(WIDTH), .DEPTH(DEPTH)
    ) axis_out(
        .clk(clk), .reset(reset),
        .IN_AXIS_TDATA(out),
        .IN_AXIS_TVALID(),  //input pipelined valid signal
        .IN_AXIS_TREADY(),  //out check last valid for complete 

        .IN_AXIS_TREADY(INPUT_TREADY),
        .OUT_AXIS_TDATA(OUTPUT_TDATA), 
        .OUT_AXIS_TVALID(OUTPUT_TVALID)
    );

    enum logic [1:0] {
        load_B, 
        inc_X_col,
        inc_X_row,
        inc_stride } state, next_state;

    always_ff @(posedge clk) begin
        if (reset)
            state <= load_B;
        else 
            state <= next_state;
    end

    always_comb begin
        case (state)

        load_B : begin
        end
        inc_X_col : begin
        end
        inc_x_row : begin
        end
        inc_stride : begin
        end 
        default :
            next_state <= load_B;
    end 

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

endmodule