// rtl/conv_pkg.sv
package com_pkg;
    localparam signed [ACCW-1:0] MAXOUT = (1 <<< (WIDTH-1)) - 1;
    localparam signed [ACCW-1:0] MINOUT = -(1 <<< (WIDTH-1));
endpackage