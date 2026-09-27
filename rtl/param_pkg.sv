`include "params.sv"

package param_pkg;
    localparam int WIDTH = `WIDTHVAL;
    localparam int ACCW  = `ACCWVAL;
    localparam signed [ACCW-1:0] MAXOUT = (1 <<< (WIDTH-1)) - 1;
    localparam signed [ACCW-1:0] MINOUT = -(1 <<< (WIDTH-1));
endpackage
