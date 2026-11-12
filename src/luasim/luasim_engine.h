#pragma once

#include "luasim.h"
#include "vpi_user.h"

#include <algorithm>
#include <cstdint>
#include <deque>
#include <fstream>
#include <limits>
#include <map>
#include <memory>
#include <queue>
#include <string>
#include <utility>
#include <vector>

namespace luasim_engine {

struct Callback;
void release_callback(Callback *callback);

struct Signal {
    std::string path;
    std::string name;
    int width;
    size_t id;
    std::vector<s_vpi_vecval> words;
    std::vector<s_vpi_vecval> scratch;
    Callback *subscribers     = nullptr;
    Callback *last_subscriber = nullptr;
    std::string text;
};

struct Callback {
    s_cb_data data{};
    s_vpi_time time{};
    s_vpi_value value{};
    uint64_t serial           = 0;
    uint32_t references       = 1; // Active registration owns one reference; each queued event owns another.
    bool active               = true;
    bool future_queued        = false;
    Signal *signal            = nullptr;
    Callback *active_previous = nullptr;
    Callback *active_next     = nullptr;
    Callback *signal_previous = nullptr;
    Callback *signal_next     = nullptr;
};

class CallbackRef {
    Callback *pointer = nullptr;

  public:
    CallbackRef() = default;
    CallbackRef(Callback *callback) : pointer(callback) {
        if (pointer)
            ++pointer->references;
    }
    CallbackRef(const CallbackRef &other) : CallbackRef(other.pointer) {}
    CallbackRef(CallbackRef &&other) noexcept : pointer(std::exchange(other.pointer, nullptr)) {}
    CallbackRef &operator=(CallbackRef other) noexcept {
        std::swap(pointer, other.pointer);
        return *this;
    }
    ~CallbackRef() {
        if (pointer)
            release_callback(pointer);
    }
    Callback &operator*() const { return *pointer; }
    Callback *operator->() const { return pointer; }
};

struct Event {
    CallbackRef callback;
    uint64_t time;
    int32_t integer = 0;
    std::vector<s_vpi_vecval> snapshot;
};

struct Later {
    bool operator()(const Event &left, const Event &right) const {
        if (left.time != right.time)
            return left.time > right.time;
        return left.callback->serial > right.callback->serial;
    }
};

class FutureQueue : public std::priority_queue<Event, std::vector<Event>, Later> {
  public:
    void compact() {
        std::erase_if(c, [](const Event &event) {
            if (event.callback->active)
                return false;
            event.callback->future_queued = false;
            return true;
        });
        std::make_heap(c.begin(), c.end(), comp);
    }
    void clear() { c.clear(); }
};

struct Scope {
    std::map<std::string, Scope> children;
    std::vector<Signal *> signals;
};

struct Engine {
    uint64_t now       = 0;
    uint64_t serial    = 0;
    uint64_t rounds    = 0;
    uint64_t max_delta = 10000;
    uint64_t max_time  = 0;
    bool has_max_time  = false;
    int precision      = -12;
    luasim_status status{};
    std::string error;
    std::map<std::string, std::unique_ptr<Signal>> signals;
    std::vector<Signal *> declaration_order;
    Callback *callbacks = nullptr;
    std::vector<Callback *> free_callbacks;
    size_t cancelled_future = 0;
    std::deque<Event> ready;
    std::deque<Event> delta;
    std::deque<Event> rw;
    std::deque<Event> ro;
    std::deque<Event> next;
    std::deque<Event> start;
    std::deque<Event> finish;
    FutureQueue future;
    std::ofstream wave;
    bool finalizing    = false;
    bool closed        = false;
    bool wave_declared = false;
    bool wave_enabled  = true;
    // Set while a value-change callback runs; Rust settles its merged counters afterwards.
    bool in_value_change = false;
    uint64_t wave_time   = std::numeric_limits<uint64_t>::max();
};

extern Engine engine;

inline bool valid(const Callback &callback) { return callback.active; }

// Registration lifetime: allocate on `vpi_register_cb`, retire on removal or one-shot dispatch.
Callback *allocate_callback();
void retire(Callback &callback);
// Value formatting shared by reads (`vpi_get_value`) and the waveform writer.
std::string binary(const Signal &signal);
std::string digits(const Signal &signal, unsigned base);
void wave_at();
void wave_value(const Signal &signal);
bool parse_value(const Signal &signal, const s_vpi_value &value, std::vector<s_vpi_vecval> &words);

} // namespace luasim_engine
