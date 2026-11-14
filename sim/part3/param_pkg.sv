package param;
    localparam int WIDTH = 10;
    localparam int R = 15;
    localparam int C = 13;
    localparam int K = 7;
    localparam int ACCW = $clog2(K*K*(128'd1 << (2*WIDTH-2)) + (1 << (WIDTH-1))) + 1;
endpackage
