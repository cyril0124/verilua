#include <stdint.h>
#include <stdio.h>

extern "C" int32_t sym_add(int32_t a, int32_t b) { return a + b; }

extern "C" int32_t sym_mul(int32_t a, int32_t b) { return a * b; }
