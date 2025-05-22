#pragma once

#include "config.h"
#include "fmt/core.h"

template <typename... T> void InfoMessage(fmt::format_string<T...> fmt, T &&...args) { fmt::println(fmt, std::forward<T>(args)...); }

#define INFO_PRINT(str, ...)                                                                                                                                                                                                                                                                                                                                                                                   \
    if (!Config::getInstance().quietEnabled) {                                                                                                                                                                                                                                                                                                                                                                 \
        InfoMessage(str __VA_OPT__(, ) __VA_ARGS__);                                                                                                                                                                                                                                                                                                                                                           \
    }