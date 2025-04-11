#pragma once

#include "SemanticModel.h"
#include "SlangCommon.h"
#include "fmt/base.h"
#include "fmt/color.h"
#include "inja/inja.hpp"
#include "libassert/assert.hpp"
#include "slang/ast/ASTVisitor.h"
#include "slang/ast/Compilation.h"
#include "slang/ast/Symbol.h"
#include "slang/driver/Driver.h"
#include "slang/syntax/AllSyntax.h"
#include "slang/syntax/SyntaxPrinter.h"
#include "slang/syntax/SyntaxTree.h"
#include "slang/util/Util.h"
#include "sol/sol.hpp"
#include <cstddef>
#include <cstdio>
#include <filesystem>
#include <fmt/ranges.h>
#include <fstream>
#include <memory>
#include <nlohmann/json.hpp>
#include <regex>
#include <span>
#include <string>
#include <unordered_set>
#include <vector>

// ===========================================================
// Optimization configs
// ===========================================================
// #define NO_STD_COPY

#define DEFAULT_OUTPUT_DIR ".dpi_exporter"
#define DEFAULT_WORK_DIR ".dpi_exporter"
#define DEFAULT_DPI_FILE_NAME "dpi_func.cpp"

#define ANSI_COLOR_RED "\x1b[31m"
#define ANSI_COLOR_YELLOW "\x1b[33m"
#define ANSI_COLOR_MAGENTA "\x1b[35m"
#define ANSI_COLOR_GREEN "\x1b[32m"
#define ANSI_COLOR_RESET "\x1b[0m"

#define DELETE_FILE(filePath)                                                                                                                                                                                                                                                                                                                                                                                  \
    do {                                                                                                                                                                                                                                                                                                                                                                                                       \
        if (std::filesystem::exists(filePath)) {                                                                                                                                                                                                                                                                                                                                                               \
            std::filesystem::remove(filePath);                                                                                                                                                                                                                                                                                                                                                                 \
        }                                                                                                                                                                                                                                                                                                                                                                                                      \
    } while (0)

#define INSERT_BEFORE_FILE_HEAD(filePath, str)                                                                                                                                                                                                                                                                                                                                                                 \
    do {                                                                                                                                                                                                                                                                                                                                                                                                       \
        std::ifstream inFile(filePath);                                                                                                                                                                                                                                                                                                                                                                        \
        std::stringstream buffer;                                                                                                                                                                                                                                                                                                                                                                              \
        buffer << "\n" << str << "\n" << inFile.rdbuf();                                                                                                                                                                                                                                                                                                                                                       \
        inFile.close();                                                                                                                                                                                                                                                                                                                                                                                        \
        std::ofstream outFile(filePath);                                                                                                                                                                                                                                                                                                                                                                       \
        outFile << buffer.rdbuf();                                                                                                                                                                                                                                                                                                                                                                             \
        outFile.close();                                                                                                                                                                                                                                                                                                                                                                                       \
    } while (0)

#define INSERT_AFTER_FILE_END(filePath, str)                                                                                                                                                                                                                                                                                                                                                                   \
    do {                                                                                                                                                                                                                                                                                                                                                                                                       \
        std::ofstream outFile(filePath, std::ios::app);                                                                                                                                                                                                                                                                                                                                                        \
        outFile << "\n" << str;                                                                                                                                                                                                                                                                                                                                                                                \
        outFile.close();                                                                                                                                                                                                                                                                                                                                                                                       \
    } while (0)

inline std::vector<std::string> parseFileList(const std::string &filePath) {
    std::vector<std::string> files;
    std::ifstream infile(filePath);
    std::string line;

    while (std::getline(infile, line)) {
        if (!line.empty()) {
            files.push_back(line);
        }
    }

    return files;
}

inline void generateNewFile(const std::string &content, const std::string &newPath) {
    std::istringstream stream(content);
    std::string line;
    std::string currentFile;
    std::ofstream outFile;
    std::vector<std::string> buffer;

    if (!newPath.empty()) {
        if (!std::filesystem::exists(newPath)) {
            std::filesystem::create_directories(newPath);
        }
    }

    auto flushBuffer = [&]() {
        if (!buffer.empty() && outFile.is_open()) {
            for (const auto &l : buffer) {
                outFile << l << '\n';
            }
            buffer.clear();
        }
    };

    while (std::getline(stream, line)) {
        if (line.find("//BEGIN:") == 0) {
            flushBuffer();
            currentFile = line.substr(8);

            std::filesystem::path path = currentFile;
            if (!newPath.empty()) {
                currentFile = newPath + "/" + path.filename().string();
            }

            outFile.open(currentFile, std::ios::out | std::ios::trunc);
            if (!outFile.is_open()) {
                std::cerr << "Failed to open file: " << currentFile << std::endl;
                ASSERT(false);
            }
        } else if (line.find("//END:") == 0) {
            flushBuffer();
            if (outFile.is_open()) {
                outFile.close();
            }
        } else {
            if (outFile.is_open()) {
                buffer.push_back(line);
                if (buffer.size() >= 10000) {
                    flushBuffer();
                }
            }
        }
    }

    flushBuffer();
    if (outFile.is_open()) {
        outFile.close();
    }
}

inline bool isFileNewer(const std::string &file1, const std::string &file2) {
    try {
        auto time1 = std::filesystem::last_write_time(file1);
        auto time2 = std::filesystem::last_write_time(file2);

        return time1 > time2;
    } catch (const std::filesystem::filesystem_error &e) {
        std::cerr << "[isFileNewer] Error: " << e.what() << std::endl;
        return false;
    }
}

inline std::string backupFile(std::string_view inputFile, std::string workdir) {
    std::filesystem::path _workdir(workdir);
    std::filesystem::path path(inputFile);
    std::string targetFile = std::string(workdir) + "/" + path.filename().string() + ".bak";

    if (std::filesystem::exists(targetFile)) {
        std::filesystem::remove(targetFile);
    }
    std::filesystem::copy_file(inputFile, targetFile.c_str());

    INSERT_BEFORE_FILE_HEAD(targetFile, fmt::format("//BEGIN:{}", inputFile));
    INSERT_AFTER_FILE_END(targetFile, fmt::format("//END:{}", inputFile));

    return targetFile;
}

inline sol::object getLuaTableItemOrFailed(sol::table &table, const std::string &key) {
    sol::object obj = table[key];
    if (obj.get_type() == sol::type::nil) {
        throw std::runtime_error("[logic_fuzzer] (nil) Failed to get lua table entry: " + key);
    }
    return obj;
}

inline uint32_t coverWith32(uint32_t size) { return (size + 31) / 32; }
inline uint32_t coverWith4(uint32_t size) { return (size + 3) / 4; }

inline uint32_t log2Ceil(uint32_t x) {
    if (x == 0) {
        PANIC("log2Ceil(0)");
    }
    return std::ceil(std::log2(x));
}

using PortInfo = struct {
    std::string name;
    std::string direction;
    bitwidth_t bitWidth;
    uint64_t handleId;
    bool writable;
    std::string typeStr;
    std::string hierPathName;
    std::string hierPathNameDot;
};

using DPIExporterInfo = struct {
    std::string moduleName;
    std::string clock;
    std::vector<std::string> signalPatternVec;
    std::vector<std::string> writableSignalPatternVec;
    std::vector<std::string> disableSignalPatternVec;
    bool isTopModule;
};

class HierPathGetter : public ASTVisitor<HierPathGetter, false, false> {
  public:
    std::string moduleName;
    std::string instName;

  public:
    std::vector<std::string> hierPaths;

    HierPathGetter(std::string moduleName, std::string instName) : moduleName(moduleName), instName(instName) {}

    void handle(const InstanceSymbol &inst) {
        auto _moduleName = inst.getDefinition().name;
        auto _instName   = inst.name;

        if (_instName == instName && _moduleName == moduleName) {
            std::string hierPath = "";
            inst.getHierarchicalPath(hierPath);
            // fmt::println("[HierPathGetter] moduleName:<{}> instName:<{}> hierPath:<{}>", _moduleName, _instName, hierPath);

            hierPaths.emplace_back(hierPath);
        } else {
            visitDefault(inst);
        }
    }
};