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
#include <fstream>
#include <iomanip>
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
    // 1. initialize verilator and create instance of the DUT
    dut = new VTEST_PLATFORM;
    Verilated::traceEverOn(true);
    m_trace = new TraceType;
    dut->trace(m_trace, 5);
    m_trace->open(trace_file);
    //=======================================================
    // 2. dut reset
    dut->rst_n = 0;
    tick();
    dut->rst_n = 1;
    tick();
    dut->start = 1;
    tick();
    dut->start = 0;
    //=======================================================
    // 3. main simulation loop
    tick();
    runtill();

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
