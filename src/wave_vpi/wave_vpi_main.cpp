#include "wave_vpi.h"
#include "vpi_user.h"
#include "lua.hpp"

#include <signal.h>
#include <iostream>
#include <boost/stacktrace.hpp>
#include <argparse/argparse.hpp>
#include <filesystem>

int main(int argc, const char *argv[]) {
    lua_State *L = luaL_newstate(); // keep luajit symbols
    
    signal(SIGABRT, [](int sig) {
        std::cerr << boost::stacktrace::stacktrace() << std::endl;
        exit(1);
    });

    signal(SIGSEGV, [](int sig) {
        std::cerr << boost::stacktrace::stacktrace() << std::endl;
        exit(1);
    });

    argparse::ArgumentParser program("wave_vpi_main");

    program.add_argument("-w", "--wave-file")
        .default_value(std::string(""))
        .required()
        .help("input wave file for wave vpi");

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

