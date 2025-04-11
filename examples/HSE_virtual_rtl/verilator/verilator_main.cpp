#include "Vtop.h"
#include "verilated.h"

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vtop* top = new Vtop;

    top->clock = 0;
    int simTime = 0;

    while (!Verilated::gotFinish()) {
        top->eval();

        top->clock = !top->clock;
        simTime += 5;
    }

    delete top;
    return 0;
}
