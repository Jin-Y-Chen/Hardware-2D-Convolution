
module control #(
    parameter WIDTH = 16,
    parameter R = 16,
    parameter C = 16,
    parameter K = 3,
    localparam X_ADDR_BITS = $clog2(R*C),
    localparam R_BITS = $clog2(R),
    localparam C_BITS = $clog2(C),
    localparam W_ADDR_BITS = $clog2(K*K),
    localparam MAXS = ((R > C) ? R : C) - K + 1,
    localparam S_BITS = $clog2(MAXS+1)
) (
    input clk, reset, en, stall_bar,
    input [S_BITS-1:0] S,
    output logic init_acc,
    output logic [X_ADDR_BITS-1:0] X_read_addr,
    output logic [W_ADDR_BITS-1:0] W_read_addr,
    output logic input_valid, y_valid, memory_fetched
);

    // reload is one idle cycle so the last product is added before the next
    // window loads B. finish is that same idle cycle on the last window.
    enum logic [1:0] {
        initiate,
        iterate,
        reload,
        finish
    } state, next_state;

    enum logic [2:0] {
        by_step,
        hold,
        by_column,
        by_row,
        to_start
    } move_window;

    logic [S_BITS+C-1:0] delta_R;
    logic [R-1:0] next_R_ptr;
    //logic [C-1:0] C_ptr, C_ptr_reg;
    logic [X_ADDR_BITS-1:0] X_next_addr, this_array, next_array, this_slice, next_slice;
    logic [W_ADDR_BITS-1:0] W_next_addr;
    logic set_X_addr, reset_W_addr, reset_X_addr;

    counter #(
        .SIZE(W_ADDR_BITS)
    ) w_ptr (
        .clk(clk), .reset(reset || reset_W_addr), //reset assert before the next clk when W_read_addr is the last address in the K by K window
        .inc_en(en && stall_bar),
        .prev_count(W_read_addr),
        .new_count(W_read_addr)
    );

    counter #(
        .SIZE(X_ADDR_BITS)
    ) x_ptr (
        .clk(clk), .reset(reset || reset_X_addr), //reset assert before the next clk when X_read_addr is the last address in the R by C matrix
        .inc_en(en && stall_bar && !set_X_addr),
        .prev_count(X_next_addr),
        .new_count(X_read_addr) // register only; always_comb is what X_read_addr shows
    );
    
    always_ff @(posedge clk) begin
        if (reset)
            state <= initiate;
        else if (en || (state == finish))
            state <= next_state;
    end 
    
    always_ff @(posedge clk) begin
        if (reset) begin
            next_R_ptr <= 0;
            this_slice <= 0;
            this_array <= 0;
            next_slice <= 0;
            next_array <= 0;
            delta_R <= 0;
            input_valid <= 0;
        end
        else if ((state == initiate) && en) begin
            next_array <= C;
            delta_R <= S*C;
            next_slice <= S;
            next_R_ptr <= S;
            if (stall_bar)
                input_valid <= 1;
            else 
                input_valid <= 0;
        end 
        else if ((state == iterate)) begin 

            case (move_window)
                by_step : begin
                end
                hold : begin
                    this_slice <= X_next_addr;
                end 
                by_column : begin  
                    this_slice <= X_next_addr;
                    next_slice <= next_slice + S; 
                end 
                by_row : begin  // i.e. set new pivot to X_next_addr, 
                    this_array <= X_next_addr;
                    next_array <= X_next_addr + C;
                    this_slice <= X_next_addr;
                    next_slice <= X_next_addr + S;
                    next_R_ptr <= next_R_ptr + S;
                    
                end
                default : begin // reset all pointer to the first element
                    this_slice <= 0;
                    next_slice <= S;
                    this_array <= 0;
                    next_array <= C;
                    next_R_ptr <= 0;
                end 
            endcase

        end 
        
    end 

    always_comb begin
        init_acc = 0;
        y_valid = 0;
        set_X_addr = 0;
        memory_fetched = 0;
        X_next_addr = X_read_addr; // next element within the same kernel row
        reset_W_addr = 0;
        reset_X_addr = 0;
        move_window = by_step;
        next_state = state;
        case (state)
            initiate : begin
                // load the weight and the first element in a
                if (en && stall_bar) begin
                    init_acc = 1;
                    next_state = iterate;
                end 
            end

            iterate : begin
                // complete the last element of the w-window, move to next w-window
                if (W_read_addr == K*K-1) begin
                    y_valid = 1; //valid output
                    reset_W_addr = 1;
                    set_X_addr = 1;
                    // next w-window on the same row;
                    if (next_slice + K <= next_array) begin
                        move_window = by_column;
                        X_next_addr = next_slice;
                    end
                    // next w-window on the next row; 
                    else if (next_R_ptr + K <= R) begin
                        move_window = by_row;
                        X_next_addr = this_array + delta_R;
                    end
                    // No next w-window; next w-window doesn't fit along the same row or next row
                    else begin
                        move_window = to_start;
                        reset_X_addr = 1;
                        memory_fetched = 1;
                    end
                    next_state = initiate; //reload weight on next w-window
                end
                // complete the last element of w-slice, move to next w-slice
                else if (X_read_addr == this_slice + K - 1) begin
                    move_window = hold;
                    set_X_addr = 1;
                    X_next_addr = this_slice + C;
                end
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