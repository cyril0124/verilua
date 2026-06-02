// signal_db_gen shared library interface for LuaJIT FFI.
//
// Exposes a single C function:
//   int signal_db_gen_main(const char* argList)
//
// Returns 0 on success, 1 when no regeneration needed, 2 on exception.

#include "signal_db_gen_core.h"

extern "C" int signal_db_gen_main(const char *argList) {
    try {
        WrappedDriver wDriver;

        // Parse command line to get `outfile` option
        ASSERT(wDriver.driver.parseCommandLine(std::string_view(argList)));
        wDriver.alreadyParsedCmdLine = true;

        std::string lockfilePath = wDriver.outfile.value_or(DEFAULT_OUTPUT_FILE) + ".lock";
        try {
            FileLock lock(lockfilePath);
            int ret = wDriver.parseCmdLine(std::string_view(argList));
            if (ret == 1) {
                wDriver.generateSignalDB();

                // Generate signal db successfully, return 0
                return 0;
            }

            // No need to generate signal db, return 1
            return 1;
        } catch (const std::exception &e) {
            PANIC("[signal_db_gen] Failed to lock file", lockfilePath, e.what());
        };
    } catch (const std::exception &e) {
        fmt::println(stderr, "[signal_db_gen] {}", e.what());

        // Exception occurred, return 2
        return 2;
    }
}
