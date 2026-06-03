// sv_lint_core.h — shared lint logic for sv_lint CLI and libsv_lint.so.
//
// Provides:
//   sv_lint_core(text) -> {ok, diagnostic_string}
//
// Header-only to avoid an extra compilation unit / link dependency.

#pragma once

#include "fmt/core.h"
#include "slang/ast/Compilation.h"
#include "slang/diagnostics/DiagnosticEngine.h"
#include "slang/diagnostics/TextDiagnosticClient.h"
#include "slang/syntax/SyntaxTree.h"
#include "slang/text/SourceManager.h"
#include "slang/util/Bag.h"

#include <algorithm>
#include <memory>
#include <string>
#include <string_view>

namespace sv_lint {

using namespace slang;
using namespace slang::syntax;
using namespace slang::ast;

struct LintResult {
    bool ok;
    std::string diagnostic; // empty when ok == true
};

/// Run slang lint on the given SystemVerilog text.
/// Returns {true, ""} on success, or {false, diagnostic_message} on failure.
inline LintResult lint(std::string_view sv_text) {
    SourceManager sourceManager;
    Bag options;
    auto tree = SyntaxTree::fromFileInMemory(std::string(sv_text), sourceManager, "sv_lint_input"sv, ""sv, options);

    // Helper: extract the first error or warning from a diagnostics collection.
    auto extractFirstDiagnostic = [&](const auto &diagnostics) -> std::string {
        auto hasDiag = std::any_of(diagnostics.begin(), diagnostics.end(), [](const auto &d) {
            auto sev = getDefaultSeverity(d.code);
            return sev == DiagnosticSeverity::Error || sev == DiagnosticSeverity::Warning;
        });
        if (!hasDiag)
            return {};

        DiagnosticEngine engine(sourceManager);
        engine.setErrorLimit(1);
        auto client = std::make_shared<TextDiagnosticClient>();
        engine.addClient(client);
        for (auto &diag : diagnostics) {
            auto sev = getDefaultSeverity(diag.code);
            if (sev == DiagnosticSeverity::Error || sev == DiagnosticSeverity::Warning)
                engine.issue(diag);
        }
        std::string msg = client->getString();
        // Trim trailing whitespace
        while (!msg.empty() && (msg.back() == '\n' || msg.back() == ' '))
            msg.pop_back();
        return msg;
    };

    // Check parse errors
    if (!tree->diagnostics().empty()) {
        auto msg = extractFirstDiagnostic(tree->diagnostics());
        if (!msg.empty())
            return {false, msg};
    }

    // Run lint-mode compilation
    CompilationOptions compOptions;
    compOptions.flags |= CompilationFlags::LintMode;
    Bag compBag;
    compBag.set(compOptions);

    Compilation compilation(compBag);
    compilation.addSyntaxTree(tree);

    auto diags = compilation.getAllDiagnostics();
    if (!diags.empty()) {
        auto msg = extractFirstDiagnostic(diags);
        if (!msg.empty())
            return {false, msg};
    }

    return {true, {}};
}

} // namespace sv_lint
