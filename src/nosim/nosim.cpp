#include "nosim.h"
#include "vpi_compat.h"

extern "C" int signal_db_gen_main(const char *argList);

// VPI bootstrap function implemented by the user.
extern "C" void vlog_startup_routines_bootstrap();

int main(int argc, char **argv) {
    bool build = false;

    // Transform argVec into string
    std::string args;
    for (int i = 0; i < argc; i++) {
        std::string arg = argv[i];

        if (arg.ends_with("nosim")) {
            args += "signal_db_gen";
            args += " ";
            continue;
        }

        if (arg == "--build") {
            build = true;
            continue;
        }

        args += argv[i];
        if (i != argc - 1) {
            args += " ";
        }
    }

    if (build) {
        // Set enviroment variable `NOSIM_BUILD` to 1, which will be used in libverilua_nosim
        // to prevent automatically finalization of the simulation.
        setenv("NOSIM_BUILD", "1", 1);

        int ret = signal_db_gen_main(args.data());
        if (ret == 1) {
            // No signal_db generated
            return 0;
        } else if (ret == 2) {
            PANIC("signal_db_gen_main failed, Exception occurred!");
        }
    } else {
        setenv("NOSIM_RUN", "1", 1);

        vlog_startup_routines_bootstrap();

        vpi_compat::startOfSimulation();
        vpi_compat::endOfSimulation();
    }

    return 0;
}
