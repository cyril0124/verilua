// Simple integration test for slang_common (no external test framework needed).
// Verifies that Driver, SemanticModel, and helper functions work correctly
// against real SystemVerilog parsing.

#include "SlangCommon.h"
#include "SemanticModel.h"

#include <cassert>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>

namespace fs = std::filesystem;

static void writeFile(const std::string &path, const std::string &content) {
    std::ofstream out(path);
    out << content;
}

static std::string readFile(const std::string &path) {
    std::ifstream in(path);
    std::stringstream buf;
    buf << in.rdbuf();
    return buf.str();
}

// --- Test: Driver basic API ---
static void test_driver_basic() {
    using namespace slang_common;

    Driver driver("TestDriver");
    driver.setName("Updated");
    driver.setVerbose(true);

    driver.addFile("a.sv");
    driver.addFile("b.sv");
    assert(driver.getFiles().size() == 2);
    assert(driver.getFiles()[0] == "a.sv");

    std::vector<std::string> more = {"c.sv", "d.sv"};
    driver.addFiles(more);
    assert(driver.getFiles().size() == 4);

    printf("  [PASS] driver_basic\n");
}

// --- Test: SemanticModel with a real SV file ---
static void test_semantic_model() {
    const std::string file = "__test_semantic.sv";
    writeFile(file, R"(
module adder(
    input  wire [7:0] a,
    input  wire [7:0] b,
    output wire [7:0] sum
);
    assign sum = a + b;
endmodule
)");

    auto sm          = std::make_shared<slang::SourceManager>();
    auto treeOrError = slang::syntax::SyntaxTree::fromFile(file, *sm);
    assert(treeOrError.has_value());
    auto tree = treeOrError.value();
    assert(tree != nullptr);

    slang::ast::Compilation compilation;
    compilation.addSyntaxTree(tree);

    SemanticModel model(compilation);

    // getDeclaredSymbol on compilation unit
    const auto &cuSyntax = tree->root().as<slang::syntax::CompilationUnitSyntax>();
    auto cuSymbol        = model.getDeclaredSymbol(cuSyntax);
    assert(cuSymbol != nullptr);

    // Find module and get instance symbol
    assert(cuSyntax.members.size() > 0);
    auto &member = cuSyntax.members[0];
    assert(member->kind == slang::syntax::SyntaxKind::ModuleDeclaration);
    auto &modDecl = member->as<slang::syntax::ModuleDeclarationSyntax>();

    auto instSymbol = model.syntaxToInstanceSymbol(modDecl);
    assert(instSymbol != nullptr);

    // getDefSymbol / getInstSymbol helpers
    auto defSym = slang_common::getDefSymbol(tree, modDecl);
    assert(defSym != nullptr);
    assert(defSym->name == "adder");

    auto instSym = slang_common::getInstSymbol(compilation, modDecl);
    assert(instSym != nullptr);

    fs::remove(file);
    printf("  [PASS] semantic_model\n");
}

// --- Test: getHierPaths ---
static void test_hier_paths() {
    const std::string file = "__test_hier.sv";
    writeFile(file, R"(
module top;
    sub inst1();
    sub inst2();
endmodule

module sub;
    reg data;
endmodule
)");

    auto sm          = std::make_shared<slang::SourceManager>();
    auto treeOrError = slang::syntax::SyntaxTree::fromFile(file, *sm);
    assert(treeOrError.has_value());
    auto tree = treeOrError.value();

    slang::ast::Compilation compilation;
    compilation.addSyntaxTree(tree);

    auto paths = slang_common::getHierPaths(compilation, std::string("sub"));
    // "sub" is instantiated twice under "top"
    assert(paths.size() == 2);

    fs::remove(file);
    printf("  [PASS] hier_paths\n");
}

// --- Test: file_manage backup and generate ---
static void test_file_manage() {
    using namespace slang_common;

    const std::string workdir = "__test_workdir";
    const std::string src     = "__test_src.sv";
    fs::create_directories(workdir);
    writeFile(src, "module m; endmodule\n");

    std::string bak = file_manage::backupFile(src, workdir);
    assert(fs::exists(bak));
    std::string content = readFile(bak);
    assert(content.find("module m") != std::string::npos);

    // generateNewFile
    std::string marked = "//BEGIN:out1.sv\nmodule out1; endmodule\n//END:out1.sv\n";
    file_manage::generateNewFile(marked, workdir);
    assert(fs::exists(workdir + "/out1.sv"));

    fs::remove(src);
    fs::remove_all(workdir);
    printf("  [PASS] file_manage\n");
}

int main() {
    printf("test_slang_common:\n");
    test_driver_basic();
    test_semantic_model();
    test_hier_paths();
    test_file_manage();
    printf("All tests passed.\n");
    return 0;
}
