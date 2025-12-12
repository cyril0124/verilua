#include <iostream>
#include <string>

// `extern "C"` is required to avoid name mangling
extern "C" void dpic_func(const char *content) { std::cout << "[dpic_func] got: " << std::string(content) << std::endl; }

extern "C" void dpic_func2(const char *content) { std::cout << "[dpic_func2] got: " << std::string(content) << std::endl; }
