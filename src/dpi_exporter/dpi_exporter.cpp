#include "dpi_exporter.h"
#include "dpi_exporter_rewriter.h"

namespace fs = std::filesystem;

int main(int argc, char **argv) {
    OS::setupConsole();
    slang::driver::Driver driver;

    std::vector<std::string> files;
    std::vector<std::string> _files;
    std::optional<std::string> _configFile;
    std::optional<std::string> _outdir;
    std::optional<std::string> _workdir;
    std::optional<std::string> _dpiFile;
    std::optional<std::string> _topClock;
    std::optional<bool> _distributeDPI;
    std::optional<bool> _quiet;

    driver.cmdLine.add("--fl,--filelist", _files, "input file or filelist", "<file/filelist>");
    driver.cmdLine.add("-c,--config", _configFile, "`Lua` file that contains the module info and the corresponding signal info", "<lua file>");
    driver.cmdLine.add("--od,--out-dir", _outdir, "output directory", "<directory>");
    driver.cmdLine.add("--wd,--work-dir", _workdir, "working directory", "<directory>");
    driver.cmdLine.add("--df,--dpi-file", _dpiFile, "name of the generated DPI file", "<file name>");
    driver.cmdLine.add("--tc,--top-clock", _topClock, "clock signal of the top-level module", "<name>");
    driver.cmdLine.add("--dd,--distribute-dpi", _distributeDPI, "distribute DPI functions");
    driver.cmdLine.add("-q,--quiet", _quiet, "quiet mode, print only necessary info");

    std::optional<bool> showHelp;
    driver.cmdLine.add("-h,--help", showHelp, "Display available options");

    driver.addStandardArgs();
    ASSERT(driver.parseCommandLine(argc, argv));

    if (showHelp) {
        std::cout << fmt::format("{}\n", driver.cmdLine.getHelpText("dpi_exporter for verilua").c_str());
        return 0;
    }

    if (_configFile->empty()) {
        PANIC("No config file specified! please use -c/--config <lua file>");
    }

    std::string configFile    = fs::absolute(_configFile.value()).string();
    std::string outdir        = fs::absolute(_outdir.value_or(DEFAULT_OUTPUT_DIR)).string();
    std::string workdir       = fs::absolute(_workdir.value_or(DEFAULT_WORK_DIR)).string();
    std::string dpiFileName   = _dpiFile.value_or(DEFAULT_DPI_FILE_NAME);
    std::string topModuleName = "";
    std::string topClock      = _topClock.value_or("clock");
    bool distributeDPI        = _distributeDPI.value_or(false);
    bool quiet                = _quiet.value_or(false);
    fmt::println("[dpi_exporter]\n\tconfigFile: {}\n\tdpiFileName: {}\n\toutdir: {}\n\tworkdir: {}\n\tdistributeDPI: {}\n\tquiet: {}\n", configFile, dpiFileName, outdir, workdir, distributeDPI, quiet);

    if (!driver.options.topModules.empty()) {
        if (driver.options.topModules.size() > 1) {
            PANIC("Multiple top-level modules specified!", driver.options.topModules);
        }
        topModuleName = driver.options.topModules[0];
    }

    std::string optString = "";
#ifdef NO_STD_COPY
    optString += " NO_STD_COPY";
#else
    optString += " STD_COPY";
#endif
#ifdef USE_PORT_STRUCT
    optString += " USE_PORT_STRUCT";
#endif
    fmt::print("[dpi_exporter] Optimization: {}\n", optString);

    if (!std::filesystem::exists(workdir)) {
        std::filesystem::create_directories(workdir);
    }

    for (const auto &file : _files) {
        if (file.ends_with(".f")) {
            // Parse filelist
            std::vector<std::string> fileList = parseFileList(file);
            for (const auto &listedFile : fileList) {
                auto f = fs::absolute(backupFile(listedFile, workdir)).string();
                driver.sourceLoader.addFiles(f);
                files.push_back(f);
            }
        } else {
            auto f = fs::absolute(backupFile(file, workdir)).string();
            driver.sourceLoader.addFiles(f);
            files.push_back(f);
        }
    }

    size_t fileCount = 0;
    for (auto buffer : driver.sourceLoader.loadSources()) {
        fileCount++;
        auto fullpathName = driver.sourceManager.getFullPath(buffer.id);

        if (!quiet) {
            fmt::println("[dpi_exporter] [{}] get file: {}", fileCount, fullpathName.string());
        }
        fflush(stdout);
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

    if tbl.signal == nil then
        tbl.signal = {{}}
    else
        for i, v in ipairs(tbl.signal) do
            assert(type(v) == "string", "item of the `signal` table must be string")
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

    std::vector<DPIExporterInfo> dpiExporterInfoVec;
    for (const auto &entry : (sol::table)lua["dpi_exporter_config"]) {
        sol::table item        = entry.second;
        std::string moduleName = getLuaTableItemOrFailed(item, "module").as<std::string>();
        std::string clock      = item["clock"].get_or(std::string("clock"));
        bool isTopModule       = item["is_top_module"].get_or(std::string("false")) == "true";

        std::vector<std::string> signalPatternVec;
        for (const auto &strEntry : (sol::table)item["signal"]) {
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

        dpiExporterInfoVec.emplace_back(DPIExporterInfo{moduleName, clock, signalPatternVec, disableSignalPatternVec, isTopModule});
    }
    ASSERT(dpiExporterInfoVec.size() > 0, "dpi_exporter_config is empty", configFile);

    std::unordered_set<uint64_t> handleSet;
    bool hasTopModule = false;

    std::string dpiFuncFileContent = "";

    // Used when distributeDPI is FALSE
    std::vector<PortInfo> portVecAll;
    std::string dpiTickFunc     = "extern \"C\" void dpi_exporter_tick(";
    std::string dpiTickFuncBody = "";

    std::string dpiHandleByNameFunc = "extern \"C\" int64_t dpi_exporter_handle_by_name(std::string_view name) {\n";
    dpiHandleByNameFunc += "\tstatic std::unordered_map<std::string_view, int64_t> name_to_handle = {\n";

    std::string dpiGetTypeStrFunc = "extern \"C\" std::string dpi_exporter_get_type_str(int64_t handle) {\n";
    dpiGetTypeStrFunc += "\tstatic std::unordered_map<int64_t, std::string_view> handle_to_type_str = {\n";

    std::string dpiGetBitWidthFunc = "extern \"C\" uint32_t dpi_exporter_get_bitwidth(int64_t handle) {\n";
    dpiGetBitWidthFunc += "\tstatic std::unordered_map<int64_t, uint32_t> handle_to_bitwidth = {\n";

    std::string dpiAllocGetValue32Func = "extern \"C\" GetValue32Func dpi_exporter_alloc_get_value32(int64_t handle) {\n";
    dpiAllocGetValue32Func += "\tstatic std::unordered_map<int64_t, GetValue32Func> handle_to_func = {\n";

    std::string dpiAllocGetValueVecFunc = "extern \"C\" GetValueVecFunc dpi_exporter_alloc_get_value_vec(int64_t handle) {\n";
    dpiAllocGetValueVecFunc += "\tstatic std::unordered_map<int64_t, GetValueVecFunc> handle_to_func = {\n";

    std::string dpiAllocGetValueHexStrFunc = "extern \"C\" GetValueHexStrFunc dpi_exporter_alloc_get_value_hex_str(int64_t handle) {\n";
    dpiAllocGetValueHexStrFunc += "\tstatic std::unordered_map<int64_t, GetValueHexStrFunc> handle_to_func = {\n";
    for (auto info : dpiExporterInfoVec) {
        auto moduleName = info.moduleName;
        fmt::println("---------------- [dpi_exporter] start processing module:<{}> ----------------", moduleName);
        auto rewriter = new DPIExporterRewriter(tree, info, distributeDPI, false, 0, quiet);
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
            tree = slang_common::rebuildSyntaxTree(*newTree, true);
            fmt::println("[dpi_exporter] [0] done rebuilding syntax tree");
            fflush(stdout);
        }

        auto rewriter_1         = new DPIExporterRewriter(tree, info, distributeDPI, true, rewriter->instSize, quiet);
        rewriter_1->hierPathVec = rewriter->hierPathVec;
        rewriter_1->portVec     = rewriter->portVec;
        auto newTree_1          = rewriter_1->transform(newTree);

        if (distributeDPI) {
            // Update syntax tree
            fmt::println("[dpi_exporter] [1] start rebuilding syntax tree");
            fflush(stdout);
            tree = slang_common::rebuildSyntaxTree(*newTree_1);
            fmt::println("[dpi_exporter] [1] done rebuilding syntax tree");
            fflush(stdout);
        } else {
            dpiTickFunc += rewriter_1->dpiTickFuncParam;
            dpiTickFuncBody += rewriter_1->dpiTickFuncBody;

            for (auto &p : rewriter_1->portVecAll) {
                portVecAll.emplace_back(p);
            }
        }

        if (rewriter->instSize == 0 && isTopModule) {
            ASSERT(rewriter_1->instSize == 0, moduleName, rewriter->instSize, rewriter_1->instSize);
            rewriter_1->instSize = 1;
        }

        for (int i = 0; i < rewriter_1->instSize; i++) {
            for (auto &p : rewriter_1->portVec) {
                auto uniqueHandleId      = p.handleId + (i << 24);
                std::string hierPathName = "";
                if (isTopModule) {
                    hierPathName = moduleName;
                } else {
                    hierPathName = rewriter_1->hierPathNameVec[i];
                }

                if (!handleSet.insert(uniqueHandleId).second) {
                    PANIC("Duplicated handle id: {}", uniqueHandleId);
                }

                dpiHandleByNameFunc += fmt::format("\t\t{{ \"{}_{}\", {} }},\n", hierPathName, p.name, uniqueHandleId);
                dpiGetTypeStrFunc += fmt::format("\t\t{{ {}, \"{}\" /* signalName: {}_{} */ }},\n", uniqueHandleId, p.typeStr, hierPathName, p.name);
                dpiGetBitWidthFunc += fmt::format("\t\t{{ {}, {} /* signalName: {}_{} */ }},\n", uniqueHandleId, p.bitWidth, hierPathName, p.name);
                dpiAllocGetValue32Func += fmt::format("\t\t{{ {}, VERILUA_DPI_EXPORTER_{}_{}_GET }},\n", uniqueHandleId, hierPathName, p.name);
                if (p.bitWidth > 32) {
                    dpiAllocGetValueVecFunc += fmt::format("\t\t{{ {}, VERILUA_DPI_EXPORTER_{}_{}_GET_VEC }},\n", uniqueHandleId, hierPathName, p.name);
                }
                dpiAllocGetValueHexStrFunc += fmt::format("\t\t{{ {}, VERILUA_DPI_EXPORTER_{}_{}_GET_HEX_STR }},\n", uniqueHandleId, hierPathName, p.name);
            }
        }
        dpiFuncFileContent += rewriter_1->dpiFuncFileContent;

        fmt::println("---------------- [dpi_exporter] finish processing module:<{}> ----------------\n", moduleName);
        delete rewriter;
        delete rewriter_1;
    }

    if (!distributeDPI) {
        int idx = 0;
        for (auto &p : portVecAll) {
            if (!quiet) {
                fmt::println("[{}] handleId:<{}> hierPathName:<{}> signalName:<{}> typeStr:<{}> bitWidth:<{}>", idx, p.handleId, p.hierPathName, p.name, p.typeStr, p.bitWidth);
            }
            idx++;
        }

        auto rewriter = new DPIExporterRewriter_1(tree, topModuleName, topClock, portVecAll);
        auto newTree  = rewriter->transform(tree);
        ASSERT(rewriter->findTopModule, "Cannot find top module", topModuleName);

        // Update syntax tree
        fmt::println("[dpi_exporter] start rebuilding syntax tree");
        fflush(stdout);
        tree = slang_common::rebuildSyntaxTree(*newTree, true);
        fmt::println("[dpi_exporter] done rebuilding syntax tree");
        fflush(stdout);
    }

    // Generate <handle_by_name>
    dpiHandleByNameFunc.pop_back();
    dpiHandleByNameFunc.pop_back();
    dpiHandleByNameFunc += "\n\t};\n";
    dpiHandleByNameFunc += R"(
    auto it = name_to_handle.find(name);
    if (it != name_to_handle.end()) {
        return it->second;
    } else {
        return -1;
    }
)";
    dpiHandleByNameFunc += "}\n\n";
    dpiFuncFileContent += dpiHandleByNameFunc;

    // Generate <get_type_str>
    dpiGetTypeStrFunc.pop_back();
    dpiGetTypeStrFunc.pop_back();
    dpiGetTypeStrFunc += "\n\t};\n";
    dpiGetTypeStrFunc += R"(
    auto it = handle_to_type_str.find(handle);
    if (it != handle_to_type_str.end()) {
        return std::string(it->second);
    } else {
        return std::string("");
    }
)";
    dpiGetTypeStrFunc += "}\n\n";
    dpiFuncFileContent += dpiGetTypeStrFunc;

    // Generate <get_bitwidth>
    dpiGetBitWidthFunc.pop_back();
    dpiGetBitWidthFunc.pop_back();
    dpiGetBitWidthFunc += "\n\t};\n";
    dpiGetBitWidthFunc += R"(
    auto it = handle_to_bitwidth.find(handle);
    if (it != handle_to_bitwidth.end()) {
        return it->second;
    } else {
        return 0;
    }
)";
    dpiGetBitWidthFunc += "}\n\n";
    dpiFuncFileContent += dpiGetBitWidthFunc;

    // Generate <alloc_get_value32>
    dpiAllocGetValue32Func.pop_back();
    dpiAllocGetValue32Func.pop_back();
    dpiAllocGetValue32Func += "\n\t};\n";
    dpiAllocGetValue32Func += R"(
    auto it = handle_to_func.find(handle);
    if (it != handle_to_func.end()) {
        return it->second;
    } else {
        return nullptr;
    }
)";
    dpiAllocGetValue32Func += "}\n\n";
    dpiFuncFileContent += dpiAllocGetValue32Func;

    // Generate <alloc_get_value_vec>
    dpiAllocGetValueVecFunc.pop_back();
    dpiAllocGetValueVecFunc.pop_back();
    dpiAllocGetValueVecFunc += "\n\t};\n";
    dpiAllocGetValueVecFunc += R"(
    auto it = handle_to_func.find(handle);
    if (it != handle_to_func.end()) {
        return it->second;
    } else {
        return nullptr;
    }
)";
    dpiAllocGetValueVecFunc += "}\n\n";
    dpiFuncFileContent += dpiAllocGetValueVecFunc;

    // Generate <alloc_get_value_hex_str>
    dpiAllocGetValueHexStrFunc.pop_back();
    dpiAllocGetValueHexStrFunc.pop_back();
    dpiAllocGetValueHexStrFunc += "\n\t};\n";
    dpiAllocGetValueHexStrFunc += R"(
    auto it = handle_to_func.find(handle);
    if (it != handle_to_func.end()) {
        return it->second;
    } else {
        return nullptr;
    }
)";
    dpiAllocGetValueHexStrFunc += "}\n\n";
    dpiFuncFileContent += dpiAllocGetValueHexStrFunc;

    dpiFuncFileContent = std::string(R"(
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
)") + "\n\n" + dpiFuncFileContent;

    std::string dpiFuncGetTopName = fmt::format(R"(
extern "C" std::string dpi_exporter_get_top_name() {{
    return std::string("{}");
}}
)",
                                                topModuleName);
    dpiFuncFileContent += "\n\n" + dpiFuncGetTopName;

    if (!distributeDPI) {
        dpiTickFunc.pop_back();
        dpiTickFunc.pop_back();
        dpiTickFunc += "){\n";
        dpiTickFunc += dpiTickFuncBody + "}\n\n";
        dpiFuncFileContent += dpiTickFunc;
    }

    std::fstream dpiFuncFile;
    dpiFuncFile.open(std::string(outdir) + "/" + dpiFileName, std::ios::out);
    dpiFuncFile << dpiFuncFileContent;
    dpiFuncFile.close();

    fmt::println("[dpi_exporter] start generating new files, outdir: {}, dpiFileName: {}", outdir, dpiFileName == DEFAULT_DPI_FILE_NAME ? dpiFileName + "(default)" : dpiFileName);
    fflush(stdout);

    generateNewFile(SyntaxPrinter::printFile(*tree), outdir);

    fmt::println("[dpi_exporter] finish generating new files, outdir: {}, dpiFileName: {}", outdir, dpiFileName == DEFAULT_DPI_FILE_NAME ? dpiFileName + "(default)" : dpiFileName);
    fflush(stdout);

    // Delete temporary files
    for (auto &file : files) {
        DELETE_FILE(file);
    }

    fmt::println("[dpi_exporter] FINISH!");
}
