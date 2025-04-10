#include "dpi_exporter.h"
#include "dpi_exporter_rewriter.h"

using json   = nlohmann::json;
namespace fs = std::filesystem;

class DPIExporter {
  private:
    slang::driver::Driver driver;

    std::vector<std::string> files;
    std::vector<std::string> tmpFiles;
    std::vector<std::string> _files;
    std::optional<std::string> _configFile;
    std::optional<std::string> _outdir;
    std::optional<std::string> _workdir;
    std::optional<std::string> _dpiFile;
    std::optional<std::string> _topClock;
    std::optional<std::string> _sampleEdge;
    std::optional<bool> _distributeDPI;
    std::optional<bool> _quiet;
    std::optional<bool> nocache;
    std::optional<bool> showHelp;
    std::optional<bool> fixBug; // TODO: consider remove this after bug is fixed in slang

    std::string configFile;
    std::string outdir;
    std::string workdir;
    std::string dpiFilePath;
    std::string topModuleName;
    std::string topClock;
    std::string sampleEdge;
    std::string cmdLineStr;
    bool distributeDPI;
    bool quiet;

    std::vector<DPIExporterInfo> dpiExporterInfoVec;

    int totalFileCount;

    json metaInfoJson;
    std::string metaInfoFilePath;

    bool checkForRegenerate() {
        if (!std::filesystem::exists(workdir)) {
            std::filesystem::create_directories(workdir);
            fmt::println("[dpi_exporter] workdir not found, creating and regenerating...");
            return true;
        }

        if (nocache.value_or(false)) {
            return true;
        }

        if (!std::filesystem::exists(metaInfoFilePath)) {
            fmt::println("[dpi_exporter] meta info file not found, regenerating...");
            return true;
        }

        if (!std::filesystem::exists(dpiFilePath)) {
            fmt::println("[dpi_exporter] dpi file not found, regenerating...");
            return true;
        }

        std::ifstream metaInfoFile(metaInfoFilePath);
        if (!metaInfoFile.is_open()) {
            fmt::println("[dpi_exporter] failed to open meta info file, regenerating...");
            return true;
        } else {
            metaInfoJson = json::parse(metaInfoFile);
            metaInfoFile.close();
        }

        std::string _dpiFilePath = metaInfoJson["dpiFilePath"];
        if (_dpiFilePath != dpiFilePath) {
            fmt::println("[dpi_exporter] dpi file path changed, regenerating...");
            return true;
        }

        if (metaInfoJson["cmdLine"] != cmdLineStr) {
            fmt::println("[dpi_exporter] cmdLine changed, regenerating...");
            return true;
        }

        for (const auto &file : files) {
            if (isFileNewer(file, _dpiFilePath)) {
                fmt::println("[dpi_exporter] `{}` is newer than `{}`, regenerating...", file, _dpiFilePath);
                return true;
            }
        }

        if (metaInfoJson["filelist"].get<std::vector<std::string>>() != files) {
            fmt::println("[dpi_exporter] filelist changed, regenerating...");
            return true;
        }

        return false;
    }

    void extractConfigInfo() {
        sol::state lua;
        lua.open_libraries(sol::lib::base);
        lua.open_libraries(sol::lib::string);
        lua.open_libraries(sol::lib::table);
        lua.open_libraries(sol::lib::math);
        lua.open_libraries(sol::lib::io);
        lua.script_file(configFile);
        lua.script(fmt::format(R"(
assert(dpi_exporter_config ~= nil, "[dpi_exporter] dpi_exporter_config is nil in the config file => {}");
for i, tbl in ipairs(dpi_exporter_config) do
    for k, v in pairs(tbl) do
        local typ = type(v)
        if typ == "number" then
            tbl[k] = tostring(v)
        elseif typ == "boolean" then
            tbl[k] = tostring(v)
        end
    end

    if tbl.signals == nil then
        tbl.signals = {{}}
    else
        for i, v in ipairs(tbl.signals) do
            assert(type(v) == "string", "item of the `signals` table must be string")
        end
    end

    if tbl.disable_signal == nil then
        tbl.disable_signal = {{}}
    else
        for i, v in ipairs(tbl.disable_signal) do
            assert(type(v) == "string", "item of the `disable_signal` table must be string")
        end
    end
end
)",
                               configFile));

        // Extract config info from the provided lua file
        for (const auto &entry : (sol::table)lua["dpi_exporter_config"]) {
            sol::table item        = entry.second;
            std::string moduleName = getLuaTableItemOrFailed(item, "module").as<std::string>();
            std::string clock      = item["clock"].get_or(std::string("clock"));
            bool isTopModule       = item["is_top_module"].get_or(std::string("false")) == "true";

            std::vector<std::string> signalPatternVec;
            for (const auto &strEntry : (sol::table)item["signals"]) {
                const auto &str = strEntry.second;
                if (str.is<std::string>()) {
                    signalPatternVec.push_back(str.as<std::string>());
                } else {
                    PANIC("Unexpected type");
                }
            }

            std::vector<std::string> disableSignalPatternVec;
            for (const auto &strEntry : (sol::table)item["disable_signal"]) {
                const auto &str = strEntry.second;
                if (str.is<std::string>()) {
                    disableSignalPatternVec.push_back(str.as<std::string>());
                } else {
                    PANIC("Unexpected type");
                }
            }

            if (signalPatternVec.empty()) {
                fmt::println("[dpi_exporter] {}WARNING{}: no signal pattern found for module: {}!", ANSI_COLOR_YELLOW, ANSI_COLOR_RESET, moduleName);
            }

            dpiExporterInfoVec.emplace_back(DPIExporterInfo{moduleName, clock, signalPatternVec, disableSignalPatternVec, isTopModule});
        }
        ASSERT(dpiExporterInfoVec.size() > 0, "dpi_exporter_config is empty", configFile);
    }

  public:
    DPIExporter() {
        driver.addStandardArgs();

        driver.cmdLine.add("--fl,--filelist", _files, "input file or filelist", "<file/filelist>");
        driver.cmdLine.add("-c,--config", _configFile, "`Lua` file that contains the module info and the corresponding signal info", "<lua file>");
        driver.cmdLine.add("--od,--out-dir", _outdir, "output directory", "<directory>");
        driver.cmdLine.add("--wd,--work-dir", _workdir, "working directory", "<directory>");
        driver.cmdLine.add("--df,--dpi-file", _dpiFile, "name of the generated DPI file", "<file name>");
        driver.cmdLine.add("--tc,--top-clock", _topClock, "clock signal of the top-level module", "<name>");
        driver.cmdLine.add("--dd,--distribute-dpi", _distributeDPI, "distribute DPI functions");
        driver.cmdLine.add("--se,--sample-edge", _sampleEdge, "sample edge of the clock signal");
        driver.cmdLine.add("-q,--quiet", _quiet, "quiet mode, print only necessary info");
        driver.cmdLine.add("--nc,--no-cache", nocache, "do not use cache files");
        driver.cmdLine.add("--fb,--fix-bug", fixBug, "temporary fix a bug introduced in slang 8.0, will be removed in future");

        // Include paths (override default include paths of slang)
        driver.cmdLine.add(
            "-I,--include-directory,+incdir",
            [this](std::string_view value) {
                if (auto ec = this->driver.sourceManager.addUserDirectories(value)) {
                    fmt::println("include directory '{}': {}", value, ec.message());
                }

                // Append the include directory into the default source manager which will be used by `slang_common::rebuildSyntaxTree()`.
                // Without this, the include directories will not be considered when building the syntax tree.
                SyntaxTree::getDefaultSourceManager().addUserDirectories(value);

                return "";
            },
            "Additional include search paths", "<dir-pattern>[,...]", CommandLineFlags::CommaList);

        driver.cmdLine.add(
            "--isystem",
            [this](std::string_view value) {
                if (auto ec = this->driver.sourceManager.addSystemDirectories(value)) {
                    fmt::println("system include directory '{}': {}", value, ec.message());
                }

                // The same as above, but for the default source manager
                SyntaxTree::getDefaultSourceManager().addSystemDirectories(value);

                return "";
            },
            "Additional system include search paths", "<dir-pattern>[,...]", CommandLineFlags::CommaList);

        driver.cmdLine.setPositional(
            [this](std::string_view value) {
                if (!this->driver.options.excludeExts.empty()) {
                    if (size_t extIndex = value.find_last_of('.'); extIndex != std::string_view::npos) {
                        if (driver.options.excludeExts.count(std::string(value.substr(extIndex + 1))))
                            return "";
                    }
                }

                this->_files.push_back(std::string(value));
                return "";
            },
            "files", {}, true);

        driver.cmdLine.add("-h,--help", showHelp, "Display available options");
    }

    int parseCommandLine(int argc, char **argv) {
        ASSERT(driver.parseCommandLine(argc, argv));

        if (showHelp) {
            std::cout << fmt::format("{}\n", driver.cmdLine.getHelpText("dpi_exporter for verilua").c_str());
            return 0;
        }

        if (_configFile->empty()) {
            PANIC("No config file specified! please use -c/--config <lua file>");
        }

        configFile       = fs::absolute(_configFile.value()).string();
        outdir           = fs::absolute(_outdir.value_or(DEFAULT_OUTPUT_DIR)).string();
        workdir          = fs::absolute(_workdir.value_or(DEFAULT_WORK_DIR)).string();
        topClock         = _topClock.value_or("clock");
        sampleEdge       = _sampleEdge.value_or("negedge");
        distributeDPI    = _distributeDPI.value_or(false);
        quiet            = _quiet.value_or(false);
        metaInfoFilePath = workdir + "/dpi_exporter.meta.json";
        dpiFilePath      = outdir + "/" + _dpiFile.value_or(DEFAULT_DPI_FILE_NAME);
        fmt::println("[dpi_exporter]\n\tconfigFile: {}\n\tdpiFileName: {}\n\toutdir: {}\n\tworkdir: {}\n\tdistributeDPI: {}\n\tquiet: {}\n", configFile, _dpiFile.value_or(DEFAULT_DPI_FILE_NAME), outdir, workdir, distributeDPI, quiet);

        if (!driver.options.topModules.empty()) {
            if (driver.options.topModules.size() > 1) {
                PANIC("Multiple top-level modules specified!", driver.options.topModules);
            }
            topModuleName = driver.options.topModules[0];
        }

        ASSERT(sampleEdge == "posedge" || sampleEdge == "negedge", "Invalid sample edge '{}', should be either 'posedge' or 'negedge'", sampleEdge);

        std::string optString = "";
#ifdef NO_STD_COPY
        optString += " NO_STD_COPY";
#else
        optString += " STD_COPY";
#endif
        fmt::print("[dpi_exporter] Optimization: {}\n", optString);

        for (const auto &file : _files) {
            if (file.ends_with(".f")) {
                // Parse filelist
                std::vector<std::string> fileList = parseFileList(file);
                for (const auto &listedFile : fileList) {
                    files.push_back(listedFile);
                    totalFileCount++;
                }
            } else {
                files.push_back(file);
                totalFileCount++;
            }
        }

        // Get command line into string
        cmdLineStr.clear();
        for (int i = 0; i < argc; i++) {
            cmdLineStr += argv[i];
            cmdLineStr += " ";
        }

        return 1;
    }

    void generate() {
        if (!this->checkForRegenerate()) {
            fmt::println("[dpi_exporter] No need to regenerate, using cache files");
            return;
        }

        size_t fileCount = 0;
        for (const auto &file : files) {
            fileCount++;

            if (!quiet) {
                fmt::println("[dpi_exporter] [{}/{}] get file: {}", fileCount, totalFileCount, file);
                fflush(stdout);
            }

            auto f = fs::absolute(backupFile(file, workdir)).string();
            tmpFiles.push_back(f);
        }

        if (fixBug.value_or(false)) {
            std::vector<std::string> fixCmdVec;
            for (const auto &f : tmpFiles) {
                // fixCmdVec.emplace_back(fmt::format("sed -i 's/^[[:space:]]*`include .*/& `define _ 0/' {}", f));
                fixCmdVec.emplace_back(fmt::format(R"(sed -i '/^[[:space:]]*`include .*/a \`define _ 0 `define _ 0\n`define _ 0 `define _ 0' {})", f));
            }
            std::string fixCmd = fmt::to_string(fmt::join(fixCmdVec, "\n"));

            // Write the fix cmd into a shell file
            std::ofstream fixScript(workdir + "/fix_include.sh");
            fixScript << "#!/bin/bash\n";
            fixScript << fixCmd << "\n";
            fixScript.close();

            // Execute the fix script
            std::string cmd = "if command -v parallel >/dev/null 2>&1; then ";
            cmd += "bash " + workdir + "/fix_include.sh | parallel -j 50; ";
            cmd += "else bash " + workdir + "/fix_include.sh; fi";
            if (system(cmd.c_str()) != 0) {
                fmt::println("[dpi_exporter] Failed to execute fix script");
                return;
            } else {
                fmt::println("[dpi_exporter] Executed fix script");
            }
        }

        for (const auto &f : tmpFiles) {
            driver.sourceLoader.addFiles(f);
        }

        ASSERT(driver.processOptions());
        driver.options.singleUnit = true;

        ASSERT(driver.parseAllSources());
        ASSERT(driver.reportParseDiags());
        ASSERT(driver.syntaxTrees.size() == 1, "Only one SyntaxTree is expected", driver.syntaxTrees.size());

        auto compilation    = driver.createCompilation();
        bool compileSuccess = driver.reportCompilation(*compilation, false);
        ASSERT(compileSuccess);

        // Get syntax tree
        ASSERT(driver.syntaxTrees.size() == 1, "Only one SyntaxTree is expected", driver.syntaxTrees.size());
        std::shared_ptr<SyntaxTree> tree = driver.syntaxTrees[0];

        if (topModuleName == "") {
            topModuleName = compilation->getRoot().topInstances[0]->name;
            fmt::println("[dpi_exporter] `--top` is not set, use `{}` as top module name", topModuleName);
        }
        fmt::println("[dpi_exporter] topModuleName: {}", topModuleName);

        // Get DPIExporterInfoVec from the provided lua config file
        this->extractConfigInfo();

        std::string dpiFuncFileContent = "";
        std::vector<PortInfo> portVecAll; // Used when distributeDPI is FALSE
        std::unordered_set<uint64_t> handleSet;
        bool hasTopModule = false;

        std::vector<std::string> handleByNameVec;
        std::vector<std::string> getTypeStrVec;
        std::vector<std::string> getBitWidthVec;
        std::vector<std::string> getValue32Vec;
        std::vector<std::string> getValueVecVec;
        std::vector<std::string> getValueHexStrVec;

        std::vector<std::string> dpiTickFuncParamVec;
        std::vector<std::string> dpiTickFuncBodyVec;

        for (auto info : dpiExporterInfoVec) {
            auto moduleName = info.moduleName;
            fmt::println("---------------- [dpi_exporter] start processing module:<{}> ----------------", moduleName);
            auto rewriter = new DPIExporterRewriter(tree, info, sampleEdge, distributeDPI, false, 0, quiet);
            auto newTree  = rewriter->transform(tree);

            auto isTopModule = false;
            if (rewriter->instSize == 0) {
                ASSERT(!hasTopModule, "Multiple top-level modules found in the design!", moduleName);
                hasTopModule = true;
                isTopModule  = true;
            }

            if (distributeDPI) {
                // Update syntax tree
                fmt::println("[dpi_exporter] [0] start rebuilding syntax tree");
                fflush(stdout);
                tree = slang_common::rebuildSyntaxTree(*newTree, !quiet);
                fmt::println("[dpi_exporter] [0] done rebuilding syntax tree");
                fflush(stdout);
            }

            auto rewriter_1         = new DPIExporterRewriter(tree, info, sampleEdge, distributeDPI, true, rewriter->instSize, quiet);
            rewriter_1->hierPathVec = rewriter->hierPathVec;
            rewriter_1->portVec     = rewriter->portVec;
            auto newTree_1          = rewriter_1->transform(newTree);

            if (distributeDPI) {
                // Update syntax tree
                fmt::println("[dpi_exporter] [1] start rebuilding syntax tree");
                fflush(stdout);

                tree = slang_common::rebuildSyntaxTree(*newTree_1, !quiet);

                fmt::println("[dpi_exporter] [1] done rebuilding syntax tree");
                fflush(stdout);
            } else {
                dpiTickFuncParamVec.insert(dpiTickFuncParamVec.end(), rewriter_1->dpiTickFuncParamVec.begin(), rewriter_1->dpiTickFuncParamVec.end());
                dpiTickFuncBodyVec.insert(dpiTickFuncBodyVec.end(), rewriter_1->dpiTickFuncBodyVec.begin(), rewriter_1->dpiTickFuncBodyVec.end());
            }

            // Collect all valid signals
            portVecAll.insert(portVecAll.end(), rewriter_1->portVecAll.begin(), rewriter_1->portVecAll.end());

            if (rewriter->instSize == 0 && isTopModule) {
                ASSERT(rewriter_1->instSize == 0, moduleName, rewriter->instSize, rewriter_1->instSize);
                rewriter_1->instSize = 1;
            }

            for (int i = 0; i < rewriter_1->instSize; i++) {
                for (auto &p : rewriter_1->portVec) {
                    // Make sure every signal has a unique handleId
                    // We should mix the instance index with the handleId to avoid value collision
                    auto uniqueHandleId = p.handleId + (i << 24);

                    // e.g. path.to.module.signalName ==> hierPathName: path_to_module p.name: signalName
                    std::string hierPathName    = "";
                    std::string hierPathNameDot = "";
                    if (isTopModule) {
                        hierPathName    = moduleName;
                        hierPathNameDot = moduleName;
                    } else {
                        hierPathName    = rewriter_1->hierPathNameVec[i];
                        hierPathNameDot = rewriter_1->hierPathNameDotVec[i];
                    }

                    if (!handleSet.insert(uniqueHandleId).second) {
                        PANIC("Duplicated handle id: {}", uniqueHandleId);
                    }

                    std::string extraInfo = fmt::format("/* signalName: {}.{} instId: {} */", hierPathNameDot, p.name, i);
                    handleByNameVec.push_back(fmt::format("\t\t{{ \"{}_{}\", 0x{:x} }} {}", hierPathName, p.name, uniqueHandleId, extraInfo));
                    getTypeStrVec.push_back(fmt::format("\t\t{{ 0x{:x}, \"{}\" }} {}", uniqueHandleId, p.typeStr, extraInfo));
                    getBitWidthVec.push_back(fmt::format("\t\t{{ 0x{:x}, {} }} {}", uniqueHandleId, p.bitWidth, extraInfo));
                    getValue32Vec.push_back(fmt::format("\t\t{{ 0x{:x}, VERILUA_DPI_EXPORTER_{}_{}_GET }} {}", uniqueHandleId, hierPathName, p.name, extraInfo));
                    if (p.bitWidth > 32) {
                        getValueVecVec.push_back(fmt::format("\t\t{{ 0x{:x}, VERILUA_DPI_EXPORTER_{}_{}_GET_VEC }} {}", uniqueHandleId, hierPathName, p.name, extraInfo));
                    }
                    getValueHexStrVec.push_back(fmt::format("\t\t{{ 0x{:x}, VERILUA_DPI_EXPORTER_{}_{}_GET_HEX_STR }} {}", uniqueHandleId, hierPathName, p.name, extraInfo));
                }
            }
            dpiFuncFileContent += rewriter_1->dpiFuncFileContent;

            fmt::println("---------------- [dpi_exporter] finish processing module:<{}> ----------------\n", moduleName);
            delete rewriter;
            delete rewriter_1;
        }

        // Print all valid signals
        int idx = 0;
        std::vector<std::string> portHierPathVec;
        for (auto &p : portVecAll) {
            idx++;

            if (!quiet) {
                fmt::println("[{}] handleId:<{}> hierPath:<{}> signalName:<{}> typeStr:<{}> bitWidth:<{}>", idx, p.handleId, p.hierPathNameDot, p.name, p.typeStr, p.bitWidth);
            }

            portHierPathVec.emplace_back(p.hierPathNameDot + "." + p.name);
        }
        metaInfoJson["exportedSignals"] = portHierPathVec;

        // Insert dpi tick function into the top-level module(if distributeDPI is FALSE).
        // If distributeDPI is TRUE, the dpi tick function is inserted into each module which owns the signals that need to be exported.
        if (!distributeDPI) {
            auto rewriter = new DPIExporterRewriter_1(tree, topModuleName, topClock, sampleEdge, portVecAll);
            auto newTree  = rewriter->transform(tree);
            ASSERT(rewriter->findTopModule, "Cannot find top module", topModuleName);

            // Update syntax tree
            fmt::println("[dpi_exporter] start rebuilding syntax tree");
            fflush(stdout);
            tree = slang_common::rebuildSyntaxTree(*newTree, !quiet);
            fmt::println("[dpi_exporter] done rebuilding syntax tree");
            fflush(stdout);
        }

        // Generate the target C++ file
        json j;
        j["topModuleName"]      = topModuleName;
        j["distributeDPI"]      = distributeDPI ? 1 : 0;
        j["dpiFuncFileContent"] = dpiFuncFileContent;
        j["handleByName"]       = fmt::to_string(fmt::join(handleByNameVec, ",\n"));
        j["getTypeStr"]         = fmt::to_string(fmt::join(getTypeStrVec, ",\n"));
        j["getBitWidth"]        = fmt::to_string(fmt::join(getBitWidthVec, ",\n"));
        j["getValue32"]         = fmt::to_string(fmt::join(getValue32Vec, ",\n"));
        j["getValueVec"]        = fmt::to_string(fmt::join(getValueVecVec, ",\n"));
        j["getValueHexStr"]     = fmt::to_string(fmt::join(getValueHexStrVec, ",\n"));
        j["dpiTickFuncParam"]   = fmt::to_string(fmt::join(dpiTickFuncParamVec, ", "));
        j["dpiTickFuncBody"]    = fmt::to_string(fmt::join(dpiTickFuncBodyVec, "\n"));

        std::string dpiFileContent = inja::render(R"(
#include <svdpi.h>
#include <stdint.h>
#include <stdio.h>
#include <string>
#include <string_view>
#include <unordered_map>
#include <algorithm>
#include <functional>

using GetValue32Func = std::function<uint32_t ()>;
using GetValueVecFunc = std::function<void (uint32_t *)>;
using GetValueHexStrFunc = std::function<void (char*)>;

{{dpiFuncFileContent}}

extern "C" int64_t dpi_exporter_handle_by_name(std::string_view name) {
    static std::unordered_map<std::string_view, int64_t> name_to_handle = {
{{handleByName}}
    };

    auto it = name_to_handle.find(name);
    if (it != name_to_handle.end()) {
        return it->second;
    } else {
        return -1;
    }
}

extern "C" std::string dpi_exporter_get_type_str(int64_t handle) {
    static std::unordered_map<int64_t, std::string_view> handle_to_type_str = {
{{getTypeStr}}
    };

    auto it = handle_to_type_str.find(handle);
    if (it != handle_to_type_str.end()) {
        return std::string(it->second);
    } else {
        return std::string("");
    }
}

extern "C" uint32_t dpi_exporter_get_bitwidth(int64_t handle) {
    static std::unordered_map<int64_t, uint32_t> handle_to_bitwidth = {
{{getBitWidth}}
    };

    auto it = handle_to_bitwidth.find(handle);
    if (it != handle_to_bitwidth.end()) {
        return it->second;
    } else {
        return 0;
    }
}

extern "C" GetValue32Func dpi_exporter_alloc_get_value32(int64_t handle) {
    static std::unordered_map<int64_t, GetValue32Func> handle_to_func = {
{{getValue32}}
    };

    auto it = handle_to_func.find(handle);
    if (it!= handle_to_func.end()) {
        return it->second;
    } else {
        return nullptr;
    }
}

extern "C" GetValueVecFunc dpi_exporter_alloc_get_value_vec(int64_t handle) {
    static std::unordered_map<int64_t, GetValueVecFunc> handle_to_func = {
{{getValueVec}}
    };

    auto it = handle_to_func.find(handle);
    if (it!= handle_to_func.end()) {
        return it->second;
    } else {
        return nullptr;
    }
}

extern "C" GetValueHexStrFunc dpi_exporter_alloc_get_value_hex_str(int64_t handle) {
    static std::unordered_map<int64_t, GetValueHexStrFunc> handle_to_func = {
{{getValueHexStr}}
    };

    auto it = handle_to_func.find(handle);
    if (it!= handle_to_func.end()) {
        return it->second;
    } else {
        return nullptr;
    }
}

extern "C" std::string dpi_exporter_get_top_name() {
    return std::string("{{topModuleName}}");
}

## if distributeDPI == 0
extern "C" void dpi_exporter_tick({{dpiTickFuncParam}}) {
{{dpiTickFuncBody}}
}
## endif
        )",
                                                  j);

        {
            fmt::println("[dpi_exporter] start generating dpi file, outdir: {}, dpiFilePath: {}", outdir, dpiFilePath);
            fflush(stdout);

            std::fstream dpiFuncFile;
            dpiFuncFile.open(dpiFilePath, std::ios::out);
            dpiFuncFile << dpiFileContent;
            dpiFuncFile.close();

            metaInfoJson["dpiFilePath"] = dpiFilePath;

            fmt::println("[dpi_exporter] finish generating dpi file, outdir: {}, dpiFilePath: {}", outdir, dpiFilePath);
            fflush(stdout);
        }

        {
            // The syntaxtree of the input rtl files has been changed, so we need to regenerate the new rtl files.
            fmt::println("[dpi_exporter] start generating new rtl files, outdir: {}", outdir);
            fflush(stdout);

            generateNewFile(SyntaxPrinter::printFile(*tree), outdir);

            fmt::println("[dpi_exporter] finish generating new rtl files, outdir: {}", outdir);
            fflush(stdout);
        }

        // Delete temporary files
        for (auto &file : tmpFiles) {
            DELETE_FILE(file);
        }

        // Save the command line arguments and files into json file
        metaInfoJson["cmdLine"]       = cmdLineStr;
        metaInfoJson["filelist"]      = files;
        metaInfoJson["topModuleName"] = topModuleName;

        // Write meta info into a json file, which can be used next time to check if the output is up to date
        std::ofstream o(metaInfoFilePath);
        o << metaInfoJson.dump(4) << std::endl;
        o.close();

        fmt::println("[dpi_exporter] FINISH!");
    }
};

int main(int argc, char **argv) {
    OS::setupConsole();
    DPIExporter dpiExporter;

    if (dpiExporter.parseCommandLine(argc, argv) == 0) {
        return 0;
    }

    dpiExporter.generate();

    return 0;
}
