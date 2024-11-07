#include "lua_vpi.h"
#include "Vtb_top.h"
#include "verilated.h"
#include "verilated_vpi.h"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <csignal>
#include <cstdlib>
#include <cassert>
#include <argparse/argparse.hpp>
#include "lightsss.h"

#ifndef VM_TRACE_FST
// emulate new verilator behavior for legacy versions
#define VM_TRACE_FST 0
#endif

#ifdef VM_TRACE
#if VM_TRACE_FST
#include <verilated_fst_c.h>
#else
#include <verilated_vcd_c.h>
#endif
#endif

void vlog_startup_routines_bootstrap(void);
void verilua_main_step(); // Verilua step
void verilua_schedule_loop(); // Only for dominant mode

static volatile int got_sigint = 0;
static volatile int got_sigabrt = 0;

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

static struct timeval boot_time = {};
uint32_t uptime(void) {
  struct timeval t;
  gettimeofday(&t, NULL);

  int s = t.tv_sec - boot_time.tv_sec;
  int us = t.tv_usec - boot_time.tv_usec;
  if (us < 0) {
    s--;
    us += 1000000;
  }

  return s * 1000 + (us + 500) / 1000;
}

struct EmuArgs {
    bool verbose           = false;
    bool enable_wave       = false;
    bool wave_is_enable    = false;
    bool wave_is_close     = false;
    char *trace_file       = "dump.vcd";
    bool enable_coverage   = false;
    bool enable_fork       = false;
    int fork_interval      = 1000;
};

class Emulator final {
private:
    Vtb_top *dut_ptr;
#if VM_TRACE
#if VM_TRACE_FST
    VerilatedFstC *tfp;
#else
    VerilatedVcdC *tfp;
#endif
#endif
    EmuArgs args;

    LightSSS *lightsss = nullptr;
    uint32_t lasttime_snapshot = 0;

public:
    Emulator(int argc, char *argv[]);
    ~Emulator();

    void start_simulation();
    void end_simulation();
    void dump_wave();
    void stop_dump_wave();

    inline bool is_fork_child() {
        return lightsss->is_child();
    }

    void fork_child_init();
    
    int lightsss_check_finish() {
        if(is_fork_child()) {
            auto cycles = dut_ptr->cycles_o;
            if(cycles != 0) {
                if (cycles == lightsss->get_end_cycles()) {
                    VL_WARN("checkpoint has reached the main process abort point: {}\n", cycles);
                }
                if (cycles == lightsss->get_end_cycles() + STEP_FORWARD_CYCLES) {
                    return -1;
                }
            }
        }
        return 0;
    }
    
    int lightsss_try_fork() {
        static bool have_initial_fork = false;
        uint32_t timer = uptime();

        // check if it's time to fork a checkpoint process
        if (((timer - lasttime_snapshot > args.fork_interval) || !have_initial_fork) && !is_fork_child()) {
            have_initial_fork = true;
            lasttime_snapshot = timer;
            switch (lightsss->do_fork()) {
                case FORK_ERROR: return -1;
                case FORK_CHILD: fork_child_init();
                default: break;
            }
        }
        return 0;
    }

    int normal_mode_main();
    int step_mode_main();
    int timming_mode_main();
    int dominant_mode_main();

    int run_main();

    void finalize();
};

Emulator::Emulator(int argc, char *argv[]) {
    dut_ptr = new Vtb_top("");

    argparse::ArgumentParser program("verilator main for verilua");
    
    program.add_argument("-w", "--wave").help("wave enable").default_value(false).implicit_value(true);
    program.add_argument("-c", "--cov").help("coverage enable").default_value(false).implicit_value(true);
    program.add_argument("-ef", "--enable-fork").help("enable folking child processes to debug").default_value(false).implicit_value(true);
    program.add_argument("-fi", "--fork-interval").help("LightSSS snapshot interval (in seconds)").default_value(1000).action([](const std::string &value) { return std::stoi(value); });

    try {
        program.parse_args(argc, argv);
    } catch (const std::runtime_error& err) {
        std::cerr << err.what() << std::endl;
        std::cerr << program;
        exit(1);
    }

    args.enable_wave = program.get<bool>("--wave");
    args.enable_coverage = program.get<bool>("--cov");
    args.enable_fork = program.get<bool>("--enable-fork");
    args.fork_interval = 1000 * program.get<int>("--fork-interval");

    if (args.enable_fork) {
        lightsss = new LightSSS;
        VL_INFO("enable fork debugging...\n");
    }

    Verilua::alloc_verilator_func([](void *mode_output) {
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
    }, "get_mode");

    std::function<void(void*)> next_sim_step = [this](void *params) {
        if(Verilated::gotFinish()) {
            VL_FATAL(false, "Simulation end...");
        }
        dut_ptr->eval_step();
        dut_ptr->clock = dut_ptr->clock ? 0 : 1;
        dut_ptr->eval_step();
        Verilated::timeInc(5);
    };
    Verilua::alloc_verilator_func(next_sim_step, "next_sim_step");

    std::function<void(void*)> simulation_initializeTrace = [this](void *traceFilePath) {
#if VM_TRACE
        args.trace_file = new char[strlen((char *)traceFilePath) + 1];
        strcpy(args.trace_file, (char *)traceFilePath);
        VL_INFO("initializeTrace trace_file:{}\n", args.trace_file);
        this->dump_wave();
#else
        VL_FATAL(false, "VM_TRACE is not defined!\n");
#endif
    };
    Verilua::alloc_verilator_func(simulation_initializeTrace, "simulation_initializeTrace");

    std::function<void(void*)> simulation_enableTrace = [this](void *params) {
#if VM_TRACE
        args.enable_wave = true;
        args.wave_is_close = false;
        VL_INFO("simulation_enableTrace trace_file:{}\n", args.trace_file);
        this->dump_wave();
#else
        VL_FATAL(false, "VM_TRACE is not defined!\n");
#endif
    };
    Verilua::alloc_verilator_func(simulation_enableTrace, "simulation_enableTrace");
    
    std::function<void(void*)> simulation_disableTrace = [this](void *params) {
#if VM_TRACE
        args.enable_wave = false;
        args.wave_is_enable = false;
        VL_INFO("simulation_disableTrace trace_file:{}\n", args.trace_file);
        this->stop_dump_wave();
#else
        VL_FATAL(false, "VM_TRACE is not defined!\n");
#endif        
    };
    Verilua::alloc_verilator_func(simulation_disableTrace, "simulation_disableTrace");
}

void Emulator::fork_child_init() {
#ifdef VERILATOR_VERSION_INTEGER // >= v4.220
#if VERILATOR_VERSION_INTEGER >= 5016000
    // This will cause 288 bytes leaked for each one fork call.
    // However, one million snapshots cause only 288MB leaks, which is still acceptable.
    // See verilator/test_regress/t/t_wrapper_clone.cpp:48 to avoid leaks.
    dut_ptr->atClone();
#else
#error Please use Verilator v5.016 or newer versions.
#endif                 // check VERILATOR_VERSION_INTEGER values
#else
#error Please use Verilator v5.016 or newer versions.
#endif


#if VM_TRACE
#if VM_TRACE_FST
    std::string trace_file = std::string(fmt::format("lightsss_checkpoint_{}.fst", dut_ptr->cycles_o));
    
#else
    std::string trace_file = std::string(fmt::format("lightsss_checkpoint_{}.vcd", dut_ptr->cycles_o));
#endif
    VL_WARN("the oldest checkpoint start to dump wave: {}\n", trace_file);
    args.trace_file = (char*)trace_file.c_str();
    args.enable_wave = true;
    args.wave_is_enable = false;
    args.wave_is_close = false;
#endif
    this->dump_wave();
}

void Emulator::start_simulation() {
    vlog_startup_routines_bootstrap();
    VerilatedVpi::callCbs(cbStartOfSimulation);
}

void Emulator::end_simulation() {
    VerilatedVpi::callCbs(cbEndOfSimulation);

    dut_ptr->final();

    this->stop_dump_wave();

// VM_COVERAGE is a define which is set if Verilator is
// instructed to collect coverage (when compiling the simulation)
#if VM_COVERAGE
    if(args.enable_coverage) {
        VerilatedCov::write("coverage.dat");
    }
#endif
}

void Emulator::dump_wave() {
#if VM_TRACE
    if(args.enable_wave && !args.wave_is_enable) {
        Verilated::traceEverOn(true);
#if VM_TRACE_FST
        tfp = new VerilatedFstC;
#else
        tfp = new VerilatedVcdC;
#endif
        dut_ptr->trace(tfp, 99);
        tfp->open(args.trace_file);
        args.wave_is_enable = true;
    }
#endif
}

void Emulator::stop_dump_wave() {
#if VM_TRACE
    if (!args.wave_is_close) {
        tfp->close();
        args.wave_is_close = true;
    }
#endif
}

int Emulator::normal_mode_main() {
    this->start_simulation();

    while (!Verilated::gotFinish() | got_sigint | got_sigabrt) {
        if (args.enable_fork) {
            lightsss_check_finish();
        }

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
            dut_ptr->eval_step(); 
            again |= VerilatedVpi::callCbs(cbReadWriteSynch);
            again = settle_value_callbacks(); 
        }
        VerilatedVpi::callCbs(cbReadOnlySynch);

        auto time = Verilated::time();
        if ((time % 10) == 0) {
            dut_ptr->eval_step();
            dut_ptr->clock = dut_ptr->clock ? 0 : 1; // Toggle clock
        }

        dut_ptr->eval_end_step();

        VerilatedVpi::callCbs(cbNextSimTime);

        // Call Value Change callbacks triggered by NextTimeStep callbacks
        // These can modify signal values
        settle_value_callbacks();

#if VM_TRACE
        if (args.enable_wave) {
            tfp->dump(time);
        }
#endif
        if (args.enable_fork && (lightsss_try_fork() == -1)) {
            return -1;
        }
        Verilated::timeInc(5);
    }

    this->end_simulation();

    if (args.enable_fork && !is_fork_child()) {
        int _ret = lightsss->do_clear();
        delete lightsss;
    }

    return 0;
}

int Emulator::step_mode_main() {
    this->start_simulation();

    while (!Verilated::gotFinish() | got_sigint | got_sigabrt) {
        if (args.enable_fork) {
            lightsss_check_finish();
        }

        dut_ptr->clock = 0;
        dut_ptr->eval();
        dut_ptr->clock = 1;
        dut_ptr->eval();

        verilua_main_step();

#if VM_TRACE
        if (args.enable_wave) {
            tfp->dump(Verilated::time());
        }
#endif

        if (args.enable_fork && (lightsss_try_fork() == -1)) {
            return -1;
        }
        Verilated::timeInc(5);
    }

    this->end_simulation();

    if (args.enable_fork && !is_fork_child()) {
        int _ret = lightsss->do_clear();
        delete lightsss;
    }

    return 0;
}

int Emulator::timming_mode_main() {
    this->start_simulation();

    // TODO: not checked!
    while (!Verilated::gotFinish() | got_sigint | got_sigabrt) {
        if (args.enable_fork) {
            lightsss_check_finish();
        }

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
            dut_ptr->eval_step();

            // Call Value Change callbacks triggered by eval()
            // These can modify signal values
            again = settle_value_callbacks();

            // Call registered ReadWrite callbacks
            again |= VerilatedVpi::callCbs(cbReadWriteSynch);

            // Call Value Change callbacks triggered by ReadWrite callbacks
            // These can modify signal values
            again |= settle_value_callbacks();
        }
        dut_ptr->eval_end_step();

        // Call ReadOnly callbacks
        VerilatedVpi::callCbs(cbReadOnlySynch);

#if VM_TRACE
        if (args.enable_wave) {
            tfp->dump(Verilated::time());
        }
#endif

        // cocotb controls the clock inputs using cbAfterDelay so
        // skip ahead to the next registered callback
        const vluint64_t NO_TOP_EVENTS_PENDING = static_cast<vluint64_t>(~0ULL);
        vluint64_t next_time_cocotb = VerilatedVpi::cbNextDeadline();
        vluint64_t next_time_timing =
            dut_ptr->eventsPending() ? dut_ptr->nextTimeSlot() : NO_TOP_EVENTS_PENDING;
        vluint64_t next_time = std::min(next_time_cocotb, next_time_timing);

        // If there are no more cbAfterDelay callbacks,
        // the next deadline is max value, so end the simulation now
        if (next_time == NO_TOP_EVENTS_PENDING) {
            break;
        } else {
            Verilated::time(next_time);
        }

        // Call registered NextSimTime
        // It should be called in simulation cycle before everything else
        // but not on first cycle
        VerilatedVpi::callCbs(cbNextSimTime);

        // Call Value Change callbacks triggered by NextTimeStep callbacks
        // These can modify signal values
        settle_value_callbacks();

        if (args.enable_fork && (lightsss_try_fork() == -1)) {
            return -1;
        }
    }

    this->end_simulation();

    if (args.enable_fork && !is_fork_child()) {
        int _ret = lightsss->do_clear();
        delete lightsss;
    }

    return 0;
}

int Emulator::dominant_mode_main() {
    this->start_simulation();

    // TODO: enable-fork for dominant mode
    // if (args.enable_fork) {
    //     lightsss_check_finish();
    // }
    
    verilua_schedule_loop();
    VL_INFO("Leaving verilua_loop...\n");

    // TODO: enable-fork for dominant mode
    // if (args.enable_fork && (lightsss_try_fork() == -1)) {
    //     return -1;
    // }

    this->end_simulation();

    if (args.enable_fork && !is_fork_child()) {
        int _ret = lightsss->do_clear();
        delete lightsss;
    }

    return 0;
}

void Emulator::finalize() {
    VL_INFO("finalize\n");
    fflush(stdout);

    dut_ptr->final();

#if VM_TRACE
    if (args.enable_wave) {
        Verilated::timeInc(5);
        tfp->dump(Verilated::time());
        tfp->flush();
    }
#endif

    if (args.enable_fork && !is_fork_child()) {
        VL_WARN("\nlightsss wakeup_child at {} cycles\n", dut_ptr->cycles_o);
        fflush(stdout);

        lightsss->wakeup_child(dut_ptr->cycles_o);
        delete lightsss;
    }

    delete dut_ptr;
#if VM_TRACE
    delete tfp;
#endif
}

Emulator::~Emulator() {
    // if (args.enable_fork && !is_fork_child()) {
    //     int _ret = lightsss->do_clear();
    //     delete lightsss;
    // }
}

int Emulator::run_main() {
#ifdef NORMAL_MODE
    VL_INFO("using verilua NORMAL_MODE\n");
    return normal_mode_main();
#endif

#ifdef STEP_MODE
    VL_INFO("using verilua STEP_MODE\n");
    return step_mode_main();
#endif

#ifdef TIMMING_MODE
    VL_INFO("using verilua TIMMING_MODE\n");
    return timming_mode_main(argc, argv);
#endif

#ifdef DOMINANT_MODE
    VL_INFO("using verilua DOMINANT_MODE\n");
    return dominant_mode_main(argc, argv);
#endif

    VL_FATAL(false, "unknown mode");
}

std::unique_ptr<Emulator> global_emu = nullptr;

void signal_handler(int signal) {
    Verilated::threadContextp()->gotError(true);
    Verilated::threadContextp()->gotFinish(true);
    Verilated::runFlushCallbacks();
    Verilated::runExitCallbacks();

    switch (signal) {
        case SIGABRT: 
            if(got_sigabrt == 0) {
                got_sigabrt = 1;

                VL_WARN(R"(
----------------------------------------------------------------------------
----   Verilator main get <SIGABRT>, the program will terminate...      ----
----------------------------------------------------------------------------
)");
                fflush(stdout);

                global_emu->finalize();
                VerilatedVpi::callCbs(cbEndOfSimulation);
                exit(1);
            }
            break;
        case SIGINT:
            if(got_sigint == 0) {
                got_sigint = 1;

                VL_WARN(R"(
---------------------------------------------------------------------------
----   Verilator main get <SIGINT>, the program will terminate...      ----
---------------------------------------------------------------------------
)");
                fflush(stdout);

                global_emu->finalize();
                VerilatedVpi::callCbs(cbEndOfSimulation);
                exit(0);
            }
            break;
        default:
            break;
    }
}

int main(int argc, char** argv) {
    gettimeofday(&boot_time, NULL);

    Verilated::commandArgs(argc, argv);
#ifdef VERILATOR_SIM_DEBUG
    Verilated::debug(99);
#endif
    Verilated::fatalOnVpiError(false);  // otherwise it will fail on systemtf

#ifdef VERILATOR_SIM_DEBUG
    Verilated::internalsDump();
#endif

    global_emu = std::make_unique<Emulator>(argc, argv);
    std::signal(SIGINT, signal_handler);
    std::signal(SIGABRT, signal_handler);

    return global_emu->run_main();
}