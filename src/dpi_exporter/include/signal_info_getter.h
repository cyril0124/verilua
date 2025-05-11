#pragma once

#include "dpi_exporter.h"

using json = nlohmann::json;

struct SignalInfoGetter : public slang::syntax::SyntaxVisitor<SignalInfoGetter> {
    ConciseSignalPattern cpattern;
    std::string moduleName;
    slang::ast::Compilation *compilation;
    std::vector<std::string> hierPaths;
    SignalGroup signalGroup;
    bool isTopModule;

    std::vector<std::string> shouldRemoveHierPaths;

    SignalInfoGetter(ConciseSignalPattern cpattern, slang::ast::Compilation *compilation, bool isTopModule) : cpattern(cpattern), moduleName(cpattern.module), compilation(compilation), isTopModule(isTopModule) {
        signalGroup.name       = cpattern.name;
        signalGroup.moduleName = cpattern.module;
        signalGroup.cpattern   = cpattern;
    };

    void handle(const slang::syntax::ModuleDeclarationSyntax &syntax) {
        uint64_t globalHandleIdx = 0;
        if (syntax.header->name.rawText() == moduleName) {
            fmt::println("[dpi_exporter] SignalInfoGetter get module: {}", syntax.header->name.rawText());
            auto def  = compilation->getDefinition(compilation->getRoot(), syntax);
            auto inst = &InstanceSymbol::createDefault(*compilation, *def);

            hierPaths = getHierPaths(compilation, moduleName);
            if (hierPaths.empty()) {
                hierPaths.push_back(moduleName);
                ASSERT(isTopModule, "TODO: hierPaths.empty() and !isTopModule", moduleName);
            }

            auto netIter = inst->body.membersOfType<slang::ast::NetSymbol>();
            for (const auto &net : netIter) {
                auto bitWidth = net.getType().getBitWidth();

                if (!cpattern.checkValidSignal(net.name)) {
                    continue;
                }

                for (auto &hierPath : hierPaths) {
                    std::string hierPathFull = std::string(hierPath) + "." + std::string(net.name);
                    auto hierPathPair        = spiltHierPath(hierPathFull);
                    auto handleId            = getUniqueHandleId();
                    auto isWritable          = cpattern.checkWritableSignal(net.name);
                    auto isUnique            = checkUniqueSignal(hierPathFull);

                    ASSERT(!isWritable, "NET should not be mark as writable", hierPathFull);

                    if (isUnique) {
                        if (!Config::getInstance().quietEnabled) {
                            fmt::println("\t<NET>: name: {}, width: {}, hierPath: {}, modulePath: {}, signalName: {}, handleId: {}, isWritable: {}", net.name, bitWidth, hierPathFull, hierPathPair.first, hierPathPair.second, handleId, isWritable);
                        }

                        auto signalInfo = SignalInfo(hierPathFull, hierPathPair.first, hierPathPair.second, "vpiNet", bitWidth, handleId, isWritable);
                        signalGroup.signalInfoVec.push_back(signalInfo);
                    } else {
                        if (!Config::getInstance().quietEnabled) {
                            fmt::println("\t<NET_IGNORE>: name: {}, width: {}, hierPath: {}, modulePath: {}, signalName: {}, handleId: {}, isWritable: {}", net.name, bitWidth, hierPathFull, hierPathPair.first, hierPathPair.second, handleId, isWritable);
                        }
                    }
                }
            }

            auto varIter = inst->body.membersOfType<slang::ast::VariableSymbol>();
            for (const auto &var : varIter) {
                auto bitWidth = var.getType().getBitWidth();

                if (!cpattern.checkValidSignal(var.name)) {
                    continue;
                }

                for (auto &hierPath : hierPaths) {
                    std::string hierPathFull = std::string(hierPath) + "." + std::string(var.name);
                    auto hierPathPair        = spiltHierPath(hierPathFull);
                    auto handleId            = getUniqueHandleId();
                    auto isWritable          = cpattern.checkWritableSignal(var.name);
                    auto isUnique            = checkUniqueSignal(hierPathFull);
                    auto writableNotUnique   = !isUnique && isWritable;

                    if (isUnique || writableNotUnique) {
                        if (!Config::getInstance().quietEnabled) {
                            fmt::println("\t<VAR>: name: {}, width: {}, hierPath: {}, modulePath: {}, signalName: {}, handleId: {}, isWritable: {}", var.name, bitWidth, hierPathFull, hierPathPair.first, hierPathPair.second, handleId, isWritable);
                        }

                        auto signalInfo = SignalInfo(hierPathFull, hierPathPair.first, hierPathPair.second, "vpiReg", bitWidth, handleId, isWritable);
                        signalGroup.signalInfoVec.push_back(signalInfo);

                        if (writableNotUnique) {
                            shouldRemoveHierPaths.push_back(hierPathFull);
                        }
                    } else {
                        if (!Config::getInstance().quietEnabled) {
                            fmt::println("\t<VAR_IGNORE>: name: {}, width: {}, hierPath: {}, modulePath: {}, signalName: {}, handleId: {}, isWritable: {}", var.name, bitWidth, hierPathFull, hierPathPair.first, hierPathPair.second, handleId, isWritable);
                        }
                    }
                }
            }
        } else {
            visitDefault(syntax);
        }
    }
};