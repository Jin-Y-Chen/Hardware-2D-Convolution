// ESE 507 Stony Brook University
// Peter Milder
// You may not redistribute this code.
// Testbench for mac_pipe and mac modules


// This file contains the DPI functions used in the MAC testbench.
// For each simulation cycle, the testbench will call this
// sim_cycle function, which computes the expected values of the registers
// and output.

#include <svdpi.h>
#include <stdio.h>

// Store the accumulator value as a 128-bit int. 
// (We need __int128 instead of int or long because ACCW can be as large as 80 bits.)
typedef __int128 acc_t;

// Global variables that will store the simulated state
acc_t prod_pipe = 0;
int prod_valid = 0;
acc_t accum = 0;
int shift_r1 = 0;
int shift_r2 = 0;

// Truncate accumulated value v down to a "width"-bit two's complement value 
static acc_t truncate(acc_t v, int width) {
    acc_t m;

    if (width >= 128)
        return v;

    m = ((acc_t)1) << width;
    v &= (m - 1);
    if (v & (((acc_t)1) << (width - 1)))
        v -= m;

    return v;
}

// Compute the expected output given the accumulator value: arithmetic 
// right shift the accumulator by "shift" bits, then saturate the 
// result to "width" bits.
static long long shift_and_saturate(acc_t acc, int shift, int width) {
    acc_t s;
    acc_t maxval = (((acc_t)1) << (width - 1)) - 1;
    acc_t minval = -(((acc_t)1) << (width - 1));

    if (shift >= 128)
        s = (acc < 0) ? -1 : 0;
    else
        s = acc >> shift;   // arithmetic shift, since acc is signed

    if (s > maxval)
        return (long long)maxval;
    else if (s < minval)
        return (long long)minval;
    else
        return (long long)s;
}

// Simulate one cycle of the pipelined system. The expected result will be stored in res, where it
// can be read by the testbench.
void sim_cycle_pipelined(int in0, int in1, int init_val, svBit valid_data, svBit clear_acc,
                         svBit reset, int shift, int WIDTH, int ACCW, long long* res) {

    if (reset) {
        // Synchronous reset has priority over everything else, and it resets
        // every register in the design: the accumulator, the pipeline
        // register and its valid bit, and the shift alignment registers.
        accum = 0;
        prod_pipe = 0;
        prod_valid = 0;
        shift_r1 = 0;
        shift_r2 = 0;
    }
    else {
        // simulate the accumulator register
        if (clear_acc == 1) {
            accum = truncate((acc_t)init_val, ACCW);
        }
        else if (prod_valid) {
            accum = truncate(accum + prod_pipe, ACCW);
        }

        // simulate the two shift alignment registers. shift accompanies the data it
        // arrived with, so each register has the enable of the data at its own
        // pipeline depth: the first is enabled by input_valid, the second by the
        // registered input_valid (prod_valid, the same signal that enables the
        // accumulator). A shift presented while input_valid is 0 is discarded.
        // Note that prod_valid must be read here before it is updated below.
        if (prod_valid)
            shift_r2 = shift_r1;
        if (valid_data)
            shift_r1 = shift;

        // simulate the product register
        prod_pipe = (acc_t)in0 * (acc_t)in1;
        prod_valid = valid_data;
    }

    // The output is a combinational function of the accumulator register and
    // the delayed shift amount.
    *res = shift_and_saturate(accum, shift_r2, WIDTH);
}

// Simulate one cycle. The expected result will be stored in res, where it
// can be read by the testbench.
void sim_cycle_unpipelined(int in0, int in1, int init_val, svBit valid_data, svBit clear_acc,
                           svBit reset, int shift, int WIDTH, int ACCW, long long* res) {

    if (reset) {
        // Synchronous reset has priority over everything else, and it resets
        // every register in the design: the accumulator and the shift
        // alignment register.
        accum = 0;
        shift_r1 = 0;
    }
    else {
        // simulate the accumulator register
        if (clear_acc == 1) {
            accum = truncate((acc_t)init_val, ACCW);
        }
        else if (valid_data) {
            accum = truncate(accum + (acc_t)in0 * (acc_t)in1, ACCW);
        }

        // simulate the shift alignment register. shift is qualified by input_valid
        // exactly like the data it accompanies: a shift presented while input_valid
        // is 0 has no data to apply to, so it is discarded and the previously
        // captured amount stays in effect.
        if (valid_data)
            shift_r1 = shift;
    }

    // the output is a combinational function of the accumulator register
    *res = shift_and_saturate(accum, shift_r1, WIDTH);
}
