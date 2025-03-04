#include "dpi_exporter.h"

// Used when distributeDPI is FALSE
class DPIExporterRewriter_1 : public slang::syntax::SyntaxRewriter<DPIExporterRewriter_1> {
  private:
    slang::ast::Compilation compilation;
    std::shared_ptr<SyntaxTree> &tree;

    SemanticModel model;

    std::string topModuleName;
    std::string clock;

  public:
    std::vector<PortInfo> portVec;
    bool findTopModule = false;

    DPIExporterRewriter_1(std::shared_ptr<SyntaxTree> &tree, std::string topModuleName, std::string clock, std::vector<PortInfo> portVec) : tree(tree), topModuleName(topModuleName), clock(clock), portVec(portVec), model(compilation) { compilation.addSyntaxTree(tree); }

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

  public:
    std::string dpiFuncFileContent;
    std::vector<std::string> hierPathVec;
    std::vector<std::string> hierPathNameVec;
    std::vector<PortInfo> portVec;

    std::vector<PortInfo> portVecAll;

    std::string dpiTickFuncParam;
    std::string dpiTickFuncBody;

    int instSize          = 0;
    bool writeGenStatment = false;
    bool distributeDPI    = false;
    bool quiet            = false;

    DPIExporterRewriter(std::shared_ptr<SyntaxTree> &tree, DPIExporterInfo info, bool distributeDPI, bool writeGenStatment = false, int instSize = 0, bool quiet = false) : tree(tree), info(info), distributeDPI(distributeDPI), writeGenStatment(writeGenStatment), instSize(instSize), quiet(quiet), model(compilation) {
        compilation.addSyntaxTree(tree);
        moduleName = info.moduleName;
        clock      = info.clock;
    }

    bool _checkValidSignal(std::string signal) {
        for (const auto &pattern : info.signalPatternVec) {
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

    bool checkValidSignal(std::string signal) {
        if (info.signalPatternVec.size() == 0) {
            return !_checkInvalidSignal(signal);
        }

        if (_checkInvalidSignal(signal)) {
            return false;
        }

        return _checkValidSignal(signal);
    }

    void handle(ModuleDeclarationSyntax &syntax);
    void handle(HierarchyInstantiationSyntax &inst);
};