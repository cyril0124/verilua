#include "luasim.h"

#include "luasim_engine.h"

extern "C" {
// Pending values remain owned by Rust(libverilua).
// TODO: Consider isolating the Rust side from the C++ side, so that the C++ side can be used independently.
void libverilua_register_rw_synch_cb();
void vpiml_flush_callbacks();
}

#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <new>
#include <stdexcept>

namespace luasim_engine {

// One engine for the whole run; this loop and the VPI shims both reach it, and
// every call happens on the simulator thread.
Engine engine;

// A record survives while its registration or any queued event still points at it.
void release_callback(Callback *callback) {
    if (--callback->references != 0)
        return;
    // Cache a bounded number of records; bursts do not establish a permanent high-water mark.
    if (engine.free_callbacks.size() < 256)
        engine.free_callbacks.push_back(callback);
    else
        delete callback;
}

// Recycled records are cleared first, so a reused slot carries no previous state.
Callback *allocate_callback() {
    Callback *callback;
    if (engine.free_callbacks.empty())
        callback = new Callback;
    else {
        callback = engine.free_callbacks.back();
        engine.free_callbacks.pop_back();
        *callback = Callback{};
    }
    callback->active_next = engine.callbacks;
    if (engine.callbacks)
        engine.callbacks->active_previous = callback;
    engine.callbacks = callback;
    return callback;
}

// Retiring unlinks the callback from the active and signal lists and drops its
// own reference; queued events keep theirs until they are dispatched or popped.
void retire(Callback &callback) {
    if (!callback.active)
        return;
    callback.active = false;
    if (callback.signal) {
        if (callback.signal_previous)
            callback.signal_previous->signal_next = callback.signal_next;
        else
            callback.signal->subscribers = callback.signal_next;
        if (callback.signal_next)
            callback.signal_next->signal_previous = callback.signal_previous;
        else
            callback.signal->last_subscriber = callback.signal_previous;
    }
    if (callback.active_previous)
        callback.active_previous->active_next = callback.active_next;
    else
        engine.callbacks = callback.active_next;
    if (callback.active_next)
        callback.active_next->active_previous = callback.active_previous;
    if (callback.future_queued)
        ++engine.cancelled_future;
    release_callback(&callback);
    // Scan only when dead entries dominate: cancellation is amortized O(1) plus heap rebuilding.
    if (engine.cancelled_future >= 64 && engine.cancelled_future >= engine.future.size() / 2) {
        engine.future.compact();
        engine.cancelled_future = 0;
    }
}

void pop_future() {
    auto &callback         = *engine.future.top().callback;
    callback.future_queued = false;
    if (!callback.active)
        --engine.cancelled_future;
    engine.future.pop();
}

// VCD binary form is MSB first, while words store bit 0 as the least significant bit.
std::string binary(const Signal &signal) {
    std::string result(signal.width, '0');
    for (int bit = 0; bit < signal.width; ++bit) {
        if ((signal.words[bit / 32].aval >> (bit % 32)) & 1U)
            result[signal.width - bit - 1] = '1';
    }
    return result;
}

// Repeated long division converts the packed words; hex output is padded to nibble width.
std::string digits(const Signal &signal, unsigned base) {
    std::vector<uint32_t> words;
    for (const auto &word : signal.words)
        words.push_back(word.aval);
    std::string result;
    do {
        uint64_t remainder = 0;
        for (size_t i = words.size(); i > 0; --i) {
            uint64_t value = (remainder << 32) | words[i - 1];
            words[i - 1]   = static_cast<uint32_t>(value / base);
            remainder      = value % base;
        }
        result.push_back("0123456789abcdef"[remainder]);
        while (!words.empty() && words.back() == 0)
            words.pop_back();
    } while (!words.empty());
    std::reverse(result.begin(), result.end());
    if (base == 16)
        result.insert(0, (static_cast<size_t>(signal.width) + 3) / 4 - result.size(), '0');
    return result;
}

// Timestamp lines are emitted at most once per time step.
void wave_at() {
    if (engine.wave_time != engine.now) {
        engine.wave << '#' << engine.now << '\n';
        engine.wave_time = engine.now;
    }
}

// VCD writes scalars as `<bit><id>` and vectors as `b<bits> <id>`.
void wave_value(const Signal &signal) {
    if (signal.width == 1)
        engine.wave << binary(signal) << 'v' << signal.id << '\n';
    else
        engine.wave << 'b' << binary(signal) << " v" << signal.id << '\n';
}

// Declares the flat signal list under the nested scopes built from the signal paths.
void declare_scope(const Scope &scope) {
    for (const auto *signal : scope.signals) {
        engine.wave << "$var wire " << signal->width << " v" << signal->id << ' ' << signal->name << " $end\n";
    }
    for (const auto &[name, child] : scope.children) {
        engine.wave << "$scope module " << name << " $end\n";
        declare_scope(child);
        engine.wave << "$upscope $end\n";
    }
}

// The header is written once: scope tree, variable declarations, then the initial values.
void seal_wave() {
    if (!engine.wave.is_open() || engine.wave_declared)
        return;
    engine.wave_declared = true;
    const char *units[]  = {"fs", "ps", "ns", "us", "ms", "s"};
    int index            = (engine.precision + 15) / 3;
    int scale            = 1;
    for (int i = 0; i < (engine.precision + 15) % 3; ++i)
        scale *= 10;
    engine.wave << "$timescale " << scale << units[index] << " $end\n";
    Scope root;
    for (auto *signal : engine.declaration_order) {
        Scope *scope = &root;
        size_t begin = 0;
        size_t dot;
        while ((dot = signal->path.find('.', begin)) != std::string::npos) {
            scope = &scope->children[signal->path.substr(begin, dot - begin)];
            begin = dot + 1;
        }
        scope->signals.push_back(signal);
    }
    declare_scope(root);
    engine.wave << "$enddefinitions $end\n";
    wave_at();
    engine.wave << "$dumpvars\n";
    for (const auto *signal : engine.declaration_order)
        wave_value(*signal);
    engine.wave << "$end\n";
}

// Guards the zero-delay loop; every dispatched batch advances this counter.
bool check_delta_limit() {
    if (++engine.rounds > engine.max_delta) {
        luasim_fail("max_delta_cycles exceeded (zero-time loop)");
        return false;
    }
    return true;
}

void dispatch(std::deque<Event> &queue, bool finalizing = false) {
    // A complete ready batch precedes events generated by any of its callbacks.
    std::deque<Event> batch;
    batch.swap(queue);
    if (!finalizing && !check_delta_limit())
        return;
    for (auto &event : batch) {
        if (engine.status.stopped && !finalizing)
            break;
        auto &callback = *event.callback;
        if (!valid(callback))
            continue;
        bool persistent = callback.data.reason == cbValueChange;
        if (!persistent) {
            retire(callback);
        }
        callback.time.high = static_cast<uint32_t>(engine.now >> 32);
        callback.time.low  = static_cast<uint32_t>(engine.now);
        if (persistent) {
            if (callback.value.format == vpiIntVal)
                callback.value.value.integer = event.integer;
            else if (callback.value.format == vpiVectorVal)
                callback.value.value.vector = event.snapshot.data();
        }
        if (callback.data.cb_rtn) {
            engine.in_value_change = callback.data.reason == cbValueChange;
            callback.data.cb_rtn(&callback.data);
            engine.in_value_change = false;
        }
    }
}

// Two-state only: any X/Z digit is reported as unsupported. The top word is masked
// so bits above the declared width never reach the simulation.
bool parse_value(const Signal &signal, const s_vpi_value &value, std::vector<s_vpi_vecval> &words) {
    words.assign(signal.words.size(), s_vpi_vecval{});
    if (value.format == vpiIntVal)
        words[0].aval = static_cast<uint32_t>(value.value.integer);
    else if (value.format == vpiVectorVal) {
        if (!value.value.vector) {
            luasim_fail("null vector value");
            return false;
        }
        for (size_t i = 0; i < words.size(); ++i) {
            if (value.value.vector[i].bval) {
                luasim_fail("X/Z values are unsupported");
                return false;
            }
            words[i] = value.value.vector[i];
        }
    } else {
        unsigned base;
        switch (value.format) {
        case vpiBinStrVal:
            base = 2;
            break;
        case vpiOctStrVal:
            base = 8;
            break;
        case vpiDecStrVal:
            base = 10;
            break;
        case vpiHexStrVal:
            base = 16;
            break;
        default:
            luasim_fail("unsupported value format");
            return false;
        }
        const char *digits = value.value.str;
        if (!digits || !digits[0]) {
            luasim_fail("empty signal value");
            return false;
        }
        // `0d` marks an explicit decimal value, as `0x` and `0b` do for the other bases.
        if (base == 10 && digits[0] == '0' && (digits[1] == 'd' || digits[1] == 'D'))
            digits += 2;
        for (const char *cursor = digits; *cursor; ++cursor) {
            unsigned char c = static_cast<unsigned char>(*cursor);
            if (c == '_')
                continue;
            unsigned digit = std::isdigit(c) ? c - '0' : std::tolower(c) - 'a' + 10;
            if (digit >= base) {
                luasim_fail("invalid two-state value (X/Z unsupported)");
                return false;
            }
            uint64_t carry = digit;
            for (auto &word : words) {
                carry += static_cast<uint64_t>(static_cast<uint32_t>(word.aval)) * base;
                word.aval = static_cast<uint32_t>(carry);
                carry >>= 32;
            }
        }
    }
    if (signal.width % 32)
        words.back().aval &= (uint32_t{1} << (signal.width % 32)) - 1;
    return true;
}

} // namespace luasim_engine

using namespace luasim_engine;

extern "C" {
const char *luasim_backend_kind() { return "cpp"; }
const volatile luasim_status *luasim_get_status() { return &engine.status; }
const char *luasim_error() { return engine.error.c_str(); }
// Every failure is appended, so a later one never hides the first; the status view
// latches the failure and stops the loop.
void luasim_fail(const char *message) {
    if (!engine.error.empty())
        engine.error += "\n";
    engine.error += message ? message : "unknown native error";
    engine.status.failed  = 1;
    engine.status.stopped = true;
}

void luasim_set_top(const char *top) {
    if (!top || setenv("VL_DUT_TOP", top, 1) != 0)
        luasim_fail("cannot publish configured top module");
}

void luasim_stop() { engine.status.stopped = true; }
// `precision` is the power of ten in seconds (vpiTimePrecision form); limits are step counts.
void luasim_configure(int precision, uint64_t max_delta, uint64_t max_time, int has_max_time) {
    if (precision < -15 || precision > 0 || max_delta == 0) {
        luasim_fail("invalid luasim configuration");
        return;
    }
    engine.precision    = precision;
    engine.max_delta    = max_delta;
    engine.max_time     = max_time;
    engine.has_max_time = has_max_time;
}

// Paths are dot-separated and fully qualified; a signal and a scope may not share a name.
int luasim_declare(const char *path, int width) try {
    if (engine.status.sealed) {
        luasim_fail("signals must be declared before the first task starts");
        return 0;
    }
    if (width <= 0 || width > std::numeric_limits<PLI_INT32>::max()) {
        luasim_fail("signal width must fit positive signed 32-bit VPI size");
        return 0;
    }
    std::string name = path ? path : "";
    bool beginning   = true;
    bool qualified   = false;
    for (unsigned char c : name) {
        if (c == '.' && !beginning) {
            beginning = true;
            qualified = true;
            continue;
        }
        if (!(std::isalpha(c) || c == '_' || (!beginning && (c == '$' || std::isdigit(c))))) {
            luasim_fail("invalid signal path");
            return 0;
        }
        beginning = false;
    }
    if (beginning || !qualified) {
        luasim_fail("signal path must be fully qualified");
        return 0;
    }
    if (engine.signals.count(name)) {
        luasim_fail("duplicate signal path");
        return 0;
    }
    const std::string scope_prefix = name + ".";
    auto descendant                = engine.signals.lower_bound(scope_prefix);
    if (descendant != engine.signals.end() && descendant->first.starts_with(scope_prefix)) {
        luasim_fail("signal path conflicts with a scope");
        return 0;
    }
    for (size_t dot = name.find('.'); dot != std::string::npos; dot = name.find('.', dot + 1)) {
        if (engine.signals.count(name.substr(0, dot))) {
            luasim_fail("signal path conflicts with a scope");
            return 0;
        }
    }
    auto signal             = std::make_unique<Signal>();
    signal->path            = name;
    signal->name            = name.substr(name.rfind('.') + 1);
    signal->width           = width;
    signal->id              = engine.declaration_order.size() + 1;
    const size_t word_count = (static_cast<size_t>(width) + 31) / 32;
    signal->words.resize(word_count);
    auto *declared = signal.get();
    engine.signals.emplace(name, std::move(signal));
    engine.declaration_order.push_back(declared);
    return 1;
} catch (const std::bad_alloc &) {
    luasim_fail("cannot allocate packed signal storage");
    return 0;
} catch (const std::length_error &) {
    luasim_fail("packed signal allocation exceeds container capacity");
    return 0;
}

void luasim_seal() {
    engine.status.sealed = true;
    seal_wave();
}

int luasim_dump(const char *path) {
    if (engine.wave.is_open()) {
        luasim_fail("waveform already opened");
        return 0;
    }
    engine.wave.open(path);
    if (!engine.wave) {
        luasim_fail("cannot open waveform file");
        return 0;
    }
    if (engine.status.sealed)
        seal_wave();
    return 1;
}

void luasim_dump_enabled(int enabled) {
    // Repeated enable only repeats the state; the header snapshot already carried the values.
    if (engine.wave_enabled == (enabled != 0)) {
        engine.wave_enabled = enabled;
        return;
    }
    engine.wave_enabled = enabled;
    if (engine.wave_declared) {
        wave_at();
        engine.wave << (enabled ? "$dumpon\n" : "$dumpoff\n");
        if (enabled)
            for (auto *signal : engine.declaration_order)
                wave_value(*signal);
        engine.wave << "$end\n";
    }
}

// Callbacks run in phase order: ready, read-write, zero-delay, read-only. Only when all
// of them are empty does time advance to the next scheduled timestamp.
int luasim_loop() {
    if (!engine.start.empty())
        dispatch(engine.start);
    if (!engine.status.stopped)
        libverilua_register_rw_synch_cb();
    while (!engine.status.stopped) {
        vpiml_flush_callbacks();
        if (!engine.ready.empty()) {
            dispatch(engine.ready);
            continue;
        }
        if (!engine.rw.empty()) {
            dispatch(engine.rw);
            continue;
        }
        if (!engine.delta.empty()) {
            dispatch(engine.delta);
            continue;
        }
        if (!engine.ro.empty()) {
            engine.status.readonly = true;
            dispatch(engine.ro);
            continue;
        }
        while (!engine.future.empty() && !valid(*engine.future.top().callback))
            pop_future();
        if (engine.future.empty())
            break;
        uint64_t next_time = engine.future.top().time;
        if (engine.has_max_time && next_time > engine.max_time) {
            luasim_fail("max_time exceeded");
            break;
        }
        engine.now             = next_time;
        engine.status.readonly = false;
        engine.rounds          = 0;
        // Next-time callbacks install pending subscriptions before any timed activity.
        while (!engine.next.empty()) {
            engine.ready.push_back(std::move(engine.next.front()));
            engine.next.pop_front();
        }
        while (!engine.future.empty() && engine.future.top().time == next_time) {
            engine.ready.push_back(engine.future.top());
            pop_future();
        }
    }
    return engine.error.empty() ? 0 : 1;
}

// Idempotent shutdown: end-of-simulation callbacks run first, then the waveform is
// flushed and every remaining callback record is released.
void luasim_close() {
    if (engine.closed)
        return;
    engine.finalizing = true;
    if (!engine.finish.empty())
        dispatch(engine.finish, true);
    engine.closed = true;
    seal_wave();
    if (engine.wave.is_open()) {
        wave_at();
        engine.wave.flush();
        if (!engine.wave)
            luasim_fail("waveform write failed");
        engine.wave.close();
    }
    while (engine.callbacks)
        retire(*engine.callbacks);
    engine.ready.clear();
    engine.delta.clear();
    engine.rw.clear();
    engine.ro.clear();
    engine.next.clear();
    engine.start.clear();
    engine.finish.clear();
    engine.future.clear();
    for (auto *callback : engine.free_callbacks)
        delete callback;
    engine.free_callbacks.clear();
}
}
