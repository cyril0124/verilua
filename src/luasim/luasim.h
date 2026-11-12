#pragma once

#include "vpi_user.h"

#include <cstdint>

extern "C" {
// LuaJIT FFI binds these by unmangled name.
// All calls run on the simulator thread.

// Stable for the process lifetime; written only by the single simulation thread.
// Lua reads volatile fields directly and must never modify this status view.
struct luasim_status {
    uint32_t stopped, readonly, failed, sealed;
};
const volatile luasim_status *luasim_get_status();

// Kernel identity for tests and diagnostics.
const char *luasim_backend_kind();
// Publish a signal before the first task runs.
int luasim_declare(const char *path, int width);
// Apply time precision and the optional simulation limits.
void luasim_configure(int precision, uint64_t max_delta, uint64_t max_time, int has_max_time);
// Retained failure message, empty when the run is healthy.
const char *luasim_error();
// Append a failure message; the run latches it and stops.
void luasim_fail(const char *message);
// Mark the run stopped without closing it.
void luasim_stop();
// Freeze the signal table and write the initial VCD snapshot.
void luasim_seal();
// Open a VCD file for the remaining simulation.
int luasim_dump(const char *path);
// Toggle VCD recording without closing the file.
void luasim_dump_enabled(int enabled);
// Run queued VPI callbacks until the simulation stops.
int luasim_loop();
// Run end-of-simulation callbacks and release the engine once.
void luasim_close();

void luasim_set_top(const char *top);

// The VPI bootstrap registers start/end callbacks.
void vlog_startup_routines_bootstrap();
}
