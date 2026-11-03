

module control #(
    parameter WIDTH = 16,
    parameter R = 16,
    parameter C = 16,
    parameter K = 3,
    localparam X_ADDR_BITS = $clog2(R*C),
    localparam W_ADDR_BITS = $clog2(K*K),
    localparam MAXS = ((R > C) ? R : C) - K + 1,
    localparam S_BITS = $clog2(MAXS+1),
) (
    input clk, reset, en;
    input [S_BITS-1:0] S,
    output logic init_acc;
    output logic [X_ADDR_BITS-1:0] X_read_addr;
    output logic [W_ADDR_BITS-1:0] W_read_addr;
    output logic valid_read, compute_finished;
);

    counter #(
        .SIZE(W_ADDR_BITS)
    ) w_ptr (
        .clk(clk), .reset(reset), //reset assert before the next clk when W_read_addr is the last address in the K by K window
        .inc_en((state == iterate) && stall_bar),
        .prev_count(W_next_addr),
        .new_count(W_read_addr)
    );

    counter #(
        .SIZE(X_ADDR_BITS)
    ) x_ptr (
        .clk(clk), .reset(reset), //reset assert before the next clk when X_read_addr is the last address in the R by C matrix
        .inc_en((state == iterate) && stall_bar),
        .prev_count(X_next_addr),
        .new_count(X_read_addr) // register only; always_comb is what X_read_addr shows
    );

    enum logic [0:0] {
        inital,
        iterate
    } state, next_state;
    
    always_ff @(posedge clk) begin
        if (reset)
            state <= inital;
        else 
            state <= next_state;
    end 

    logic [S_BITS+C-1 : 0] delta_R_reg, delta_R
    
    always_ff @(posedge clk) begin
        delta_R_reg <= delta_R
    end 

    always_comb begin
        init_acc = 0;
        valid_read = 0;
        case(state)
            inital : begin
                if (en) begin
                    init_acc = 1;
                    delta_R = R * C; 
                    next_state = iterate;
                end 
            end

            iterate : begin

                valid_read = 1; 

                if ( ) begin                                    //complete the last window's last row, complete
                        reset_W_addr = 1;
                        reset_X_addr = 1;
                        compute_finished = 1;
                        next_state <= inital;
                    end else if () begin                        //complete the last element in the window, move to next window
                        reset_W_addr = 1;
                        X_next_addr = next_window;              //next_Window along the same row ot the next row
                    end else if (W_read_addr == base_column + K) begin
                        X_next_addr = X_read_addr + (C - K) + 1; //complete the last element in the slice, move to next row
                    end

            end

        endcase

    end 

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