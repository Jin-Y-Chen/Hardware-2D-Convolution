// Modified dump/trace DPI for input_mems_tb_mod.sv.
// Prints one block per check, in the same layout as mac_tb_mod.c.

#include <stdio.h>

static void kv_i(const char *name, int v)
{
    printf("  %16s = %10d (0x%x)\n", name, v, (unsigned)v);
}

static const char *kind_name(int kind)
{
    switch (kind) {
    case -1: return "t";
    case 0:  return "B";
    case 1:  return "S";
    case 2:  return "Q";
    case 3:  return "X";
    case 4:  return "W";
    default: return "?";
    }
}

static const char *state_name(int state)
{
    switch (state) {
    case 0: return "idle";
    case 1: return "input_W";
    case 2: return "input_B";
    case 3: return "input_X";
    case 4: return "input_loaded";
    default: return "?";
    }
}

void dump_cycle(long long t, int fail_n, int test_n, int kind, int idx,
                int tvalid, int tready, int tdata, int tuser, int cfin,
                int loaded, int state, int mem_addr,
                int b, int s, int q,
                int x_data, int w_data,
                int exp_b, int exp_s, int exp_q,
                int exp_x, int exp_w)
{
    if (fail_n > 0)
        printf("\n[FAIL] t=%lld | test=%d %s[%d]\n", t, test_n, kind_name(kind), idx);
    else
        printf("\n[PASS] t=%lld | test=%d %s[%d]\n", t, test_n, kind_name(kind), idx);

    printf("\n  --- inputs ---\n");
    kv_i("TVALID", tvalid);
    kv_i("TREADY", tready);
    kv_i("TDATA", tdata);
    kv_i("TUSER", tuser);
    kv_i("compute_finished", cfin);

    printf("\n  --- dut ---\n");
    kv_i("inputs_loaded", loaded);
    kv_i("state", state);
    printf("  %16s = %10s\n", "state_name", state_name(state));
    kv_i("mem_addr", mem_addr);

    printf("\n  --- outputs ---\n");
    kv_i("B", b);
    kv_i("S", s);
    kv_i("Q", q);
    kv_i("X_data", x_data);
    kv_i("W_data", w_data);

    printf("\n  --- expected ---\n");
    kv_i("B", exp_b);
    kv_i("S", exp_s);
    kv_i("Q", exp_q);
    kv_i("X", exp_x);
    kv_i("W", exp_w);
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
