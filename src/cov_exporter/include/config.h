#pragma once

class Config {
  public:
    bool quietEnabled{false};
    bool sepAlwaysBlock{true};

    Config() = default;

    static Config &getInstance() {
        static Config instance;
        return instance;
    }

    Config(Config const &)         = delete;
    void operator=(Config const &) = delete;
};
