#include "wave_vpi.h"
#include "vpi_user.h"
#include "lua.hpp"

#include <signal.h>
#include <iostream>
#include <cpptrace/cpptrace.hpp>
#include <argparse/argparse.hpp>
#include <filesystem>

#ifndef VERILUA_VERSION
#define VERILUA_VERSION "Unknown"
#endif

int main(int argc, const char *argv[]) {
    lua_State *L = luaL_newstate(); // keep luajit symbols
    
    signal(SIGABRT, [](int sig) {
        fmt::println("[wave_vpi_main] SIGABRT");
        cpptrace::generate_trace().print(std::cerr, true); 
        exit(1);
    });

    signal(SIGSEGV, [](int sig) {
        fmt::println("[wave_vpi_main] SIGSEGV");
        cpptrace::generate_trace().print(std::cerr, true); 
        exit(1);
    });

#ifdef USE_FSDB
    argparse::ArgumentParser program("wave_vpi_main_fsdb", VERILUA_VERSION);
    program.add_argument("-w", "--wave-file")
        .default_value(std::string(""))
        .required()
        .help("input wave file for wave vpi(FSDB)");
#else
    argparse::ArgumentParser program("wave_vpi_main", VERILUA_VERSION);
    program.add_argument("-w", "--wave-file")
        .default_value(std::string(""))
        .required()
        .help("input wave file for wave vpi(VCD, FST)");
#endif


    try {
        program.parse_args(argc, argv);
    }
    catch (const std::exception& err) {
        std::cerr << err.what() << std::endl;
        std::cerr << program;
        return 1;
    }

    auto waveFile = std::string("");
    if(program.is_used("--wave-file")) {
        waveFile = std::filesystem::absolute(program.get<std::string>("--wave-file"));
    } else {
        auto _waveFile = std::getenv("WAVE_FILE");
        if(_waveFile == nullptr) {
            std::cerr << "[wave_vpi_main] either env var WAVE_FILE or command line argument --wave-file is required" << std::endl;
            std::cerr << program;
            return 1;
        } else {
            waveFile = std::string(_waveFile);
        }
    }
    
    fmt::println("[wave_vpi_main] waveFile is => {}", waveFile);
    std::cout << std::flush;

    fmt::println("[wave_vpi_main] init...");
    std::cout << std::flush;
    
    wave_vpi_init(waveFile.c_str());

    fmt::println("[wave_vpi_main] init finish!");
    std::cout << std::flush;

    fmt::println("[wave_vpi_main] start running wave_vpi_main()!");
    std::cout << std::flush;
    wave_vpi_main();
}

