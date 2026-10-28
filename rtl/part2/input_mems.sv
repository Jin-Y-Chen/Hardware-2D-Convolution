import param::*;

module memory #(
    parameter WIDTH=16, SIZE=64,
    localparam LOGSIZE=$clog2(SIZE)
)(
    input clk, wr_en, // clock and write enable
    input [LOGSIZE-1:0] addr, // address input
    input [WIDTH-1:0]   data_in, // data input
    output logic [WIDTH-1:0] data_out // data output
);
    logic [SIZE-1:0][WIDTH-1:0] mem;

    always_ff @(posedge clk) begin
        data_out <= mem[addr];

        if (wr_en)
            mem[addr] <= data_in;
    end

endmodule

module counter #(
    parameter SIZE = 32
) (
    input clk, reset, inc_en,
    input [SIZE-1 : 0] prev_count,
    output logic [SIZE-1:0] new_count
);
    always_ff @(posedge clk) begin //same rising edge as the memory write
        if (reset) begin
            new_count <= 0;
        end
        else if (inc_en)
            new_count <= prev_count + 1;
    end 

endmodule


module input_mems #(
    parameter WIDTH = param::WIDTH,
    parameter R = param::R,
    parameter C = param::C,
    parameter K = param::K,
    localparam MAXS = ((R > C) ? R : C) - K + 1,
    localparam S_BITS = $clog2(MAXS+1),
    localparam X_ADDR_BITS = $clog2(R*C),
    localparam W_ADDR_BITS = $clog2(K*K),
    localparam SIZE = (X_ADDR_BITS > W_ADDR_BITS) ? X_ADDR_BITS : W_ADDR_BITS
)(
    input clk, reset,
    input [WIDTH-1:0] AXIS_TDATA,
    input AXIS_TVALID,
    input [S_BITS+7:0] AXIS_TUSER,
    output logic AXIS_TREADY,
    output logic inputs_loaded,

    input compute_finished,
    output logic [S_BITS-1:0] S,
    output logic signed [WIDTH-1:0] B,
    output logic [6:0] Q,

    input [X_ADDR_BITS-1:0] X_read_addr,
    output logic signed [WIDTH-1:0] X_data,

    input [W_ADDR_BITS-1:0] W_read_addr,
    output logic signed [WIDTH-1:0] W_data
);
    enum logic [1:0] {
        input_W, 
        input_B, 
        input_X, 
        input_loaded} state, next_state;

    //internal logic to drive addr and wr_en of memory
    logic new_W, rst_addr;
    logic [SIZE-1:0] mem_addr;

    //internal register, non-memory component
    logic valid_W, valid_B, valid_X, is_finished; //stay 1 after the first accepted beat of that phase

    counter #(.SIZE(SIZE)) address_counter (
        .clk(clk), .reset(reset || rst_addr),
        .inc_en(AXIS_TVALID && AXIS_TREADY && (state == input_X || state == input_W)), //shared counter to maybe reduce area.  
        .prev_count(mem_addr),
        .new_count(mem_addr)
    );

    // W matrix
    memory #(.WIDTH(WIDTH), .SIZE(K * K)) W_memory (
        .clk(clk),  //data will be stored in the W memory on positive clock edge
        .wr_en(AXIS_TVALID && AXIS_TREADY && (state == input_W)), //only writen to W_memory in valid input_W
        .addr((state == input_loaded) ? W_read_addr : mem_addr[W_ADDR_BITS-1:0]), //Read and write share the same port depening on the FSM state
        .data_in(AXIS_TDATA),   //data_in port should connect directly to the AXIS_TDATA
        .data_out(W_data)       //data_out port of the W memory should connect directly to the W_data
    );

    // X matrix memory
    memory #(.WIDTH(WIDTH), .SIZE(R * C)) X_memory (
        .clk(clk),  //data will be stored in the X memory on positive clock edge
        .wr_en(AXIS_TVALID && AXIS_TREADY && (state == input_X)), //only writen to X_memory in valid input_X
        .addr((state == input_loaded) ? X_read_addr : mem_addr[X_ADDR_BITS-1:0]), //Read and write share the same port depening on the FSM state
        .data_in(AXIS_TDATA),   //data_in port should connect directly to the AXIS_TDATA
        .data_out(X_data)       //data_out port of the X memory should connect directly to the X_data
    );

    assign new_W = AXIS_TUSER[0];

    always_ff @(posedge clk) begin
        if (reset) //synchronized reset, update output on rising edge of clock with asserted reset
            state <= input_W;
        else
            state <= next_state;
    end 

    always_ff @(posedge clk) begin
        if (reset) begin
            valid_W <= 0;
            valid_B <= 0;
            valid_X <= 0;
            is_finished <= 0;
        end
        //store the values of 𝑆 and 𝑄 during the first cycle of this state.
        else if (AXIS_TVALID && AXIS_TREADY && !valid_W && (state == input_W)) begin //lock with SQ
            S <= AXIS_TUSER[S_BITS:1];
            Q <= AXIS_TUSER[S_BITS+7:S_BITS+1];
            valid_W <= 1;
            is_finished <= 0;
        end
        // take in the 𝐵 (bias) value on the next valid rising edge
        else if (AXIS_TVALID && AXIS_TREADY && !valid_B && (state == input_B)) begin
            B <= signed'(AXIS_TDATA);
            valid_B <= 1;
        end
        else if (AXIS_TVALID && AXIS_TREADY && !valid_X && (state == input_X)) begin
            valid_X <= 1;
            is_finished <= 0;
        end
        //monitor the compute_finished input signal. When compute_finished==1 on a positive clock edge,
        else if ((state == input_loaded) && compute_finished) begin
            is_finished <= 1;
        end
        //skip input_W if new_W = 0. TREADY is 0 here, so this first beat is not accepted yet.
        else if ((state == input_loaded) && is_finished && AXIS_TVALID) begin
            is_finished <= 0;
            valid_X <= 0;
            if (new_W) begin
                valid_W <= 0;
                valid_B <= 0;
            end
        end
    end

    always_comb begin
        // every path assigns these, so synthesis makes combo logic instead of latches
        next_state = state;
        AXIS_TREADY = 0;
        rst_addr = 0;
        inputs_loaded = 0;

        if (reset) begin
            next_state = input_W;
            rst_addr = 1;
        end 
        else begin
        case (state)
            // take in W matrix data via its AXI-Stream input interface.
            input_W : begin
                AXIS_TREADY = 1;
                if (mem_addr == unsigned'((K * K) - 1) && AXIS_TVALID) begin //This phase is complete after the entire 𝑊 matrix is loaded (𝐾2 values).
                    next_state = input_B;
                    rst_addr = 1;
                end
            end
            // single handshake 
            input_B: begin
                AXIS_TREADY = 1; //stay ready between W and X
                next_state = AXIS_TVALID ? input_X : state;
            end
            // take in 𝑋 matrix data via its AXI-Stream input interface.
            input_X : begin
                AXIS_TREADY = 1;
                if (mem_addr == unsigned'((R * C) - 1) && AXIS_TVALID) begin //This phase is complete after the entire 𝑋 matrix is loaded(𝑅 × 𝐶 values)
                    next_state = input_loaded;
                    rst_addr = 1;
                end
            end
            // In this phase, ensure that the S, B, and Q output signals hold the correct values.
            input_loaded    : begin
                AXIS_TREADY = 0; //not ready to receive new inputs, so it must output AXIS_TREADY=0.
                if (is_finished) begin //if complete == 1, set inputs_loaded to 0
                    inputs_loaded = 0;
                    // TREADY is 0, so this beat stays on the bus. Branch only once it is valid.
                    // new_W (TUSER[0]) is meaningful on that first beat: 1 reloads W, 0 skips to X.
                    if (AXIS_TVALID)
                        next_state = new_W ? input_W : input_X;
                end
                else
                    inputs_loaded = 1; //output inputs_loaded=1 during this phase.
            end
            //Lets hope it does not go to this state...
            default : begin
                AXIS_TREADY = 0;
            end 
        endcase
        end
    end

endmodule

/* 
Section 1.1: loading the 𝑊 and 𝑋 matrices and the bias value 𝐵. (Testbench Stage 1.)
Section 1.2: loading the values of 𝑆 and 𝑄. (Testbench Stage 2.)
Section 1.3: reusing previously loaded 𝑊, 𝐵, 𝑄, and 𝑆. (Testbench Stage 3.)

First load the values of the W matrix, follow by the scalar value B, followed by the X matrix

Matrix values provided in row-major order
*/