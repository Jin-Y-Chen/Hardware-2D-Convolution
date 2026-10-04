// Generated from constraint/all_config.json. Edit that file, not this one.
package param;
    localparam int WIDTH = 24;  // input / output bits
    localparam int ACCW  = 48;  // accumulator bits
    localparam int PIPELINED = 1;  // testbench: 0 = mac, 1 = mac_pipe

    localparam signed [ACCW-1:0] MAXOUT = (1 <<< (WIDTH-1)) - 1;
    localparam signed [ACCW-1:0] MINOUT = -(1 <<< (WIDTH-1));
endpackage
