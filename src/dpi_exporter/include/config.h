#pragma once

#include <string>

class Config {
  public:
    bool quietEnabled{false};
    std::string topModuleName;
    std::string sampleEdge;

    Config() = default;

    static Config &getInstance() {
        static Config instance;
        return instance;
    }

    Config(Config const &)         = delete;
    void operator=(Config const &) = delete;
};
