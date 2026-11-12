#include "luasim.h"
#include "verilua_version.h"

#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <string>

namespace {
namespace fs = std::filesystem;

bool set_environment(const char *name, const std::string &value) {
    if (setenv(name, value.c_str(), 1) == 0)
        return true;
    std::fprintf(stderr, "[luasim] cannot set %s\n", name);
    return false;
}

fs::path install_root() {
    if (const char *home = std::getenv("VERILUA_HOME"); home && home[0])
        return home;
    std::error_code error;
    auto executable = fs::canonical("/proc/self/exe", error);
    if (error)
        return {};
    auto directory = executable.parent_path();
    if (directory.filename() == "tools")
        return directory.parent_path();
    if (directory.filename() == "bin" && directory.parent_path().filename() == "build") {
        return directory.parent_path().parent_path();
    }
    return {};
}

} // namespace

// With a leading `--`, the entry script comes from VL_CFG_FILE.
int main(int argc, const char **argv) {
    if (argc >= 2 && (std::string(argv[1]) == "--help" || std::string(argv[1]) == "-h")) {
        std::fprintf(stdout, "Usage: luasim [script.lua] [--] [script arguments...]\n");
        return 0;
    }
    if (argc >= 2 && std::string(argv[1]) == "--version") {
        // Limit the shared scanner to engine arguments; later --version belongs to the script.
        verilua_check_version_arg(2, argv, "luasim");
        return 0;
    }
    std::error_code error;
    bool has_script = false;
    fs::path script;
    if (argc >= 2 && argv[1][0] != '-') {
        script     = fs::canonical(argv[1], error);
        has_script = true;
        if (error || !fs::is_regular_file(script, error)) {
            std::fprintf(stderr, "[luasim] Lua script does not exist or is not a file: %s\n", argv[1]);
            return 2;
        }
    } else if (argc >= 2 && std::string(argv[1]) != "--") {
        std::fprintf(stderr, "[luasim] unknown option: %s\n", argv[1]);
        return 2;
    }
    if (!has_script && !std::getenv("VL_CFG_FILE")) {
        std::fprintf(stderr, "[luasim] pass a Lua script or set VL_CFG_FILE\n");
        return 2;
    }
    auto home = fs::absolute(install_root(), error);
    if (error || !fs::is_regular_file(home / "src/lua/verilua/init.lua", error)) {
        std::fprintf(stderr, "[luasim] set VERILUA_HOME to a valid Verilua installation\n");
        return 2;
    }
    // The activation script supplies the Lua module search path.
    if (std::getenv("LUA_PATH") == nullptr) {
        std::fprintf(stderr, "[luasim] LUA_PATH is not set; source the Verilua activation script first\n");
        return 2;
    }
    if (!set_environment("VERILUA_HOME", home.string()) || !set_environment("SIM", "luasim"))
        return 2;
    // Without a script argument the entry comes from the generated `cfg.script`.
    if (has_script && !set_environment("VL_LUA_SCRIPT", script.string()))
        return 2;
    std::atexit(luasim_close);
    vlog_startup_routines_bootstrap();
    luasim_loop();
    luasim_close();
    const char *failure = luasim_error();
    if (failure[0] != '\0') {
        std::fprintf(stderr, "[luasim] %s\n", failure);
        return 1;
    }
    return 0;
}
