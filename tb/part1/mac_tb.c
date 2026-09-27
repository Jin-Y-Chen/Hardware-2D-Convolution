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

static void i128_str(acc_t v, char *out, int cap)
{
    char tmp[80];
    int n = 0;
    int i;
    int neg = 0;

    if (cap < 2)
        return;
    if (v == 0) {
        out[0] = '0';
        out[1] = '\0';
        return;
    }
    if (v < 0) {
        neg = 1;
        v = -v;
    }
    while (v > 0 && n < (int)sizeof(tmp)) {
        tmp[n++] = (char)('0' + (int)(v % 10));
        v /= 10;
    }
    i = 0;
    if (neg && i < cap - 1)
        out[i++] = '-';
    while (n > 0 && i < cap - 1)
        out[i++] = tmp[--n];
    out[i] = '\0';
}

static void i128_hex(acc_t v, char *out, int cap)
{
    unsigned __int128 u = (unsigned __int128)v;
    char tmp[40];
    int n = 0;
    int i;

    if (cap < 4)
        return;
    if (u == 0) {
        snprintf(out, (size_t)cap, "0x0");
        return;
    }
    while (u > 0 && n < (int)sizeof(tmp)) {
        tmp[n++] = "0123456789abcdef"[u & 0xf];
        u >>= 4;
    }
    i = 0;
    out[i++] = '0';
    out[i++] = 'x';
    while (n > 0 && i < cap - 1)
        out[i++] = tmp[--n];
    out[i] = '\0';
}

static void kv_s(const char *name, const char *val)
{
    printf("  %16s = %18s\n", name, val);
}

static void kv_dec_hex(const char *name, const char *dec, const char *hex)
{
    printf("  %16s = %10s (%s)\n", name, dec, hex);
}

static void kv_i(const char *name, int v)
{
    printf("  %16s = %10d (0x%x)\n", name, v, (unsigned)v);
}

static void kv_ll(const char *name, long long v)
{
    printf("  %16s = %10lld (0x%llx)\n", name, v, (unsigned long long)v);
}

void dump_cycle(long long t, int rst, int init_acc, int valid, int Q,
                int i0, int i1, int initv,
                int outv, int exp_d, int expv,
                long long acc_dut,
                int pipelined, int fail_n)
{
    char accs[48];
    char acch[48];
    char prods[48];
    char prodh[48];

    i128_str(accum, accs, sizeof accs);
    i128_hex(accum, acch, sizeof acch);
    i128_str(prod_pipe, prods, sizeof prods);
    i128_hex(prod_pipe, prodh, sizeof prodh);

    if (fail_n > 0)
        printf("\n[FAIL] t=%lld | reset=%d init_acc=%d input_valid=%d Q=%d\n",
               t, rst, init_acc, valid, Q);
    else
        printf("\n[PASS] t=%lld | reset=%d init_acc=%d input_valid=%d Q=%d\n",
               t, rst, init_acc, valid, Q);

    printf("\n  --- inputs ---\n");
    kv_i("reset", rst);
    kv_i("init_acc", init_acc);
    kv_i("input_valid", valid);
    kv_i("Q", Q);
    kv_i("input0", i0);
    kv_i("input1", i1);
    kv_i("init_value", initv);

    printf("\n  --- dut ---\n");
    kv_ll("acc_w", acc_dut);

    printf("\n  --- outputs ---\n");
    kv_i("out", outv);
    kv_i("out_exp_d", exp_d);
    kv_i("out_exp", expv);

    printf("\n  --- golden (C) ---\n");
    kv_dec_hex("accum", accs, acch);
    kv_i("shift_r1", shift_r1);
    if (pipelined) {
        kv_i("shift_r2", shift_r2);
        kv_dec_hex("prod_pipe", prods, prodh);
        kv_i("prod_valid", prod_valid);
    }
    fflush(stdout);
}

void dump_summary(int cycles, int fails)
{
    int passes = cycles - fails;
    double match = (cycles > 0) ? (100.0 * (double)passes / (double)cycles) : 0.0;

    printf("\n========================================\n");
    if (fails == 0)
        printf("[VALID] summary\n");
    else
        printf("[INVALID] summary\n");
    printf("  pass  = %d\n", passes);
    printf("  fail  = %d\n", fails);
    printf("  total = %d\n", cycles);
    printf("  match = %.1f%%  (%d/%d)\n", match, passes, cycles);
    printf("========================================\n");
    fflush(stdout);
}

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
