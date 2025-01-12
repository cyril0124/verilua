#include "lua_vpi.h"
#include "vpi_access.h"
#include "vpi_callback.h"

// ----------------------------------------------------------------------------------------------------------
//  Export functions for embeding Verilua inside other simulation environments
//  Make sure to use verilua_init() at the beginning of the simulation and use verilua_final() at the end of the simulation.
//  The verilua_main_step() should be invoked at the beginning of each simulation step.
// ----------------------------------------------------------------------------------------------------------
VERILUA_EXPORT void verilua_init() {
    VL_STATIC_DEBUG("enter verilua_init()\n");
    VeriluaEnv::get_instance().initialize();
    VL_STATIC_DEBUG("leave verilua_init()\n");
}

VERILUA_EXPORT void verilua_final() {
    VL_STATIC_DEBUG("enter verilua_init()\n");
    VeriluaEnv::get_instance().finalize();
    VL_STATIC_DEBUG("leave verilua_init()\n");
}

VERILUA_EXPORT void verilua_main_step() {
    execute_main_step();
}

VERILUA_EXPORT void verilua_main_step_safe() {
    execute_main_step_safe();
}

VERILUA_PRIVATE std::string get_top_module() {
    vpiHandle iter, top_module;

    // Get module handle 
    iter = vpi_iterate(vpiModule, NULL);
    VL_FATAL(iter != NULL, "No module exist...");

    // Scan the first module (Usually this will be the top module of your DUT)
    top_module = vpi_scan(iter);
    VL_FATAL(top_module != NULL, "Cannot find top module!");

    if(setenv("DUT_TOP", vpi_get_str(vpiName, top_module), 1)) {
        VL_FATAL(false, "setenv error for DUT_TOP");
    }
    
    if(const char* env_val = std::getenv("DUT_TOP")) {
        VL_DEBUG("DUT_TOP is {}\n", env_val);
        return std::string(env_val);
    }
    else {
        VL_FATAL(false, "Error while getenv(DUT_TOP)");
    }
}

static void sigabrt_handler(int signal) {
    VeriluaEnv::get_instance().finalize();

    VL_WARN(R"(
---------------------------------------------------------------------
----   Verilua get <SIGABRT>, the program will terminate...      ----
---------------------------------------------------------------------
)");
    exit(1);
}

void VeriluaEnv::finalize() {
    if (finalized) return;
    finalized = true;
    
    VL_STATIC_DEBUG("VeriluaEnv::finalize() called\n");

    if (!initialized) {
        VL_FATAL(false, "FATAL! and verilua is NOT init yet.");
    }

    sol::protected_function lua_finish_callback = (*this->lua)["finish_callback"];
    auto ret = lua_finish_callback();
    if(!ret.valid()) [[unlikely]] {
        sol::error err = ret;
        VL_FATAL(false, "Error calling finish_callback: {}", err.what());
    }

    auto end = std::chrono::high_resolution_clock::now();
    this->end_time = std::chrono::duration_cast<std::chrono::duration<double>>(end.time_since_epoch()).count();

    double time_taken = this->end_time - this->start_time;

#ifdef VL_DEF_ACCUMULATE_LUA_TIME
    double percent = lua_time * 100 / time_taken;
    VL_INFO("time_taken: {:.2f} sec   lua_time_taken: {:.2f} sec   lua_overhead: {:.2f}%\n", time_taken, lua_time, percent);
#else
    VL_INFO("time_taken: {:.2f} sec\n", time_taken);
#endif

#ifdef VL_DEF_VPI_LEARN
    std::ofstream outfile("vpi_learn.log");
    if (!outfile.is_open()) {
        VL_FATAL("Failed to create or open the file.");
    }

    int index = 0;
    VL_INFO("------------- VPI hdl_cache -------------\n");
    for(const auto& pair: this->hdl_cache) {
        auto search = this->hdl_cache_rev.find(pair.second);
        VL_FATAL(search != this->hdl_cache_rev.end());

        VL_INFO("[{}]\t{}\t{}\n", index, pair.first, (int)search->second);
        outfile << pair.first << "\t" << "rw:" << (int)search->second << std::endl;
        ++index;
    }
    VL_INFO("\n");

    outfile.close();
#endif

    VL_STATIC_DEBUG("VeriluaEnv::finalize() finish!\n");
}

void VeriluaEnv::initialize() {
    if (initialized) return;
    VL_STATIC_DEBUG("VeriluaEnv::initialize() called\n");

    if(!this->has_final_cb) {
        register_final_calllback();
    }

    // Make sure that VERILUA_HOME is defined
    const char *VERILUA_HOME = std::getenv("VERILUA_HOME");
    if (VERILUA_HOME == nullptr) {
        VL_FATAL(false, "Error: VERILUA_HOME environment variable is not set.");
    }
    VL_DEBUG("VERILUA_HOME is {}\n", VERILUA_HOME);

#if !defined(VERILATOR) && !defined(WAVE_VPI) // Verilator/wave_vpi has its own sigabrt_handler() in verilator_main.cpp
    signal(SIGABRT, sigabrt_handler);
#endif

    // Initialize Lua state
    this->L = luaL_newstate();
    luaL_openlibs(this->L);

    // Initialize sol Lua state
    this->lua = std::make_unique<sol::state_view>(L);

    // Register breakpoint function for lua
    // DebugPort is 8818
    const char *debug_enable = std::getenv("VL_DEBUGGER");
    if (debug_enable != nullptr && (std::strcmp(debug_enable, "1") == 0 || std::strcmp(debug_enable, "enable") == 0) ) {
        VL_WARN("VL_DEBUGGER is enable\n");
        this->lua->set_function("bp", [](sol::this_state L){
            luaL_dostring(L,"require('LuaPanda').start('localhost', 8818); local ret = LuaPanda and LuaPanda.BP and LuaPanda.BP();");
            return 0;
        });
    } else {
        VL_DEBUG("VL_DEBUGGER is disable\n");
        this->lua->set_function("bp", [](sol::this_state L){
            luaL_dostring(L, "print(\"  \\27[31m [lua_vpi.cpp] ==> Invalid breakpoint! \\27[0m \")");
            return 0;
        });
    }

#ifdef IVERILOG
    const char *_resolve_x_as_zero = std::getenv("VL_RESOLVE_X_AS_ZERO");
    if(_resolve_x_as_zero != nullptr) {
        auto str = std::string(_resolve_x_as_zero);
        if(str == "false" || str == "0") {
            VL_DEBUG("[iverilog] RESOLVE_X_AS_ZERO is false!\n");
            this->resolve_x_as_zero = false;
        } else {
            VL_DEBUG("[iverilog] RESOLVE_X_AS_ZERO is true!\n");
            this->resolve_x_as_zero = true;
        }
    } else {
        VL_DEBUG("[iverilog] RESOLVE_X_AS_ZERO is not set, use default setting => true!\n");
        this->resolve_x_as_zero = true;
    }
#endif

    // Call init.lua at the beginning of the simulation
    std::string INIT_FILE = std::string(VERILUA_HOME) + "/src/lua/verilua/init.lua";
    VL_STATIC_DEBUG("INIT_FILE is {}\n", INIT_FILE);

    // Use pure luaL_dofile() to make luajit-pro load the script successfully
    if (luaL_dofile(this->L, INIT_FILE.c_str()) != LUA_OK) {
        auto _err_info = lua_tostring(this->L, -1);
        std::string err_info = _err_info ? std::string(_err_info) : "No error information found. Perhaps you didn't provide error information when calling `assert`.";
        VL_FATAL(false,"Error calling INIT_FILE: {}, {}", INIT_FILE, err_info);
    }

    const char *DUT_TOP = std::getenv("DUT_TOP");
    if(DUT_TOP == nullptr) {
        auto dut_top = get_top_module();
        VL_WARN("DUT_TOP is not set, automatically set DUT_TOP as {}\n", dut_top);
    }

    // Load lua main script
    const char *LUA_SCRIPT = std::getenv("LUA_SCRIPT");
    if (LUA_SCRIPT == nullptr) {
        VL_FATAL(false, "Error: LUA_SCRIPT environment variable is not set.");
    }
    VL_DEBUG("LUA_SCRIPT is {}\n", LUA_SCRIPT);

    // Use pure luaL_dofile() to make luajit-pro load the script successfully
    if (luaL_dofile(this->L, LUA_SCRIPT) != LUA_OK) {
        auto _err_info = lua_tostring(this->L, -1);
        std::string err_info = _err_info ? std::string(_err_info) : "No error information found. Perhaps you didn't provide error information when calling `assert`.";
        VL_FATAL(false,"Error calling LUA_SCRIPT: {}, {}", LUA_SCRIPT, err_info);
    }

    sol::protected_function verilua_init = (*this->lua)["verilua_init"];
    verilua_init.set_error_handler((*this->lua)["debug"]["traceback"]);
    
    auto ret = verilua_init();
    if(!ret.valid()) {
        sol::error  err = ret;
        VL_FATAL(false, "Error calling verilua_init, {}", err.what());
    }

    this->sim_event = (*this->lua)["sim_event"];
    this->sim_event.set_error_handler((*this->lua)["debug"]["traceback"]); 
    this->main_step = (*this->lua)["lua_main_step"];
    this->main_step.set_error_handler((*this->lua)["debug"]["traceback"]);

#ifdef VL_DEF_OPT_MERGE_CALLBACK
#include "gen_alloc_sim_event.h"
#endif

    auto start = std::chrono::high_resolution_clock::now();
    this->start_time = std::chrono::duration_cast<std::chrono::duration<double>>(start.time_since_epoch()).count();

    initialized = true;
    VL_STATIC_DEBUG("VeriluaEnv::initialize() finish!\n");

    // -----------------------------------------------------------------------------------------
    // Test access time(only for performance test)
    // -----------------------------------------------------------------------------------------
    // {
    //     const uint64_t TIMES = 10000 * 10;
    //     std::vector<double> times;

    //     auto calculate_time = [](std::vector<double> &times) {
    //         std::sort(times.begin(), times.end());

    //         if (times.size() > 4) {
    //             times.erase(times.begin(), times.begin() + 2);
    //             times.erase(times.end() - 2, times.end());
    //         }

    //         double sum = 0;
    //         for (double time : times) {
    //             sum += time;
    //         }

    //         double average_time = sum / times.size();
    //         times.clear();

    //         return average_time;
    //     };
        
    //     sol::protected_function test_func = (*VeriluaEnv::get_instance().lua)["test_func"];
    //     for(int i = 0; i < TIMES; i++) {
    //         auto start1 = std::chrono::high_resolution_clock::now();
    //         test_func();
    //         auto end1 = std::chrono::high_resolution_clock::now();
    //         double start_time = std::chrono::duration_cast<std::chrono::duration<double>>(start1.time_since_epoch()).count();
    //         double end_time = std::chrono::duration_cast<std::chrono::duration<double>>(end1.time_since_epoch()).count();
    //         times.push_back((end_time - start_time) * 1000 * 1000);
    //         // VL_INFO("[{}] test_func time is {} us\n", i, (end_time - start_time) * 1000 * 1000);
    //     }
    //     VL_INFO("[test_func] TIMES: {} Average time: {:.4f} us\n", TIMES, calculate_time(times));


    //     sol::protected_function test_func_with_1arg = (*VeriluaEnv::get_instance().lua)["test_func_with_1arg"];
    //     for(int i = 0; i < TIMES; i++) {
    //         auto start1 = std::chrono::high_resolution_clock::now();
    //         auto ret = test_func_with_1arg(i);
    //         auto end1 = std::chrono::high_resolution_clock::now();
    //         VL_FATAL(ret.valid(), "Error while calling test_func_with_1arg()");
    //         VL_FATAL(ret.get<int>() == i);
    //         double start_time = std::chrono::duration_cast<std::chrono::duration<double>>(start1.time_since_epoch()).count();
    //         double end_time = std::chrono::duration_cast<std::chrono::duration<double>>(end1.time_since_epoch()).count();
    //         times.push_back((end_time - start_time) * 1000 * 1000);
    //     }
    //     VL_INFO("[test_func_with_1arg] TIMES: {} Average time: {:.4f} us\n", TIMES, calculate_time(times));

    //     sol::protected_function test_func_with_2arg = (*VeriluaEnv::get_instance().lua)["test_func_with_2arg"];
    //     for(int i = 0; i < TIMES; i++) {
    //         auto start1 = std::chrono::high_resolution_clock::now();
    //         auto ret = test_func_with_2arg(i, i);
    //         auto end1 = std::chrono::high_resolution_clock::now();
    //         VL_FATAL(ret.valid(), "Error while calling test_func_with_2arg()");
    //         VL_FATAL(ret.get<int>() == i);
    //         double start_time = std::chrono::duration_cast<std::chrono::duration<double>>(start1.time_since_epoch()).count();
    //         double end_time = std::chrono::duration_cast<std::chrono::duration<double>>(end1.time_since_epoch()).count();
    //         times.push_back((end_time - start_time) * 1000 * 1000);
    //     }
    //     VL_INFO("[test_func_with_2arg] TIMES: {} Average time: {:.4f} us\n", TIMES, calculate_time(times));

    //     sol::protected_function test_func_with_4arg = (*VeriluaEnv::get_instance().lua)["test_func_with_4arg"];
    //     for(int i = 0; i < TIMES; i++) {
    //         auto start1 = std::chrono::high_resolution_clock::now();
    //         auto ret = test_func_with_4arg(i, i, i, i);
    //         auto end1 = std::chrono::high_resolution_clock::now();
    //         VL_FATAL(ret.valid(), "Error while calling test_func_with_4arg()");
    //         VL_FATAL(ret.get<int>() == i);
    //         double start_time = std::chrono::duration_cast<std::chrono::duration<double>>(start1.time_since_epoch()).count();
    //         double end_time = std::chrono::duration_cast<std::chrono::duration<double>>(end1.time_since_epoch()).count();
    //         times.push_back((end_time - start_time) * 1000 * 1000);
    //     }
    //     VL_INFO("[test_func_with_4arg] TIMES: {} Average time: {:.4f} us\n", TIMES, calculate_time(times));

    //     sol::protected_function test_func_with_8arg = (*VeriluaEnv::get_instance().lua)["test_func_with_8arg"];
    //     for(int i = 0; i < TIMES; i++) {
    //         auto start1 = std::chrono::high_resolution_clock::now();
    //         auto ret = test_func_with_8arg(i, i, i, i, i, i, i, i);
    //         auto end1 = std::chrono::high_resolution_clock::now();
    //         VL_FATAL(ret.valid(), "Error while calling test_func_with_8arg()");
    //         VL_FATAL(ret.get<int>() == i);
    //         double start_time = std::chrono::duration_cast<std::chrono::duration<double>>(start1.time_since_epoch()).count();
    //         double end_time = std::chrono::duration_cast<std::chrono::duration<double>>(end1.time_since_epoch()).count();
    //         times.push_back((end_time - start_time) * 1000 * 1000);
    //     }
    //     VL_INFO("[test_func_with_8arg] TIMES: {} Average time: {:.4f} us\n", TIMES, calculate_time(times));

    //     sol::protected_function test_func_with_vec_arg = (*VeriluaEnv::get_instance().lua)["test_func_with_vec_arg"];
    //     for(int i = 0; i < TIMES; i++) {
    //         std::vector<int> vec = {i, i, i, i, i, i, i, i};
    //         auto start1 = std::chrono::high_resolution_clock::now();
    //         auto ret = test_func_with_vec_arg(vec);
    //         auto end1 = std::chrono::high_resolution_clock::now();
    //         VL_FATAL(ret.valid(), "Error while calling test_func_with_vec_arg()");
    //         VL_FATAL(ret.get<int>() == i);
    //         double start_time = std::chrono::duration_cast<std::chrono::duration<double>>(start1.time_since_epoch()).count();
    //         double end_time = std::chrono::duration_cast<std::chrono::duration<double>>(end1.time_since_epoch()).count();
    //         times.push_back((end_time - start_time) * 1000 * 1000);
    //     }
    //     VL_INFO("[test_func_with_vec_arg] TIMES: {} Average time: {:.4f} us\n", TIMES, calculate_time(times));
    
    //     VL_FATAL(false);
    // }
}

#ifndef WITHOUT_BOOT_STRAP
void (*vlog_startup_routines[])() = {
    register_next_sim_time_calllback,
    register_start_calllback,
    register_final_calllback, 
    nullptr
};
#endif

// For non-VPI compliant applications that cannot find vlog_startup_routines
VERILUA_EXPORT void vlog_startup_routines_bootstrap() {
    // call each routine in turn like VPI would
    for (auto it = &vlog_startup_routines[0]; *it != nullptr; it++) {
        auto routine = *it;
        routine();
    }
}


// ----------------------------------------------------------------------------------------------------------
// Functions for verilator
// ----------------------------------------------------------------------------------------------------------
TO_VERILATOR void verilua_schedule_loop() {
    sol::protected_function verilua_schedule_loop = (*VeriluaEnv::get_instance().lua)["verilua_schedule_loop"];
    
    auto ret = verilua_schedule_loop();
    if(!ret.valid()) [[unlikely]] {
        sol::error err = ret;
        VL_FATAL(false, "{}", err.what());
    }
}


// ----------------------------------------------------------------------------------------------------------
// SystemVerilog DPI releated functions
// ----------------------------------------------------------------------------------------------------------
TO_LUA void dpi_set_scope(char *str) {
#ifdef IVERILOG
    VL_FATAL(false, "Unsupported!");
#else
    VL_STATIC_DEBUG("set svScope name: {}\n", str);
    const svScope scope = svGetScopeFromName(str);
    VL_FATAL(scope, "scope is NULL");
    svSetScope(scope);
#endif
}


// ----------------------------------------------------------------------------------------------------------
// Other functions expoted to Lua
// ----------------------------------------------------------------------------------------------------------
// Only for test (LuaJIT FFI)
TO_LUA void hello() {
  printf("hello from C\n");
  fmt::print("hello from fmt:print\n");
}

TO_LUA uint64_t bitfield64(uint64_t begin, uint64_t end, uint64_t val) {
    uint64_t mask = ((1ULL << (end - begin + 1)) - 1) << begin;
    return (val & mask) >> begin;
}

TO_LUA void c_simulator_control(long long cmd) {
    // #define vpiStop                  66   /* execute simulator's $stop */
    // #define vpiFinish                67   /* execute simulator's $finish */
    // #define vpiReset                 68   /* execute simulator's $reset */
    // #define vpiSetInteractiveScope   69   /* set simulator's interactive scope */
    VL_DEBUG("simulator control cmd: {}\n", cmd);
    vpi_control(cmd);
}

#include <elfio/elfio.hpp>
#include <unistd.h>
#include <limits.h>
#include "dlfcn.h"
#include <link.h>

VERILUA_PRIVATE void print_link_map(void *handle) {
    struct link_map *map;
    if (dlinfo(handle, RTLD_DI_LINKMAP, &map) != 0) {
        perror("dlinfo");
        return;
    }

    while (map != NULL) {
        printf("Library: %s\n", map->l_name);
        printf("Address: %p\n", (void *)map->l_addr);
        map = map->l_next;
    }
}

TO_LUA char *get_executable_name() {
    char path[PATH_MAX];
    ssize_t len = readlink("/proc/self/exe", path, sizeof(path) - 1);

    if (len != -1) {
        path[len] = '\0'; // Null-terminate the string
        // VL_INFO("Current executable path: {}\n", path);

        char *executable_name = (char *)malloc(len + 1);
        if (executable_name) {
            snprintf(executable_name, len + 1, "%s", path); // Copy the path to allocated memory
            return executable_name; // Return the dynamically allocated string
        } else {
            VL_FATAL(false, "malloc failed!");
        }
    } else {
        VL_FATAL(false, "Failed to get executable name");
    }

    return NULL;
}

TO_LUA char* get_self_cmdline() {
    std::ifstream cmdline_file("/proc/self/cmdline", std::ios::in | std::ios::binary);
    VL_FATAL(cmdline_file.is_open(), "Failed to open /proc/self/cmdline");

    std::ostringstream buffer;
    buffer << cmdline_file.rdbuf();
    std::string cmdline_content = buffer.str();

    // Replace null characters with spaces
    for (size_t i = 0; i < cmdline_content.size(); ++i) {
        if (cmdline_content[i] == '\0') {
            cmdline_content[i] = ' ';
        }
    }

    char* result = strdup(cmdline_content.c_str());
    VL_FATAL(result, "Failed to allocate memory");

    return result;
}

TO_LUA uint64_t get_symbol_address(const char *filename, const char *symbol) {
    static UNORDERED_MAP<std::string, uint64_t> symbol_address_map;
    static uint64_t offset = 0;
    static bool get_offset = false;
    if (!get_offset) {
        get_offset = true;

        void *handle = dlopen(NULL, RTLD_LAZY);
        VL_FATAL(handle != NULL, "handle is NULL!");

        struct link_map *map;
        VL_FATAL(dlinfo(handle, RTLD_DI_LINKMAP, &map) == 0, "dlinfo failed!");
        offset = (uint64_t)map->l_addr;
    }

    if(symbol_address_map.find(symbol) != symbol_address_map.end()) {
        uint64_t address = symbol_address_map[symbol];
        VL_INFO("Symbol `{}` found at `symbol_address_map`, address: 0x{:x}\n", symbol, address);
        return address;
    }

    ELFIO::elfio reader;

    if (!reader.load(filename)) {
        VL_FATAL(false, "Failed to load ELF file: {}", filename);
    }

    ELFIO::section* symtab = reader.sections[".symtab"];
    if (!symtab) {
        VL_FATAL(false, "Symbol table not found in ELF file: {}", filename);
    }

    ELFIO::symbol_section_accessor symbols(reader, symtab);
    for (unsigned int i = 0; i < symbols.get_symbols_num(); ++i) {
        std::string name;
        ELFIO::Elf_Xword size;
        ELFIO::Elf64_Addr value;
        ELFIO::Elf_Half section_index;
        unsigned char bind, type, other;

        symbols.get_symbol(i, name, value, size, bind, type, section_index, other);

        if (name == symbol) {
            VL_INFO("Symbol `{}` found at address: 0x{:x} offset: 0x{:x} final_address: 0x{:x}\n", symbol, static_cast<uint64_t>(value), offset, static_cast<uint64_t>(value + offset));
            symbol_address_map.insert({symbol, static_cast<uint64_t>(value + offset)});
            return static_cast<uint64_t>(value + offset);
        }
    }

    VL_FATAL(false, "Symbol '{}' not found in ELF file: {}", symbol, filename);
    return 0; 
}

TO_LUA char *get_simulator_auto() {
    static const std::unordered_map<std::string, std::string> SYMBOL_TO_SIMULATOR = {
        {"+verilator+", "verilator"},
        {"liblua_vpi_vcs.so", "vcs"},
        {"liblua_vpi_iverilog.so", "iverilog"},
        {"liblua_vpi_wave_vpi.so", "wave_vpi"}
    };

    static std::string executable_name = get_executable_name();
    static std::string cached_result;

    if (!cached_result.empty()) {
        return const_cast<char*>(cached_result.c_str());
    }

    ELFIO::elfio reader;
    if (!reader.load(executable_name)) {
        VL_FATAL(false, "Failed to load ELF file: {}", executable_name);
        return "unknown";
    }

    for (const auto& section : reader.sections) {
        if (section->get_size() == 0 || !section->get_data()) {
            continue; // Skip empty sections
        }

        std::string_view content(section->get_data(), section->get_size());
        size_t pos = 0;

        // Check the last line
        while ((pos = content.find('\n', pos)) != std::string_view::npos) {
            std::string_view line = content.substr(0, pos);
            for (const auto& [symbol, simulator] : SYMBOL_TO_SIMULATOR) {
                if (line.find(symbol) != std::string_view::npos) {
                    cached_result = simulator; // Cached result
                    VL_INFO("Symbol `{}` found, simulator type: {}\n", symbol, simulator);
                    return const_cast<char*>(cached_result.c_str());
                }
            }
            content.remove_prefix(pos + 1);
            pos = 0;
        }

        // Check the last line
        if (!content.empty()) {
            for (const auto& [symbol, simulator] : SYMBOL_TO_SIMULATOR) {
                if (content.find(symbol) != std::string_view::npos) {
                    cached_result = simulator;
                    VL_INFO("Symbol `{}` found, simulator type: {}\n", symbol, simulator);
                    return const_cast<char*>(cached_result.c_str());
                }
            }
        }
    }

    VL_INFO("No target symbol found in ELF file: {}\n", executable_name);
    cached_result = "unknown";
    return const_cast<char*>(cached_result.c_str());
}

TO_LUA {
    typedef struct {
        int *pool;
        int size;
        int top;
    } IDPoolForLua;

    void* idpool_init(int size, int shuffle) {
        IDPoolForLua *idpool = (IDPoolForLua *)malloc(sizeof(IDPoolForLua));
        idpool->size = size;
        idpool->pool = (int *)malloc(size * sizeof(int));
        idpool->top = size - 1;
        
        for (int i = 0; i < size; i++) {
            idpool->pool[i] = size - i;
        }

        if(shuffle >= 1) {
            for (int i = idpool->top; i > 0; --i) {
                int j = std::rand() % (i + 1);
                std::swap(idpool->pool[i], idpool->pool[j]);
            }
        }
        
        return (void*)idpool;
    }

    int idpool_alloc(void *idpool_void) {
        IDPoolForLua *idpool = (IDPoolForLua *)idpool_void;
        if (idpool->top >= 0) {
            return idpool->pool[idpool->top--];
        } else {
            VL_FATAL(false, "IDPool is empty! size => {}", idpool->size);
        }
    }

    void idpool_release(void *idpool_void, int id) {
        IDPoolForLua *idpool = (IDPoolForLua *)idpool_void;
        if (id > idpool->size) {
            VL_FATAL(false, "The released id is out of range! id => {}, size => {}", id, idpool->size);
        }
        idpool->pool[++idpool->top] = id;
    }

    int idpool_pool_size(void *idpool_void) {
        IDPoolForLua *idpool = (IDPoolForLua *)idpool_void;
        return idpool->top + 1;
    }

    void idpool_free(void *idpool_void) {
        IDPoolForLua *idpool = (IDPoolForLua *)idpool_void;
        free(idpool->pool);
        free(idpool);
    }
}