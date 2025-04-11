#include "dpi_exporter.h"

#define DEFAULT_CLOCK_NAME "clock"

// Used when distributeDPI is FALSE
class DPIExporterRewriter_1 : public slang::syntax::SyntaxRewriter<DPIExporterRewriter_1> {
  private:
    slang::ast::Compilation compilation;
    std::shared_ptr<SyntaxTree> &tree;

    SemanticModel model;

    std::string topModuleName;
    std::string clock;
    std::string sampleEdge;

  public:
    std::vector<PortInfo> portVec;
    bool findTopModule = false;

    DPIExporterRewriter_1(std::shared_ptr<SyntaxTree> &tree, std::string topModuleName, std::string clock, std::string sampleEdge, std::vector<PortInfo> portVec) : tree(tree), topModuleName(topModuleName), clock(clock), sampleEdge(sampleEdge), portVec(portVec), model(compilation) { compilation.addSyntaxTree(tree); }

    void handle(ModuleDeclarationSyntax &syntax);
};

class DPIExporterRewriter : public slang::syntax::SyntaxRewriter<DPIExporterRewriter> {
  private:
    slang::ast::Compilation compilation;
    std::shared_ptr<SyntaxTree> &tree;

    SemanticModel model;

    DPIExporterInfo info;
    std::string moduleName;
    std::string clock;
    std::string sampleEdge;

  public:
    std::vector<std::string> hierPathVec;
    std::vector<std::string> hierPathNameVec;
    std::vector<std::string> hierPathNameDotVec;
    std::vector<PortInfo> portVec;

    std::vector<PortInfo> portVecAll;

    std::string dpiFuncFileContent;
    std::vector<std::string> dpiTickFuncParamVec;
    std::vector<std::string> dpiTickFuncBodyVec;

    int instSize          = 0;
    bool writeGenStatment = false;
    bool distributeDPI    = false;
    bool quiet            = false;

    DPIExporterRewriter(std::shared_ptr<SyntaxTree> &tree, DPIExporterInfo info, std::string sampleEdge, bool distributeDPI, bool writeGenStatment = false, int instSize = 0, bool quiet = false) : tree(tree), info(info), sampleEdge(sampleEdge), distributeDPI(distributeDPI), writeGenStatment(writeGenStatment), instSize(instSize), quiet(quiet), model(compilation) {
        compilation.addSyntaxTree(tree);
        moduleName = info.moduleName;
        clock      = info.clock;
    }

    bool _checkValidSignal(std::string signal, std::vector<std::string> &signalPatternVec) {
        for (const auto &pattern : signalPatternVec) {
            std::regex regexPattern(pattern);

            if (std::regex_match(signal, regexPattern)) {
                return true;
            }
        }

        return false;
    }

    bool _checkInvalidSignal(std::string signal) {
        for (const auto &pattern : info.disableSignalPatternVec) {
            std::regex regexPattern(pattern);

            if (std::regex_match(signal, regexPattern)) {
                return true;
            }
        }

        return false;
    }

    bool checkValidSignal(std::string signal, std::vector<std::string> &signalPatternVec) {
        if (_checkInvalidSignal(signal)) {
            return false;
        }

        if (signalPatternVec.empty()) {
            return true;
        } else {
            return _checkValidSignal(signal, signalPatternVec);
        }
    }

    bool appendPortVec(std::string_view type, PortInfo &portInfo) {
        ASSERT(type == "PORT" || type == "NET" || type == "VAR" || type == "WR_VAR", type, portInfo);

        auto &signalPatternVec = type == "WR_VAR" ? info.writableSignalPatternVec : info.signalPatternVec;

        if (checkValidSignal(portInfo.name, signalPatternVec)) {
            portVec.emplace_back(portInfo);

            if (!quiet) {
                fmt::println("[DPIExporterRewriter] [{}VALID{}] [{}] moudleName:<{}> signalName:<{}> bitWidth:<{}> handleId:<{}>", ANSI_COLOR_GREEN, ANSI_COLOR_RESET, type, moduleName, portInfo.name, portInfo.bitWidth, portInfo.handleId);
                fflush(stdout);
            }

            return true;
        } else {
            if (!quiet) {
                fmt::println("[DPIExporterRewriter] [{}IGNORED{}] [{}] moudleName:<{}> signalName:<{}> bitWidth:<{}> handleId:<{}>", ANSI_COLOR_RED, ANSI_COLOR_RESET, type, moduleName, portInfo.name, portInfo.bitWidth, portInfo.handleId);
                fflush(stdout);
            }
            return false;
        }
    }

    void handle(ModuleDeclarationSyntax &syntax);
    void handle(HierarchyInstantiationSyntax &inst);
};