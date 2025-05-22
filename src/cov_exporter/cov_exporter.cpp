// -------------------------------------------------------
// Light-weight Coverage(lcov) Exporter
// -------------------------------------------------------

#include "cov_exporter.h"
#include "SlangCommon.h"
#include "config.h"
#include "cov_info_getter.h"
#include "cov_info_writter.h"

using json = nlohmann::json;
json metaInfoJson;
std::string metaInfoFilePath;

struct InstanceVisitor : public slang::ast::ASTVisitor<InstanceVisitor, false, false> {
    int targetDepth;
    std::string moduleName;
    std::set<std::string> subModuleSet;

    InstanceVisitor(std::string moduleName, int targetDepth) : moduleName(moduleName), targetDepth(targetDepth) {}

    void iterInstance(const slang::ast::InstanceSymbol &instance, int depth) {
        depth++;

        if (targetDepth != -1 && depth > targetDepth) {
            return;
        }

        auto instIter = instance.body.membersOfType<slang::ast::InstanceSymbol>();
        if (instIter.empty()) {
            return;
        }
        for (auto &inst : instIter) {
            subModuleSet.insert(std::string(inst.getDefinition().name));
            this->iterInstance(inst, depth);
        }
    }

    void handle(const slang::ast::InstanceSymbol &instance) {
        if (instance.getDefinition().name == moduleName) {
            this->iterInstance(instance, 1);
        }

        visitDefault(instance);
    }
};

struct CovExporter {
    std::vector<std::string> moduleNames;
    std::vector<std::string> recursiveModules;
    std::vector<std::string> disableModulePatterns;
    std::vector<std::string> disableSignalPatterns;
    std::vector<std::string> globalDisableSignalPatterns;
    std::vector<std::string> clockSignals;
    std::optional<bool> noSepAlwaysBlock;
    std::optional<bool> errPrintTree;
    std::optional<bool> quiet;
    std::optional<std::string> defaultClockName;
    std::optional<std::string> altClockName;
    std::optional<std::string> _workdir;
    std::optional<std::string> _outdir;
    std::string workdir;
    std::string outdir;

    std::unordered_map<std::string, ModuleOption> moduleOptionMap;
    std::vector<std::string> tmpFiles;

    slang_common::Driver driver;
    CovExporter() {
        driver.setName("cov_exporter");
        driver.addStandardArgs();

        driver.cmdLine.add("--ept,--err-print-tree", errPrintTree, "Print entire syntax tree if error occurs");
        driver.cmdLine.add("-m,--module", moduleNames, "Module name to generate coverage annotations", "<module name>");
        driver.cmdLine.add("--rm,--recursive-module", recursiveModules, "Recursive module name to generate coverage annotations", "<module name>");
        driver.cmdLine.add("--dm,--disable-module-pattern", disableModulePatterns, "Disable module pattern to generate coverage annotations", "<regex pattern>");
        driver.cmdLine.add("--wd,--workdir", _workdir, "Work directory", "<directory>");
        driver.cmdLine.add("--od,--outdir", _outdir, "Output directory", "<directory>");
        driver.cmdLine.add("--ds,--disable-signal-pattern", disableSignalPatterns, "Disable signal pattern", "<<module name>:<regex pattern>>");
        driver.cmdLine.add("--gds,--global-disable-signal-pattern", globalDisableSignalPatterns, "Global disable signal pattern", "<regex pattern>");
        driver.cmdLine.add("--cs,--clock-signal", clockSignals, "Clock signal name(default: `clock`)", "<<module name>:<signal name>>");
        driver.cmdLine.add("--dc,--default-clock", defaultClockName, "Default clock signal name(default: `clock`)", "<signal name>");
        driver.cmdLine.add("--ac,--alt-clock", altClockName, "Alternative clock signal name(default: `tb_top.clock`), available when defaultClock cannot be found in the module", "<signal name>");
        driver.cmdLine.add("--ns,--no-sep-always-block", noSepAlwaysBlock, "Disable seperating always block");
        driver.cmdLine.add("-q,--quiet", quiet, "Quiet mode, print only necessary info");
    }

    ~CovExporter() {
        for (auto &file : tmpFiles) {
            DELETE_FILE(file);
        }
    }

    void parse(int argc, char **argv) {
        driver.parseCommandLine(argc, argv);
        driver.setVerbose(!quiet.value_or(false));

        Config::getInstance().quietEnabled   = quiet.value_or(false);
        Config::getInstance().sepAlwaysBlock = !noSepAlwaysBlock.value_or(false);

        workdir = _workdir.value_or("./.cov_exporter");
        outdir  = _outdir.value_or(workdir);

        metaInfoFilePath = outdir + "/cov_exporter.meta.json";

        for (const auto &moduleName : moduleNames) {
            ModuleOption moduleOption(moduleName, defaultClockName.value_or(DEFAULT_CLOCK_NAME), altClockName.value_or(ALTERNATIVE_CLOCK_NAME));
            moduleOptionMap.emplace(moduleName, moduleOption);
        }

        auto parseValuePair = [&](std::string_view param) {
            auto moduleName = param.substr(0, param.find(":"));
            auto value      = param.substr(param.find(":") + 1);
            auto it         = moduleOptionMap.find(std::string(moduleName));
            if (it == moduleOptionMap.end()) {
                PANIC("Module not found, maybe you forgot to add module name via `-m,--module` option", moduleName);
            }
            return std::make_pair(&it->second, value);
        };

        // Parse disable signal patterns
        for (const auto &p : disableSignalPatterns) {
            auto [moduleOption, pattern] = parseValuePair(p);
            moduleOption->disablePatterns.emplace_back(pattern);
            fmt::println("[cov_exporter] Disable signal pattern, moduleName: <{}>, pattern: <{}>", moduleOption->moduleName, pattern);
        }

        // Parse clock signal names
        for (const auto &p : clockSignals) {
            auto [moduleOption, signalName] = parseValuePair(p);
            moduleOption->clockName         = signalName;
            fmt::println("[cov_exporter] Clock signal name, moduleName: <{}>, signalName: <{}>", moduleOption->moduleName, signalName);
        }

        // TODO: Check for regenerate
        if (!std::filesystem::exists(workdir)) {
            std::filesystem::create_directories(workdir);
        }
        if (!std::filesystem::exists(outdir)) {
            std::filesystem::create_directories(outdir);
        }

        driver.loadAllSources([&](std::string_view file) {
            auto f = std::filesystem::absolute(slang_common::file_manage::backupFile(file, workdir)).string();
            tmpFiles.push_back(f);
            return f;
        });

        assert(driver.processOptions());
        assert(driver.parseAllSources());
        assert(driver.reportParseDiags());

        auto startTime = std::chrono::high_resolution_clock::now();

        auto tree        = driver.getSingleSyntaxTree();
        auto compilation = driver.createAndReportCompilation();

        auto endTime = std::chrono::high_resolution_clock::now();
        fmt::println("[cov_exporter] Parse time: {} ms", std::chrono::duration_cast<std::chrono::milliseconds>(endTime - startTime).count());

        for (auto &recursiveModule : recursiveModules) {
            auto it = moduleOptionMap.find(recursiveModule);
            if (it == moduleOptionMap.end()) {
                PANIC("Module not found, maybe you forgot to add module name via `-m,--module` option", recursiveModule, moduleOptionMap);
            }
            auto &moduleOption = it->second;

            // Get submodules of the target recursive module
            auto v = InstanceVisitor(recursiveModule, -1); // TODO: Configurable depth
            compilation->getRoot().visit(v);
            moduleOption.subModuleSet = v.subModuleSet;

            for (auto &subModule : v.subModuleSet) {
                if (moduleOptionMap.find(std::string(subModule)) != moduleOptionMap.end()) {
                    continue;
                }

                // Check disable module patterns
                bool disabled = false;
                for (auto &disableModulePattern : disableModulePatterns) {
                    std::regex re(disableModulePattern);
                    if (std::regex_match(std::string(subModule), re)) {
                        disabled = true;
                        moduleOption.subModuleSet.erase(subModule);
                        break;
                    }
                }
                if (disabled) {
                    continue;
                }

                ModuleOption moduleOption1(std::string(subModule), defaultClockName.value_or(DEFAULT_CLOCK_NAME), altClockName.value_or(ALTERNATIVE_CLOCK_NAME));
                auto v1 = InstanceVisitor(subModule, -1); // TODO: Configurable depth
                compilation->getRoot().visit(v1);
                moduleOption1.subModuleSet = v1.subModuleSet;
                // Also need to check disable module patterns for submodules
                for (auto &subModule1 : v1.subModuleSet) {
                    for (auto &disableModulePattern : disableModulePatterns) {
                        std::regex re(disableModulePattern);
                        if (std::regex_match(std::string(subModule1), re)) {
                            moduleOption1.subModuleSet.erase(subModule1);
                        }
                    }
                }
                moduleOptionMap.emplace(std::string(subModule), moduleOption1);
            }
        }

        // Get coverage signal info
        std::vector<CoverageInfo> coverageInfos;
        for (auto [moduleName, moduleOption] : moduleOptionMap) {
            fmt::println("[cov_exporter] Processing module: `{}`", moduleName);

            CoverageInfoGetter getter(moduleOption, globalDisableSignalPatterns, compilation.get());
            tree->root().visit(getter);

            ASSERT(getter.findModule, "Module not found", moduleOption.moduleName, moduleOption.disablePatterns);

            auto findClock = [&]() {
                // If clock signal name contains ".", it is a hierarchical signal name
                if (moduleOption.clockName.find(".") != std::string::npos) {
                    if (auto sym = compilation->getRoot().lookupName(moduleOption.clockName); sym != nullptr) {
                        getter.coverageInfo.clockName = moduleOption.clockName;
                        return true;
                    }
                }
                return false;
            };
            auto findAltClock = [&]() {
                // Try find alternative clock signal(hierarchical signal name)
                if (moduleOption.altClockName.find(".") != std::string::npos) {
                    if (auto altSym = compilation->getRoot().lookupName(moduleOption.altClockName); altSym != nullptr) {
                        getter.coverageInfo.clockName = moduleOption.altClockName;
                        return true;
                    }
                }
                return false;
            };

            if (!getter.findClockSignal && !getter.findAltClockSignal) {
                if (!findClock()) {
                    if (findAltClock()) {
                        getter.coverageInfo.clockName = moduleOption.altClockName;
                    } else {
                        PANIC("Clock signal not found", moduleOption.moduleName, moduleOption.clockName, moduleOption.altClockName);
                    }
                }
            }

            auto coverageInfo = getter.coverageInfo;
            coverageInfos.emplace_back(coverageInfo);
        }

        // Write coverage signal info
        for (auto &coverageInfo : coverageInfos) {
            fmt::println("[cov_exporter] Processing coverage signal info: `{}`", coverageInfo.moduleName);

            CoverageInfoWritter writter(coverageInfo);
            auto newTree = writter.transform(tree);
            tree         = newTree;
        }

        // Save hierPaths to moduleName mapping
        for (auto &coverageInfo : coverageInfos) {
            for (auto &hierPath : coverageInfo.hierPaths) {
                metaInfoJson["hierPathToModuleName"][hierPath] = coverageInfo.moduleName;
            }
        }

        // Save hierPaths into a `cov_exporter.meta.json` file
        for (auto &coverageInfo : coverageInfos) {
            metaInfoJson["exportedModules"][coverageInfo.moduleName]["hierPaths"]                  = coverageInfo.hierPaths;
            metaInfoJson["exportedModules"][coverageInfo.moduleName]["statistics"]["netCount"]     = coverageInfo.statistic.netCount;
            metaInfoJson["exportedModules"][coverageInfo.moduleName]["statistics"]["varCount"]     = coverageInfo.statistic.varCount;
            metaInfoJson["exportedModules"][coverageInfo.moduleName]["statistics"]["binExprCount"] = coverageInfo.statistic.binExprCount;
            metaInfoJson["exportedModules"][coverageInfo.moduleName]["subModules"]                 = coverageInfo.subModuleSet;
        }
        std::ofstream o(metaInfoFilePath);
        ASSERT(o.is_open(), "Failed to open meta info file", metaInfoFilePath);
        o << metaInfoJson.dump(4) << std::endl;
        o.close();

        slang_common::file_manage::generateNewFile(SyntaxPrinter::printFile(*tree), outdir);
    }
};

int main(int argc, char **argv) {
    CovExporter covExporter;
    covExporter.parse(argc, argv);
    return 0;
}