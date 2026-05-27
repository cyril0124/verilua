// A standalone shared library NOT linked into the simulator binary.
// SymbolHelper.get_global_symbol_addr should NOT find symbols from this .so.
#include <stdint.h>

int32_t ext_only_func(int32_t x) { return x + 1000; }

int32_t ext_undeclared_func(int32_t x) { return x * 3; }
