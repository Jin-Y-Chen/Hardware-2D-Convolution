
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
    enum logic [1:0] {
        initiate,
        iterate
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
    logic set_X_addr, reset_W_addr, reset_X_addr, new_matrix;

    counter #(
        .SIZE(W_ADDR_BITS)
    ) w_ptr (
        .clk(clk), .reset(reset || reset_W_addr), //reset assert before the next clk when W_read_addr is the last address in the K by K window
        .inc_en(input_valid && stall_bar),
        .prev_count(W_read_addr),
        .new_count(W_read_addr)
    );

    counter #(
        .SIZE(X_ADDR_BITS)
    ) x_ptr (
        .clk(clk), .reset(reset || reset_X_addr), //reset assert before the next clk when X_read_addr is the last address in the R by C matrix
        .inc_en(input_valid && stall_bar && !set_X_addr),
        .prev_count(X_next_addr),
        .new_count(X_read_addr) // register only; always_comb is what X_read_addr shows
    );
    
    always_ff @(posedge clk) begin
        if (reset)
            state <= initiate;
        else if (en)
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
            new_matrix <= 1;
        end
        // pointer initialization on C-by-R new_matrix
        else if ((state == initiate) && en && new_matrix) begin
            next_array <= C;
            delta_R <= S*C;
            next_slice <= S;
            next_R_ptr <= S;
            new_matrix <= 0;
        end

        // iterate until done or next C-by-R new_maxtrix 
        else if ((state == iterate)) begin

            case (move_window)
                by_step : begin                 // do nothing counter perform steping
                end
                hold : begin
                    this_slice <= X_next_addr;  // determine X_read_addr of all head-slice (this_slice) address in a w-window
                end
                by_column : begin               // stride window by shifting to next_slice
                    this_slice <= X_next_addr;
                    next_slice <= next_slice + S;
                end
                by_row : begin                  // set window to new pivot = X_next_addr,
                    this_array <= X_next_addr;
                    next_array <= X_next_addr + C;
                    this_slice <= X_next_addr;
                    next_slice <= X_next_addr + S;
                    next_R_ptr <= next_R_ptr + S;
                end
                default : begin                 // reset all pointer to the first element in the matrix 
                    this_slice <= 0;
                    next_slice <= S;
                    this_array <= 0;
                    next_array <= C;
                    next_R_ptr <= 0;
                    new_matrix <= 1;
                end
            endcase

        end 
        
    end 

    always_comb begin
        init_acc = 0;
        input_valid = 0;
        y_valid = 0;
        set_X_addr = 0;        
        reset_W_addr = 0;
        reset_X_addr = 0;
        memory_fetched = 0;
        X_next_addr = X_read_addr; // default counter loopback, next count relative to current count
        move_window = by_step;     // default; no pointer operation
        next_state = state;        // default next_state is current state
        case (state)
            initiate : begin
                // first tap of the image: load B and present X[0], W[0]
                if (en && stall_bar) begin
                    init_acc = 1;
                    next_state = iterate;
                end
            end
            
            iterate : begin     
                //biased value load and counter enable on the next cycle; count = 0 on the current cycle
                input_valid = 1;
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