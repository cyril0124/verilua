#include "luasim.h"

#include "luasim_engine.h"

#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <limits>

using namespace luasim_engine;

// Provided by libverilua: forwards to `vpi_control`.
extern "C" void c_simulator_control(long long command);

extern "C" void verilua_backend_fail(const char *message) {
    luasim_fail(message);
    c_simulator_control(vpiFinish);
}

extern "C" {
// Publishes pending edge subscriptions; pending values remain owned by Rust.
void vpiml_flush_callbacks();

// Looks up a declared path; an unknown name returns null so callers can probe.
vpiHandle vpi_handle_by_name(PLI_BYTE8 *name, vpiHandle) {
    auto found = engine.signals.find(name ? name : "");
    return found == engine.signals.end() ? nullptr : reinterpret_cast<vpiHandle>(found->second.get());
}

// Time properties ignore the handle; size and type apply to a signal.
PLI_INT32 vpi_get(PLI_INT32 property, vpiHandle handle) {
    if (property == vpiTimePrecision || property == vpiTimeUnit)
        return engine.precision;
    if (!handle)
        return 0;
    auto &signal = *reinterpret_cast<Signal *>(handle);
    if (property == vpiSize)
        return signal.width;
    if (property == vpiType)
        return vpiReg;
    if (property == vpiScalar)
        return signal.width == 1;
    if (property == vpiVector)
        return signal.width > 1;
    return 0;
}

// Returned strings point into the signal record, which lives until shutdown.
PLI_BYTE8 *vpi_get_str(PLI_INT32 property, vpiHandle handle) {
    static char reg[]   = "vpiReg";
    static char empty[] = "";
    if (property == vpiType)
        return reg;
    if (!handle)
        return empty;
    auto &signal = *reinterpret_cast<Signal *>(handle);
    if (property == vpiName)
        return signal.name.data();
    if (property == vpiFullName)
        return signal.path.data();
    return empty;
}

// Scalar and vector reads hand out stored words; string reads format into the signal buffer.
void vpi_get_value(vpiHandle handle, p_vpi_value value) {
    if (!handle || !value) {
        luasim_fail("invalid signal handle");
        return;
    }
    auto &signal = *reinterpret_cast<Signal *>(handle);
    switch (value->format) {
    case vpiIntVal:
        value->value.integer = signal.words[0].aval;
        return;
    case vpiVectorVal:
        value->value.vector = signal.words.data();
        return;
    case vpiBinStrVal:
        signal.text = binary(signal);
        break;
    case vpiOctStrVal:
        signal.text = digits(signal, 8);
        break;
    case vpiDecStrVal:
        signal.text = digits(signal, 10);
        break;
    case vpiHexStrVal:
        signal.text = digits(signal, 16);
        break;
    case vpiSuppressVal:
        return;
    default:
        luasim_fail("unsupported read format");
        return;
    }
    value->value.str = signal.text.data();
}

// Immediate writes only. A write never calls subscribers inline: it queues them, so the
// caller finishes before any dependent Lua task resumes.
vpiHandle vpi_put_value(vpiHandle handle, p_vpi_value value, p_vpi_time, PLI_INT32 flags) {
    if (engine.status.readonly) {
        luasim_fail("signal writes forbidden in read-only phase");
        return nullptr;
    }
    if (flags != vpiNoDelay) {
        luasim_fail("force/release and delayed VPI writes are unsupported");
        return nullptr;
    }
    if (!handle || !value) {
        luasim_fail("invalid signal handle");
        return nullptr;
    }
    auto &signal = *reinterpret_cast<Signal *>(handle);
    auto &words  = signal.scratch;
    if (!parse_value(signal, *value, words))
        return nullptr;
    // Publish pending subscriptions before the write so an immediate change reaches them.
    // Inside a merged batch Rust has not updated its counters yet.
    if (!engine.in_value_change)
        vpiml_flush_callbacks();
    bool changed = false;
    for (size_t i = 0; i < words.size(); ++i)
        changed |= words[i].aval != signal.words[i].aval;
    if (!changed)
        return nullptr;
    signal.words.swap(words);
    if (engine.wave_declared && engine.wave_enabled) {
        wave_at();
        wave_value(signal);
    }
    for (auto *callback = signal.subscribers; callback; callback = callback->signal_next) {
        Event event{callback, engine.now, signal.words[0].aval, {}};
        if (callback->value.format == vpiVectorVal)
            event.snapshot = signal.words;
        engine.ready.push_back(std::move(event));
    }
    return nullptr;
}

// Reports the current step; `real` mirrors the integer time for convenience.
void vpi_get_time(vpiHandle, p_vpi_time time) {
    if (!time)
        return;
    time->high = static_cast<uint32_t>(engine.now >> 32);
    time->low  = static_cast<uint32_t>(engine.now);
    time->real = static_cast<double>(engine.now);
}

// Each reason maps to the queue drained by the matching loop phase. Value-change
// subscriptions stay registered until `vpi_remove_cb`, one-shot events are retired when fired.
vpiHandle vpi_register_cb(p_cb_data data) {
    if (!data || !data->cb_rtn) {
        luasim_fail("invalid VPI callback");
        return nullptr;
    }
    uint64_t delay = data->time ? (uint64_t{data->time->high} << 32) | data->time->low : 0;
    if (engine.status.readonly && (data->reason == cbReadWriteSynch || (data->reason == cbAfterDelay && delay == 0))) {
        luasim_fail("cannot reenter read-write/zero-delay from read-only phase");
        return nullptr;
    }
    if (delay > std::numeric_limits<uint64_t>::max() - engine.now) {
        luasim_fail("timer overflow");
        return nullptr;
    }
    auto *callback = allocate_callback();
    callback->data = *data;
    if (data->time)
        callback->time = *data->time;
    if (data->value)
        callback->value = *data->value;
    callback->data.time  = &callback->time;
    callback->data.value = &callback->value;
    callback->serial     = ++engine.serial;
    Event event{callback, engine.now + delay, 0, {}};
    switch (data->reason) {
    case cbStartOfSimulation:
        engine.start.push_back(event);
        break;
    case cbEndOfSimulation:
        engine.finish.push_back(event);
        break;
    case cbAfterDelay:
        if (delay == 0)
            engine.delta.push_back(event);
        else {
            callback->future_queued = true;
            engine.future.push(std::move(event));
        }
        break;
    case cbNextSimTime:
        engine.next.push_back(event);
        break;
    case cbReadWriteSynch:
        engine.rw.push_back(event);
        break;
    case cbReadOnlySynch:
        engine.ro.push_back(event);
        break;
    case cbValueChange:
        if (!data->obj) {
            luasim_fail("value-change callback requires a signal");
            retire(*callback);
            return nullptr;
        }
        callback->signal          = reinterpret_cast<Signal *>(data->obj);
        callback->signal_previous = callback->signal->last_subscriber;
        if (callback->signal_previous)
            callback->signal_previous->signal_next = callback;
        else
            callback->signal->subscribers = callback;
        callback->signal->last_subscriber = callback;
        break;
    default:
        luasim_fail("unsupported VPI callback reason");
        retire(*callback);
        return nullptr;
    }
    return reinterpret_cast<vpiHandle>(callback);
}

// Removes a subscription; queued events observe the retired record as inactive.
PLI_INT32 vpi_remove_cb(vpiHandle handle) {
    if (!handle)
        return 0;
    retire(*reinterpret_cast<Callback *>(handle));
    return 1;
}

PLI_INT32 vpi_free_object(vpiHandle) { return 1; }
// Finish and stop close the engine and exit with the recorded status. Other controls are
// not modelled; a nested call from a final callback returns without exiting again.
PLI_INT32 vpi_control(PLI_INT32 operation, ...) {
    if (operation == vpiFinish || operation == vpiStop) {
        if (engine.finalizing)
            return 1;
        luasim_stop();
        luasim_close();
        if (!engine.error.empty())
            std::fprintf(stderr, "[luasim] %s\n", engine.error.c_str());
        std::exit(engine.error.empty() ? 0 : 1);
    } else
        luasim_fail("unsupported simulation control");
    return 1;
}

// Arrays are unsupported: the engine stores packed scalars only.
vpiHandle vpi_handle_by_index(vpiHandle, PLI_INT32) {
    luasim_fail("arrays are unsupported");
    return nullptr;
}

// Hierarchy is not discoverable; callers resolve signals by path.
vpiHandle vpi_iterate(PLI_INT32, vpiHandle) {
    luasim_fail("hierarchy iteration is unsupported");
    return nullptr;
}

vpiHandle vpi_scan(vpiHandle) { return nullptr; }
// Plain `vprintf`; the VPI formatting differences are not implemented.
PLI_INT32 vpi_printf(const char *format, ...) {
    va_list args;
    va_start(args, format);
    int result = std::vprintf(format, args);
    va_end(args);
    return result;
}
}
