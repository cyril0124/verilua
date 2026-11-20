// Custom main for the dummy_vpi (vl-verilator-dpi) flow: plain eval loop, no
// VPI. verilua is driven by the DPI ticks injected into the rewritten RTL.
#include "Vtb_top.h"
#include "verilated.h"

#include <cstdint>

static Vtb_top *top = nullptr;

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    top = new Vtb_top;

    top->reset = 1;
    top->clk = 0;
    int simTime = 0;

    while (!Verilated::gotFinish() && simTime < 100000) {
        top->clk = !top->clk;
        top->reset = (simTime < 10) ? 1 : 0;
        top->eval();
        Verilated::timeInc(5);
        simTime += 5;
    }

    delete top;
    return 0;
}
