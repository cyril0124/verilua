// sv_lint — lightweight SystemVerilog lint tool backed by slang.
//
// Usage:
//   sv_lint --text '<sv_code>'
//
// Runs slang lint-only on the provided SV text. Exits 0 on success, 1 on
// lint failure (first diagnostic printed to stderr).

#include "sv_lint_core.h"

#include "fmt/core.h"

#include <cstring>

static void printUsage() { fmt::println(stderr, "Usage: sv_lint --text '<sv_code>'"); }

int main(int argc, char *argv[]) {
    std::string svText;

    // Parse arguments: --text '<code>'
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--text") == 0) {
            if (i + 1 < argc) {
                svText = argv[++i];
            } else {
                fmt::println(stderr, "Error: --text requires an argument");
                return 2;
            }
        } else if (std::strcmp(argv[i], "--help") == 0 || std::strcmp(argv[i], "-h") == 0) {
            printUsage();
            return 0;
        } else {
            fmt::println(stderr, "Error: unknown argument '{}'", argv[i]);
            printUsage();
            return 2;
        }
    }

    if (svText.empty()) {
        fmt::println(stderr, "Error: no input provided. Use --text '<sv_code>'");
        printUsage();
        return 2;
    }

    auto result = sv_lint::lint(svText);
    if (!result.ok) {
        fmt::print(stderr, "{}", result.diagnostic);
        return 1;
    }

    return 0;
}
