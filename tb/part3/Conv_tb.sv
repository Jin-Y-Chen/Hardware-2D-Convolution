// ESE 507 Stony Brook University
// Peter Milder
// You may not redistribute this code.
// Testbench for Conv module

// Directions for running this testbench can be found in the project description

// Import the C function (in test_helper.c) that computes the output matrix given the
// input matrices, the bias, the stride, and the Q amount.
import "DPI-C" function void calcOutput(input int X[], input int W[],
                                        input int R, input int C, input int K, input int S,
                                        input int B, input int Q,
                                        input int WIDTH, input int ACCW,
                                        output longint outmat[]);


// A class to hold one instance of test data and its expected output. When we call
// .randomize() on an object of this class, it will randomly generate values for the
// inputs X, weights W, bias B, scaling amount Q, stride S, and the value of new_W.
// This class also has two functions force_new_W() and allow_old_W().
// These functions will generate random input values. The difference between
// these is that force_new_W() will always set new_W=1 while allow_old_W() will
// randomly pick whether to use the weights or create a new one.
class testdata #(parameter WIDTH=8, parameter ACCW=32, parameter R=18, parameter C=15, parameter K=3);

    // Stride S. Randomly pick S uniformly from 1 to the maximum
    rand int S;
    localparam MAXS = ((R > C) ? R : C) - K + 1;
    constraint S_constr {S inside {[1:MAXS]};}

    // Q (scaling amount)
    // We need to be careful about how we randomly generate Q: 
    //   - if we pick lots of very high Q values, then most of our outputs will be close to 0
    //   - if we pick lots of very low Q values, then most of our outputs will be saturated
    // So, we will: 
    //   - make most (70%) of the Q values to be near a medium value, which will keep
    //     outputs close to the middle
    //   - choose the other 30% of the random Q values to be over the entire legal range
    rand int Q;
    localparam Q_MAX = ACCW-1;
    localparam Q_TYP = WIDTH - 1 + $clog2(K);      // brings typical output back to about WIDTH bits
    localparam Q_LO = (Q_TYP > 3) ? Q_TYP-3 : 0;   // don't go below 0 for very small WIDTH
    localparam Q_HI = Q_TYP+3;                     
    constraint Q_constr {Q dist {[Q_LO:Q_HI] :/ 70, [0:Q_MAX] :/ 30};}

    // X, W, and B values. 
    // In addition to random testing, we want some tests that force large accumulator 
    // outputs. So, we will use two different kinds of tests:
    //    max_acc_test == 0: normal random values of X, W, and B
    //    max_acc_test == 1: every matrix value is the most negative number (to test large 
    //                       positive accumulator outputs)
    // 98% of tests are random; 2% are max-accumulator tests.

    rand int B;
    rand int X[R*C];
    rand int W[K*K];

    rand bit max_acc_test;
    constraint max_acc_constr {max_acc_test dist {0 := 98, 1 := 2};}

    // The largest and smallest values that fit in a signed WIDTH-bit number
    localparam int MAXV =  (1 << (WIDTH-1)) - 1;
    localparam int MINV = -(1 << (WIDTH-1));

    // The values of X, W, and the bias, chosen based on the kind of test
    constraint value_constr {
        if (!max_acc_test) {
            // random WIDTH-bit values of X, W, B
            foreach(X[i]) {X[i] inside {[MINV:MAXV]};}
            foreach(W[i]) {W[i] inside {[MINV:MAXV]};}
            B inside {[MINV:MAXV]};
        }
        else {
            // force X and W to be MINV and B to be MAXV to make the accumulator as large as possible
            foreach(X[i]) {X[i] == MINV;}
            foreach(W[i]) {W[i] == MINV;}
            B == MAXV;
        }
    }

    // new_W==0 means this test will use the previous weights, bias, Q, and stride;
    // new_W==1 means this test will load new ones
    rand bit new_W;

    // The expected output matrix of this convolution calculation.
    // This is actually Rout x Cout (which depends on S), but we size it to match the
    // largest possible output, which occurs when S=1.
    longint output_matrix[(R-K+1)*(C-K+1)];

    // The number of rows and columns of the expected output matrix
    function int Rout();
        return (R-K)/S + 1;
    endfunction

    function int Cout();
        return (C-K)/S + 1;
    endfunction

    // This will randomize all inputs, forcing new_W to 1. It will
    // then calculate the expected output. We use this at the beginning
    // of the testbench (since there is no old W to re-use!)
    function void force_new_W();
        // randomize everything
        assert(this.randomize());

        // force new_W to 1
        this.new_W = 1;

        // calculate the expected result and store in this.output_matrix
        calcOutput(this.X, this.W, R, C, K, this.S, this.B, this.Q, WIDTH, ACCW, this.output_matrix);

    endfunction


    // This will randomly choose new_W. If it is 1, it will generate a new
    // weight matrix, bias, Q, and stride. If it is 0, it will copy those from olddata.
    // Then it will generate a new X and compute the expected output.
    function void allow_old_W(testdata #(WIDTH, ACCW, R, C, K) olddata);
        // randomize
        assert(this.randomize());

        // a max-accumulator test needs its own weights and bias, so it always loads them
        if (this.max_acc_test)
            this.new_W = 1;

        // if the random new_W is 0, then we will copy the previous W, B,
        // Q, and S from olddata
        if (this.new_W == 0) begin
            this.W = olddata.W;
            this.B = olddata.B;
            this.Q = olddata.Q;
            this.S = olddata.S;
        end

        // calculate the expected result and store in this.output_matrix
        calcOutput(this.X, this.W, R, C, K, this.S, this.B, this.Q, WIDTH, ACCW, this.output_matrix);

    endfunction

endclass

`include "params.sv"

module Conv_tb();

    parameter TESTS = 10000;      // the number of convolutions to test
    parameter WIDTH = `WIDTHVAL;  // WIDTH is the number of bits of each input and output value

    // We require 2 <= WIDTH < 32, and the derived accumulator width ACCW must be <= 80.
    parameter R     = `RVAL;      // R is the number of rows in the X matrix
    parameter C     = `CVAL;      // C is the number of cols in the X matrix
    parameter K     = `KVAL;      // K is the number of rows/cols in the W matrix


    // The probability that the testbench asserts INPUT_TVALID=1 and OUTPUT_TREADY
    // on any given cycle.
    // You can adjust these values to simulate different scenarios.
    // Valid values for these parameters are 0.001 to 1.
    // If a value is set to 0, then it will be randomized when you start
    // your simulation.
    parameter real INPUT_TVALID_PROB = `TVPR;
    parameter real OUTPUT_TREADY_PROB = `TRPR;

    // These must match the localparams inside the Conv module
    localparam ACCW   = $clog2(K*K*(128'd1 << (2*WIDTH-2)) + (1<<(WIDTH-1)))+1;
    localparam QW = 7;   // constant: the Q signal is always 7 bits

    localparam MAXS   = ((R > C) ? R : C) - K + 1; // the largest useful stride
    localparam S_BITS = $clog2(MAXS+1);            // the number of bits needed for S

    // The number of input words in one complete set of inputs, when new_W==1:
    // K*K weights, then B, then R*C values of X. (The Q amount is not a data
    // word: it arrives on INPUT_TUSER alongside the first weight.)
    localparam W_LEN     = K*K;
    localparam B_IDX     = W_LEN;       // element index of the bias
    localparam X_IDX     = W_LEN + 1;   // element index of the first value of X
    localparam TOTAL_LEN = X_IDX + R*C;

    logic clk, reset;

    // Signals for the DUT's AXI-Stream input interface
    logic signed [WIDTH-1:0] INPUT_TDATA;
    logic INPUT_TVALID;

    // INPUT_TUSER[0] is the new_W signal during the first entry
    // INPUT_TUSER[S_BITS:1] is the value of S during the first W entry
    // INPUT_TUSER[S_BITS+7:S_BITS+1] is the Q amount, also during the
    //   first W entry
    logic [S_BITS+7:0] INPUT_TUSER;
    logic INPUT_TREADY;

    // Signals for the DUT's AXI-Stream output interface
    logic signed [WIDTH-1:0] OUTPUT_TDATA;
    logic                    OUTPUT_TVALID;
    logic                    OUTPUT_TREADY;

    initial clk=0;
    always #5 clk = ~clk;

    // Instantiate the DUT
    Conv #(WIDTH, R, C, K) dut(clk, reset, INPUT_TDATA, INPUT_TVALID, INPUT_TUSER, INPUT_TREADY, OUTPUT_TDATA, OUTPUT_TVALID, OUTPUT_TREADY);

    // This is an array of "testdata" objects. (See definition of the testdata class above.)
    // It will will hold all of our test data. Each "testdata" object holds data for one convolution operation test case.
    // It holds a set of inputs (X, W, B, Q, S, new_W) and the corresponding expected output.
    testdata #(WIDTH, ACCW, R, C, K) td[TESTS];

    // generate random bits to use when randomizing INPUT_TVALID and OUTPUT_TREADY
    logic rb0, rb1;
    logic [9:0] randomNum;
    logic [9:0] tvalid_prob, tready_prob;

    initial begin
        // if needed, randomize tvalid_prob and tready_prob
        if (INPUT_TVALID_PROB >= 0.001)
            tvalid_prob = (1024*INPUT_TVALID_PROB-1);
        else
            tvalid_prob = ($urandom % 1024);

        if (OUTPUT_TREADY_PROB >= 0.001)
            tready_prob = (1024*OUTPUT_TREADY_PROB-1);
        else
            tready_prob = ($urandom % 1024);

        $display("--------------------------------------------------------");
        $display("Starting top-level simulation: %d tests", TESTS);
        $display("R x C: %d x %d", R, C);
        $display("K:     %d", K);
        $display("WIDTH: %d", WIDTH);
        $display("ACCW:  %d", ACCW);        

        $display("INPUT_TVALID_PROB  = %1.3f", real'(tvalid_prob+1)/1024);
        $display("OUTPUT_TREADY_PROB = %1.3f", real'(tready_prob+1)/1024);
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
        if (ACCW > 80) begin
            $error("PARAMETER ERROR: ACCW must be <= 80. ACCW depends on WIDTH and K");
            $stop;
        end
    end

    // Every clock cycle, randomly generate rb0 and rb1 for the INPUT_TVALID and
    // OUTPUT_TREADY signals, respectively
    always begin
        @(posedge clk);
        #1;
        randomNum = $urandom;
        rb0 = (randomNum <= tvalid_prob);
        randomNum = $urandom;
        rb1 = (randomNum <= tready_prob);
    end

    // Logic to keep track of where we are in the test data.
    // which_test keeps track of which of the TESTS test cases we are operating on.
    // which_element keeps track of which input value within this test case we
    // are sending.
    logic [31:0] which_test, which_element;
    initial which_test=0;
    initial which_element=0;
    always @(posedge clk) begin
        if (INPUT_TVALID && INPUT_TREADY) begin
            if (which_element == TOTAL_LEN - 1) begin // if we just finished loading this test...
                which_test <= #1 which_test+1;   // increment to next test

                // if we are not at the last test input:
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
    // The stride S and the Q amount are only transmitted alongside the first
    // weight value, when new_W==1. At all other times the TUSER_S and TUSER_Q
    // fields are don't cares, so we drive random values there to make sure your
    // design does not depend on them.
    always @(INPUT_TVALID or which_element or which_test) begin
        INPUT_TUSER = 'x;
         if (INPUT_TVALID == 1) begin
            if ((td[which_test].new_W == 1) && (which_element == 0))
                INPUT_TUSER = {7'(td[which_test].Q), S_BITS'(td[which_test].S), 1'b1};
            else
                INPUT_TUSER = {7'($urandom), S_BITS'($urandom), 1'b0};
        end
    end

    // generate our test input data and expected output data
    initial begin
        #1;
        td[0]=new();
        td[0].force_new_W(); // the first test needs a new_W

        for (int i=1; i<TESTS; i++) begin
            td[i]=new();
            td[i].allow_old_W(td[i-1]);
        end
    end

    // Logic to set OUTPUT_TREADY based on random value rb1
    logic [31:0] which_test_out, which_element_out;
    always @* begin
        if ((which_test_out < TESTS) && (rb1==1'b1))
            OUTPUT_TREADY = 1;
        else
            OUTPUT_TREADY = 0;
    end


    integer errors = 0;
    initial which_test_out = 0;
    initial which_element_out = 0;

    integer cycle_count=0;

    // Logic to check the outputs and keep track of which output test you are checking
    always @(posedge clk) begin
        if (OUTPUT_TVALID && OUTPUT_TREADY) begin
            if (OUTPUT_TDATA !== td[which_test_out].output_matrix[which_element_out]) begin
                $display($time,,"ERROR: Test %d, y[%d] = %d; expected value = %d", which_test_out, which_element_out, OUTPUT_TDATA, td[which_test_out].output_matrix[which_element_out]);
                errors = errors+1;
            end
            if (errors >= 100) begin
                $display($time,, "100 errors reached. Stopping simulation early.");
                $finish;
            end
            if (which_element_out == td[which_test_out].Rout() * td[which_test_out].Cout() - 1) begin
                which_element_out = 0;
                which_test_out = which_test_out+1;
            end
            else begin
                which_element_out = which_element_out+1;
            end
        end
    end

    // Logic to count cycles, used in our throughput testing
    always @(posedge clk) begin

        // reset the cycle_counter on the first element of the first input
        if (INPUT_TVALID && INPUT_TREADY && (which_test==0) && (which_element==0))
            cycle_count <= 0;
        else
            cycle_count <= cycle_count+1;

    end

    // Logic to assert reset at the beginning, then wait until all tests are done,
    // print the results, and then quit the simulation.
    initial begin
        reset = 1;
        @(posedge clk); #1; reset = 0;

        wait(which_test_out == TESTS);
        $display("Simulated %d tests. Detected %d errors.", TESTS, errors);
        $display("Your system computed %d Convs in %d cycles", TESTS, cycle_count);
        #1;
        $finish;
    end

    // logic to stop simulation if no progress is being made
    logic [31:0] which_test_out_last, which_element_out_last;
    initial begin
        forever begin
            which_test_out_last = which_test_out;
            which_element_out_last = which_element_out;


            repeat (1000000) @(posedge clk);

            if ((which_test_out == which_test_out_last) && (which_element_out == which_element_out_last)) begin
                $error();
                $display("");
                $display("");
                $display("");
                $display("------------------------ Timeout Error ------------------------");
                $display("ERROR: The testbench has not made progress in the last 1,000,000 cycles. Terminating.");
                $display("The simulation was not successful!");
                $display("");
                $display("The testbench made it up to the following input and output before terminating: ");
                $display("   input: td[%d][%d]; output: td[%d][%d]", which_test, which_element, which_test_out, which_element_out);
                $display("--------------------------------------------------------------");
                $display("");
                $display("");
                $display("");
                $finish;
            end
        end
    end

endmodule
