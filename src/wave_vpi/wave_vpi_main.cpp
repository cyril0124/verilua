#include "wave_vpi.h"

#include <argparse/argparse.hpp>
#include <csignal>
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
        exit(1);
    });

    signal(SIGSEGV, [](int sig) {
        fmt::println("[wave_vpi::main] SIGSEGV");
#ifdef USE_CPPTRACE
        cpptrace::generate_trace().print(std::cerr, true);
#endif
        exit(1);
    });

#ifdef USE_FSDB
    argparse::ArgumentParser program("wave_vpi_main_fsdb", VERILUA_VERSION);
    program.add_argument("-w", "--wave-file").default_value(std::string("")).required().help("input wave file for wave vpi(FSDB)");
#else
    argparse::ArgumentParser program("wave_vpi_main", VERILUA_VERSION);
    program.add_argument("-w", "--wave-file").default_value(std::string("")).required().help("input wave file for wave vpi(VCD, FST)");
#endif

    try {
        program.parse_args(argc, argv);
    } catch (const std::exception &err) {
        std::cerr << err.what() << std::endl;
        std::cerr << program;
        return 1;
    }

    auto waveFile = std::string("");
    if (program.is_used("--wave-file")) {
        waveFile = std::filesystem::absolute(program.get<std::string>("--wave-file"));
    } else {
        auto _waveFile = std::getenv("WAVE_FILE");
        if (_waveFile == nullptr) {
            std::cerr << "[wave_vpi::main] either env var WAVE_FILE or command line argument --wave-file is required" << std::endl;
            std::cerr << program;
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

    wave_vpi_init(waveFile.c_str());

    if (!is_quiet_mode()) {
        fmt::println("[wave_vpi::main] initialization finish!");
        std::cout << std::flush;

        fmt::println("[wave_vpi::main] start running wave_vpi_loop()!");
        std::cout << std::flush;
    }
    wave_vpi_loop();
}
