#include "SemanticModel.h"
#include "SlangCommon.h"
#include "argparse/argparse.hpp"
#include "fmt/base.h"
#include "libassert/assert.hpp"
#include "slang/ast/ASTVisitor.h"
#include "slang/ast/Expression.h"
#include "slang/ast/SemanticFacts.h"
#include "slang/ast/Symbol.h"
#include "slang/ast/symbols/InstanceSymbols.h"
#include "slang/ast/symbols/PortSymbols.h"
#include "slang/ast/symbols/VariableSymbols.h"
#include "slang/numeric/SVInt.h"
#include "slang/parsing/Parser.h"
#include "slang/parsing/Preprocessor.h"
#include "slang/parsing/TokenKind.h"
#include "slang/syntax/AllSyntax.h"
#include "slang/syntax/SyntaxKind.h"
#include "slang/syntax/SyntaxNode.h"
#include "slang/util/Util.h"
#include <cstddef>
#include <cstdio>
#include <fstream>
#include <regex>
#include <span>
#include <string>
#include <unordered_set>
#include <vector>

#define LUA_IMPL
#include "minilua/minilua.h"
#include "sol/sol.hpp"

using namespace slang::parsing;

namespace fs = std::filesystem;

uint64_t globalHandleIdx = 0; // Each signal has its own handle value(integer)

#define DEFAULT_OUTPUT_DIR ".dpi_exporter"
#define DEFAULT_WORK_DIR ".dpi_exporter"

#define ANSI_COLOR_RED "\x1b[31m"
#define ANSI_COLOR_GREEN "\x1b[32m"
#define ANSI_COLOR_RESET "\x1b[0m"

#define INSERT_BEFORE_FILE_HEAD(filePath, str)                                                                                                                                                                                                                                                                                                                                                                 \
    do {                                                                                                                                                                                                                                                                                                                                                                                                       \
        system(fmt::format("sed -i \"1i {}\" {}", str, filePath).c_str());                                                                                                                                                                                                                                                                                                                                     \
    } while (0)

#define INSERT_AFTER_FILE_END(filePath, str)                                                                                                                                                                                                                                                                                                                                                                   \
    do {                                                                                                                                                                                                                                                                                                                                                                                                       \
        system(fmt::format("echo \"\n{}\" >> {}", str, filePath).c_str());                                                                                                                                                                                                                                                                                                                                     \
    } while (0)

std::vector<std::string> parseFileList(const std::string &filePath) {
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

void generateNewFile(const std::string &content, const std::string &newPath) {
    std::istringstream stream(content);
    std::string line;
    std::string currentFile;
    std::ofstream outFile;

    if (newPath != "") {
        if (!std::filesystem::exists(newPath)) {
            std::filesystem::create_directories(newPath);
        }
    }

    while (std::getline(stream, line)) {
        if (line.find("//BEGIN:") == 0) {
            currentFile = line.substr(8);

            std::filesystem::path path = currentFile;
            if (newPath != "") {
                currentFile = newPath + "/" + path.filename().string();

                if (!std::filesystem::exists(newPath)) {
                    std::filesystem::create_directories(newPath);
                }
            }

            outFile.open(currentFile, std::ios::out | std::ios::trunc);
            if (!outFile.is_open()) {
                std::cerr << "Failed to open file: " << currentFile << std::endl;
                ASSERT(false);
            }
        } else if (line.find("//END:") == 0) {
            if (outFile.is_open()) {
                outFile.close();
            }
        } else {
            if (outFile.is_open()) {
                outFile << line << std::endl;
            }
        }
    }

    if (outFile.is_open()) {
        outFile.close();
    }
}

std::string backupFile(std::string_view inputFile, std::string workdir) {
    std::filesystem::path _workdir(workdir);
    std::filesystem::path path(inputFile);
    std::string targetFile = std::string(workdir) + "/" + path.filename().string() + ".bak";

    if (!std::filesystem::exists(_workdir)) {
        std::filesystem::create_directories(_workdir);
    }

    if (std::filesystem::exists(targetFile)) {
        std::filesystem::remove(targetFile);
    }
    std::filesystem::copy_file(inputFile, targetFile.c_str());

    INSERT_BEFORE_FILE_HEAD(targetFile, fmt::format("//BEGIN:{}", inputFile));
    INSERT_AFTER_FILE_END(targetFile, fmt::format("//END:{}", inputFile));

    return targetFile;
}

sol::object getLuaTableItemOrFailed(sol::table &table, const std::string &key) {
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

class HierPathGetter : public ASTVisitor<HierPathGetter, false, false> {
  public:
    std::string moduleName;
    std::string instName;
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

using PortInfo = struct {
    std::string name;
    std::string direction;
    bitwidth_t bitWidth;
    uint64_t handleId;
    std::string typeStr;
};

using DPIExporterInfo = struct {
    std::string moduleName;
    std::string clock;
    std::vector<std::string> signalPatternVec;
};

class DPIExporterRewriter : public slang::syntax::SyntaxRewriter<DPIExporterRewriter> {
  public:
    slang::ast::Compilation compilation;
    std::shared_ptr<SyntaxTree> &tree;

    SemanticModel model;

    DPIExporterInfo info;
    std::string moduleName;
    std::string clock;
    std::string dpiFuncFileContent;
    std::vector<std::string> hierPathVec;
    std::vector<std::string> hierPathNameVec;
    std::vector<PortInfo> portVec;

    int instSize          = 0;
    bool writeGenStatment = false;

    DPIExporterRewriter(std::shared_ptr<SyntaxTree> &tree, DPIExporterInfo info, bool writeGenStatment = false, int instSize = 0) : tree(tree), info(info), writeGenStatment(writeGenStatment), instSize(instSize), model(compilation) {
        compilation.addSyntaxTree(tree);
        moduleName = info.moduleName;
        clock      = info.clock;
    }

    bool checkValidSignal(std::string signal) {
        if (info.signalPatternVec.size() == 0) {
            return true;
        }

        for (const auto &pattern : info.signalPatternVec) {
            std::regex regexPattern(pattern);

            if (std::regex_match(signal, regexPattern)) {
                return true;
            }
        }

        return false;
    }

    void handle(ModuleDeclarationSyntax &syntax) {
        if (syntax.header->name.rawText() == moduleName) {
            fmt::println("[DPIExporterRewriter] found module: {}, writeGenStatment: {}", moduleName, writeGenStatment);

            if (writeGenStatment) {
                MemberSyntax *lastMember;
                for (auto m : syntax.members) {
                    lastMember = m;
                }
                ASSERT(lastMember != nullptr, "TODO:");

                ASSERT(hierPathNameVec.size() == 0);
                for (int i = 0; i < hierPathVec.size(); i++) {
                    std::string hierPathName = hierPathVec[i];
                    std::replace(hierPathName.begin(), hierPathName.end(), '.', '_');
                    hierPathNameVec.emplace_back(hierPathName);
                }

                std::string sv_genStatement = "\ngenerate // DPI Exporter\n";

                std::string sv_readSignalFuncParam       = "";
                std::string sv_readSignalFuncInvokeParam = "";
                std::string dpiFuncParam                 = "";
                std::string dpiFuncBody                  = "";
                for (int i = 0; i < portVec.size(); i++) {
                    auto &p = portVec[i];
                    if (p.bitWidth == 1) {
                        sv_readSignalFuncParam += fmt::format("\t\tinput bit {},\n", p.name, p.name);
                    } else {
                        sv_readSignalFuncParam += fmt::format("\t\tinput bit [{}:0] {},\n", p.bitWidth - 1, p.name);
                    }

                    sv_readSignalFuncInvokeParam += fmt::format("{}, ", p.name);

                    if (p.bitWidth == 1) {
                        dpiFuncParam += fmt::format("const uint8_t {}, ", p.name);
                        // dpiFuncParam += fmt::format("const svBit {}, ", p.name);
                    } else {
                        dpiFuncParam += fmt::format("const uint32_t *{}, ", p.name);
                        // dpiFuncParam += fmt::format("const svBitVecVal *{}, ", p.name);
                    }
                }

                // Remove the last comma
                sv_readSignalFuncParam.pop_back();
                sv_readSignalFuncParam.pop_back();

                sv_readSignalFuncInvokeParam.pop_back();
                sv_readSignalFuncInvokeParam.pop_back();

                dpiFuncParam.pop_back();
                dpiFuncParam.pop_back();

                for (int instId = 0; instId < instSize; instId++) {
                    std::string hierPathName      = hierPathNameVec[instId];
                    std::string dpiFuncNamePrefix = fmt::format("VERILUA_DPI_EXPORTER_{}", hierPathName);
                    std::string dpiFuncName       = fmt::format("{}_TICK", dpiFuncNamePrefix);

                    std::string sv_dpiBlock = fmt::format(R"(
if(instId == {}) begin
    // hierPath: {}
    import "DPI-C" function void {}(
{}
    );

    always @(posedge {}) begin
        {}({});
    end
end
                    )",
                                                          instId, hierPathVec[instId], dpiFuncName, sv_readSignalFuncParam, clock, dpiFuncName, sv_readSignalFuncInvokeParam);

                    sv_genStatement += sv_dpiBlock;

                    // Generate DPI file
                    dpiFuncBody += fmt::format("extern \"C\" void {}({}) {{\n", dpiFuncName, dpiFuncParam);
                    dpiFuncFileContent += fmt::format("// hierPath: {}\n", hierPathName, instId);
                    for (auto &p : portVec) {
                        auto beatSize = coverWith32(p.bitWidth);
                        ASSERT(beatSize >= 1);

                        // Signal declaration
                        if (beatSize == 1) {
                            if (p.bitWidth == 1) {
                                // dpiFuncFileContent += fmt::format("volatile uint8_t __{}_{}; // bits: {}, handleId: {}\n", hierPathName, p.name, p.bitWidth, p.handleId);
                                dpiFuncFileContent += fmt::format("uint8_t __{}_{}; // bits: {}, handleId: {}\n", hierPathName, p.name, p.bitWidth, p.handleId);
                                dpiFuncBody += fmt::format("\t__{}_{} = {};\n", hierPathName, p.name, p.name);
                            } else {
                                // dpiFuncFileContent += fmt::format("volatile uint32_t __{}_{}; // bits: {}, handleId: {}\n", hierPathName, p.name, p.bitWidth, p.handleId);
                                dpiFuncFileContent += fmt::format("uint32_t __{}_{}; // bits: {}, handleId: {}\n", hierPathName, p.name, p.bitWidth, p.handleId);
                                dpiFuncBody += fmt::format("\t__{}_{} = *{};\n", hierPathName, p.name, p.name);
                            }
                        } else {
                            // dpiFuncFileContent += fmt::format("volatile uint32_t __{}_{}[{}]; // bits: {}, handleId: {}\n", hierPathName, p.name, beatSize, p.bitWidth, p.handleId);
                            dpiFuncFileContent += fmt::format("uint32_t __{}_{}[{}]; // bits: {}, handleId: {}\n", hierPathName, p.name, beatSize, p.bitWidth, p.handleId);
                            for (int k = 0; k < beatSize; k++) {
                                dpiFuncBody += fmt::format("\t__{}_{}[{}] = {}[{}];\n", hierPathName, p.name, k, p.name, k);
                            }
                        }
                    }

                    for (auto &p : portVec) {
                        auto beatSize = coverWith32(p.bitWidth);

                        if (beatSize == 1) {
                            dpiFuncFileContent += fmt::format(R"(
extern "C" uint32_t {}_{}_GET() {{
    return (uint32_t)__{}_{};
}}
                            )",
                                                              dpiFuncNamePrefix, p.name, hierPathName, p.name);

                            dpiFuncFileContent += fmt::format(R"(
extern "C" uint64_t {}_{}_GET64() {{
    return (uint64_t)__{}_{};
}}
                            )",
                                                              dpiFuncNamePrefix, p.name, hierPathName, p.name);

                            dpiFuncFileContent += fmt::format(R"(
extern "C" void {}_{}_GET_HEX_STR(char *hexStr) {{
    uint32_t value = __{}_{};
    for(int i = {}; i >= 0; --i) {{
        hexStr[i] = "0123456789abcdef"[value & 0xF];
        value >>= 4;
    }}
    hexStr[{}] = '\0';
}}
                            )",
                                                              dpiFuncNamePrefix, p.name, hierPathName, p.name, coverWith4(p.bitWidth) - 1, coverWith4(p.bitWidth));

                        } else { // beatSize > 1
                            dpiFuncFileContent += fmt::format(R"(
extern "C" uint32_t {}_{}_GET() {{
    return (uint32_t)__{}_{}[0];
}}
                            )",
                                                              dpiFuncNamePrefix, p.name, hierPathName, p.name);

                            dpiFuncFileContent += fmt::format(R"(
extern "C" uint64_t {}_{}_GET64() {{
    return (uint64_t)((uint64_t)(__{}_{}[1]) << 32 | (uint64_t)__{}_{}[0]);
}}
                            )",
                                                              dpiFuncNamePrefix, p.name, hierPathName, p.name, hierPathName, p.name);

                            {
                                std::string tmp = "";
                                for (int k = 0; k < beatSize; k++) {
                                    tmp = tmp + fmt::format("\tvalues[{}] = __{}_{}[{}];\n", k, hierPathName, p.name, k);
                                }
                                tmp.pop_back();

                                dpiFuncFileContent += fmt::format(R"(
extern "C" void {}_{}_GET_VEC(uint32_t *values) {{
{}
}}
                                )",
                                                                  dpiFuncNamePrefix, p.name, tmp);
                            }

                            if (beatSize == 2) {
                                dpiFuncFileContent += fmt::format(R"(
extern "C" void {}_{}_GET_HEX_STR(char *hexStr) {{
    uint32_t value;
    value = __{}_{}[0];
    for(int i = 8 + {} - 1; i >= {}; --i) {{
        hexStr[i] = "0123456789abcdef"[value & 0xF];
        value >>= 4;
    }}
    
    value = __{}_{}[1];
    for(int i = {} - 1; i >= 0; --i) {{
        hexStr[i] = "0123456789abcdef"[value & 0xF];
        value >>= 4;
    }}

    hexStr[{}] = '\0';
}}
)",

                                                                  dpiFuncNamePrefix, p.name, hierPathName, p.name, coverWith4(p.bitWidth) - 8, coverWith4(p.bitWidth) - 8, hierPathName, p.name, coverWith4(p.bitWidth) - 8, coverWith4(p.bitWidth));
                            } else { // beatSize > 2
                                std::string tmp         = "";
                                std::string beatValName = fmt::format("__{}_{}", hierPathName, p.name);
                                int beatIdx             = 0;
                                for (int k = beatSize - 1; k >= 0; k--) {
                                    tmp = tmp + fmt::format(R"(
    value = {}[{}];
    for(int i = {}; i >= {}; --i) {{
        hexStr[i] = "0123456789abcdef"[value & 0xF];
        value >>= 4;
    }}
)",
                                                            beatValName, beatIdx, (k + 1) * 8 - 1, k * 8);
                                    beatIdx++;
                                }
                                tmp.pop_back();

                                dpiFuncFileContent += fmt::format(R"(
extern "C" void {}_{}_GET_HEX_STR(char *hexStr) {{
    uint32_t value;
{}
    hexStr[{}] = '\0';
}}
                                )",
                                                                  dpiFuncNamePrefix, p.name, tmp, coverWith4(p.bitWidth));
                            }
                        }
                    }
                    dpiFuncBody += "}\n\n";
                    dpiFuncFileContent += "\n";
                }
                sv_genStatement += "\nendgenerate\n";

                dpiFuncFileContent += dpiFuncBody;
                dpiFuncFileContent += "\n";

                insertAfter(*lastMember, parse(sv_genStatement));
            } else {
                auto instSym    = model.syntaxToInstanceSymbol(syntax);
                auto foundClock = false;
                for (auto p : instSym->body.getPortList()) {
                    // fmt::println("p type => {}", toString(p->kind));

                    auto &pp      = p->as<PortSymbol>();
                    auto portName = std::string(pp.name);

                    auto bitWidth  = pp.getType().getBitWidth();
                    auto direction = toString(pp.direction);

                    if (portName == clock && bitWidth == 1 && direction == "In") {
                        foundClock = true;
                    }

                    // TODO: Check port type
                    if (checkValidSignal(portName)) {
                        portVec.emplace_back(PortInfo{.name = portName, .direction = std::string(direction), .bitWidth = bitWidth, .handleId = globalHandleIdx, .typeStr = "vpiNet"}); // TODO: typeStr
                        fmt::println("[DPIExporter] [{}VALID{}] moudleName:<{}> portName:<{}> direction:<{}> bitWidth:<{}> handleId:<{}>", ANSI_COLOR_GREEN, ANSI_COLOR_RESET, moduleName, portName, direction, bitWidth, globalHandleIdx);
                        fflush(stdout);
                        globalHandleIdx++;
                    } else {
                        fmt::println("[DPIExporter] [{}IGNORED{}] moudleName:<{}> portName:<{}> direction:<{}> bitWidth:<{}>", ANSI_COLOR_RED, ANSI_COLOR_RESET, moduleName, portName, direction, bitWidth);
                        fflush(stdout);
                    }
                }
                ASSERT(foundClock, "Clock signal not found!", moduleName, clock);

                if (syntax.header->parameters == nullptr) {
                    // If the module has no parameters, add one
                    SmallVector<TokenOrSyntax> declsVec;
                    declsVec.push_back(TokenOrSyntax(&parse("parameter instId = 5555")));

                    std::span<TokenOrSyntax> decls = declsVec.copy(this->alloc);
                    syntax.header->parameters      = &this->factory.parameterPortList(makeId("#"), makeId("("), decls, makeId(")"));
                } else {
                    PANIC("TODO: has Parameters");
                }
            }
        }

        if (!writeGenStatment) {
            visitDefault(syntax);
        }
    };

    // void handle(ParameterDeclarationSyntax &decl) {
    //     PANIC("TODO: handle ParameterDeclarationSyntax");
    // }

    void handle(HierarchyInstantiationSyntax &inst) {
        std::string _moduleName = std::string(inst.type.rawText());

        if (_moduleName == moduleName) {
            std::string _instName = std::string(inst.instances[0]->decl->name.rawText());

            HierPathGetter visitor(_moduleName, _instName);
            compilation.getRoot().visit(visitor);
            ASSERT(visitor.hierPaths.size() == 1, "TODO:", visitor.hierPaths.size());

            std::string hierPath = visitor.hierPaths[0];
            hierPathVec.emplace_back(hierPath);
            fmt::println("[DPIExporterRewriter] moudleName:<{}>, instName:<{}>, hierPath:<{}>", inst.type.rawText(), _instName, hierPath);

            // Each module has only one unique instance ID
            SmallVector<TokenOrSyntax> paramAssignVec;
            paramAssignVec.push_back(TokenOrSyntax(&parse(fmt::format(".instId({})", instSize))));
            inst.parameters = &this->factory.parameterValueAssignment(makeId("#"), makeId("("), paramAssignVec.copy(this->alloc), makeId(")"));

            instSize++;
        }
    };
};

int main(int argc, char **argv) {
    argparse::ArgumentParser program("dpi_exporter");
    program.add_argument("-f", "--file").help("file/filelist to parse").required().append().action([](const std::string &value) { return value; });
    program.add_argument("-c", "--config").help("`Lua` file that contains the module info and the corresponding signal info").required().action([](const std::string &value) { return value; });
    program.add_argument("-od", "--out-dir").help("output directory").default_value(DEFAULT_OUTPUT_DIR).action([](const std::string &value) { return value; });
    program.add_argument("-wd", "--work-dir").help("working directory").default_value(DEFAULT_WORK_DIR).action([](const std::string &value) { return value; });

    try {
        program.parse_args(argc, argv);
    } catch (const std::runtime_error &err) {
        ASSERT(false, err.what());
    }

    std::string configFile = fs::absolute(program.get<std::string>("--config")).string();
    std::string outdir     = fs::absolute(program.get<std::string>("--out-dir")).string();
    std::string workdir    = fs::absolute(program.get<std::string>("--work-dir")).string();

    std::vector<std::string> _files = program.get<std::vector<std::string>>("--file");
    std::vector<std::string> files;
    for (const auto &file : _files) {
        if (file.ends_with(".f")) {
            // Parse filelist
            std::vector<std::string> fileList = parseFileList(file);
            for (const auto &listedFile : fileList) {
                files.push_back(backupFile(fs::absolute(listedFile).string(), workdir));
            }
        } else {
            files.push_back(backupFile(fs::absolute(file).string(), workdir));
        }
    }

    for (const auto &file : files) {
        fmt::println("[dpi_exporter] get file: {}", file);
        fflush(stdout);
    }

    std::vector<std::string_view> filesSV;
    filesSV.reserve(files.size());
    for (const auto &str : files) {
        filesSV.emplace_back(str);
    }

    // Parse syntax tree
    std::shared_ptr<SyntaxTree> tree;
    auto treeOrError = SyntaxTree::fromFiles(filesSV);
    if (treeOrError) {
        tree = *treeOrError;
    } else {
        auto err = treeOrError.error();
        fmt::println("Error: {}\ncode: {}\nmessage: {}\ncatagory: {}", err.second, err.first.value(), err.first.message(), err.first.category().name());
        PANIC("SyntaxTree::fromFiles failed");
    }

    // Make sure that we have built the SyntaxTree successfully, any error will stop the program
    auto treeDiags = tree->diagnostics();
    if (treeDiags.empty() == false) {
        if (slang_common::checkDiagsError(treeDiags)) {
            auto ret = DiagnosticEngine::reportAll(SyntaxTree::getDefaultSourceManager(), treeDiags);
            fmt::println("{}", ret);
            PANIC("Syntax error");
        }
    }

    // Do compilation and check any compilation error
    Compilation compilation;
    compilation.addSyntaxTree(tree);

    auto compDiags = compilation.getAllDiagnostics();
    if (compDiags.empty() == false) {
        if (slang_common::checkDiagsError(compDiags)) {
            auto ret = DiagnosticEngine::reportAll(SyntaxTree::getDefaultSourceManager(), compDiags);
            fmt::println("{}", ret);
            PANIC("Compilation error");
        }
    }

    sol::state lua;
    lua.open_libraries(sol::lib::base);
    lua.open_libraries(sol::lib::string);
    lua.open_libraries(sol::lib::table);
    lua.open_libraries(sol::lib::math);
    lua.open_libraries(sol::lib::string);
    lua.open_libraries(sol::lib::io);
    lua.script_file(configFile);
    lua.script(fmt::format(R"(
assert(dpi_exporter_config ~= nil, "[dpi_exporter] dpi_exporter_config is nil in the config file => {}");
for i, tbl in ipairs(dpi_exporter_config) do
    for k, v in pairs(tbl) do
        if type(v) == "number" then
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
end
)",
                           configFile));

    std::vector<DPIExporterInfo> dpiExporterInfoVec;
    for (const auto &entry : (sol::table)lua["dpi_exporter_config"]) {
        sol::table item        = entry.second;
        std::string moduleName = getLuaTableItemOrFailed(item, "module").as<std::string>();
        std::string clock      = item["clock"].get_or(std::string("clock"));

        std::vector<std::string> signalPatternVec;
        for (const auto &strEntry : (sol::table)item["signal"]) {
            const auto &str = strEntry.second;
            if (str.is<std::string>()) {
                signalPatternVec.push_back(str.as<std::string>());
            } else {
                PANIC("Unexpected type");
            }
        }

        dpiExporterInfoVec.emplace_back(DPIExporterInfo{moduleName, clock, signalPatternVec});
    }
    ASSERT(dpiExporterInfoVec.size() > 0, "dpi_exporter_config is empty", configFile);

    std::unordered_set<uint64_t> handleSet;
    std::string dpiFuncFileContent = "";

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
        auto rewriter   = new DPIExporterRewriter(tree, info, false);
        auto newTree    = rewriter->transform(tree);
        ASSERT(rewriter->instSize > 0, "TODO: No instance found in the design, maybe it is a top-level module?", moduleName);

        auto rewriter_1         = new DPIExporterRewriter(newTree, info, true, rewriter->instSize);
        rewriter_1->hierPathVec = rewriter->hierPathVec;
        rewriter_1->portVec     = rewriter->portVec;
        auto newTree_1          = rewriter_1->transform(newTree);
        tree                    = slang_common::rebuildSyntaxTree(*newTree_1);

        for (int i = 0; i < rewriter_1->instSize; i++) {
            for (auto &p : rewriter_1->portVec) { // TODO: other module
                auto uniqueHandleId = p.handleId + (i << 24);
                auto &hierPathName  = rewriter_1->hierPathNameVec[i];

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
#include <functional>

using GetValue32Func = std::function<uint32_t ()>;
using GetValueVecFunc = std::function<void (uint32_t *)>;
using GetValueHexStrFunc = std::function<void (char*)>;
)") + "\n\n" + dpiFuncFileContent;

    std::fstream dpiFuncFile;
    dpiFuncFile.open(std::string(outdir) + "/dpi_func.cpp", std::ios::out);
    dpiFuncFile << dpiFuncFileContent;
    dpiFuncFile.close();

    generateNewFile(SyntaxPrinter::printFile(*tree), outdir);

    // Delete temporary files
    for (auto &file : files) {
        std::system(fmt::format("rm {}", file).c_str());
    }

    fmt::println("FINISH!");
}
