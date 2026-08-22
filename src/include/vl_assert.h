#pragma once

#include <cstdlib>
#include <exception>
#include <string_view>
#include <type_traits>
#include <typeinfo>
#include <utility>

#include <fmt/core.h>
#include <fmt/format.h>
#include <fmt/ranges.h>

namespace vl_assert_detail {

template <typename T> constexpr bool is_string_like_v = std::is_convertible_v<std::remove_cvref_t<T>, std::string_view>;

template <typename T> void dump_one(const T &value) {
    if constexpr (fmt::is_formattable<T>::value) {
        fmt::println(stderr, "  {}", value);
    } else {
        fmt::println(stderr, "  <{}>", typeid(T).name());
    }
}

inline void print_payload() {}

template <typename First, typename... Rest> void print_payload(First &&first, Rest &&...rest) {
    if constexpr (is_string_like_v<First>) {
        std::string_view message        = first;
        constexpr bool rest_formattable = (fmt::is_formattable<std::remove_cvref_t<Rest>>::value && ... && true);
        if constexpr (rest_formattable) {
            if (message.find('{') != std::string_view::npos && sizeof...(Rest) > 0) {
                try {
                    fmt::print(stderr, fmt::runtime(message), rest...);
                    fmt::print(stderr, "\n");
                    return;
                } catch (const std::exception &err) {
                    fmt::println(stderr, "{}", message);
                    fmt::println(stderr, "  (format error: {})", err.what());
                    (dump_one(rest), ...);
                    return;
                }
            }
        }
        fmt::println(stderr, "{}", message);
        (dump_one(rest), ...);
    } else {
        dump_one(first);
        (dump_one(rest), ...);
    }
}

template <typename... Ts> [[noreturn]] void panic_at(const char *file, int line, const char *func, Ts &&...args) {
    fmt::print(stderr, "{}:{}: {}: ", file, line, func);
    if constexpr (sizeof...(Ts) == 0) {
        fmt::println(stderr, "panic");
    } else {
        print_payload(std::forward<Ts>(args)...);
    }
    std::abort();
}

template <typename... Ts> [[noreturn]] void fail_assert(const char *file, int line, const char *func, const char *expr, Ts &&...args) {
    fmt::println(stderr, "{}:{}: {}: assertion failed: {}", file, line, func, expr);
    print_payload(std::forward<Ts>(args)...);
    std::abort();
}

} // namespace vl_assert_detail

// clang-format off
#define PANIC(...) ::vl_assert_detail::panic_at(__FILE__, __LINE__, __func__ __VA_OPT__(, ) __VA_ARGS__)
#define UNREACHABLE(...) PANIC(__VA_ARGS__)
#define ASSERT(cond, ...)                                                                                  \
    do {                                                                                                   \
        if (!(cond)) {                                                                                     \
            ::vl_assert_detail::fail_assert(__FILE__, __LINE__, __func__, #cond __VA_OPT__(, ) __VA_ARGS__); \
        }                                                                                                  \
    } while (0)
// clang-format on
