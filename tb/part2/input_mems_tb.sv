// ESE 507 Stony Brook University
// Peter Milder
// You may not redistribute this code.
// Testbench for input_mems module

// Directions for running this testbench can be found in the project description

// A class to hold one set of inputs for the input_mems module. When we call
// .randomize() on an object of this class, it will randomly generate values for the
// inputs X, weights W, bias B, scaling amount Q, stride S, and the value of new_W.
// This class also has two functions force_new_W() and allow_old_W().
// These functions will generate random input values. The difference between
// these is that force_new_W() will always set new_W=1 while allow_old_W() will
// randomly pick whether to use the weights or create a new one.
class testdata #(parameter WIDTH=8, parameter R=8, parameter C=7, parameter K=3);

    // Stride S. Randomly pick S uniformly from 1 to the maximum useful stride
    // MAXS. (See Part 2 description, section 4.1)
    rand int S;
    localparam MAXS = ((R > C) ? R : C) - K + 1;
    constraint S_constr {S inside {[1:MAXS]};}

    // The Q (scaling) amount. Q is carried in the 7-bit Q field of AXIS_TUSER,
    // so any 7-bit value is legal here. (This module just stores and forwards
    // it; only the full system in Part 3 constrains it to 0..ACCW-1.)
    rand int Q;
    constraint Q_constr {Q inside {[0:127]};}

    // The bias B
    rand int B;

    // an R x C input matrix
    rand int X[R*C];

    // a K x K weight matrix
    rand int W[K*K];

    // The largest and smallest values that fit in a signed WIDTH-bit number
    localparam int MAXV =  (1 << (WIDTH-1)) - 1;
    localparam int MINV = -(1 << (WIDTH-1));

    // The values of X, W, and B can be anything that fits in WIDTH bits
    constraint value_constr {
        foreach(X[i]) {X[i] inside {[MINV:MAXV]};}
        foreach(W[i]) {W[i] inside {[MINV:MAXV]};}
        B inside {[MINV:MAXV]};
    }

    // new_W==0 means this test will use the previous W, B, Q, and S
    // new_W==1 means this test will load new ones
    rand bit new_W;

    // This will randomize all inputs, forcing new_W to 1. We use this at the beginning
    // of the testbench (since there is no old W to re-use!)
    function void force_new_W();
        // randomize everything
        assert(this.randomize());

        // force new_W to 1
        this.new_W = 1;
    endfunction

    // This will randomly choose new_W. If it is 1, it will generate a new W, B, Q, and S.
    // If it is 0, it will copy those from olddata. Either way, it generates a new X.
    function void allow_old_W(testdata #(WIDTH, R, C, K) olddata);
        // randomize
        assert(this.randomize());

        // if the random new_W is 0, then we will copy the previous W, B,
        // Q, and S from olddata
        if (this.new_W == 0) begin
            this.W = olddata.W;
            this.B = olddata.B;
            this.Q = olddata.Q;
            this.S = olddata.S;
        end

    endfunction

endclass

// This file defines `WIDTHVAL, `RVAL, `CVAL, `KVAL, `TVPR, and `STAGEVAL
`include "params.sv"

module input_mems_tb();

    parameter WIDTH  = `WIDTHVAL;  // WIDTH is the number of bits of each input value (X, W, B)
    parameter R      = `RVAL;      // R is the number of rows in the X matrix
    parameter C      = `CVAL;      // C is the number of cols in the X matrix
    parameter K      = `KVAL;      // K is the number of rows/cols in the W matrix
    parameter TESTS  = 10000;      // the number of sets of inputs to simulate

    // The probability that the testbench asserts AXIS_TVALID=1
    // on any given cycle. You can adjust this value to simulate different
    // scenarios. Valid values for this parameter are 0.001 to 1.
    // If the value is set to 0, then it will be randomized when you start
    // your simulation.
    parameter real INPUT_TVALID_PROB = `TVPR;

    // STAGE selects how much of the Part 2 specification this testbench
    // exercises, so that you can build and test this module a piece at a time.
    // See the "Building your design in stages" section of the Part 2 handout.
    //
    //   1 -- Sends the full W, B, X sequence for every set of inputs. 
    //        This does not send or check S or Q. This mode always sets new_W to 1.
    //        In this mode, you can ignore AXIS_TUSER entirely.
    //   2 -- Same data as Stage 1, but now S and Q are sent and checked too. new_W is
    //        still always 1 here.
    //   3 -- The complete specification, including with new_W = 0.
    //
    // Stage 3 is the complete test, and Stage 3 is what you submit.
    parameter STAGE = `STAGEVAL;

    localparam MAXS        = ((R > C) ? R : C) - K + 1; // the largest useful stride
    localparam S_BITS      = $clog2(MAXS+1);            // the number of bits needed for S
    localparam X_ADDR_BITS = $clog2(R*C);               // number of bits to address X
    localparam W_ADDR_BITS = $clog2(K*K);               // number of bits to address W

    // The number of input words in one complete set of inputs, when new_W==1:
    // K*K weights, then B, then R*C values of X. (The Q value is not a data
    // word; it arrives in AXIS_TUSER alongside the first weight.)
    localparam W_LEN     = K*K;
    localparam B_IDX     = W_LEN;       // element index of the bias
    localparam X_IDX     = W_LEN + 1;   // element index of the first value of X
    localparam TOTAL_LEN = X_IDX + R*C;

    logic clk, reset;
    initial clk=0;
    always #5 clk = ~clk;

    // Signals for the DUT's AXI-Stream input interface
    logic signed [WIDTH-1:0] INPUT_TDATA;
    logic INPUT_TVALID;

    // AXIS_TUSER[0] is the new_W signal during the first entry
    // AXIS_TUSER[S_BITS:1] is the value of S during the first W entry
    // AXIS_TUSER[S_BITS+7:S_BITS+1] is the Q value during the first W entry
    logic [S_BITS+7:0] INPUT_TUSER;
    logic INPUT_TREADY;

    // control/status signals to the rest of the system
    logic inputs_loaded;        // tells the control module to start computing
    logic compute_finished;     // comes from outside of this module to say we're done with these inputs
    logic [S_BITS-1:0]       S;     // the stride
    logic signed [WIDTH-1:0] B;     // the bias value
    logic [6:0]              Q;     // the Q (scaling) amount

    // memory interfaces to read data from the memories
    logic [X_ADDR_BITS-1:0]  X_read_addr;
    logic signed [WIDTH-1:0] X_data;
    logic [W_ADDR_BITS-1:0]  W_read_addr;
    logic signed [WIDTH-1:0] W_data;

    // instantiate the DUT
    input_mems #(WIDTH, R, C, K) dut(clk, reset, INPUT_TDATA, INPUT_TVALID, INPUT_TUSER, INPUT_TREADY, inputs_loaded, compute_finished, S, B, Q, X_read_addr, X_data, W_read_addr, W_data);

    // This is an array of "testdata" objects. (See definition of the testdata class above.)
    // It will will hold all of our test data. Each "testdata" object holds data for one convolution input.
    testdata #(WIDTH, R, C, K) td[TESTS];

    // generate random bits to use when randomizing INPUT_TVALID
    logic rb0;
    logic [9:0] randomNum;
    logic [9:0] tvalid_prob;

    initial begin
        // if needed, randomize tvalid_prob
        if (INPUT_TVALID_PROB >= 0.001)
            tvalid_prob = (1024*INPUT_TVALID_PROB-1);
        else
            tvalid_prob = ($urandom % 1024);

        $display("--------------------------------------------------------");
        $display("Starting input_mems simulation: %d tests", TESTS);
        $display("R x C: %d x %d", R, C);
        $display("K:     %d", K);
        $display("WIDTH: %d", WIDTH);

        $display("INPUT_TVALID_PROB = %1.3f", real'(tvalid_prob+1)/1024);
        case (STAGE)
            1: $display("STAGE 1: sending W, B, X; checking both memories and B.");
            2: $display("STAGE 2: sending W, B, X; checking both memories, B, S, and Q.");
            3: $display("STAGE 3: complete test, including sets of inputs that reuse the previous W.");
        endcase
        if (STAGE != 3)
            $display("NOTE: this is not the complete test. A full design must pass Stage 3.");
        $display("--------------------------------------------------------");

        // check parameters
        if (K >= R) begin
            $error("PARAMETER ERROR: K must be < R");
            $stop;
        end
        if (K >= C) begin
            $error("PARAMETER ERROR: K must be < C");
            $stop;
        end
        if ((R < 3) || (C < 3)) begin
            $error("PARAMETER ERROR: R and C must both be >= 3");
            $stop;
        end
        if (K < 2) begin
            $error("PARAMETER ERROR: K must be >= 2");
            $stop;
        end
        if ((WIDTH >= 32) || (WIDTH < 2)) begin
            $error("PARAMETER ERROR: WIDTH must be 2 <= WIDTH < 32");
            $stop;
        end
        if ((STAGE < 1) || (STAGE > 3)) begin
            $error("PARAMETER ERROR: STAGE must be 1, 2, or 3");
            $stop;
        end
    end

    // Every clock cycle, randomly generate rb0 for the INPUT_TVALID signal
    always begin
        @(posedge clk);
        #1;
        randomNum = $urandom;
        rb0 = (randomNum <= tvalid_prob);
    end

    // Logic to keep track of where we are in the test data.
    // which_test keeps track of which of the TESTS test cases we are operating on.
    // which_element keeps track of which input value within this test case we
    // are sending.
    logic [31:0] which_test, which_element;
    initial which_test=0;

    // Every set of inputs begins at element 0, the first value of the W matrix.
    // (A set that reuses the old W restarts at X_IDX instead; see below.)
    initial which_element = 0;
    always @(posedge clk) begin
        if (INPUT_TVALID && INPUT_TREADY) begin
            if (which_element == TOTAL_LEN - 1) begin // if we just finished loading this test...
                which_test <= #1 which_test+1;   // increment to next test

                // if we are not at the last test:
                if (which_test < TESTS-1) begin
                    // if the next test has a new_W, set the counter back to 0
                    if (td[which_test+1].new_W == 1) begin
                        which_element <= #1 0;
                    end
                    else begin // if it doesn't have a new_W, set the counter to the X location
                        which_element <= #1 X_IDX;
                    end
                end

            end
            else begin   // or if we are in the middle of a test, just increment
                which_element <= #1 which_element+1;
            end
        end
    end

    // Logic to set INPUT_TVALID based on random value rb0.
    always @* begin
        // If we haven't finished all of our test inputs and the random bit rb0 is 1,
        if ((which_test < TESTS) && (rb0==1'b1))
            INPUT_TVALID=1;
        else
            INPUT_TVALID=0;
    end

    // Logic to set the value of INPUT_TDATA based on the random input value and the
    // which_element and which_test variables
    always @(which_element or which_test or INPUT_TVALID) begin
        INPUT_TDATA = 'x;
         if (INPUT_TVALID == 1) begin
            if (which_element < W_LEN)               // we are loading the weights
                INPUT_TDATA = td[which_test].W[which_element];
            else if (which_element == B_IDX)         // we are loading the bias
                INPUT_TDATA = td[which_test].B;
            else                                     // we are loading X
                INPUT_TDATA = td[which_test].X[which_element-X_IDX];
        end
    end

    // Logic to set the value of INPUT_TUSER based on the random input value and the
    // which_element and which_test variables.
    // Randomize INPUT_TUSER when it should be a don't-care.
    always @(INPUT_TVALID or which_test or which_element) begin
         if (INPUT_TVALID == 1) begin
            if (which_element == ((td[which_test].new_W == 1) ? 0 : X_IDX)) begin
                // First word: new_W is meaningful here and must be driven for
                // real. S and Q are meaningful too, but only when new_W==1.
                if (td[which_test].new_W == 1)
                    INPUT_TUSER = {7'(td[which_test].Q), S_BITS'(td[which_test].S), 1'b1};
                else
                    INPUT_TUSER = {7'($urandom), S_BITS'($urandom), 1'b0};
            end
            else
                // Not the first word: all three fields are don't cares.
                INPUT_TUSER = $urandom;
        end
        else
            INPUT_TUSER = $urandom;
    end


    // Generate our test input data and expected output data.
    initial begin
        td[0]=new();
        td[0].force_new_W(); // the first test needs a new_W

        for (int i=1; i<TESTS; i++) begin
            td[i]=new();
            if (STAGE == 3)
                td[i].allow_old_W(td[i-1]);
            else
                td[i].force_new_W();
        end
    end

    logic [31:0] which_test_out;
    integer errors = 0;
    initial which_test_out = 0;

    integer cycle_count=0;
    // When inputs_loaded is 1, check the S, B, and Q outputs of the DUT.
    // B is always checked.
    // S and Q are checked in STAGE 2 and 3
    always @(posedge clk) begin
        if ((inputs_loaded == 1) && (B !== td[which_test_out].B)) begin
            $display($time,, "ERROR: Test %d, B = %d; expected value = %d", which_test_out, B, td[which_test_out].B);
            errors = errors+1;
        end
        if ((STAGE >= 2) && (inputs_loaded == 1) && (S !== td[which_test_out].S)) begin
            $display($time,, "ERROR: Test %d, S = %d; expected value = %d", which_test_out, S, td[which_test_out].S);
            errors = errors+1;
        end
        if ((STAGE >= 2) && (inputs_loaded == 1) && (Q !== td[which_test_out].Q)) begin
            $display($time,, "ERROR: Test %d, Q = %d; expected value = %d", which_test_out, Q, td[which_test_out].Q);
            errors = errors+1;
        end

    end

    // Logic to check the outputs and keep track of which output test you are checking
    initial begin
        compute_finished = 0;

        while (which_test_out < TESTS) begin
            wait (inputs_loaded == 1); #1; // wait until inputs are loaded into memory

            // Read the DUT's X and W memories and check correctness.
            W_read_addr = 0;
            X_read_addr = 0;
            for (int i=1; i <= R*C; i++) begin
                @(posedge clk);
                #1;

                // Check W values until we have reached the end of them
                if (i <= W_LEN) begin 
                    if (W_data !== td[which_test_out].W[i-1]) begin
                        $display($time,,"ERROR: Test %d, W_data[%d] = %d; expected value = %d", which_test_out, i-1, W_data, td[which_test_out].W[i-1]);
                        errors = errors+1;
                    end
                end
                
                // Check X values
                if (X_data !== td[which_test_out].X[i-1]) begin
                    $display($time,,"ERROR: Test %d, X_data[%d] = %d; expected value = %d", which_test_out, i-1, X_data, td[which_test_out].X[i-1]);
                    errors = errors+1;
                end

                W_read_addr = (i < W_LEN) ? i : 0;
                X_read_addr = (i < R*C)   ? i : 0;
            end

            if (errors >= 100) begin
                $display($time,, "100 errors reached. Stopping simulation early.");
                $finish;
            end

            // Toggle "compute_finished" so the DUT can start on its next task
            #1;
            compute_finished = 1;

            @(posedge clk);
            #1;
            compute_finished = 0;
            which_test_out = which_test_out+1;
        end
    end

    // Logic to assert reset at the beginning, then wait until all tests are done,
    // print the results, and then quit the simulation.
    initial begin
        reset = 1;
        @(posedge clk); #1; reset = 0;

        wait(which_test_out == TESTS);
        $display("Simulated %d tests. Detected %d errors.", TESTS, errors);
        #1;
        $finish;
    end

    // logic to stop simulation if no progress is being made
    logic [31:0] which_test_out_last;
    initial begin
        forever begin
            which_test_out_last = which_test_out;

            repeat (1000000) @(posedge clk);

            if (which_test_out == which_test_out_last) begin
                $error();
                $display("");
                $display("");
                $display("");
                $display("------------------------ Timeout Error ------------------------");
                $display("ERROR: The testbench has not made progress in the last 1,000,000 cycles. Terminating.");
                $display("The simulation was not successful");
                $display("");
                $display("The testbench made it up to the following input and output before terminating: ");
                $display("    input: td[%d][%d]; output: td[%d][]", which_test, which_element, which_test_out);
                $display("---------------------------------------------------------------");
                $display("");
                $display("");
                $display("");
                $finish;
            end
        end
    end


endmodule


