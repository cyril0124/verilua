// This code is highly inspired by cocotb. 
// www.cocotb.org
// https://github.com/cocotb/cocotb/tree/master/cocotb/share/lib/verilator

// TODO: Command line argparser
#include "Vtb_top.h"
#include "verilated.h"
#include "verilated_vpi.h"

#include <memory>
#include <csignal>
#include <cstdlib>
#include <cassert>
#include <argparse/argparse.hpp>

#include "lua_vpi.h"


#ifndef VM_TRACE_FST
// emulate new verilator behavior for legacy versions
#define VM_TRACE_FST 0
#endif

#if VM_TRACE
    #if VM_TRACE_FST
        #include <verilated_fst_c.h>
    #else
        #include <verilated_vcd_c.h>
    #endif
#endif

std::unique_ptr<Vtb_top> top(new Vtb_top(""));

#if VM_TRACE
    #if VM_TRACE_FST
        std::unique_ptr<VerilatedFstC> tfp;
    #else
        std::unique_ptr<VerilatedVcdC> tfp;
    #endif
#endif

struct Config {
    bool verbose           = false;
    bool enable_wave       = false;
    bool wave_is_enable    = false;
    bool wave_is_close     = false;
    char *trace_file       = "dump.vcd";
    bool enable_coverage   = false;
};

Config cfg;

#if VM_TRACE
    #if VM_TRACE_FST
        #define DUMP_WAVE_INIT() \
            do { \
                if (cfg.enable_wave && !cfg.wave_is_enable) { \
                    Verilated::traceEverOn(true); \
                    tfp.reset(new VerilatedFstC()); \
                    top->trace(tfp.get(), 99); \
                    tfp->open(cfg.trace_file); \
                    cfg.wave_is_enable = true; \
                } \
            } while(0)
    #else
        #define DUMP_WAVE_INIT() \
            do { \
                if (cfg.enable_wave && !cfg.wave_is_enable) { \
                    Verilated::traceEverOn(true); \
                    tfp.reset(new VerilatedVcdC()); \
                    top->trace(tfp.get(), 99); \
                    tfp->open(cfg.trace_file); \
                    cfg.wave_is_enable = true; \
                } \
            } while(0)
    #endif
#else
    #define DUMP_WAVE_INIT() \
        do { \
        } while(0)
#endif


#if VM_TRACE
    #define DUMP_WAVE(time) \
        do { \
            if (cfg.enable_wave) \
                tfp->dump(time); \
        } while(0)
    #define DUMP_STOP() \
        do { \
            if (!cfg.wave_is_close) { \
                tfp->close(); \
                cfg.wave_is_close = true; \
            } \
        } while(0)
#else
    #define DUMP_WAVE(time) \
        do { \
        } while(0)
    #define DUMP_STOP() \
        do { \
        } while(0)
#endif

static vluint64_t main_time = 0;  // Current simulation time

double sc_time_stamp() {  // Called by $time in Verilog
    return main_time;     // converts to double, to match
                          // what SystemC does
}

void vlog_startup_routines_bootstrap(void);
void verilua_main_step(); // Verilua step

static inline void enter_verilua_loop() { verilua_schedule_loop(); }

static inline bool settle_value_callbacks() {
    bool cbs_called, again;

    // Call Value Change callbacks
    // These can modify signal values so we loop
    // until there are no more changes
    cbs_called = again = VerilatedVpi::callValueCbs();
    while (again) {
        again = VerilatedVpi::callValueCbs();
    }

    return cbs_called;
}

void verilator_next_sim_step(void *args) {
    if(Verilated::gotFinish()) {
        VL_FATAL(false, "Simulation end...");
    }

    top->eval_step();
    top->clock = top->clock ? 0 : 1;
    
    DUMP_WAVE(main_time);

    main_time += 5; 
}

void verilator_get_mode(void *mode_output) {
    int *mode_ptr = (int *)mode_output;

    int mode_defines = 0;
    int mode = 0;

#ifdef NORMAL_MODE
    mode_defines++;
    mode = (int)Verilua::VeriluaMode::Normal;
#endif

#ifdef DOMINANT_MODE
    mode_defines++;
    mode = (int)Verilua::VeriluaMode::Dominant;
#endif

#ifdef STEP_MODE
    mode_defines++;
    mode = (int)Verilua::VeriluaMode::Step;
#endif

    if (mode_defines > 1) {
        VL_FATAL(false, "multiple MODE macros are defined!");
    }

    *mode_ptr = mode;
}

void simulation_initializeTrace(void *traceFilePath) {
#if VM_TRACE
    cfg.trace_file = new char[strlen((char *)traceFilePath) + 1];
    strcpy(cfg.trace_file, (char *)traceFilePath);
    VL_INFO("initializeTrace trace_file:{}\n", cfg.trace_file);
#else
    VL_INFO("VM_TRACE is not defined!\n");
    assert(false);
#endif
}

void simulation_enableTrace(void *args) {
#if VM_TRACE
    cfg.enable_wave = true;
    cfg.wave_is_close = false;
    VL_INFO("simulation_enableTrace trace_file:{}\n", cfg.trace_file);
    DUMP_WAVE_INIT();
#else
    VL_INFO("VM_TRACE is not defined!\n");
    assert(false);
#endif
}

void simulation_disableTrace(void *args) {
#if VM_TRACE
    tfp->close();
    cfg.enable_wave = false;
    VL_INFO("simulation_disableTrace trace_file:{}\n", cfg.trace_file);
    DUMP_STOP();
#else
    VL_INFO("VM_TRACE is not defined!\n");
    assert(false);
#endif
}


static inline void end_of_simulation() {
    VerilatedVpi::callCbs(cbEndOfSimulation);
    top->final();

#if VM_TRACE
    tfp->close();
#endif

// VM_COVERAGE is a define which is set if Verilator is
// instructed to collect coverage (when compiling the simulation)
#if VM_COVERAGE
    VerilatedCov::write("coverage.dat");
#endif
}

inline int timming_mode_main(int argc, char** argv) {
    vlog_startup_routines_bootstrap();
    VerilatedVpi::callCbs(cbStartOfSimulation);

    DUMP_WAVE_INIT();

    while (!Verilated::gotFinish()) {
        // Call registered timed callbacks (e.g. clock timer)
        // These are called at the beginning of the time step
        // before the iterative regions (IEEE 1800-2012 4.4.1)
        VerilatedVpi::callTimedCbs();

        // Call Value Change callbacks triggered by Timer callbacks
        // These can modify signal values
        settle_value_callbacks();

        // We must evaluate whole design until we process all 'events'
        bool again = true;
        while (again) {
            // Evaluate design
            top->eval_step();

            // Call Value Change callbacks triggered by eval()
            // These can modify signal values
            again = settle_value_callbacks();

            // Call registered ReadWrite callbacks
            again |= VerilatedVpi::callCbs(cbReadWriteSynch);

            // Call Value Change callbacks triggered by ReadWrite callbacks
            // These can modify signal values
            again |= settle_value_callbacks();
        }
        top->eval_end_step();

        // Call ReadOnly callbacks
        VerilatedVpi::callCbs(cbReadOnlySynch);

        DUMP_WAVE(main_time);

        // cocotb controls the clock inputs using cbAfterDelay so
        // skip ahead to the next registered callback
        const vluint64_t NO_TOP_EVENTS_PENDING = static_cast<vluint64_t>(~0ULL);
        vluint64_t next_time_cocotb = VerilatedVpi::cbNextDeadline();
        vluint64_t next_time_timing =
            top->eventsPending() ? top->nextTimeSlot() : NO_TOP_EVENTS_PENDING;
        vluint64_t next_time = std::min(next_time_cocotb, next_time_timing);

        // If there are no more cbAfterDelay callbacks,
        // the next deadline is max value, so end the simulation now
        if (next_time == NO_TOP_EVENTS_PENDING) {
            break;
        } else {
            main_time = next_time;
        }

        // Call registered NextSimTime
        // It should be called in simulation cycle before everything else
        // but not on first cycle
        VerilatedVpi::callCbs(cbNextSimTime);

        // Call Value Change callbacks triggered by NextTimeStep callbacks
        // These can modify signal values
        settle_value_callbacks();
    }

    VerilatedVpi::callCbs(cbEndOfSimulation);

    top->final();

    DUMP_STOP();

// VM_COVERAGE is a define which is set if Verilator is
// instructed to collect coverage (when compiling the simulation)
#if VM_COVERAGE
    if(cfg.enable_coverage)
        VerilatedCov::write("coverage.dat");
#endif

    return 0;
}

inline int normal_mode_main(int argc, char** argv) {
    vlog_startup_routines_bootstrap();
    VerilatedVpi::callCbs(cbStartOfSimulation);

    DUMP_WAVE_INIT();

    static uint64_t wave_ticks = 20;
    while (!Verilated::gotFinish()) {
        // Call registered timed callbacks (e.g. clock timer)
        // These are called at the beginning of the time step
        // before the iterative regions (IEEE 1800-2012 4.4.1)
        VerilatedVpi::callTimedCbs();

        // Call Value Change callbacks triggered by Timer callbacks
        // These can modify signal values
        settle_value_callbacks();

        // We must evaluate whole design until we process all 'events'
        bool again = true;
        while (again) { 
            top->eval_step(); 
            again |= VerilatedVpi::callCbs(cbReadWriteSynch);
            again = settle_value_callbacks(); 
        }
        VerilatedVpi::callCbs(cbReadOnlySynch);

        if ((main_time % 10) == 0) {
            top->clock = top->clock ? 0 : 1; // Toggle clock
            top->eval_step();
        }

        top->eval_end_step();

        VerilatedVpi::callCbs(cbNextSimTime);

        // Call Value Change callbacks triggered by NextTimeStep callbacks
        // These can modify signal values
        settle_value_callbacks();
        // lua_main_step();

        DUMP_WAVE(main_time);
        
        main_time += 5;
    }

    VerilatedVpi::callCbs(cbEndOfSimulation);

    top->final();

    DUMP_STOP();

// VM_COVERAGE is a define which is set if Verilator is
// instructed to collect coverage (when compiling the simulation)
#if VM_COVERAGE
    if(cfg.enable_coverage)
        VerilatedCov::write("coverage.dat");
#endif

    return 0;
}

inline int dominant_mode_main(int argc, char** argv) {
    vlog_startup_routines_bootstrap();
    VerilatedVpi::callCbs(cbStartOfSimulation);

    DUMP_WAVE_INIT();

    static uint64_t wave_ticks = 20;
    
    enter_verilua_loop();

    VL_INFO("Leaving verilua_loop...\n");
    
    end_of_simulation();

#if VM_COVERAGE
    if(cfg.enable_coverage)
        VerilatedCov::write("coverage.dat");
#endif

    return 0;
}

inline int step_mode_main(int argc, char** argv) {
    vlog_startup_routines_bootstrap();
    VerilatedVpi::callCbs(cbStartOfSimulation);

    DUMP_WAVE_INIT();

    static uint64_t wave_ticks = 20;
    while (!Verilated::gotFinish()) {
        top->clock = 0;
        top->eval();
        top->clock = 1;
        top->eval();

        verilua_main_step();

        DUMP_WAVE(main_time);

        main_time += 5;
    }

    VerilatedVpi::callCbs(cbEndOfSimulation);

    top->final();

    DUMP_STOP();

// VM_COVERAGE is a define which is set if Verilator is
// instructed to collect coverage (when compiling the simulation)
#if VM_COVERAGE
    if(cfg.enable_coverage)
        VerilatedCov::write("coverage.dat");
#endif

    return 0;
}

int main(int argc, char** argv) {
    std::signal(SIGABRT, [](int sig){
        VL_INFO("accept SIGABRT\n");
        VerilatedVpi::callCbs(cbEndOfSimulation);
    });

    Verilated::commandArgs(argc, argv);
#ifdef VERILATOR_SIM_DEBUG
    Verilated::debug(99);
#endif
    Verilated::fatalOnVpiError(false);  // otherwise it will fail on systemtf

#ifdef VERILATOR_SIM_DEBUG
    Verilated::internalsDump();
#endif

    argparse::ArgumentParser program("verilator main for verilua");
    
    program.add_argument("-w", "--wave")
      .help("wave enable")
      .default_value(false)
      .implicit_value(true);
    
    program.add_argument("-c", "--cov")
      .help("coverage enable")
      .default_value(false)
      .implicit_value(true);

    try {
        program.parse_args(argc, argv);
    }
    catch (const std::runtime_error& err) {
        std::cerr << err.what() << std::endl;
        std::cerr << program;
        exit(1);
    }

    cfg.enable_wave = program.get<bool>("--wave");
    cfg.enable_coverage = program.get<bool>("--cov");

    Verilua::alloc_verilator_func(verilator_next_sim_step, "next_sim_step");
    Verilua::alloc_verilator_func(verilator_get_mode, "get_mode");
    Verilua::alloc_verilator_func(simulation_initializeTrace, "simulation_initializeTrace");
    Verilua::alloc_verilator_func(simulation_enableTrace, "simulation_enableTrace");
    Verilua::alloc_verilator_func(simulation_disableTrace, "simulation_disableTrace");
    

#ifdef NORMAL_MODE
    VL_INFO("using verilua NORMAL_MODE\n");
    return normal_mode_main(argc, argv);
#else
    #ifdef DOMINANT_MODE
        VL_INFO("using verilua DOMINANT_MODE\n");
        return dominant_mode_main(argc, argv);
    #else
        #ifdef STEP_MODE
            VL_INFO("using verilua STEP_MODE\n");
            return step_mode_main(argc, argv);
        #else
            VL_INFO("using verilua TIMMING_MODE\n");
            return timming_mode_main(argc, argv);
        #endif
    #endif
#endif

}
