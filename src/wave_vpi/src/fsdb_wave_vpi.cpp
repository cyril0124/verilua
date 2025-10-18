#include "wave_vpi.h"
#ifdef USE_FSDB
#include "fsdb_wave_vpi.h"

namespace fsdb_wave_vpi {
std::shared_ptr<FsdbWaveVpi> fsdbWaveVpi;

// Used by <ffrReadScopeVarTree2>
typedef struct {
    int desiredDepth;
    std::string_view fullName;
    fsdbVarIdcode retVarIdCode;
} FsdbTreeCbContext;

uint32_t currentDepth = 0;
char currentScope[MAX_SCOPE_DEPTH][256];

static bool_T fsdbTreeCb(fsdbTreeCBType cbType, void *cbClientData, void *cbData) {
    switch (cbType) {
    case FSDB_TREE_CBT_SCOPE: {
        fsdbTreeCBDataScope *scopeData = (fsdbTreeCBDataScope *)cbData;
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
        fsdbTreeCBDataVar *varData = (fsdbTreeCBDataVar *)cbData;

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

        // fsdbObj = std::make_shared<ffrObject>(ffrObject::ffrOpen3(fsdbName));
        // if (NULL == fsdbObj) {
        //     VL_FATAL(false, "ffrObject::ffrOpen() failed", this->waveFileName);
        // } else {
        //     fmt::println("[wave_vpi::fsdb_wave_vpi] open fsdb file:{} SUCCESS!", this->waveFileName);
        //     fflush(stdout);
        // }

        fsdbObj->ffrReadScopeVarTree();
        maxVarIdcode = fsdbObj->ffrGetMaxVarIdcode();

        fmt::println("[wave_vpi::fsdb_wave_vpi] start load all signals...");
        fflush(stdout);

        // TODO: Value change on envvar "MAX_INDEX_VAR_CODE" should resultin recompile
        uint32_t maxIndexVarCode = TIME_TABLE_MAX_INDEX_VAR_CODE;
        auto _maxIndexVarCode    = std::getenv("MAX_INDEX_VAR_CODE");
        if (_maxIndexVarCode != nullptr) {
            maxIndexVarCode = std::stoull(_maxIndexVarCode);
            sigNum          = maxIndexVarCode;
        }

        fmt::println("[wave_vpi::fsdb_wave_vpi] TIME_TABLE_MAX_INDEX_VAR_CODE => {}", maxIndexVarCode);
        fflush(stdout);

        for (int i = FSDB_MIN_VAR_IDCODE; i <= maxIndexVarCode; i++) {
            // !! DO NOT try to load all signals !!
            fsdbObj->ffrAddToSignalList(i);
            sigArr[i - 1] = i;
        }
        fsdbObj->ffrLoadSignals();
        fmt::println("[wave_vpi::fsdb_wave_vpi] load all signals finish");
        fflush(stdout);

        if (sigNum > maxVarIdcode) {
            sigNum = maxVarIdcode - 1;
        }
        tbVcTrvsHdl = fsdbObj->ffrCreateTimeBasedVCTrvsHdl(sigNum, sigArr);
        if (NULL == tbVcTrvsHdl) {
            VL_FATAL(false, "Failed to create time based vc trvs hdl! please re-execute the program. sigNum: {}, waveFileName: {}", sigNum, this->waveFileName);
        }

        bool useCachedData = false;
        std::ifstream lastModifiedTimeFile(LAST_MODIFIED_TIME_FILE);
        auto waveFileSize  = std::filesystem::file_size(waveFileName);
        auto lastWriteTime = (uint64_t)std::filesystem::last_write_time(waveFileName).time_since_epoch().count();

        auto updateLastModifiedTimeFile = [&waveFileSize, &lastWriteTime]() {
            std::ofstream _lastModifiedTimeFile(LAST_MODIFIED_TIME_FILE);
            _lastModifiedTimeFile << waveFileSize << std::endl;
            _lastModifiedTimeFile << lastWriteTime << std::endl;
            _lastModifiedTimeFile.close();
        };

        if (lastModifiedTimeFile.is_open()) {
            std::string waveFileSizeStr;
            std::string lastModifiedTimeStr;
            std::string isFinish;

            try {
                std::getline(lastModifiedTimeFile, waveFileSizeStr);
                std::getline(lastModifiedTimeFile, lastModifiedTimeStr);
                std::getline(lastModifiedTimeFile, isFinish);
                lastModifiedTimeFile.close();

                auto _waveFileSize     = std::stoull(waveFileSizeStr);
                auto _lastModifiedTime = std::stoull(lastModifiedTimeStr);

                if (_waveFileSize == waveFileSize && _lastModifiedTime == lastWriteTime) {
                    useCachedData = true;
                } else {
                    updateLastModifiedTimeFile();
                }
            } catch (std::invalid_argument &e) {
                fmt::println("[wave_vpi::fsdb_wave_vpi] ERROR while reading:{}! => std::invalid_argument", LAST_MODIFIED_TIME_FILE);
                updateLastModifiedTimeFile();
            }
        } else {
            updateLastModifiedTimeFile();
        }

        fmt::println("[wave_vpi::fsdb_wave_vpi] useCachedData: {}", useCachedData);

        if (useCachedData) {
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

                fmt::println("[wave_vpi::fsdb_wave_vpi] read from timeTableFile => xtagU64Vec size: {}", xtagU64Vec.size());
            } else {
                fmt::println("[wave_vpi::fsdb_wave_vpi] failed to open {}, doing normal parse...", TIME_TABLE_FILE);
                goto NormalParse;
            }
        } else {
        NormalParse:
            fmt::println("[wave_vpi::fsdb_wave_vpi] start collecting xtagU64Set");
            fflush(stdout);

            int i = 0;
            fsdbXTag xtag;
            std::set<uint64_t> xtagU64Set;
            while (FSDB_RC_SUCCESS == tbVcTrvsHdl->ffrGotoNextVC()) {
                tbVcTrvsHdl->ffrGetXTag((void *)&xtag);
                auto u64Xtag = Xtag64ToUInt64(xtag.hltag);
                if (xtagU64Set.find(u64Xtag) == xtagU64Set.end()) {
                    xtagU64Set.insert(u64Xtag);
                    xtagVec.emplace_back(xtag);
                }
                i++;
            }
            fmt::println("[wave_vpi::fsdb_wave_vpi] xtagU64Set size: {}, total size: {}", xtagU64Set.size(), i);
            fflush(stdout);

            // Create xtagU64Vec besed on xtagU64Set
            xtagU64Vec.assign(xtagU64Set.begin(), xtagU64Set.end());

            // Save time table into file so that we do not require much time to parse time table.
            std::ofstream timeTableFile(TIME_TABLE_FILE, std::ios::binary);
            std::size_t vecSize = xtagU64Vec.size();
            VL_FATAL(timeTableFile.is_open(), "Failed to open TIME_TABLE_FILE({})!", TIME_TABLE_FILE);
            timeTableFile.write(reinterpret_cast<char *>(&vecSize), sizeof(vecSize));
            timeTableFile.write(reinterpret_cast<char *>(xtagU64Vec.data()), vecSize * sizeof(uint64_t));
            VL_FATAL(timeTableFile, "Failed to write to file({})!", TIME_TABLE_FILE);
            timeTableFile.close();
        }

        // Recreate tbVcTrvsHdl to reset the xtag to start point
        tbVcTrvsHdl->ffrFree();
        tbVcTrvsHdl = fsdbObj->ffrCreateTimeBasedVCTrvsHdl(sigNum, sigArr);
    }
}

fsdbVarIdcode FsdbWaveVpi::getVarIdCodeByName(char *name) {
    auto it = varIdCodeCache.find(std::string(name));
    if (it != varIdCodeCache.end()) {
        // fmt::println("found in varIdCodeCache! {}", name);
        // fflush(stdout);
        fsdbVarIdcode existingValue = it->second;
        return existingValue;
    }

    currentDepth = 0;
    for (int i = 0; i < MAX_SCOPE_DEPTH; i++) {
        std::memset(currentScope[i], 0, sizeof(currentScope[i]));
    }

    std::string fullName          = std::string(name);
    FsdbTreeCbContext contextData = {.desiredDepth = static_cast<int>(std::count(fullName.begin(), fullName.end(), '.')), .fullName = fullName, .retVarIdCode = 0};
    fsdbObj->ffrReadScopeVarTree2(fsdbTreeCb, (void *)&contextData);

    if (contextData.retVarIdCode == 0) {
        return -1;
    }
    return contextData.retVarIdCode;
}

uint32_t FsdbWaveVpi::findNearestTimeIndex(uint64_t time) {
    auto it = std::lower_bound(xtagU64Vec.begin(), xtagU64Vec.end(), time);

    if (it == xtagU64Vec.end()) {
        return xtagU64Vec.size() - 1;
    } else if (it == xtagU64Vec.begin()) {
        return 0;
    } else {
        uint32_t index = it - xtagU64Vec.begin();
        if (xtagU64Vec[index] == time) {
            return index;
        } else {
            uint32_t before = index - 1;
            if (xtagU64Vec[before] < time) {
                return before;
            } else {
                return index;
            }
        }
    }
}
}; // namespace fsdb_wave_vpi
#endif // USE_FSDB
