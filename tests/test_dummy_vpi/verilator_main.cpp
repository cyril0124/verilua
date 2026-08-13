#include "Vtb_top.h"
#include "verilated.h"

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    auto *top = new Vtb_top;

    top->reset = 1;
    top->clock = 0;
    int sim_time = 0;

    while (!Verilated::gotFinish()) {
        top->eval();
        top->reset = sim_time < 10 ? 1 : 0;
        top->clock = !top->clock;
        sim_time += 5;
    }

    delete top;
    return 0;
}
