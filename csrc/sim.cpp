#include <stdlib.h>
#include <iostream>
#include <verilated.h>
#ifdef TRACE_VCD
#include <verilated_vcd_c.h>
#else
#include <verilated_fst_c.h>
#endif
#include "VTEST_PLATFORM.h"
#include "VTEST_PLATFORM__Syms.h"
#include "memory.h"
#include <cstring>
#include "config.h"

#ifdef TRACE_ON
bool trace_on = true;
#else
bool trace_on = false;
#endif

vluint64_t sim_time = 0;

VTEST_PLATFORM *dut = nullptr;
#ifdef TRACE_VCD
using TraceType = VerilatedVcdC;
const char *trace_file = "waveform.vcd";
#else
using TraceType = VerilatedFstC;
const char *trace_file = "waveform.fst";
#endif

TraceType *m_trace = nullptr;
void tick();
void runtill();

int main(int argc, char **argv, char **env)
{
    dut = new VTEST_PLATFORM;
    Verilated::traceEverOn(trace_on);
    if (trace_on) {
        m_trace = new TraceType;
        dut->trace(m_trace, 5);
        m_trace->open(trace_file);
    }

    load_bin_to_ram("bin/dense.bin", dense_ram, RAM_SIZE, 0);
    load_bin_to_ram("bin/sparse.bin", sparse_ram, RAM_SIZE, 0);
    memset(result_ram, 0, RAM_SIZE);

    dut->rst_n = 0;
    dut->start = 0;
    dut->HQC_MODE = 0b010;
    tick();
    tick();
    dut->rst_n = 1;
    tick();

    dut->start = 1;
    tick();
    dut->start = 0;

    runtill();

    dump_ram_to_bin("bin/result.bin", result_ram, RAM_SIZE, 0, 2224);

    if (trace_on && m_trace)
        m_trace->close();
    delete dut;
    exit(EXIT_SUCCESS);
}

void tick()
{
    dut->clk = 0;
    dut->eval();
    if (trace_on && m_trace)
        m_trace->dump(sim_time);
    sim_time++;
    dut->clk = 1;
    dut->eval();
    if (trace_on && m_trace)
        m_trace->dump(sim_time);
    sim_time++;
}

void runtill()
{
    do
    {
        dut->clk ^= 1;
        dut->eval();
        if (trace_on && m_trace)
            m_trace->dump(sim_time);
        sim_time++;
    } while (sim_time < MAX_SIM_TIME);
}
