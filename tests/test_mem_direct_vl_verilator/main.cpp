#include "Vtb_top.h"
#include "verilated.h"
#include "verilated_vpi.h"

#include <cstdint>

static Vtb_top *top = nullptr;

// Provided by libverilua_verilator.
extern "C" void vlog_startup_routines_bootstrap(void);
extern "C" void verilua_main_step_safe(void);

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    top = new Vtb_top;

    vlog_startup_routines_bootstrap();
    VerilatedVpi::callCbs(cbStartOfSimulation);

    top->reset = 1;
    top->clk = 0;
    int simTime = 0;

    while (!Verilated::gotFinish() && simTime < 100000) {
        top->clk = !top->clk;
        top->reset = (simTime < 10) ? 1 : 0;
        top->eval();
        if (top->clk) {
            // HSE embedding: advance the verilua step scheduler once per posedge.
            verilua_main_step_safe();
        }
        Verilated::timeInc(5);
        simTime += 5;
    }

    VerilatedVpi::callCbs(cbEndOfSimulation);

    delete top;
    return 0;
}
