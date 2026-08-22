#include "wave_vpi.h"

#include <csignal>
#include <cstring>
#include <filesystem>
#include <iostream>

#ifdef USE_CPPTRACE
#include <cpptrace/cpptrace.hpp>
#endif

#ifndef VERILUA_VERSION
#define VERILUA_VERSION "Unknown"
#endif

int main(int argc, const char *argv[]) {
    signal(SIGABRT, [](int sig) {
        fmt::println("[wave_vpi::main] SIGABRT");
#ifdef USE_CPPTRACE
        cpptrace::generate_trace().print(std::cerr, true);
#endif
        _exit(1);
    });

    signal(SIGSEGV, [](int sig) {
        fmt::println("[wave_vpi::main] SIGSEGV");
#ifdef USE_CPPTRACE
        cpptrace::generate_trace().print(std::cerr, true);
#endif
        _exit(1);
    });

#ifdef USE_FSDB
    const char *prog     = "wave_vpi_main_fsdb";
    const char *waveHelp = "input wave file for wave vpi(FSDB)";
#else
    const char *prog     = "wave_vpi_main";
    const char *waveHelp = "input wave file for wave vpi(VCD, FST)";
#endif
    auto print_usage = [&]() {
        std::cerr << prog << " " << VERILUA_VERSION << "\n"
                  << "  -w, --wave-file FILE   " << waveHelp << "\n"
                  << "  --hierarchy-only       only load hierarchy, skip signal data and time table\n"
                  << "  -h, --help             show this help\n";
    };

    std::string waveFileArg;
    bool hierarchyOnly = false;
    for (int i = 1; i < argc; ++i) {
        const char *arg = argv[i];
        if (std::strcmp(arg, "-h") == 0 || std::strcmp(arg, "--help") == 0) {
            print_usage();
            return 0;
        }
        if (std::strcmp(arg, "--hierarchy-only") == 0) {
            hierarchyOnly = true;
            continue;
        }
        if (std::strcmp(arg, "-w") == 0 || std::strcmp(arg, "--wave-file") == 0) {
            if (i + 1 >= argc) {
                std::cerr << "missing value for " << arg << '\n';
                print_usage();
                return 1;
            }
            waveFileArg = argv[++i];
            continue;
        }
        std::cerr << "unknown argument: " << arg << '\n';
        print_usage();
        return 1;
    }

    auto waveFile = std::string("");
    if (!waveFileArg.empty()) {
        waveFile = std::filesystem::absolute(waveFileArg);
    } else {
        auto _waveFile = std::getenv("WAVE_FILE");
        if (_waveFile == nullptr) {
            std::cerr << "[wave_vpi::main] either env var WAVE_FILE or command line argument --wave-file is required" << std::endl;
            print_usage();
            return 1;
        }
        waveFile = std::string(_waveFile);
    }

    if (!is_quiet_mode()) {
        fmt::println("[wave_vpi::main] waveform: {}{}{}", ANSI_COLOR_GREEN, waveFile, ANSI_COLOR_RESET);
        std::cout << std::flush;

        fmt::println("[wave_vpi::main] initializing...");
        std::cout << std::flush;
    }

    // Expose the resolved waveform path for hierarchy cache mtime detection.
    setenv("VL_WAVEFORM_FILE", waveFile.c_str(), 1);

    // Bridge --hierarchy-only CLI flag to env var so all is_hierarchy_only_mode() checks work.
    if (hierarchyOnly) {
        setenv("WAVE_VPI_HIERARCHY_ONLY", "1", 1);
    }

    wave_vpi_init(waveFile.c_str());

    if (!is_quiet_mode()) {
        fmt::println("[wave_vpi::main] initialization finish!");
        std::cout << std::flush;

        fmt::println("[wave_vpi::main] start running wave_vpi_loop()!");
        std::cout << std::flush;
    }
    wave_vpi_loop();
}
