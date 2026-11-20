// Generated from constraint/all_config.json. Edit that file, not this one.
`define WIDTHVAL 16
`define ACCWVAL 48
`define PIPELINEDVAL 1

package params;
    localparam int WIDTH = `WIDTHVAL;  // input / output bits
    localparam int ACCW  = `ACCWVAL;  // accumulator bits
    localparam int PIPELINED = `PIPELINEDVAL;  // 0 = mac, 1 = mac_pipe

    localparam signed [ACCW-1:0] MAXOUT = (1 <<< (WIDTH-1)) - 1;
    localparam signed [ACCW-1:0] MINOUT = -(1 <<< (WIDTH-1));
endpackage
