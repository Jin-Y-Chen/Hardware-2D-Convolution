// ESE 507 Stony Brook University
// Peter Milder
// You may not redistribute this code.
// This file contains the DPI functions used in the Conv_tb testbench.


#include <svdpi.h>
#include <stdio.h>
#include <time.h>
#include <stdlib.h>

// The accumulator can be up to ACCW = 80 bits wide, which does not fit in a
// 64-bit long, so the accumulation below is done in the compiler's 128-bit
// integer type. Only the final saturated WIDTH-bit result crosses back into
// SystemVerilog, and that always fits in a longint.
typedef __int128 acc_t;

// printf has no length modifier for __int128, so render one by hand. Used only
// by the accumulator-overflow diagnostic below, which should never fire; if it
// ever does, the value it reports needs to be the real one, not a truncation.
// "buf" must have room for 41 characters.
static const char *i128_str(acc_t v, char *buf) {
    char tmp[40];
    int  n = 0, i = 0;
    int  neg = (v < 0);
    // Negate into the unsigned domain so the most negative value still works.
    unsigned __int128 u = neg ? (unsigned __int128)0 - (unsigned __int128)v
                             : (unsigned __int128)v;
    if (u == 0) tmp[n++] = '0';
    while (u > 0) { tmp[n++] = (char)('0' + (int)(u % 10)); u /= 10; }
    if (neg) buf[i++] = '-';
    while (n > 0) buf[i++] = tmp[--n];
    buf[i] = '\0';
    return buf;
}

// Given the input matrix X and the weight matrix W, compute the 2D convolution
// with bias B and stride S, scale each result down by Q bits, saturate it to
// WIDTH bits, and store the results in outmat.
//
// This models exactly what the hardware does:
//    - the accumulator is ACCW bits wide, and ACCW is chosen so that it cannot
//      overflow (we check that assumption here anyway)
//    - the accumulated value is arithmetic right shifted by Q bits
//    - the shifted value is saturated to a signed WIDTH-bit value
void calcOutput(svOpenArrayHandle X, svOpenArrayHandle W,
                int R, int C, int K, int S, int B, int Q,
                int WIDTH, int ACCW, svOpenArrayHandle outmat) {

    // Min and max values of the accumulator, used to check that the results
    // don't overflow the number of bits we allotted. ACCW <= 80 < 127, so these
    // are always exactly representable in acc_t.
    acc_t min = -(((acc_t)1)<<(ACCW-1));
    acc_t max = (((acc_t)1)<<(ACCW-1))-1;

    // Min and max values representable in the WIDTH-bit output.
    long out_min = -1*(1l<<(WIDTH-1));
    long out_max = (1l<<(WIDTH-1))-1;

    // The number of output rows and columns. Note the integer division: any
    // window that would run off the edge of X is simply not computed.
    int Rout = (R-K)/S + 1;
    int Cout = (C-K)/S + 1;

    for (int out_row = 0; out_row < Rout; out_row++) {
        for (int out_col = 0; out_col < Cout; out_col++) {

            // The upper-left corner of the K x K window of X used for this output
            int row_start = out_row * S;
            int col_start = out_col * S;

            acc_t bias = (acc_t)B;

            acc_t out = bias;

            for (int weight_row = 0; weight_row < K; weight_row++) {
                for (int weight_col = 0; weight_col < K; weight_col++) {

                    // get the appropriate values
                    int xVal = *(int*)(svGetArrElemPtr1(X, (row_start+weight_row)*C + (col_start+weight_col)));
                    int wVal = *(int*)(svGetArrElemPtr1(W, weight_row*K + weight_col));

                    // Compute the multiply and accumulate.
                    // Note: we need to widen these to acc_t so that "out" doesn't
                    // overflow on this line.
                    acc_t prod = (acc_t)xVal * (acc_t)wVal;
                    acc_t old_accum = out;
                    out += prod;

                    // Check for accumulator overflow. This should never happen, since
                    // ACCW is chosen to be large enough, but if it does, the expected
                    // results would be wrong, so we warn about it. Because acc_t is
                    // wider than any legal ACCW, comparing against min/max detects it
                    // directly; "out" itself never wraps.
                    if ((out < min) || (out > max)) {
                        char buf[41];
                        printf("ERROR: Accumulator overflow. Computed %ld * %ld + %s.\n",
                               (long)xVal, (long)wVal, i128_str(old_accum, buf));
                        return;
                    }
                }
            }

            // Scale the accumulated value down. This is an arithmetic right shift
            // (so the sign is preserved) and it truncates: the result is rounded
            // toward negative infinity, not toward zero.
            acc_t shifted = out >> Q;

            // Saturate to a signed WIDTH-bit value.
            if (shifted > (acc_t)out_max)
                shifted = (acc_t)out_max;
            else if (shifted < (acc_t)out_min)
                shifted = (acc_t)out_min;

            // Save the matrix output value (fits in WIDTH < 32 bits)
            *(long int*)(svGetArrElemPtr1(outmat, out_row * Cout + out_col)) = (long int)shifted;
        }
    }
}
