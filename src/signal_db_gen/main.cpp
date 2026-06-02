// signal_db_gen — CLI binary entry point.

#include "signal_db_gen_core.h"

int main(int argc, char **argv) {
    try {
        OS::setupConsole();
        WrappedDriver wDriver;

        // Parse command line to get `outfile` option
        ASSERT(wDriver.driver.parseCommandLine(argc, argv));
        wDriver.alreadyParsedCmdLine = true;

        std::string lockfilePath = wDriver.outfile.value_or(DEFAULT_OUTPUT_FILE) + ".lock";
        try {
            FileLock lock(lockfilePath);
            int ret = wDriver.parseCmdLine(argc, argv);
            if (ret == 1) {
                wDriver.generateSignalDB();
                // SIGNALDB_SUCCESS = 0
                return 0;
            }
            // SIGNALDB_NO_NEED_GEN = 1
            return 1;
        } catch (const std::exception &e) {
            PANIC("[signal_db_gen] Failed to lock file", lockfilePath, e.what());
        };
    } catch (const std::exception &e) {
        fmt::println(stderr, "[signal_db_gen] {}", e.what());
        // SIGNALDB_EXCEPTION_OCCURRED = 2
        return 2;
    }
    // Should not reach here
    return 0;
}
