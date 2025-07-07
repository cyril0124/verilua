#include <algorithm>
#include <assert.h>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <functional>
#include <memory>
#include <stdio.h>
#include <stdlib.h>
#include <string>
#include <vector>

#ifdef DUMMY_VPI_NOT_USE_WRAPPER
#define DEFINE_VPI_FUNC(func) func
#else
// The reason for appending `__wrap_` prefix to the function name is that in some case the origin `vpi_*`
// functions are used by the simulator itself even we do not use any vpi functionality. So we need to wrap
// the `vpi_*` functions to avoid the conflict.
// (e.g. In vcs simulator, when we enable fsdb waveform dump, the `vpi_*` functions get called by fsdb library to dump waveform.)
// For example, if we use `vpi_get` function, we need to wrap it to `__wrap_vpi_get`.
#define DEFINE_VPI_FUNC(func) __wrap_##func
#endif

#define VPI_GET_MAX_BUFFER_SIZE 1024 * 2
#define VPI_GET_MAX_VEC_VALS 256

#define ANSI_COLOR_RED "\x1b[31m"
#define ANSI_COLOR_GREEN "\x1b[32m"
#define ANSI_COLOR_YELLOW "\x1b[33m"
#define ANSI_COLOR_BLUE "\x1b[34m"
#define ANSI_COLOR_MAGENTA "\x1b[35m"
#define ANSI_COLOR_CYAN "\x1b[36m"
#define ANSI_COLOR_RESET "\x1b[0m"

#define cbNextSimTime 8
#define cbStartOfSimulation 11
#define cbEndOfSimulation 12

#define vpiStop 66   /* execute simulator's $stop */
#define vpiFinish 67 /* execute simulator's $finish */

#define vpiType 1 /* type of object */
#define vpiSize 4 /* size of gate, net, port, etc. */

#define vpiBinStrVal 1
#define vpiHexStrVal 4
#define vpiIntVal 6
#define vpiVectorVal 9

#define INFO(...)                                                                                                                                                                                                                                                                                                                                                                                              \
    do {                                                                                                                                                                                                                                                                                                                                                                                                       \
        printf("[%s:%s:%d] [%sINFO%s] ", __FILE__, __FUNCTION__, __LINE__, ANSI_COLOR_MAGENTA, ANSI_COLOR_RESET);                                                                                                                                                                                                                                                                                              \
        printf(__VA_ARGS__);                                                                                                                                                                                                                                                                                                                                                                                   \
    } while (0)

#define WARN(...)                                                                                                                                                                                                                                                                                                                                                                                              \
    do {                                                                                                                                                                                                                                                                                                                                                                                                       \
        printf("[%s:%s:%d] [%sWARN%s] ", __FILE__, __FUNCTION__, __LINE__, ANSI_COLOR_YELLOW, ANSI_COLOR_RESET);                                                                                                                                                                                                                                                                                               \
        printf(__VA_ARGS__);                                                                                                                                                                                                                                                                                                                                                                                   \
    } while (0)

#define FATAL(cond, ...)                                                                                                                                                                                                                                                                                                                                                                                       \
    do {                                                                                                                                                                                                                                                                                                                                                                                                       \
        if (!(cond)) {                                                                                                                                                                                                                                                                                                                                                                                         \
            printf("\n");                                                                                                                                                                                                                                                                                                                                                                                      \
            printf("[%s:%s:%d] [%sFATAL%s] ", __FILE__, __FUNCTION__, __LINE__, ANSI_COLOR_RED, ANSI_COLOR_RESET);                                                                                                                                                                                                                                                                                             \
            printf(__VA_ARGS__ __VA_OPT__(, ) "A fatal error occurred without a message.\n");                                                                                                                                                                                                                                                                                                                  \
            fflush(stdout);                                                                                                                                                                                                                                                                                                                                                                                    \
            fflush(stderr);                                                                                                                                                                                                                                                                                                                                                                                    \
            abort();                                                                                                                                                                                                                                                                                                                                                                                           \
        }                                                                                                                                                                                                                                                                                                                                                                                                      \
    } while (0)

inline uint32_t coverWith32(uint32_t size) { return (size + 31) / 32; }

using GetValue32Func     = std::function<uint32_t()>;
using GetValueVecFunc    = std::function<void(uint32_t *)>;
using GetValueHexStrFunc = std::function<void(char *)>;

using SetValue32Func     = std::function<void(uint32_t)>;
using SetValueVecFunc    = std::function<void(uint32_t *)>;
using SetValueHexStrFunc = std::function<void(char *)>;

#ifdef __cplusplus
extern "C" {
#endif

char *dpi_exporter_get_top_name();
int64_t dpi_exporter_handle_by_name(std::string name);
std::string dpi_exporter_get_type_str(int64_t handle);
uint32_t dpi_exporter_get_bitwidth(int64_t handle);
uint32_t dpi_exporter_get_value32(int64_t handle);

GetValue32Func dpi_exporter_alloc_get_value32(int64_t handle);
GetValueVecFunc dpi_exporter_alloc_get_value_vec(int64_t handle);
GetValueHexStrFunc dpi_exporter_alloc_get_value_hex_str(int64_t handle);

SetValue32Func dpi_exporter_alloc_set_value32(int64_t handle);
SetValueVecFunc dpi_exporter_alloc_set_value_vec(int64_t handle);
SetValueHexStrFunc dpi_exporter_alloc_set_value_hex_str(int64_t handle);

#ifdef __cplusplus
}
#endif

typedef char PLI_BYTE8;
typedef int PLI_INT32;
typedef unsigned int PLI_UINT32;
typedef PLI_UINT32 *vpiHandle;

#define vpiNoDelay 1

typedef struct t_vpi_time {
    PLI_INT32 type;       /* [vpiScaledRealTime, vpiSimTime,
                              vpiSuppressTime] */
    PLI_UINT32 high, low; /* for vpiSimTime */
    double real;          /* for vpiScaledRealTime */
} s_vpi_time, *p_vpi_time;

typedef struct t_vpi_value {
    PLI_INT32 format; /* vpi[[Bin,Oct,Dec,Hex]Str,Scalar,Int,Real,String,
                             Vector,Strength,Suppress,Time,ObjType]Val */
    union {
        PLI_BYTE8 *str;                     /* string value */
        PLI_INT32 scalar;                   /* vpi[0,1,X,Z] */
        PLI_INT32 integer;                  /* integer value */
        double real;                        /* real value */
        struct t_vpi_time *time;            /* time value */
        struct t_vpi_vecval *vector;        /* vector value */
        struct t_vpi_strengthval *strength; /* strength value */
        PLI_BYTE8 *misc;                    /* ...other */
    } value;
} s_vpi_value, *p_vpi_value;

typedef struct t_cb_data {
    PLI_INT32 reason;                        /* callback reason */
    PLI_INT32 (*cb_rtn)(struct t_cb_data *); /* call routine */
    vpiHandle obj;                           /* trigger object */
    p_vpi_time time;                         /* callback time */
    p_vpi_value value;                       /* trigger object value */
    PLI_INT32 index;                         /* index of the memory word or
                                                var select that changed */
    PLI_BYTE8 *user_data;
} s_cb_data, *p_cb_data;

typedef struct t_vpi_vecval {
    /* following fields are repeated enough times to contain vector */
    PLI_INT32 aval, bval; /* bit encoding: ab: 00=0, 10=1, 11=X, 01=Z */
} s_vpi_vecval, *p_vpi_vecval;

class MemoryAllocator {
  public:
    template <typename T, typename... Args> T *allocate(Args &&...args) {
        T *ptr = new T(std::forward<Args>(args)...);
        allocatedMemory.push_back(static_cast<void *>(ptr));
        return ptr;
    }

    void deallocate() {
        for (void *ptr : allocatedMemory) {
            delete static_cast<char *>(ptr);
        }
        allocatedMemory.clear();
    }

    ~MemoryAllocator() { deallocate(); }

  private:
    std::vector<void *> allocatedMemory;
};

MemoryAllocator memAllocator;

class ComplexHandle {
  public:
    std::string name;
    int64_t handle;
    uint32_t bitwidth;
    uint32_t beatSize;
    uint32_t *valueVec;
    bool isWritable = false;

    GetValue32Func getValue32;
    GetValueVecFunc getValueVec;
    GetValueHexStrFunc getValueHexStr;

    SetValue32Func setValue32;
    SetValueVecFunc setValueVec;
    SetValueHexStrFunc setValueHexStr;

    ComplexHandle(std::string name, int64_t handle) : handle(handle), name(name) {
        this->bitwidth = dpi_exporter_get_bitwidth(handle);
        FATAL(this->bitwidth > 0, "Cannot get bitwidth for %s\n", name.c_str());

        this->getValue32     = dpi_exporter_alloc_get_value32(handle);
        this->getValueVec    = dpi_exporter_alloc_get_value_vec(handle);
        this->getValueHexStr = dpi_exporter_alloc_get_value_hex_str(handle);

        this->setValue32 = dpi_exporter_alloc_set_value32(handle);
        if (this->setValue32 != nullptr) {
            this->isWritable     = true;
            this->setValueVec    = dpi_exporter_alloc_set_value_vec(handle);
            this->setValueHexStr = dpi_exporter_alloc_set_value_hex_str(handle);
            this->valueVec       = memAllocator.allocate<uint32_t>(this->beatSize);
        }

        if (this->bitwidth <= 32) {
            FATAL(this->getValueVec == nullptr);
        }

        this->beatSize = coverWith32(this->bitwidth);
    }
};

typedef ComplexHandle *ComplexHandlePtr;
std::unique_ptr<s_cb_data> endOfSimulationCb = NULL;

inline std::string replace(std::string input, std::string toReplace, std::string replacement, bool errorIfNotFound = true) {
    std::string result = std::string(input);
    size_t pos         = result.find(toReplace);
    if (pos != std::string::npos) {
        result.replace(pos, toReplace.length(), replacement);
        return result;
    }
    if (errorIfNotFound) {
        FATAL(0, "Cannot find %s in %s\n", toReplace.data(), input.data());
    } else {
        return result;
    }
}

#ifdef __cplusplus
extern "C" {
#endif

vpiHandle DEFINE_VPI_FUNC(vpi_handle_by_index)(vpiHandle object, PLI_INT32 indx) { FATAL(0, "`vpi_handle_by_index` not implemented\n"); }

vpiHandle DEFINE_VPI_FUNC(vpi_put_value)(vpiHandle object, p_vpi_value value_p, p_vpi_time time_p, PLI_INT32 flags) {
    auto complexHandle = reinterpret_cast<ComplexHandlePtr>(object);
    FATAL(complexHandle->isWritable, "Cannot write to read-only signal! name: %s\n", complexHandle->name.data());
    FATAL(flags == vpiNoDelay, "flags: %d is not supported", flags);

    switch (value_p->format) {
    case vpiVectorVal:
        switch (complexHandle->beatSize) {
        case 1:
            complexHandle->setValue32(value_p->value.vector[0].aval);
            break;
        case 2:
            complexHandle->valueVec[0] = value_p->value.vector[0].aval;
            complexHandle->valueVec[1] = value_p->value.vector[1].aval;
            complexHandle->setValueVec(complexHandle->valueVec);
            break;
        default:
            for (int i = 0; i < complexHandle->beatSize; i++) {
                complexHandle->valueVec[i] = value_p->value.vector[i].aval;
            }
            complexHandle->setValueVec(complexHandle->valueVec);
            break;
        }
        break;
    case vpiHexStrVal:
        complexHandle->setValueHexStr(value_p->value.str);
        break;
    default:
        FATAL(0, "`vpi_put_value` not implemented, format: %d\n", value_p->format);
        break;
    }

    return nullptr;
}

vpiHandle DEFINE_VPI_FUNC(vpi_scan)(vpiHandle iterator) { FATAL(0, "`vpi_scan` not implemented\n"); }

PLI_INT32 DEFINE_VPI_FUNC(vpi_control)(PLI_INT32 operation, ...) {
    switch (operation) {
    case vpiStop:
    case vpiFinish:
        if (operation == vpiStop) {
            INFO("get vpiStop\n");
        } else {
            INFO("get vpiFinish\n");
        }
        FATAL(endOfSimulationCb != nullptr, "get %s, but endOfSimulationCb is nullptr!\n", operation == vpiStop ? "vpiStop" : "vpiFinish");
        endOfSimulationCb->cb_rtn(endOfSimulationCb.get());
        exit(0);
    default:
        FATAL(0, "Unsupported operation: %d\n", operation);
        break;
    }
    return 0;
}

vpiHandle DEFINE_VPI_FUNC(vpi_register_cb)(p_cb_data cb_data_p) {
    if (cb_data_p->reason == cbStartOfSimulation) {
        WARN("get %s callback, which will be ignored!\n", cb_data_p->reason == cbStartOfSimulation ? "cbStartOfSimulation" : "cbEndOfSimulation");
        return nullptr;
    } else if (cb_data_p->reason == cbNextSimTime) {
        WARN("get cbNextSimTime callback, which will be ignored!\n");
        return nullptr;
    } else if (cb_data_p->reason == cbEndOfSimulation) {
        FATAL(endOfSimulationCb == nullptr, "get cbEndOfSimulation callback, but endOfSimulationCb is not a nullptr!\n");
        endOfSimulationCb.reset(new s_cb_data(*cb_data_p));
        return nullptr;
    }
    FATAL(0, "`vpi_register_cb` not implemented, reason: %d\n", cb_data_p->reason);
}

void DEFINE_VPI_FUNC(vpi_get_value)(vpiHandle expr, p_vpi_value value_p) {
    static char buffer[VPI_GET_MAX_BUFFER_SIZE] = {0};
    static s_vpi_vecval vpiValueVecs[VPI_GET_MAX_VEC_VALS];
    static uint32_t vecVals[VPI_GET_MAX_VEC_VALS];

    auto complexHandle = reinterpret_cast<ComplexHandlePtr>(expr);

    switch (value_p->format) {
    case vpiIntVal:
        value_p->value.integer = complexHandle->getValue32();
        break;
    case vpiHexStrVal:
        complexHandle->getValueHexStr(buffer);
        value_p->value.str = buffer;
        break;
    case vpiVectorVal:
        if (complexHandle->bitwidth <= 32) {
            vpiValueVecs[0].aval = complexHandle->getValue32();
            vpiValueVecs[0].bval = 0;
        } else {
            complexHandle->getValueVec(vecVals);
            for (uint32_t i = 0; i < complexHandle->beatSize; i++) {
                vpiValueVecs[i].aval = vecVals[i];
                vpiValueVecs[i].bval = 0;
            }
        }
        value_p->value.vector = vpiValueVecs;
        break;
    default:
        FATAL(0, "Unsupported format: %d\n", value_p->format);
    }
}

PLI_BYTE8 *DEFINE_VPI_FUNC(vpi_get_str)(PLI_INT32 property, vpiHandle object) {
    FATAL(property == vpiType, "unsupported property: %d\n", property);
    FATAL(object != nullptr, "[dummy_vpi] vpi_get_str: object is nullptr\n");

    auto handle = reinterpret_cast<ComplexHandlePtr>(object)->handle;
    auto str    = dpi_exporter_get_type_str(handle);
    FATAL(str != "", "Cannot get type str: %s\n", str.c_str());

    return (PLI_BYTE8 *)(memAllocator.allocate<std::string>(str)->c_str());
}

PLI_INT32 DEFINE_VPI_FUNC(vpi_get)(PLI_INT32 property, vpiHandle object) {
    FATAL(property == vpiSize, "unsupported property: %d\n", property);

    if (object == nullptr) {
        WARN("[dummy_vpi] vpi_get: get vpi_get, but object is nullptr! return 0\n");
        return 0;
    } else {
        auto complexHandle = reinterpret_cast<ComplexHandlePtr>(object);
        return complexHandle->bitwidth;
    }
}

PLI_INT32 DEFINE_VPI_FUNC(vpi_remove_cb)(vpiHandle cb_obj) { FATAL(0, "`vpi_remove_cb` not implemented\n"); }

PLI_INT32 DEFINE_VPI_FUNC(vpi_free_object)(vpiHandle object) {
    // Nothing to free
    return 0;
}

vpiHandle DEFINE_VPI_FUNC(vpi_handle_by_name)(PLI_BYTE8 *name, vpiHandle scope) {
    static std::string topName = []() {
        auto envVar = std::getenv("DUT_TOP");
        if (envVar == nullptr) {
            return std::string("");
        } else {
            return std::string(envVar);
        }
    }();

    static std::string topModuleName = []() { return std::string(dpi_exporter_get_top_name()); }();

    std::string nameString(name);
    if (topName != "" && topModuleName != "") {
        nameString = replace(nameString, topName, topModuleName);
    }
    std::replace(nameString.begin(), nameString.end(), '.', '_');
    std::replace(nameString.begin(), nameString.end(), '[', '_');
    std::replace(nameString.begin(), nameString.end(), ']', '_');

#ifdef DUMMY_VPI_STRICT_HANDLE_BY_NAME
    auto _hdl = dpi_exporter_handle_by_name(nameString);
    FATAL(_hdl != -1, "[dummy_vpi] vpi_handle_by_name: Cannot find handle => name: %s, org_name: %s, topName:<%s> topModuleName:<%s>\n", nameString.c_str(), name, topName.c_str(), topModuleName.c_str());

    ComplexHandlePtr hdl = memAllocator.allocate<ComplexHandle>(std::string(name), _hdl);

    return reinterpret_cast<vpiHandle>(hdl);
#else
    auto _hdl = dpi_exporter_handle_by_name(nameString);
    if (_hdl == -1) {
        WARN("[dummy_vpi] vpi_handle_by_name: Cannot find handle => name: %s, org_name: %s, topName:<%s> topModuleName:<%s>\n", nameString.c_str(), name, topName.c_str(), topModuleName.c_str());
        return nullptr;
    } else {
        ComplexHandlePtr hdl = memAllocator.allocate<ComplexHandle>(std::string(name), _hdl);
        return reinterpret_cast<vpiHandle>(hdl);
    }
#endif
}

vpiHandle DEFINE_VPI_FUNC(vpi_iterate)(PLI_INT32 type, vpiHandle refHandle) { FATAL(0, "`vpi_iterate` not implemented\n"); }

#ifdef __cplusplus
}
#endif