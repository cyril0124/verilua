#include "nosim.h"
#include "verilua_version.h"
#include "vpi_compat.h"

#include "fmt/ranges.h"

#include <string>
#include <string_view>
#include <vector>

extern "C" int signal_db_gen_main(const char *argList);

// VPI bootstrap function implemented by the user.
extern "C" void vlog_startup_routines_bootstrap();

int main(int argc, char **argv) {
    verilua_check_version_arg(argc, argv, "nosim");

    bool build = false;

    // `signal_db_gen_main` takes a single command-line string, so rebuild `argv` into one.
    // The first token becomes the program name in help and error output: report `signal_db_gen`
    // rather than the `nosim` executable that is being run.
    std::vector<std::string> args;
    args.reserve(static_cast<size_t>(argc));
    for (int i = 0; i < argc; i++) {
        if (i == 0) {
            args.emplace_back("signal_db_gen");
            continue;
        }

        if (std::string_view(argv[i]) == "--build") {
            build = true;
            continue;
        }

        args.emplace_back(argv[i]);
    }

    std::string argList = fmt::format("{}", fmt::join(args, " "));

    if (build) {
        // Set environment variable `VL_NOSIM_BUILD` to 1, which `libverilua_nosim` reads to
        // disable automatic finalization of the simulation.
        setenv("VL_NOSIM_BUILD", "1", 1);

        int ret = signal_db_gen_main(argList.c_str());
        if (ret == 1) {
            // No signal_db generated
            return 0;
        } else if (ret == 2) {
            PANIC("signal_db_gen_main failed, Exception occurred!");
        }
    } else {
        vlog_startup_routines_bootstrap();

        vpi_compat::startOfSimulation();
        vpi_compat::endOfSimulation();
    }

    return 0;
}
