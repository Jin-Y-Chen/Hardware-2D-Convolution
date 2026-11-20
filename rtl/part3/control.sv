
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
    // state FSM to generate the control signal 
    enum logic [1:0] {
        idle,
        next_window,
        this_window,
        load_stall
    } state, next_state;

    // state FSM to compute the next X_read_addr
    enum logic [1:0] {
        slice_down,         //take the slice directly down the current
        stride_slice,       //stride to the next slice (within C)
        stride_array,       //stride to the next array (row major with R)
        start               //start control
    } window_op, next_window_op;

    logic [S_BITS+C-1:0] delta_R;
    logic [R-1:0] next_R_ptr;
    logic [C-1:0] next_C_ptr;
    logic [X_ADDR_BITS-1:0] X_next_addr, this_array, this_slice, next_window_addr, next_slice_addr;
    logic set_X_addr, reset_W_addr, reset_X_addr;

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
            state <= idle;
        else if (en)
            state <= next_state; //en low holds the machine between images
    end 
    
    always_ff @(posedge clk) begin
        if (reset) begin
            next_window_addr <= 0;
            next_slice_addr <= 0;
            next_R_ptr <= 0;
            next_C_ptr <= 0;
            this_slice <= 0;
            this_array <= 0;
            delta_R <= 0;
            window_op <= start;
        end
        else if (state == idle) begin
            next_window_addr <= 0;                  //first window is the 0th array, undetermined if it will stride right or down
            next_slice_addr <= C;                   //next slice of this window is one row down
            next_R_ptr <= S;                        //to comparte if next window will fit on the next row
            next_C_ptr <= S;                        //to compare if next window will fit on this row
            this_slice <= 0;                        //current working slice is the 0th slice
            this_array <= 0;                        //current working window is the 0th array
            if (en && stall_bar)
                delta_R <= S*C;                         //address step of one stride down
            window_op <= start;                     //default window operation to starting window
        end

        else if ((state == next_window)) begin
            this_slice <= next_window_addr;             //set the first address of this window
            next_slice_addr <= next_window_addr + C;    //set the next slice of this window one row down
            window_op <= next_window_op;                //remember the next_window_op 

            if (next_window_op == stride_slice) begin
                next_window_addr <= next_window_addr + S;       //next address assignment by addition of S
                next_C_ptr <= next_C_ptr + S;                   //stride next column pointer
            end 
            else if (next_window_op == stride_array) begin
                next_window_addr <= this_array + delta_R;       //next address assignment by multiple of C * S
                this_array <= this_array + delta_R;             //move the row base onto that next row
                next_C_ptr <= S;                                //new row, reset next column pointer
                next_R_ptr <= next_R_ptr + S;                   //stride Row pointer
            end
        end 

        else if ((state == this_window) && next_window_op == slice_down) begin
            //window_op <= next_window_op;              //since window_op will return to previous state, this case we dont need to perform window_op <= next_window_op
            this_slice <= next_slice_addr;              //update this slice for next comparison
            next_slice_addr <= next_slice_addr + C;     //update the next slice to set x_next_addr
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
        next_window_op = start;    //default; a stride or a slice step overwrites it
        next_state = state;        //hold the state while stalled or while en is low

        //if (en && stall_bar) begin //stall_bar low holds the address and the state
        case (state)
            idle: begin
                // first tap of the image: load B and present X[0], W[0]
                if (en && stall_bar) begin
                    init_acc = 1;
                    next_state = next_window;
                end
            end
            // compute next window operation state, input to the window_op fsm
            next_window: begin
                input_valid = 1; 
                // next w-window on the same row;
                if (next_C_ptr + K <= C) begin
                    next_window_op = stride_slice;
                end
                // next w-window on the next row;
                else if (next_R_ptr + K <= R) begin
                    next_window_op = stride_array;
                end
                // No next w-window; next w-window doesn't fit along the same row or next row
                else begin
                    next_window_op = start;
                end 

                next_state = this_window;
            end
            //evaluate current window 
            this_window: begin
                input_valid = 1; //always increment the address until the full window is fetch for one single y to be computed
                // complete the last address of the window, move to the next window
                if (W_read_addr == K*K-1) begin
                    y_valid = 1;                        //valid output, one convolution window computed
                    reset_W_addr = 1;                   //reset the weight address to the start of the window
                    if (window_op == start) begin
                        reset_X_addr = 1;               //next X address to 0 for the new matrix
                        memory_fetched = 1;             //matrix fetched from memory completed
                        next_state = idle;              //ready to fetch another matrix
                    end else begin
                        set_X_addr = 1;                     //set the next X address to the next window with no increment
                        X_next_addr = next_window_addr;     //next window address loaded into the X counter
                        next_state = load_stall;            //one additional cycle to load the accumulator
                    end
                // complete the last address of the slice, move to the next slice of the window
                end else if (X_read_addr == (this_slice + K - 1)) begin
                    next_window_op = slice_down;        //one cycle to update this slice, 
                    
                    set_X_addr = 1;                     //set the X address to the next slice with no increment
                    X_next_addr = next_slice_addr;      //next slice addres loaded into the X counter
                end
            end
            //one cycle stall to load accumulator
            load_stall: begin
                init_acc = 1;
                input_valid = 0;                    //stall counter for 1 cycle to load accumlator, since accum will prioritize intial load over accumulation
                next_state = next_window;           //compute the next window relative to this window (at the new window from previoous next_window)
            end
        endcase
        //end
    end 
endmodule


