#include "Vtb_top.h"
#include "verilated.h"
#include "verilated_vpi.h"

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vtb_top* top = new Vtb_top;

    top->reset = 1;
    top->clk = 0;
    int simTime = 0;

    while (!Verilated::gotFinish()) {
        top->eval();

        if (simTime < 10) {
            top->reset = 1;
        } else {
            top->reset = 0;
        }

        top->clk = !top->clk;
        simTime += 5;
    }

    VerilatedVpi::callCbs(cbEndOfSimulation);

    delete top;
    return 0;
}
