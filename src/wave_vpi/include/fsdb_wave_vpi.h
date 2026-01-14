#pragma once

#include "boost_unordered.hpp"
#include "ffrAPI.h"
#include "fsdbShr.h"
#include "nlohmann/json.hpp"

#include <condition_variable>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <set>
#include <thread>
#include <vector>

#define LAST_MODIFIED_TIME_FILE "last_modified_time.wave_vpi_fsdb"
#define TIME_TABLE_FILE "time_table.wave_vpi_fsdb"
#define USED_VAR_ID_CODE_CACHE_FILE "used_var_id_code_cache.wave_vpi_fsdb"

#define MAX_SCOPE_DEPTH 100
#define TIME_TABLE_MAX_INDEX_VAR_CODE 10
#define TIME_TABLE_MAX_INDEX_VAR_CODE_MAX 2000
#define Xtag64ToUInt64(xtag64) (uint64_t)(((uint64_t)xtag64.H << 32) + xtag64.L)

namespace fsdb_wave_vpi {
class FsdbWaveVpi {
  public:
    std::string waveFileName;
    ffrObject *fsdbObj = nullptr;
    ffrFSDBInfo fsdbInfo;
    fsdbVarIdcode maxVarIdcode;
    fsdbVarIdcode sigArr[TIME_TABLE_MAX_INDEX_VAR_CODE_MAX];
    ffrTimeBasedVCTrvsHdl tbVcTrvsHdl = nullptr;
    uint64_t maxXtagValue;

    uint32_t sigNum = TIME_TABLE_MAX_INDEX_VAR_CODE;
    std::vector<uint64_t> xtagU64Vec;
    std::vector<fsdbXTag> xtagVec;

    bool hasNewlyAddedVarIdCode = false;
    boost::unordered_flat_map<std::string, fsdbVarIdcode> varIdCodeCache;
    std::unordered_map<std::string, fsdbVarIdcode> usedVarIdCodeCache;

    FsdbWaveVpi(ffrObject *fsdbObj, std::string_view waveFileName);
    ~FsdbWaveVpi();
    fsdbVarIdcode getVarIdCodeByName(char *name);
    uint32_t findNearestTimeIndex(uint64_t time);

  private:
    uint64_t setupMaxIndexVarCode(uint64_t maxIndexVarCode);
};

struct FsdbSignalHandle_t {
    std::string name;
    ffrVCTrvsHdl vcTrvsHdl;
    fsdbVarIdcode varIdCode;
    size_t bitSize;

    // Used by JIT-like feature
    uint64_t readCnt = 0;              // Number of times signal has been read, triggers JIT when reaching threshold
    std::thread optThread;             // Thread performing incremental pre-optimization
    bool doOpt       = false;          // Flag to start first optimization when readCnt reaches threshold
    bool canOpt      = false;          // Whether signal can be JIT optimized (bitSize <= 32 only)
    bool optFinish   = false;          // Whether first optimization window is complete
    bool continueOpt = false;          // Main thread requests optThread to continue pre-optimizing next window
    std::vector<uint32_t> optValueVec; // Pre-optimized signal values cache for fast access
    uint64_t optFinishIdx;             // Last index position optimized by optThread
    std::condition_variable cv;        // Notifies optThread to wake up when continueOpt is set
    std::mutex mtx;                    // Protects continueOpt variable access for thread safety
};

using FsdbSignalHandle    = FsdbSignalHandle_t;
using FsdbSignalHandlePtr = FsdbSignalHandle_t *;

extern std::shared_ptr<FsdbWaveVpi> fsdbWaveVpi;

}; // namespace fsdb_wave_vpi
