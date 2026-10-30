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

/*
- control logic and memories for holding the input matrix 𝑋 and weight
matrix 𝑊. It also contains registers to hold the values of 𝑆, 𝐵, and 𝑄.

- AXI-Stream interface will be used to load 𝑋, 𝑊,
𝐵, 𝑄, 𝑆, and new_W (the latter will be introduced below) 

- inputs_loaded signal is an output that your module will use to indicate when its internal
memories hold complete inputs (𝑋 and 𝑊 matrices and values of 𝑆, 𝐵, and 𝑄).

- when input loaded is asserted, X_read_addr and X_data are used to read data from the 𝑋 
input matrix memory, otherwise these signal are ignored

- when input loaded is asserted, W_read_addr and W_data are used to read data from the 𝑊 
weight matrix memory, otherwise these signal are ignored

- 𝑆 controls how far the weight matrix “moves” across 𝑋 as you compute output values.
𝑆 can be any value such that 1 ≤ 𝑆 ≤ MAXS, where MAXS is derived from R, C, and K.)

- B is an output that holds the bias value 𝐵. 

- Q is an output that holds the value of 𝑄: the number of bits the MAC unit will use to scale its accumulated
result down before it leaves your system 

- "We require the S, B, and Q output to be correct and valid anytime
inputs_loaded is 1."

- compute_finished signal is an input that is used to tell the Input Memory module when the sys-
tem is done computing the convolution on the matrices stored in memory

- When compute_finished is asserted on a positive clock edge, your module should set inputs_loaded
to 0 and go back to its initial state to begin taking in new input values. 

- The compute_finished signal should only ever be 1 when inputs_loaded is 1. (So your system can 
safely ignore compute_finished when inputs_loaded is 0.)

- S Q B detail 

input_memes module should contain a register to hold the value S and guarantee that S ouput is correct any time
inputs_loaded == 1

    MAX_S = Max(R, R) - K + 1, 

    S_BITS = $clog2(MAX_S + 1)

    TOP
    localparam MAXS = ((R > C) ? R : C) - K + 1,
    localparam S_BITS = $clog2(MAXS+1),

input_memes module should contain a register to hold the value S and guarantee that S ouput is correct any time
inputs_loaded == 1

    The Q signal is always 7 bits wide.

The bias 𝐵 will be stored in a WIDTH-bit register, which should directly drive the module’s output signal
named B. Your system must guarantee that the B output is correct any time inputs_loaded==1.

    The B is a single WIDTH-bit Regsiter


*/

module input_mems #(
    parameter WIDTH = 24,
    parameter R = 9,
    parameter C = 8,
    parameter K = 4,
    localparam MAXS = ((R > C) ? R : C) - K + 1,
    localparam S_BITS = $clog2(MAXS+1),
    localparam X_ADDR_BITS = $clog2(R*C),
    localparam W_ADDR_BITS = $clog2(K*K)
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

    enum logic [2:0] {
        idle, 
        input_W, 
        input_B, 
        input_X, 
        input_loaded} state, next_state;

    //internal logic to drive addr and wr_en of memory
    logic wr_X_en, wr_W_en, new_W, valid_ready;
    logic [W_ADDR_BITS-1:0] W_mem_addr, W_mem_addr_reg; 
    logic [X_ADDR_BITS-1:0] X_mem_addr, X_mem_addr_reg;

    //internal register, non-memory component
    logic [6:0] TUSER_Q;
    logic [S_BITS-1:0] TUSER_S;
    logic [WIDTH-1:0] B_reg;

    // W matrix memory 
    memory #(.WIDTH(WIDTH), .SIZE(K * K)) W_matrix (
        .clk(clk),
        .wr_en(wr_W_en),
        .addr(W_mem_addr),
        .data_in(AXIS_TDATA),   //data_in port should connect directly to the AXIS_TDATA
        .data_out(W_data)       //data_out port of the W memory should connect directly to the W_data
    );

    // X matrix memory
    memory #(.WIDTH(WIDTH), .SIZE(R * C)) X_matrix (
        .clk(clk),
        .wr_en(wr_X_en),
        .addr(X_mem_addr),
        .data_in(AXIS_TDATA),   //data_in port should connect directly to the AXIS_TDATA
        .data_out(X_data)       //data_out port of the X memory should connect directly to the X_data
    );

    assign new_W = AXIS_TUSER[0];
   

    always_ff @(posedge clk) begin
        if (reset) //synchronized reset, update output on rising edge of clock with asserted reset
            state <= idle;
        else
            state <= next_state;     
            W_mem_addr <= W_mem_addr_reg;
            X_mem_addr <= X_mem_addr_reg;
            valid_ready <= AXIS_TVALID && AXIS_TREADY;
    end 

    always_comb begin
        if (reset) begin
            next_state = idle;
            AXIS_TREADY = 1;
            W_mem_addr_reg = 0;         //reset to start of memory
            X_mem_addr_reg = 0;
        end 
        else begin
            case (state)
                // take in 𝑊 matrix data via its AXI-Stream input interface.
                input_W : begin 
                    if (!new_W) //This step will be skipped if new_W is 0; in that case, you would jump to the Input X Matrix phase.
                        next_state = input_X;

                    else begin
                        //store the values of 𝑆 and 𝑄 during the first cycle of this state. 
                        TUSER_Q = AXIS_TUSER[S_BITS+7:S_BITS+1];
                        TUSER_S = AXIS_TUSER[S_BITS:1];

                        if (W_mem_addr == K * K) begin //This phase is complete after the entire 𝑊 matrix is loaded (𝐾2 values).
                            next_state = input_B;
                            W_mem_addr_reg = 0;
                            wr_W_en = 0;
                        end
                        else if (valid_ready) begin//data will be stored in the W memory on positive clock edge
                            wr_W_en = 1;
                            W_mem_addr_reg <= W_mem_addr_reg + 1;
                        end
                    end 
                end 
                // take in the 𝐵 (bias) value via the AXI-Stream input interface.
                input_B : begin
                    if (!new_W) // This step is skipped if new_W was 0 at the start of the input operation above 
                        next_state = input_X;

                    else if (valid_ready) begin 
                        B_reg = AXIS_TDATA;   //B single scalar value, one word received is stored in B register
                        next_state = input_X; //This phase is complete after this input is loaded. 
                    end
                end
                // take in 𝑋 matrix data via its AXI-Stream input interface.
                input_X : begin
                    if (X_mem_addr == R * C) begin //This phase is complete after the entire 𝑋 matrix is loaded(𝑅 × 𝐶 values)
                        next_state = input_loaded;
                        X_mem_addr_reg = 0;
                        wr_X_en = 0;
                    end
                    else if (valid_ready) begin //data will be stored in the X memory on positive clock edge
                        wr_X_en = 1; 
                        X_mem_addr_reg <= X_mem_addr_reg + 1;
                    end
                end
                // begins after the inputs are complete.
                input_loaded    : begin
                    /*
                    In this phase, your system should ensure that the S, B, and Q
                    output signals hold the correct values. 
                    */
                    if (compute_finished) begin //monitor the compute_finished input signal. When compute_finished==1 on a positive clock edge,
                        inputs_loaded = 0;      //set inputs_loaded to 0
                        next_state = input_W;   // and go back to the beginning, waiting for new input data.
                        AXIS_TREADY = 1;

                        W_mem_addr_reg = 0;         //reset to start of memory
                        X_mem_addr_reg = 0;
                    end
                    else begin
                        AXIS_TREADY = 0;    //not ready to receive new inputs, so it must output AXIS_TREADY=0.
                        inputs_loaded = 1;  //output inputs_loaded=1 during this phase.

                        // allow the memory read interfaces (on the right side of Figure 1) to read data from the matrix memories.
                        W_mem_addr_reg = W_read_addr;
                        X_mem_addr_reg = X_read_addr;
                    end
                end

                default : begin
                    inputs_loaded = 0;
                    next_state = input_W;
                    AXIS_TREADY = 1;
                    W_mem_addr_reg = 0;         //reset to start of memory
                    X_mem_addr_reg = 0;
                end 

            endcase

            Q = TUSER_Q;   //assign the value of TUSER_Q to the Q output
            S = TUSER_S;   //assign the value of TUSER_S to the S output
            B = B_reg;     //assign the value of B_reg to the B output
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