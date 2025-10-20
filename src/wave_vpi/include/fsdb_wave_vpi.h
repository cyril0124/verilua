#pragma once

#include "boost_unordered.hpp"
#include "ffrAPI.h"
#include "fsdbShr.h"

#include <condition_variable>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <set>
#include <thread>
#include <vector>

#define LAST_MODIFIED_TIME_FILE "last_modified_time.wave_vpi_fsdb"
#define TIME_TABLE_FILE "time_table.wave_vpi_fsdb"

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

    boost::unordered_flat_map<std::string, fsdbVarIdcode> varIdCodeCache; // TODO: store into json file at the end of simulation and read back at the start of simulation

    FsdbWaveVpi(ffrObject *fsdbObj, std::string_view waveFileName);
    ~FsdbWaveVpi() {};
    fsdbVarIdcode getVarIdCodeByName(char *name);
    uint32_t findNearestTimeIndex(uint64_t time);

  private:
    uint64_t setupMaxIndexVarCode(uint64_t maxIndexVarCode);
};

typedef struct {
    std::string name;
    ffrVCTrvsHdl vcTrvsHdl;
    fsdbVarIdcode varIdCode;
    size_t bitSize;

    // Used by JIT-like feature
    uint64_t readCnt = 0;
    std::thread optThread;
    bool doOpt       = false;
    bool canOpt      = false;
    bool optFinish   = false;
    bool continueOpt = false;
    std::vector<uint32_t> optValueVec;
    uint64_t optFinishIdx;
    std::condition_variable cv;
    std::mutex mtx;
} FsdbSignalHandle, *FsdbSignalHandlePtr;

extern std::shared_ptr<FsdbWaveVpi> fsdbWaveVpi;

}; // namespace fsdb_wave_vpi
