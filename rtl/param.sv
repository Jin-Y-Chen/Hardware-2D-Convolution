// Generated from constraint/all_config.json. Edit that file, not this one.
package param;
    localparam int WIDTH = 10;  // input / output bits
    localparam int ACCW  = 24;  // accumulator bits
    localparam int PIPELINED = 1;  // testbench: 0 = mac, 1 = mac_pipe

    localparam int R = 15;  // rows in X
    localparam int C = 13;  // cols in X
    localparam int K = 7;  // rows and cols in W

    localparam signed [ACCW-1:0] MAXOUT = (1 <<< (WIDTH-1)) - 1;
    localparam signed [ACCW-1:0] MINOUT = -(1 <<< (WIDTH-1));
endpackage
