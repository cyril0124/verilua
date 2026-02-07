/// This file is modified from https://github.com/cocotb/cocotb/blob/master/src/cocotb/share/lib/verilator/verilator.cpp
/// with some modifications to satisfy this project.
///
/// To enable LightSSS, you need to add `ENABLE_LIGHTSSS` to defines:
/// e.g. (in your xmake.lua)
/// ```lua
///     add_defines("ENABLE_LIGHTSSS")
/// ```
///
/// To disable internal clock generation, you need to add `NO_INTERNAL_CLOCK` to defines:
/// e.g. (in your xmake.lua)
/// ```lua
///     add_defines("NO_INTERNAL_CLOCK")
/// ```

#include "Vtb_top.h"
#include "verilated.h"
#include "verilated_vpi.h"

#include "lightsss.h"
#include <cassert>
#include <csignal>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

#ifndef VERILATOR_STEP_TIME
// VERILATOR_STEP_TIME defines the time increment for each simulation step
// Value: 10000 (represents 10ns in timescale 1ns/1ps)
//
// Explanation:
// - Verilator uses integer values to represent time, where the unit is determined by the timescale precision
// - Timescale 1ns/1ps means: time unit = 1ns, time precision = 1ps
// - Verilator internally uses the precision (1ps) as the base unit for time representation
// - Therefore: 10000 units × 1ps/unit = 10000ps = 10ns
//
// Why 10ns?
// - CLK_PERIOD = 20000 (20ns for full clock cycle)
// - CLK_HALF_PERIOD = CLK_PERIOD / 2 = 10000 (10ns for clock toggle)
// - VERILATOR_STEP_TIME = CLK_HALF_PERIOD = 10000
// - Each Verilated::timeInc(VERILATOR_STEP_TIME) advances time by 10ns
// - The internal clock toggles every 10ns (see line ~402, ~486: dut_ptr->clock = !dut_ptr->clock)
#define VERILATOR_STEP_TIME 10000
#endif

// CLK_PERIOD controls the internal clock rate.
// For timescale 1ns/1ps (precision = 1ps), a 20ns clock period (10ns high, 10ns low)
// requires CLK_PERIOD = 20000 (20ns / 1ps = 20000 steps).
// Users can override this via -CFLAGS "-DVERILATOR_CLK_PERIOD=<value>"
#ifndef VERILATOR_CLK_PERIOD
#define VERILATOR_CLK_PERIOD 20000 // Default: 20ns period for 1ns/1ps timescale
#endif

const vluint64_t CLK_PERIOD      = VERILATOR_CLK_PERIOD; // Must be multiple of `VERILATOR_STEP_TIME`
const vluint64_t CLK_HALF_PERIOD = CLK_PERIOD / 2;

#ifndef VM_TRACE_FST
// emulate new verilator behavior for legacy versions
#define VM_TRACE_FST 0
#endif

#ifdef VM_TRACE
#if VM_TRACE_FST
#include <verilated_fst_c.h>
using verilated_trace_t = VerilatedFstC;
#else
#include <verilated_vcd_c.h>
using verilated_trace_t = VerilatedVcdC;
#endif
#endif

#define VL_INFO(...)                                                                                                                                                                                                                                                                                                                                                                                           \
    do {                                                                                                                                                                                                                                                                                                                                                                                                       \
        printf("[%s:%s:%d] [%sINFO%s] ", __FILE__, __FUNCTION__, __LINE__, ANSI_COLOR_MAGENTA, ANSI_COLOR_RESET);                                                                                                                                                                                                                                                                                              \
        printf(__VA_ARGS__);                                                                                                                                                                                                                                                                                                                                                                                   \
    } while (0)

#define VL_WARN(...)                                                                                                                                                                                                                                                                                                                                                                                           \
    do {                                                                                                                                                                                                                                                                                                                                                                                                       \
        printf("[%s:%s:%d] [%sWARN%s] ", __FILE__, __FUNCTION__, __LINE__, ANSI_COLOR_YELLOW, ANSI_COLOR_RESET);                                                                                                                                                                                                                                                                                               \
        printf(__VA_ARGS__);                                                                                                                                                                                                                                                                                                                                                                                   \
    } while (0)

#define VL_FATAL(cond, fmt, ...)                                                                                                                                                                                                                                                                                                                                                                               \
    do {                                                                                                                                                                                                                                                                                                                                                                                                       \
        if (!(cond)) {                                                                                                                                                                                                                                                                                                                                                                                         \
            printf("\n");                                                                                                                                                                                                                                                                                                                                                                                      \
            printf("[%s:%s:%d] [%sFATAL%s] ", __FILE__, __FUNCTION__, __LINE__, ANSI_COLOR_RED, ANSI_COLOR_RESET);                                                                                                                                                                                                                                                                                             \
            printf(fmt __VA_OPT__(, ) __VA_ARGS__);                                                                                                                                                                                                                                                                                                                                                            \
            printf("\n");                                                                                                                                                                                                                                                                                                                                                                                      \
            fflush(stdout);                                                                                                                                                                                                                                                                                                                                                                                    \
            fflush(stderr);                                                                                                                                                                                                                                                                                                                                                                                    \
            abort();                                                                                                                                                                                                                                                                                                                                                                                           \
        }                                                                                                                                                                                                                                                                                                                                                                                                      \
    } while (0)

typedef void (*VerilatorFunc)(void *);

extern "C" {
void verilua_alloc_verilator_func(VerilatorFunc func, const char *name);
void verilator_next_sim_time_callback(void);
void vlog_startup_routines_bootstrap(void);
}

static volatile int got_sigint  = 0;
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

    int s  = t.tv_sec - boot_time.tv_sec;
    int us = t.tv_usec - boot_time.tv_usec;
    if (us < 0) {
        s--;
        us += 1000000;
    }

    return s * 1000 + (us + 500) / 1000;
}

struct EmuArgs {
    bool verbose;
    bool enable_wave;
    bool wave_is_enable;
    bool wave_is_close;
    bool enable_fork;
    int fork_interval;
    std::string trace_file;
    std::string fork_trace_file;

    // clang-format off
    EmuArgs() :
        verbose(false),
        enable_wave(false),
        wave_is_enable(false),
        wave_is_close(false),
        enable_fork(false),
        fork_interval(1000),
        trace_file("dump.vcd"),
        fork_trace_file("")
    {}
    // clang-format on
};

class Emulator final {
  public:
    EmuArgs args;
#if VM_TRACE
    std::unique_ptr<verilated_trace_t> tfp;
#endif
    LightSSS *lightsss         = nullptr;
    uint32_t lasttime_snapshot = 0;

    Vtb_top *dut_ptr;

    Emulator(int argc, char *argv[]);
    ~Emulator();

    void start_simulation();
    void end_simulation(bool success = true);
    void dump_wave();
    void stop_dump_wave();

    inline bool is_fork_child() { return lightsss->is_child(); }

    void fork_child_init();

    int lightsss_check_finish() {
        if (is_fork_child()) {
            auto cycles = dut_ptr->cycles_o;
            if (cycles != 0) {
                if (cycles == lightsss->get_end_cycles()) {
                    VL_WARN("checkpoint has reached the main process abort point: %ld\n", cycles);
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
        uint32_t timer                = uptime();

        // check if it's time to fork a checkpoint process
        if (((timer - lasttime_snapshot > args.fork_interval) || !have_initial_fork) && !is_fork_child()) {
            have_initial_fork = true;
            lasttime_snapshot = timer;
            switch (lightsss->do_fork()) {
            case FORK_ERROR:
                return -1;
            case FORK_CHILD:
                fork_child_init();
            default:
                break;
            }
        }
        return 0;
    }

    int normal_mode_main();
    int timing_mode_main();

    int run_main();

    void finalize(bool success);
};

std::unique_ptr<Emulator> global_emu = nullptr;

extern "C" void _verilator_simulation_initializeTrace(void *traceFilePath) {
#if VM_TRACE
    global_emu->args.trace_file = std::string((char *)traceFilePath);
    VL_INFO("initializeTrace trace_file:%s\n", global_emu->args.trace_file.c_str());
    global_emu->dump_wave();
#else
    VL_FATAL(false, "VM_TRACE is not defined! Maybe you need to add verilator compile flags: `--trace`/`--trace-fst` to enable VM_TRACE.\n");
#endif
}

extern "C" void _verilator_simulation_enableTrace(void *param) {
#if VM_TRACE
    global_emu->args.enable_wave   = true;
    global_emu->args.wave_is_close = false;
    VL_INFO("simulation_enableTrace trace_file:%s\n", global_emu->args.trace_file.c_str());
    global_emu->dump_wave();
#else
    VL_FATAL(false, "VM_TRACE is not defined! Maybe you need to add verilator compile flags: `--trace`/`--trace-fst` to enable VM_TRACE.\n");
#endif
}

extern "C" void _verilator_simulation_disableTrace(void *param) {
#if VM_TRACE
    global_emu->args.enable_wave    = false;
    global_emu->args.wave_is_enable = false;
    VL_INFO("simulation_disableTrace trace_file:%s\n", global_emu->args.trace_file.c_str());
    global_emu->stop_dump_wave();
#else
    VL_FATAL(false, "VM_TRACE is not defined! Maybe you need to add verilator compile flags: `--trace`/`--trace-fst` to enable VM_TRACE.\n");
#endif
}

static void print_usage(const char *prog_name) {
    std::cerr << "Usage: " << prog_name << " [options]\n"
              << "Options:\n"
              << "  -ef, --enable-fork          Enable forking child processes to debug (LightSSS)\n"
              << "  -fi, --fork-interval <sec>  LightSSS snapshot interval in seconds (default: 1000)\n"
              << "  -ftf, --fork-trace-file <f> Wavefile name when LightSSS is enabled\n"
              << "  -h, --help                  Show this help message\n";
}

Emulator::Emulator(int argc, char *argv[]) {
    dut_ptr = new Vtb_top("");

    // Filter out verilog plusargs (starting with +)
    std::vector<std::string> filtered_args;
    for (int i = 1; i < argc; ++i) {
        if (argv[i] && argv[i][0] != '+') {
            filtered_args.push_back(argv[i]);
        }
    }

    // Parse arguments manually
    for (size_t i = 0; i < filtered_args.size(); ++i) {
        const std::string &arg = filtered_args[i];

        if (arg == "-h" || arg == "--help") {
            print_usage(argv[0]);
            exit(0);
        } else if (arg == "-ef" || arg == "--enable-fork") {
            args.enable_fork = true;
        } else if (arg == "-fi" || arg == "--fork-interval") {
            if (i + 1 >= filtered_args.size()) {
                std::cerr << "Error: " << arg << " requires an argument\n";
                print_usage(argv[0]);
                exit(1);
            }
            try {
                args.fork_interval = 1000 * std::stoi(filtered_args[++i]);
            } catch (const std::exception &e) {
                std::cerr << "Error: Invalid value for " << arg << ": " << filtered_args[i] << "\n";
                print_usage(argv[0]);
                exit(1);
            }
        } else if (arg == "-ftf" || arg == "--fork-trace-file") {
            if (i + 1 >= filtered_args.size()) {
                std::cerr << "Error: " << arg << " requires an argument\n";
                print_usage(argv[0]);
                exit(1);
            }
            args.fork_trace_file = filtered_args[++i];
        } else if (arg[0] == '-') {
            std::cerr << "Error: Unknown option: " << arg << "\n";
            print_usage(argv[0]);
            exit(1);
        }
        // Ignore non-option arguments (positional args)
    }

    if (args.enable_fork) {
#ifdef ENABLE_LIGHTSSS
        lightsss = new LightSSS;
        VL_INFO("enable fork debugging...\n");
#else
        VL_FATAL(false, "LightSSS is not enabled! Maybe you need to add `ENABLE_LIGHTSSS` to defines: `add_defines(\"ENABLE_LIGHTSSS\")`\n");
#endif
    }

    verilua_alloc_verilator_func(_verilator_simulation_initializeTrace, "simulation_initializeTrace");
    verilua_alloc_verilator_func(_verilator_simulation_enableTrace, "simulation_enableTrace");
    verilua_alloc_verilator_func(_verilator_simulation_disableTrace, "simulation_disableTrace");
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
#endif // check VERILATOR_VERSION_INTEGER values
#else
#error Please use Verilator v5.016 or newer versions.
#endif

#if VM_TRACE
#if VM_TRACE_FST
    std::string trace_file = "lightsss_checkpoint_" + std::to_string(dut_ptr->cycles_o) + ".fst";

#else
    std::string trace_file = "lightsss_checkpoint_" + std::to_string(dut_ptr->cycles_o) + ".vcd";
#endif
    if (args.fork_trace_file == "") {
        args.trace_file = trace_file;
    } else {
        args.trace_file = args.fork_trace_file;
    }
    VL_WARN("the oldest checkpoint start to dump wave: %s\n", args.trace_file.c_str());
    args.enable_wave    = true;
    args.wave_is_enable = false;
    args.wave_is_close  = false;
#endif
    this->dump_wave();
}

void Emulator::start_simulation() {
    vlog_startup_routines_bootstrap();
    VerilatedVpi::callCbs(cbStartOfSimulation);
}

void Emulator::end_simulation(bool success) {
    VerilatedVpi::callCbs(cbEndOfSimulation);
    this->finalize(success);
}

void Emulator::dump_wave() {
#if VM_TRACE
    if (args.enable_wave && !args.wave_is_enable) {
        Verilated::traceEverOn(true);
        tfp = std::make_unique<verilated_trace_t>();
        dut_ptr->trace(tfp.get(), 99);
        tfp->open(args.trace_file.c_str());
        args.wave_is_enable = true;
    }
#endif
}

void Emulator::stop_dump_wave() {
#if VM_TRACE
    if (!args.wave_is_close && tfp) {
        tfp->close();
        args.wave_is_close = true;
    }
#endif
}

int Emulator::normal_mode_main() {
    this->start_simulation();

    while ((!Verilated::gotFinish()) && !got_sigint && !got_sigabrt) {
#ifdef ENABLE_LIGHTSSS
        if (args.enable_fork) {
            if (lightsss_check_finish() == -1) {
                break;
            }
        }
#endif // ENABLE_LIGHTSSS

#ifndef NO_INTERNAL_CLOCK // Has internal clock
        if ((Verilated::time() > 0) && (Verilated::time() % CLK_HALF_PERIOD) == 0) {
            dut_ptr->clock = !dut_ptr->clock;
        }
#endif

        // Call registered timed callbacks (e.g. clock timer)
        // These are called at the beginning of the time step
        // before the iterative regions (IEEE 1800-2012 4.4.1)
        VerilatedVpi::callTimedCbs();
        settle_value_callbacks();

        do {
            // We must evaluate whole design until we process all 'events' for
            // this time step
            do {
                dut_ptr->eval_step();
                VerilatedVpi::clearEvalNeeded();
                VerilatedVpi::doInertialPuts();
                settle_value_callbacks();
            } while (VerilatedVpi::evalNeeded());

            // Run ReadWrite callback as we are done processing this eval step
            VerilatedVpi::callCbs(cbReadWriteSynch);
            VerilatedVpi::doInertialPuts();
            settle_value_callbacks();
        } while (VerilatedVpi::evalNeeded());

        dut_ptr->eval_end_step();

        VerilatedVpi::callCbs(cbReadOnlySynch);

#if VM_TRACE
        if (args.enable_wave) {
            tfp->dump(Verilated::time());
        }
#endif

        // Increse simulation time for 1ps(default) when timescale is 1ns/1ps
        Verilated::timeInc(VERILATOR_STEP_TIME);

        // Call registered NextSimTime
        // It should be called in simulation cycle before everything else
        // but not on first cycle
        verilator_next_sim_time_callback(); // libverilua feature `verilator_inner_step_callback` should be enabled
        VerilatedVpi::callCbs(cbNextSimTime);
        settle_value_callbacks();

        // TODO: Not work correctly
        // if (!dut_ptr->eventsPending()) {
        //     VL_INFO("No more events pending, finish simulation\n");
        //     break;
        // }

#ifdef ENABLE_LIGHTSSS
        if (args.enable_fork && (lightsss_try_fork() == -1)) {
            return -1;
        }
#endif
    }

    this->end_simulation();

    if (args.enable_fork && !is_fork_child()) {
        int _ret = lightsss->do_clear();
        delete lightsss;
    }

    return 0;
}

int Emulator::timing_mode_main() {
    this->start_simulation();

    // TODO: not checked!
    while ((!Verilated::gotFinish()) && !got_sigint && !got_sigabrt) {
#ifdef ENABLE_LIGHTSSS
        if (args.enable_fork) {
            if (lightsss_check_finish() == -1) {
                break;
            }
        }
#endif

#ifndef NO_INTERNAL_CLOCK // Has internal clock
        if ((Verilated::time() > 0) && (Verilated::time() % CLK_HALF_PERIOD) == 0) {
            dut_ptr->clock = !dut_ptr->clock;
        }
#endif

        // Call registered timed callbacks (e.g. clock timer)
        // These are called at the beginning of the time step
        // before the iterative regions (IEEE 1800-2012 4.4.1)
        VerilatedVpi::callTimedCbs();

        // Call Value Change callbacks triggered by Timer callbacks
        // These can modify signal values
        settle_value_callbacks();

        do {
            // We must evaluate whole design until we process all 'events' for
            // this time step
            do {
                dut_ptr->eval_step();
                VerilatedVpi::clearEvalNeeded();
                VerilatedVpi::doInertialPuts();
                settle_value_callbacks();
            } while (VerilatedVpi::evalNeeded());

            // Run ReadWrite callback as we are done processing this eval step
            VerilatedVpi::callCbs(cbReadWriteSynch);
            VerilatedVpi::doInertialPuts();
            settle_value_callbacks();
        } while (VerilatedVpi::evalNeeded());

        dut_ptr->eval_end_step();

        // Call ReadOnly callbacks
        VerilatedVpi::callCbs(cbReadOnlySynch);

#if VM_TRACE
        if (args.enable_wave) {
            tfp->dump(Verilated::time());
        }
#endif

        // Copied from cocotb:
        // cocotb controls the clock inputs using cbAfterDelay so
        // skip ahead to the next registered callback
        const vluint64_t NO_TOP_EVENTS_PENDING = static_cast<vluint64_t>(~0ULL);
        vluint64_t next_time_deadline          = VerilatedVpi::cbNextDeadline();
        vluint64_t next_time_timing            = dut_ptr->eventsPending() ? dut_ptr->nextTimeSlot() : NO_TOP_EVENTS_PENDING;
        vluint64_t next_time                   = std::min(next_time_deadline, next_time_timing);

        // If there are no more cbAfterDelay callbacks,
        // the next deadline is max value, so end the simulation now
#ifndef NO_INTERNAL_CLOCK // Has internal clock
        {
            // When using internal clock, always consider the next clock toggle boundary
            // as a pending event. This prevents time misalignment when cbAfterDelay
            // callbacks (e.g., await_time(1)) shift time to a non-CLK_HALF_PERIOD-aligned
            // value, which would cause the clock to never toggle again.
            vluint64_t current_time      = Verilated::time();
            vluint64_t next_clock_toggle = ((current_time / CLK_HALF_PERIOD) + 1) * CLK_HALF_PERIOD;
            next_time                    = std::min(next_time, next_clock_toggle);
            Verilated::time(next_time);
        }
#else
        if (next_time == NO_TOP_EVENTS_PENDING) {
            VL_INFO("[Timing Mode] [No Internal Clock] No more events pending, finish simulation\n");
            break;
        } else {
            Verilated::time(next_time);
        }
#endif

        // Call registered NextSimTime
        // It should be called in simulation cycle before everything else
        // but not on first cycle
        verilator_next_sim_time_callback(); // libverilua feature `verilator_inner_step_callback` should be enabled
        VerilatedVpi::callCbs(cbNextSimTime);
        settle_value_callbacks();

#ifdef ENABLE_LIGHTSSS
        if (args.enable_fork && (lightsss_try_fork() == -1)) {
            return -1;
        }
#endif
    }

    this->end_simulation();

    if (args.enable_fork && !is_fork_child()) {
        int _ret = lightsss->do_clear();
        delete lightsss;
    }

    return 0;
}

void Emulator::finalize(bool success = true) {
    if (!dut_ptr) {
        return;
    }

    VL_INFO("finalize\n");
    fflush(stdout);

#if defined(VERILATOR_VERSION_INTEGER) && VERILATOR_VERSION_INTEGER >= 5024000
    Verilated::threadContextp()->statsPrintSummary();
#endif

    dut_ptr->final();

#if VM_TRACE
    if (args.enable_wave) {
        Verilated::timeInc(5);
        tfp->dump(Verilated::time());
        tfp->flush();
        tfp->close();
        tfp.reset();
    }
#endif

    if (success) {
        // VM_COVERAGE is a define which is set if Verilator is
        // instructed to collect coverage (when compiling the simulation)
#if VM_COVERAGE
        /// Uses +verilator+coverage+file+<filename>
        /// defaults to coverage.dat
        /// e.g.(in your xmake.lua)
        /// ```lua
        ///     add_values("verilator.run_flags", "+verilator+coverage+file+another_coverage.dat")
        /// ```
        VerilatedCov::write();
#endif
    } else {
#ifdef ENABLE_LIGHTSSS
        if (args.enable_fork && !is_fork_child()) {
            VL_WARN("\nlightsss wakeup_child at %ld cycles\n", dut_ptr->cycles_o);
            fflush(stdout);

            lightsss->wakeup_child(dut_ptr->cycles_o);
            delete lightsss;
        }
#endif
    }

    delete dut_ptr;
    dut_ptr = nullptr;
}

Emulator::~Emulator() {
    // if (args.enable_fork && !is_fork_child()) {
    //     int _ret = lightsss->do_clear();
    //     delete lightsss;
    // }
}

int Emulator::run_main() {
    dut_ptr->clock = 0;
    dut_ptr->reset = 1;

#ifdef NORMAL_MODE
    VL_INFO("Using verilator in NORMAL_MODE\n");
    return normal_mode_main();
#endif

#ifdef TIMING_MODE
    VL_INFO("Using verilator in TIMING_MODE\n");
    return timing_mode_main();
#endif

    VL_FATAL(false, "Unknown mode");
}

void signal_handler(int signal) {
    Verilated::threadContextp()->gotError(true);
    Verilated::threadContextp()->gotFinish(true);

    switch (signal) {
    case SIGABRT:
        if (got_sigabrt == 0) {
            got_sigabrt = 1;

            VL_WARN(R"(
----------------------------------------------------------------------------
----   Verilator main get <SIGABRT>, the program will terminate...      ----
----------------------------------------------------------------------------
)");
            fflush(stdout);

            global_emu->end_simulation(false);
            // exit(1);
        }
        break;
    case SIGINT:
        if (got_sigint == 0) {
            got_sigint = 1;

            VL_WARN(R"(
---------------------------------------------------------------------------
----   Verilator main get <SIGINT>, the program will terminate...      ----
---------------------------------------------------------------------------
)");
            fflush(stdout);

            global_emu->end_simulation(false);
            exit(0);
        }
        break;
    default:
        break;
    }
}

int main(int argc, char **argv) {
    gettimeofday(&boot_time, NULL);

    Verilated::commandArgs(argc, argv);
#ifdef VERILATOR_SIM_DEBUG
    Verilated::debug(99);
#endif

#ifdef VERILATOR_FATAL_ON_VPI_ERROR
    Verilated::fatalOnVpiError(true);
#else
    Verilated::fatalOnVpiError(false); // otherwise it will fail on systemtf
#endif

#ifdef VERILATOR_SIM_DEBUG
    Verilated::internalsDump();
#endif

    global_emu = std::make_unique<Emulator>(argc, argv);
    std::signal(SIGINT, signal_handler);
    std::signal(SIGABRT, signal_handler);

    return global_emu->run_main();
}
