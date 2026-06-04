// A standalone shared library NOT linked into the simulator binary.
// SymbolHelper.get_global_symbol_addr should NOT find symbols from this .so.
#include <stdint.h>

int32_t ext_only_func(int32_t x) { return x + 1000; }

// Same as ext_only_func but with a different return offset, used to exercise
// the minimal form of try_ffi_cast through the ffi.C fallback path.
int32_t ext_only_func2(int32_t x) { return x + 2000; }

int32_t ext_undeclared_func(int32_t x) { return x * 3; }
