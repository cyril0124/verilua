#include "dpi_exporter.h"
#include "exporter_rewriter.h"
#include "render_dpi_file.h"
#include "signal_info_getter.h"

using json   = nlohmann::json;
namespace fs = std::filesystem;

// TODO: Writable signal should ne use sensitive signal
// TODO: Support both posedge and negedge(LuaEdgeStepScheduler)

class DPIExporter {
  private:
    slang_common::Driver driver;

    std::vector<std::string> files;
    std::vector<std::string> tmpFiles;
    std::vector<std::string> _files;
    std::optional<std::string> _configFile;
    std::optional<std::string> _outdir;
    std::optional<std::string> _workdir;
    std::optional<std::string> _dpiFile;
    std::optional<std::string> _topClock;
    std::optional<std::string> _sampleEdge;
    std::optional<std::string> insertModuleName;
    std::optional<bool> _distributeDPI;
    std::optional<bool> _quiet;
    std::optional<bool> pldmGfifoDpi;
    std::optional<bool> nocache;
    std::optional<bool> showHelp;
    std::optional<bool> _relativeMetaPath;

    std::string configFile;
    std::string configFileContent;
    std::string outdir;
    std::string workdir;
    std::string dpiFilePath;
    std::string topModuleName;
    std::string topClock;
    std::string sampleEdge;
    std::string cmdLineStr;
    bool distributeDPI;
    bool quiet;
    bool relativeMetaPath;

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
            if (slang_common::file_manage::isFileNewer(file, _dpiFilePath)) {
                fmt::println("[dpi_exporter] `{}` is newer than `{}`, regenerating...", file, _dpiFilePath);
                return true;
            }
        }

        if (metaInfoJson["filelist"].get<std::vector<std::string>>() != files) {
            fmt::println("[dpi_exporter] filelist changed, regenerating...");
            return true;
        }

        if (metaInfoJson["configFileContent"] != configFileContent) {
            fmt::println("[dpi_exporter] config file changed, regenerating...");
            return true;
        }

        return false;
    }

    std::pair<std::vector<ConciseSignalPattern>, std::vector<SensitiveTriggerInfo>> extractConfigInfo() {
        sol::state lua;
        lua.open_libraries(sol::lib::base);
        lua.open_libraries(sol::lib::string);
        lua.open_libraries(sol::lib::table);
        lua.open_libraries(sol::lib::math);
        lua.open_libraries(sol::lib::io);
        lua.open_libraries(sol::lib::os);
        lua.open_libraries(sol::lib::package);
        lua.script(R"(
local f = string.format
local append = table.insert
local count = 0
local name_map = {}
local sensitive_name_map = {}
patterns_data = {}
sensitive_triggers_data = {}

local function is_valid_name(str)
    -- Empty string is not a valid identifier
    if str == "" then
        return false
    end

    -- First character must be a letter or underscore
    local first_char = str:sub(1, 1)
    if not first_char:match("[a-zA-Z_]") then
        return false
    end

    -- Subsequent characters can be letters, numbers, or underscores
    if #str > 1 then
        local rest = str:sub(2)
        -- If any character is invalid, return false
        if rest:match("[^a-zA-Z0-9_]") then
            return false
        end
    end

    -- All checks passed
    return true
end

local valid_keys_for_add_pattern = {
    "name",
    "module",
    "inst",
    "signals",
    "writable_signals",
    "disable_signals",
    "sensitive_signals",
    "clock",
    "writable",
}
function add_pattern(params)
    local name = params.name or "UNKNOWN_" .. count
    local module = assert(params.module, "[add_pattern] module is nil")
    local inst = params.inst or "" -- Instance name
    local signals = params.signals or ""
    local writable_signals = params.writable_signals or ""
    local disable_signals = params.disable_signals or ""
    local sensitive_signals = params.sensitive_signals or ""
    local clock = params.clock or ""
    local writable = params.writable or false

    for k, _ in pairs(params) do
        local find_matched_key = false
        for _, valid_key in ipairs(valid_keys_for_add_pattern) do
            if k == valid_key then
                find_matched_key = true
                break
            end
        end
        assert(find_matched_key, f(
            "[add_pattern] invalid params key: %s, available keys: {%s}, params.name: %s, params.module: %s",
            k,
            table.concat(valid_keys_for_add_pattern, ", "),
            name,
            params.module
        ))
    end

    assert(not(disable and writable), "[add_pattern] disable and writable cannot be both `true`")

    assert(is_valid_name(name), f("[add_pattern] name `%s` is not a valid name", name))
    assert(not name_map[name], f("[add_pattern] name `%s` is already used", name))

    append(patterns_data, {
        name = name,
        module = module,
        inst = inst,
        signals = signals,
        writable_signals = writable_signals,
        disable_signals = disable_signals,
        sensitive_signals = sensitive_signals,
        clock = clock,
        writable = writable,
    })
    count = count + 1

    name_map[name] = true

    return name
end

-- Alias name for `add_pattern`
_G.add_signals = add_pattern

local valid_keys_for_add_sensitive_trigger = {
    "name",
    "group_names",
}
function add_sensitive_trigger(params)
    local name = assert(params.name, "[add_sensitive_trigger] name is nil")
    local group_names = assert(params.group_names, "[add_sensitive_trigger] group_names is nil")

    for k, _ in pairs(params) do
        local find_matched_key = false
        for _, valid_key in ipairs(valid_keys_for_add_sensitive_trigger) do
            if k == valid_key then
                find_matched_key = true
                break
            end
        end
        assert(find_matched_key, f(
            "[add_sensitive_trigger] invalid params key: %s, available keys: {%s}, params.name: %s, params.group_names: %s",
            k,
            table.concat(valid_keys_for_add_sensitive_trigger, ", "),
            params.name,
            params.group_names
        ))
    end

    for _, n in ipairs(group_names) do
        assert(name_map[n], f("[add_sensitive_trigger] group name `%s` not found, maybe you forgot to add it with `add_pattern(<params>)/add_signals(<params>)`", n))
    end

    assert(is_valid_name(name), f("[add_sensitive_trigger] name `%s` is not a valid name", name))
    assert(not sensitive_name_map[name], f("[add_sensitive_trigger] name `%s` is already used", name))
    assert(#group_names > 0, "[add_sensitive_trigger] group_names is empty")

    append(sensitive_triggers_data, {
        name = name,
        group_names = group_names
    })

    sensitive_name_map[name] = true
end

--- Alias name for `add_sensitive_trigger`, and also fix the typo in the function name.
add_senstive_trigger = add_sensitive_trigger

)");
        lua.script_file(configFile);

        std::vector<ConciseSignalPattern> conciseSignalPatternVec;

        sol::table patternsData = lua["patterns_data"];
        patternsData.for_each([&](sol::object key, sol::object value) {
            sol::table patternData       = value.as<sol::table>();
            std::string name             = patternData["name"].get<std::string>();
            std::string moduleName       = patternData["module"].get<std::string>();
            std::string instName         = patternData["inst"].get<std::string>();
            std::string clock            = patternData["clock"].get<std::string>();
            std::string signals          = patternData["signals"].get<std::string>();
            std::string writableSignals  = patternData["writable_signals"].get<std::string>();
            std::string disableSignals   = patternData["disable_signals"].get<std::string>();
            std::string sensitiveSignals = patternData["sensitive_signals"].get<std::string>();

            if (!quiet) {
                fmt::println("[dpi_exporter] get pattern:");
                fmt::println("\tname: {}", name);
                fmt::println("\tmoduleName: {}", moduleName);
                fmt::println("\tinstName: {}", instName);
                fmt::println("\tclock: {}", clock);
                fmt::println("\tsignals: {}", signals);
                fmt::println("\twritable_signals: {}", writableSignals);
                fmt::println("\tdisable_signals: {}", disableSignals);
                fmt::println("\tsensitive_signals: {}", sensitiveSignals);
                fmt::println("\n");
                fflush(stdout);
            }

            // clang-format off
            conciseSignalPatternVec.emplace_back(ConciseSignalPattern{
                name,
                moduleName,
                instName,
                clock == "" ? DEFAULT_CLOCK_NAME : clock,
                signals,
                writableSignals,
                disableSignals,
                sensitiveSignals
            });
            // clang-format on
        });

        std::vector<SensitiveTriggerInfo> sensitiveTriggerInfoVec;

        sol::table sensitiveTriggersData = lua["sensitive_triggers_data"];
        sensitiveTriggersData.for_each([&](sol::object key, sol::object value) {
            sol::table sensitiveTriggerData     = value.as<sol::table>();
            std::string name                    = sensitiveTriggerData["name"].get<std::string>();
            std::vector<std::string> groupNames = sensitiveTriggerData["group_names"].get<std::vector<std::string>>();

            if (!quiet) {
                fmt::println("[dpi_exporter] get sensitive trigger info:");
                fmt::println("\tname: {}", name);
                fmt::println("\tgroup_names: {}", fmt::join(groupNames, ", "));
                fmt::println("\n");
                fflush(stdout);
            }

            sensitiveTriggerInfoVec.emplace_back(SensitiveTriggerInfo{name, groupNames});
        });

        return {conciseSignalPatternVec, sensitiveTriggerInfoVec};
    }

  public:
    DPIExporter() : driver(fmt::format("dpi_exporter(verilua@{})", VERILUA_VERSION)) {
        driver.addStandardArgs();

        driver.cmdLine.add("--fl,--filelist", _files, "input file or filelist", "<file/filelist>");
        driver.cmdLine.add("-c,--config", _configFile, "`Lua` file that contains the module info and the corresponding signal info", "<lua file>");
        driver.cmdLine.add("--od,--out-dir", _outdir, "output directory", "<directory>");
        driver.cmdLine.add("--wd,--work-dir", _workdir, "working directory", "<directory>");
        driver.cmdLine.add("--df,--dpi-file", _dpiFile, "name of the generated DPI file", "<file name>");
        driver.cmdLine.add("--tc,--top-clock", _topClock, "clock signal of the top-level module", "<name>");
        driver.cmdLine.add("--dd,--distribute-dpi", _distributeDPI, "distribute DPI functions"); // TODO: not supported yet
        driver.cmdLine.add("--se,--sample-edge", _sampleEdge, "sample edge of the clock signal");
        driver.cmdLine.add("-q,--quiet", _quiet, "quiet mode, print only necessary info");
        driver.cmdLine.add("--nc,--no-cache", nocache, "do not use cache files");
        driver.cmdLine.add("--im,--insert-module-name", insertModuleName, "module namne of the DPI function(available when distributeDPI is FALSE)", "<name>"); // ! make sure tha the inserted module has only one instance
        driver.cmdLine.add("--pgd,--pldm-gfifo-dpi", pldmGfifoDpi, "Mark the generated DPI functions as pldm gfifo functions(pldm => Cadence Palladium Emulation Platform)");
        driver.cmdLine.add("--rmp,--relative-meta-path", _relativeMetaPath, "use relative path for meta info file path in generated code");
    }

    int parseCommandLine(int argc, char **argv) {
        ASSERT(driver.parseCommandLine(argc, argv));

        if (!_configFile.has_value()) {
            PANIC("No config file specified! please use -c/--config <lua file>");
        }

        configFile       = fs::absolute(_configFile.value()).string();
        outdir           = fs::absolute(_outdir.value_or(DEFAULT_OUTPUT_DIR)).string();
        workdir          = fs::absolute(_workdir.value_or(DEFAULT_WORK_DIR)).string();
        topClock         = _topClock.value_or(DEFAULT_CLOCK_NAME);
        sampleEdge       = _sampleEdge.value_or(DEFAULT_SAMPLE_EDGE);
        distributeDPI    = _distributeDPI.value_or(false);
        quiet            = _quiet.value_or(false);
        relativeMetaPath = _relativeMetaPath.value_or(false);
        metaInfoFilePath = outdir + "/dpi_exporter.meta.json";
        dpiFilePath      = outdir + "/" + _dpiFile.value_or(DEFAULT_DPI_FILE_NAME);
        fmt::println("[dpi_exporter]\n\tconfigFile: {}\n\tdpiFileName: {}\n\toutdir: {}\n\tworkdir: {}\n\tdistributeDPI: {}\n\tquiet: {}\n", configFile, _dpiFile.value_or(DEFAULT_DPI_FILE_NAME), outdir, workdir, distributeDPI, quiet);

        driver.setVerbose(!quiet);

        configFileContent = [&]() {
            std::ifstream configFileStream(configFile);
            if (!configFileStream.is_open()) {
                PANIC("Failed to open config file: {}", configFile);
            }
            std::stringstream buffer;
            buffer << configFileStream.rdbuf();
            std::string content = buffer.str();
            // Replace newlines with spaces
            std::replace(content.begin(), content.end(), '\n', ' ');
            return content;
        }();

        if (distributeDPI) {
            ASSERT(insertModuleName->empty(), "`insertModuleName` should be empty when `distributeDPI` is TRUE");
        }

        topModuleName = driver.tryGetTopModuleName().value_or("");

        ASSERT(sampleEdge == "posedge" || sampleEdge == "negedge", "Invalid sample edge '{}', should be either 'posedge' or 'negedge'", sampleEdge);

        for (const auto &file : _files) {
            if (file.ends_with(".f")) {
                // Parse filelist
                std::vector<std::string> fileList = parseFileList(file);
                for (const auto &listedFile : fileList) {
                    driver.addFile(listedFile);
                }
            } else {
                driver.addFile(file);
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

        driver.loadAllSources([this](std::string_view file) -> std::string {
            auto f = fs::absolute(slang_common::file_manage::backupFile(file, this->workdir)).string();
            this->tmpFiles.push_back(f);
            return f;
        });

        ASSERT(driver.processOptions());
        ASSERT(driver.parseAllSources());
        ASSERT(driver.reportParseDiags());

        std::shared_ptr<SyntaxTree> tree = driver.getSingleSyntaxTree();

        auto compilation = driver.createAndReportCompilation(false);
        if (topModuleName == "") {
            topModuleName = compilation->getRoot().topInstances[0]->name;
            fmt::println("[dpi_exporter] `--top` is not set, use `{}` as top module name", topModuleName);
        }
        fmt::println("[dpi_exporter] topModuleName: {}", topModuleName);

        Config::getInstance().quietEnabled  = quiet;
        Config::getInstance().topModuleName = topModuleName;
        Config::getInstance().sampleEdge    = sampleEdge;
        Config::getInstance().pldmGfifoDpi  = pldmGfifoDpi.value_or(false);

        // Get DPIExporterInfoVec from the provided lua config file
        auto [conciseSignalPatternVec, sensitiveTriggerInfoVec] = this->extractConfigInfo();
        ASSERT(!conciseSignalPatternVec.empty(), "No signal pattern found in the config file");

        // Get SignalGroupVec from the provided conciseSignalPatternVec
        std::vector<SignalGroup> signalGroupVec;
        for (auto &cpattern : conciseSignalPatternVec) {
            fmt::println("\n[dpi_exporter] SignalGroup.name: {}, SignalGroup.moduleName: {}", cpattern.name, cpattern.moduleName);
            auto isTopModule = cpattern.moduleName == topModuleName;
            auto getter      = SignalInfoGetter(cpattern, compilation.get(), isTopModule);
            tree->root().visit(getter);

            // Avoid duplicate signals
            for (auto &hierPath : getter.shouldRemoveHierPaths) {
                fmt::println("\t\tshouldRemove: {}", hierPath);
                for (auto &sg : signalGroupVec) {
                    for (int i = 0; i < sg.signalInfoVec.size(); i++) {
                        if (sg.signalInfoVec[i].hierPath == hierPath) {
                            sg.signalInfoVec.erase(sg.signalInfoVec.begin() + i);
                            break;
                        }
                    }
                }
            }

            if (cpattern.sensitiveSignals != "") {
                ASSERT(getter.gotSensitiveSignal, "No sensitive signal found in the signal group, sensitive signal is chosen from `signals`, maybe you should adjust your `signals` value to include sensitive signals", cpattern.name, cpattern.signals, cpattern.sensitiveSignals);
            }

            ASSERT(!getter.signalGroup.signalInfoVec.empty(), "No signal found in the signal group, please check your `signals`/`moduleName`/`instName` value", cpattern.name, cpattern.signals, cpattern.moduleName, cpattern.instName);

            signalGroupVec.push_back(getter.signalGroup);
        }
        fmt::println("");

        std::vector<SignalGroup> mergedSignalGroupVec;
        mergedSignalGroupVec.emplace_back(SignalGroup{
            .name                   = "DEFAULT",
            .moduleName             = "",
            .cpattern               = "",
            .signalInfoVec          = {},
            .sensitiveSignalInfoVec = {},
        });

        for (auto &sg : signalGroupVec) {
            // If the signal group has sensitive signals, it will be added to the mergedSignalGroupVec as a new group,
            // otherwise, the signals in the signal group will be added to the DEFAULT group.
            if (sg.sensitiveSignalInfoVec.empty()) {
                mergedSignalGroupVec.at(0).signalInfoVec.insert(mergedSignalGroupVec.at(0).signalInfoVec.end(), sg.signalInfoVec.begin(), sg.signalInfoVec.end());
            } else {
                mergedSignalGroupVec.emplace_back(sg);
            }
        }

        // Rewrite the syntax tree(insert `dpi_exporter_tick` function into the top module)
        if (!distributeDPI) {
            auto rewriter = ExporterRewriter(compilation.get(), insertModuleName.value_or(topModuleName), sampleEdge, topModuleName, topClock, mergedSignalGroupVec);
            auto newTree  = rewriter.transform(tree);

            fmt::println("[dpi_exporter] start rebuilding syntax tree");
            fflush(stdout);

            tree = driver.rebuildSyntaxTree(*newTree, !quiet, 20);

            fmt::println("[dpi_exporter] done rebuilding syntax tree");
            fflush(stdout);
        } else {
            // `distributeDPI` means scatter the DPI functions into different modules
            ASSERT(false, "TODO: distributeDPI is not supported yet!");
        }

        std::string dpiFileContent = renderDpiFile(mergedSignalGroupVec, sensitiveTriggerInfoVec, topModuleName, distributeDPI, metaInfoFilePath, relativeMetaPath);

        {
            fmt::println("[dpi_exporter] start generating dpi file, outdir: {}, dpiFilePath: {}", outdir, dpiFilePath);
            fflush(stdout);

            std::fstream dpiFuncFile;
            dpiFuncFile.open(dpiFilePath, std::ios::out);
            dpiFuncFile << dpiFileContent;
            dpiFuncFile.close();

            fmt::println("[dpi_exporter] finish generating dpi file, outdir: {}, dpiFilePath: {}", outdir, dpiFilePath);
            fflush(stdout);
        }

        {
            // The syntaxtree of the input rtl files has been changed, so we need to regenerate the new rtl files.
            fmt::println("[dpi_exporter] start generating new rtl files, outdir: {}", outdir);
            fflush(stdout);

            slang_common::file_manage::generateNewFile(SyntaxPrinter::printFile(*tree), outdir);

            fmt::println("[dpi_exporter] finish generating new rtl files, outdir: {}", outdir);
            fflush(stdout);
        }

        // Delete temporary files
        for (auto &file : tmpFiles) {
            DELETE_FILE(file);
        }

        // Print all valid signals
        int idx = 0;
        std::vector<std::string> portHierPathVec;
        for (auto &sg : signalGroupVec) {
            for (auto &s : sg.signalInfoVec) {
                idx++;

                if (!quiet) {
                    fmt::println("[{}] handleId:<{}> hierPath:<{}> signalName:<{}> typeStr:<{}> bitWidth:<{}>", idx, s.handleId, s.hierPath, s.signalName, s.vpiTypeStr, s.bitWidth);
                }

                portHierPathVec.emplace_back(s.hierPath);
            }
        }

        // Save the command line arguments and files into json file
        metaInfoJson["cmdLine"]           = cmdLineStr;
        metaInfoJson["filelist"]          = driver.getFiles();
        metaInfoJson["topModuleName"]     = topModuleName;
        metaInfoJson["dpiFilePath"]       = dpiFilePath;
        metaInfoJson["insertModuleName"]  = insertModuleName.value_or(topModuleName);
        metaInfoJson["configFileContent"] = configFileContent;
        metaInfoJson["exportedSignals"]   = portHierPathVec;

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
