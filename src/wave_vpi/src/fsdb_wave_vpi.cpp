#include "wave_vpi.h"
#ifdef USE_FSDB
#include "fsdb_wave_vpi.h"

namespace fsdb_wave_vpi {
std::shared_ptr<FsdbWaveVpi> fsdbWaveVpi;

using json = nlohmann::json;

// Used by <ffrReadScopeVarTree2>
using FsdbTreeCbContext = struct {
    int desiredDepth;
    std::string_view fullName;
    fsdbVarIdcode retVarIdCode;
};

uint32_t currentDepth = 0;
char currentScope[MAX_SCOPE_DEPTH][256];

static bool_T fsdbTreeCb(fsdbTreeCBType cbType, void *cbClientData, void *cbData) {
    switch (cbType) {
    case FSDB_TREE_CBT_SCOPE: {
        auto scopeData = (fsdbTreeCBDataScope *)cbData;
        if (currentDepth < MAX_SCOPE_DEPTH - 1) {
            strcpy(currentScope[currentDepth], scopeData->name);
            currentDepth++;
        }
        break;
    }
    case FSDB_TREE_CBT_VAR: {
        auto contextData = (FsdbTreeCbContext *)cbClientData;
        if (contextData->desiredDepth != currentDepth) {
            return FALSE;
        }
        auto varData = (fsdbTreeCBDataVar *)cbData;

        char fullName[256] = "";
        for (int i = 0; i < currentDepth; ++i) {
            strcat(fullName, currentScope[i]);
            strcat(fullName, ".");
        }

        std::string varDataName = varData->name;
        std::size_t start, end;
        while ((start = varDataName.find('[')) != std::string::npos && (end = varDataName.find(']')) != std::string::npos) {
            if (end > start) {
                varDataName.erase(start, end - start + 1);
            }
        }
        strcat(fullName, varDataName.c_str());

        if (std::string_view(fullName) == contextData->fullName) {
            // fmt::println("Full Name: {} varDataName: {} varIdx: {} depth: {} desiredDepth: {}", fullName, varDataName, varData->u.idcode, currentDepth, contextData->desiredDepth);
            contextData->retVarIdCode                                       = varData->u.idcode;
            fsdbWaveVpi->varIdCodeCache[std::string(contextData->fullName)] = varData->u.idcode;
            return FALSE; // return FALSE to stop the traverse
        } else {
            std::string insertKeyStr = std::string(fullName);
            std::size_t start, end;
            while ((start = insertKeyStr.find('[')) != std::string::npos && (end = insertKeyStr.find(']')) != std::string::npos) {
                if (end > start) {
                    insertKeyStr.erase(start, end - start + 1);
                }
            }
            // The varIdCodeCache will store the varIdCode of the same scope depth into it even it is not required by the user.
            fsdbWaveVpi->varIdCodeCache[insertKeyStr] = varData->u.idcode;
        }
        break;
    }
    case FSDB_TREE_CBT_UPSCOPE: {
        currentDepth--;
        break;
    }
    default:
        return TRUE; // return TRUE to continue the traverse
    }
    return TRUE; // return TRUE to continue the traverse
}

uint64_t FsdbWaveVpi::setupMaxIndexVarCode(uint64_t maxIndexVarCode) {
    if (tbVcTrvsHdl != nullptr) {
        tbVcTrvsHdl->ffrFree();
        tbVcTrvsHdl = nullptr;
    }

    // TODO: Value change on envvar "MAX_INDEX_VAR_CODE" should resultin recompile
    auto _maxIndexVarCode = std::getenv("MAX_INDEX_VAR_CODE");
    if (_maxIndexVarCode != nullptr) {
        maxIndexVarCode = std::stoull(_maxIndexVarCode);
    }
    sigNum = maxIndexVarCode;

    if (!is_quiet_mode()) {
        fmt::println("[wave_vpi::fsdb_wave_vpi] maxIndexVarCode => {}", maxIndexVarCode);
        fflush(stdout);
    }

    for (int i = FSDB_MIN_VAR_IDCODE; i <= maxIndexVarCode; i++) {
        // !! DO NOT try to load all signals !!
        fsdbObj->ffrAddToSignalList(i);
        sigArr[i - 1] = i;
    }
    fsdbObj->ffrLoadSignals();
    if (!is_quiet_mode()) {
        fmt::println("[wave_vpi::fsdb_wave_vpi] load all signals finish");
        fflush(stdout);
    }

    if (sigNum > maxVarIdcode) {
        sigNum = maxVarIdcode - 1;
    }
    tbVcTrvsHdl = fsdbObj->ffrCreateTimeBasedVCTrvsHdl(sigNum, sigArr);
    if (nullptr == tbVcTrvsHdl) {
        VL_FATAL(false, "Failed to create time based vc trvs hdl! please re-execute the program. sigNum: {}, waveFileName: {}", sigNum, this->waveFileName);
    }

    return maxIndexVarCode;
}

FsdbWaveVpi::FsdbWaveVpi(ffrObject *fsdbObj, std::string_view waveFileName) : fsdbObj(fsdbObj), waveFileName(waveFileName) {
    char fsdbName[FSDB_MAX_PATH + 1] = {0};
    strncpy(fsdbName, this->waveFileName.c_str(), FSDB_MAX_PATH);

    if (FALSE == ffrObject::ffrIsFSDB(fsdbName)) {
        VL_FATAL(false, "not an fsdb file! {}", this->waveFileName);
    } else {
        ffrObject::ffrGetFSDBInfo(fsdbName, fsdbInfo);
        if (FSDB_FT_VERILOG != fsdbInfo.file_type) {
            VL_FATAL(false, "fsdb file type is not verilog! {}", this->waveFileName);
        }
        maxXtagValue = Xtag64ToUInt64(fsdbInfo.max_xtag.hltag);
        if (!is_quiet_mode()) {
            fmt::println("[wave_vpi::fsdb_wave_vpi] maxXtagValue: {}", maxXtagValue);
        }

        // fsdbObj = std::make_shared<ffrObject>(ffrObject::ffrOpen3(fsdbName));
        // if (NULL == fsdbObj) {
        //     VL_FATAL(false, "ffrObject::ffrOpen() failed", this->waveFileName);
        // } else {
        //     fmt::println("[wave_vpi::fsdb_wave_vpi] open fsdb file:{} SUCCESS!", this->waveFileName);
        //     fflush(stdout);
        // }

        fsdbObj->ffrReadScopeVarTree();
        maxVarIdcode = fsdbObj->ffrGetMaxVarIdcode();

        if (!is_quiet_mode()) {
            fmt::println("[wave_vpi::fsdb_wave_vpi] start load all signals...");
            fflush(stdout);
        }

        uint64_t maxIndexVarCode = setupMaxIndexVarCode(TIME_TABLE_MAX_INDEX_VAR_CODE);

        bool useCachedData = false;
        auto waveFileSize  = std::filesystem::file_size(waveFileName);
        auto lastWriteTime = (uint64_t)std::filesystem::last_write_time(waveFileName).time_since_epoch().count();

        // Load meta file and check freshness.
        json cachedMeta;
        bool metaLoaded = false;
        {
            std::ifstream metaFile(META_FILE);
            if (metaFile.is_open()) {
                try {
                    cachedMeta      = json::parse(metaFile);
                    metaLoaded      = true;
                    auto cachedSize = cachedMeta["modified"]["size"].get<uint64_t>();
                    auto cachedTime = cachedMeta["modified"]["time"].get<uint64_t>();
                    if (cachedSize == waveFileSize && cachedTime == lastWriteTime) {
                        useCachedData = true;
                    }
                } catch (const std::exception &e) {
                    if (!is_quiet_mode()) {
                        fmt::println("[wave_vpi::fsdb_wave_vpi] ERROR while reading meta file: {}", e.what());
                    }
                }
            }
        }

        if (!is_quiet_mode()) {
            fmt::println("[wave_vpi::fsdb_wave_vpi] useCachedData: {}", useCachedData);
        }

        if (useCachedData) {
            // Load used var id code cache from meta file.
            if (metaLoaded && cachedMeta.contains("used_var_id_code_cache")) {
                usedVarIdCodeCache = cachedMeta["used_var_id_code_cache"].get<std::unordered_map<std::string, fsdbVarIdcode>>();
            }

            std::ifstream timeTableFile(TIME_TABLE_FILE, std::ios::binary);
            if (timeTableFile.is_open()) {
                std::size_t vecSize;

                timeTableFile.read(reinterpret_cast<char *>(&vecSize), sizeof(vecSize)); // The first elements is vector size
                xtagU64Vec.resize(vecSize);

                timeTableFile.read(reinterpret_cast<char *>(xtagU64Vec.data()), vecSize * sizeof(uint64_t));
                timeTableFile.close();

                xtagVec.resize(vecSize);
                for (size_t i = 0; i < vecSize; i++) {
                    xtagVec[i].hltag.H = xtagU64Vec[i] >> 32;
                    xtagVec[i].hltag.L = xtagU64Vec[i] & 0xFFFFFFFF;
                }

                if (!is_quiet_mode()) {
                    fmt::println("[wave_vpi::fsdb_wave_vpi] read from timeTableFile => xtagU64Vec size: {}, maxValue: {}", xtagU64Vec.size(), xtagU64Vec.back());
                }
            } else {
                if (!is_quiet_mode()) {
                    fmt::println("[wave_vpi::fsdb_wave_vpi] failed to open {}, doing normal parse...", TIME_TABLE_FILE);
                }
                goto NormalParse;
            }
        } else {
        NormalParse:
            if (!is_quiet_mode()) {
                fmt::println("[wave_vpi::fsdb_wave_vpi] start collecting xtagU64Set");
                fflush(stdout);
            }

            int i = 0;
            fsdbXTag xtag;
            uint64_t parsedMaxXtagValue = 0;
            std::set<uint64_t> xtagU64Set;

            int retryTimes                  = 0;
            const int MAX_RETRY_TIMES       = 10;
            const double ACCEPTABLE_PERCENT = 95.0;

        DoNormalParse:
            i = 0;
            xtagU64Set.clear();
            xtagVec.clear();

            // Iterate specific number of signals across the entire waveform to get time table.
            while (FSDB_RC_SUCCESS == tbVcTrvsHdl->ffrGotoNextVC()) {
                auto ret = tbVcTrvsHdl->ffrGetXTag((void *)&xtag);
                VL_FATAL(ret == FSDB_RC_SUCCESS, "Failed to get xtag!");

                auto u64Xtag = Xtag64ToUInt64(xtag.hltag);
                if (xtagU64Set.find(u64Xtag) == xtagU64Set.end()) {
                    xtagU64Set.insert(u64Xtag);
                    xtagVec.emplace_back(xtag);
                }
                i++;
            }
            parsedMaxXtagValue = Xtag64ToUInt64(xtagVec.back().hltag);

            if (!is_quiet_mode()) {
                fmt::println("[wave_vpi::fsdb_wave_vpi] xtagU64Set.size: {}, xtagVec.maxValue: {}, total size: {}", xtagU64Set.size(), parsedMaxXtagValue, i);
                fflush(stdout);
            }

            // Sometimes the signals used to collect time table is not enough, so we need to increase the number of signals and try recollect the time table.
            auto matchedPercent = static_cast<double>(parsedMaxXtagValue * 100) / static_cast<double>(maxXtagValue);
            if (parsedMaxXtagValue < maxXtagValue) {
                retryTimes++;
                if (retryTimes > MAX_RETRY_TIMES) {
                    if (matchedPercent < ACCEPTABLE_PERCENT) {
                        VL_FATAL(false, "Failed to parse the whole time table! parsedMaxXtagValue({}) < maxXtagValue({}), matchedPercent: {:.2f}%", parsedMaxXtagValue, maxXtagValue, matchedPercent);
                    } else {
                        if (!is_quiet_mode()) {
                            fmt::println("[wave_vpi::fsdb_wave_vpi] matchedPercent: {:.2f}% > 95%, continue...", matchedPercent);
                        }
                        goto ParseFinish;
                    }
                }

                uint64_t newMaxIndexVarCode = maxIndexVarCode + 10 * (retryTimes ^ 2);
                if (!is_quiet_mode()) {
                    fmt::println("\n[wave_vpi::fsdb_wave_vpi] parsedMaxXtagValue({}) < maxXtagValue({}), try to increase maxIndexVarCode to {} and reparse, retryTimes: {}", parsedMaxXtagValue, maxXtagValue, newMaxIndexVarCode, retryTimes);
                    fflush(stdout);
                }

                maxIndexVarCode = setupMaxIndexVarCode(newMaxIndexVarCode);
                goto DoNormalParse;
            }
        ParseFinish:

            // Create xtagU64Vec besed on xtagU64Set
            xtagU64Vec.assign(xtagU64Set.begin(), xtagU64Set.end());

            // Save time table into file so that we do not require much time to parse time table.
            auto ttStart = std::chrono::steady_clock::now();
            std::ofstream timeTableFile(TIME_TABLE_FILE, std::ios::binary);
            std::size_t vecSize = xtagU64Vec.size();
            VL_FATAL(timeTableFile.is_open(), "Failed to open TIME_TABLE_FILE({})!", TIME_TABLE_FILE);
            timeTableFile.write(reinterpret_cast<char *>(&vecSize), sizeof(vecSize));
            timeTableFile.write(reinterpret_cast<char *>(xtagU64Vec.data()), vecSize * sizeof(uint64_t));
            VL_FATAL(timeTableFile, "Failed to write to file({})!", TIME_TABLE_FILE);
            timeTableFile.close();
            auto ttEnd  = std::chrono::steady_clock::now();
            double ttMs = std::chrono::duration<double, std::milli>(ttEnd - ttStart).count();
            if (!is_quiet_mode()) {
                fmt::println("[wave_vpi::fsdb_wave_vpi] wrote {} in {:.3f}ms", TIME_TABLE_FILE, ttMs);
            }

            // Write meta file immediately so the cached time table can be reused
            // on subsequent runs, even when no signal lookups are performed
            {
                json meta;
                meta["modified"]["size"]       = waveFileSize;
                meta["modified"]["time"]       = lastWriteTime;
                meta["used_var_id_code_cache"] = json::object();

                std::ofstream o(META_FILE);
                o << meta.dump(4) << "\n";
                o.close();
                if (!is_quiet_mode()) {
                    fmt::println("[wave_vpi::fsdb_wave_vpi] wrote {} (initial)", META_FILE);
                }
            }
        }

        // Recreate tbVcTrvsHdl to reset the xtag to start point
        tbVcTrvsHdl->ffrFree();
        tbVcTrvsHdl = fsdbObj->ffrCreateTimeBasedVCTrvsHdl(sigNum, sigArr);
    }
}

FsdbWaveVpi::~FsdbWaveVpi() {
    if (hasNewlyAddedVarIdCode) {
        // Save meta file (mtime + used var id code cache).
        auto t0            = std::chrono::steady_clock::now();
        auto waveFileSize  = std::filesystem::file_size(waveFileName);
        auto lastWriteTime = (uint64_t)std::filesystem::last_write_time(waveFileName).time_since_epoch().count();

        json meta;
        meta["modified"]["size"]       = waveFileSize;
        meta["modified"]["time"]       = lastWriteTime;
        meta["used_var_id_code_cache"] = usedVarIdCodeCache;

        std::ofstream o(META_FILE);
        o << meta.dump(4) << "\n";
        o.close();

        auto t1       = std::chrono::steady_clock::now();
        double metaMs = std::chrono::duration<double, std::milli>(t1 - t0).count();
        if (!is_quiet_mode()) {
            fmt::println("[wave_vpi::fsdb_wave_vpi] wrote {} in {:.3f}ms", META_FILE, metaMs);
        }
    }
}

fsdbVarIdcode FsdbWaveVpi::getVarIdCodeByName(char *name) {
    std::string nameStr = std::string(name);

    auto _it = usedVarIdCodeCache.find(nameStr);
    if (_it != usedVarIdCodeCache.end()) {
        return _it->second;
    }

    hasNewlyAddedVarIdCode = true;

    auto it = varIdCodeCache.find(nameStr);
    if (it != varIdCodeCache.end()) {
        // fmt::println("found in varIdCodeCache! {}", name);
        // fflush(stdout);
        fsdbVarIdcode existingValue = it->second;
        usedVarIdCodeCache[nameStr] = existingValue;
        return existingValue;
    }

    currentDepth = 0;
    for (int i = 0; i < MAX_SCOPE_DEPTH; i++) {
        std::memset(currentScope[i], 0, sizeof(currentScope[i]));
    }

    std::string fullName          = std::string(name);
    FsdbTreeCbContext contextData = {.desiredDepth = static_cast<int>(std::count(fullName.begin(), fullName.end(), '.')), .fullName = fullName, .retVarIdCode = 0};
    fsdbObj->ffrReadScopeVarTree2(fsdbTreeCb, (void *)&contextData);

    auto retVarIdCode = contextData.retVarIdCode;
    if (retVarIdCode == 0) {
        return -1;
    }

    usedVarIdCodeCache[nameStr] = retVarIdCode;
    return retVarIdCode;
}

uint32_t FsdbWaveVpi::findNearestTimeIndex(uint64_t time) {
    auto it = std::lower_bound(xtagU64Vec.begin(), xtagU64Vec.end(), time);

    if (it == xtagU64Vec.end()) {
        return xtagU64Vec.size() - 1;
    } else if (it == xtagU64Vec.begin()) {
        return 0;
    }

    uint32_t index = it - xtagU64Vec.begin();
    if (xtagU64Vec[index] == time) {
        return index;
    }

    uint32_t before = index - 1;
    if (xtagU64Vec[before] < time) {
        return before;
    }
    return index;
}
}; // namespace fsdb_wave_vpi
#endif // USE_FSDB
