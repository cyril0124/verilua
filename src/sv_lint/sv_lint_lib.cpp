// sv_lint shared library interface for LuaJIT FFI.
//
// Exposes a single C function:
//   int sv_lint_text(const char* sv_text, char* out_diag, int out_diag_size)
//
// Returns 0 on success, 1 on lint failure (diagnostic written to out_diag).

#include "sv_lint_core.h"

#include <cstring>

extern "C" {

int sv_lint_text(const char *sv_text, char *out_diag, int out_diag_size) {
    if (!sv_text || !out_diag || out_diag_size <= 0) {
        return 2;
    }
    out_diag[0] = '\0';

    auto result = sv_lint::lint(sv_text);
    if (!result.ok) {
        std::strncpy(out_diag, result.diagnostic.c_str(), out_diag_size - 1);
        out_diag[out_diag_size - 1] = '\0';
        return 1;
    }

    return 0;
}

} // extern "C"
