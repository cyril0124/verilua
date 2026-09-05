// -------------------------------------------------------
// verilua_version.h — shared `--version` pre-scan for all
// Verilua CLI tools. Header-only, no link dependencies.
// -------------------------------------------------------
#pragma once

#include <cstdio>
#include <cstdlib>
#include <cstring>

#ifndef VERILUA_VERSION
#define VERILUA_VERSION "Unknown"
#endif

// Scan argv for `--version`; if found, print "<prog> <VERILUA_VERSION>" and
// exit(0). Call as the first statement of main(), before any argument parsing
// or environment-dependent initialization (VERILUA_HOME lookup, Lua bootstrap).
// Template param accepts both `char **argv` and `const char **argv`.
template <typename CharPtr> inline void verilua_check_version_arg(int argc, CharPtr *argv, const char *prog) {
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--version") == 0) {
            std::printf("%s %s\n", prog, VERILUA_VERSION);
            std::exit(0);
        }
    }
}
