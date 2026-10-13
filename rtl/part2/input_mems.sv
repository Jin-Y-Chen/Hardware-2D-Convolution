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

    always_ff @(negedge clk) begin
        if (reset) begin
            new_count <= 0;
        end
        else if (inc_en)
            new_count <= prev_count + 1;
    end 

endmodule


module input_mems #(
    parameter WIDTH = 24,
    parameter R = 9,
    parameter C = 8,
    parameter K = 4,
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
    logic new_W, hold_b,new_B, init_W_cycle, init_X_cycle, rst_address, delay_valid;
    logic [SIZE-1:0] mem_addr, count_reg; 

    //internal register, non-memory component
    logic [6:0] TUSER_Q;
    logic [S_BITS-1:0] TUSER_S;
    logic [WIDTH-1:0] B_reg;

    counter #(.SIZE(SIZE)) addresser (
        .clk(clk), .reset(reset || rst_address), .inc_en(delay_valid && (state == input_X || state == input_W)),
        .prev_count(count_reg),
        .new_count(mem_addr)
    );

    // W matrix 
    memory #(.WIDTH(WIDTH), .SIZE(K * K)) W_matrix (
        .clk(clk),  //data will be stored in the W memory on positive clock edge
        .wr_en(AXIS_TVALID && AXIS_TREADY && (state == input_W)), 
        .addr((state == input_loaded) ? W_read_addr : mem_addr[W_ADDR_BITS-1:0]),
        .data_in(AXIS_TDATA),   //data_in port should connect directly to the AXIS_TDATA
        .data_out(W_data)       //data_out port of the W memory should connect directly to the W_data
    );

    // X matrix memory
    memory #(.WIDTH(WIDTH), .SIZE(R * C)) X_matrix (
        .clk(clk),  //data will be stored in the X memory on positive clock edge
        .wr_en(AXIS_TVALID && AXIS_TREADY && (state == input_X)), 
        .addr((state == input_loaded) ? X_read_addr : mem_addr[X_ADDR_BITS-1:0]),
        .data_in(AXIS_TDATA),   //data_in port should connect directly to the AXIS_TDATA
        .data_out(X_data)       //data_out port of the X memory should connect directly to the X_data
    );

    assign new_W = AXIS_TUSER[0];
    assign TUSER_S = AXIS_TUSER[S_BITS:1];
    assign TUSER_Q = AXIS_TUSER[S_BITS+7:S_BITS+1];
    

    always_ff @(posedge clk) begin
        if (reset) //synchronized reset, update output on rising edge of clock with asserted reset
            state <= input_W;
        else begin
            state <= next_state;    
            delay_valid <= AXIS_TVALID && AXIS_TREADY;
            count_reg <= mem_addr;
        end
    end 

    always_comb begin
        if (reset) begin
            next_state = input_W;
        end 
        else begin
            case (state)

                input_W : begin 
                    //store the values of 𝑆 and 𝑄 during the first cycle of this state. 
                    if (init_W_cycle) begin //lock with SQ
                        rst_address = 0;
                        init_W_cycle = 0;
                    end
                        
                    if (mem_addr == (K * K) - 1) begin //This phase is complete after the entire 𝑊 matrix is loaded (𝐾2 values).
                        next_state = input_B;
                        AXIS_TREADY = 0;
                        rst_address = 1;
                        new_B = 1;
                    end

                end 
                // take in the 𝐵 (bias) value via the AXI-Stream input interface.
                input_B: begin
                    
                    if (AXIS_TVALID && AXIS_TREADY) begin
                        B_reg <= AXIS_TDATA;
                        next_state = input_X;
                        init_X_cycle = 1;
                        rst_address = 1;
                        AXIS_TREADY = 0;
                    end
                end
                // take in 𝑋 matrix data via its AXI-Stream input interface.
                input_X : begin
                    if (init_X_cycle && AXIS_TVALID && AXIS_TREADY) begin
                        rst_address = 0;
                        init_X_cycle = 0;
                    end                         
                    else if (mem_addr == (R * C) - 1) begin //This phase is complete after the entire 𝑋 matrix is loaded(𝑅 × 𝐶 values)
                        next_state = input_loaded;
                        rst_address = 1;
                    end
 
                end
                // begins after the inputs are complete.
                input_loaded    : begin
                    /*
                    In this phase, your system should ensure that the S, B, and Q
                    output signals hold the correct values. 
                    */ 
                    //monitor the compute_finished input signal. When compute_finished==1 on a positive clock edge,
                    //set inputs_loaded to 0
                    // go back to the beginning, waiting for new input data of 𝑊 matrix data via its AXI-Stream input interface.
                    //skip input_W if new_W = 0, 
                    //output inputs_loaded=1 during this phase.
                    //not ready to receive new inputs, so it must output AXIS_TREADY=0.          
                end

                default : begin
                    // take in 𝑊 matrix data via its AXI-Stream input interface.
                    //skip input_W if new_W = 0, 
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