---@diagnostic disable: unnecessary-if, unnecessary-assert

---
--- SignalDB - A database utility for managing RTL signal information in Verilua
---
--- SignalDB provides a hierarchical signal database that stores information about
--- RTL signals including their names, bit widths, and VPI types. The database is
--- generated from RTL files using the signal_db_gen tool and can be queried to
--- find signals by pattern matching.
---
--- Usage Example:
--- ```lua
--- local SignalDB = require "verilua.utils.SignalDB"
---
--- -- Initialize the database (will generate if needed)
--- SignalDB:init()
---
--- -- Find all signals matching a pattern
--- local clk_signals = SignalDB:find_signal("*clk*")
---
--- -- Get signal info for a specific path
--- local info = SignalDB:get_signal_info("top.submodule.my_signal")
--- if info then
---     print("Signal name:", info[1])
---     print("Bit width:", info[2])
---     print("VPI type:", info[3])
--- end
---
--- -- Auto-bundle signals with a common prefix
--- local bundle = SignalDB:auto_bundle("top.dut", {
---     prefix = "io_",
---     filter = function(name, width) return width > 1 end
--- })
--- ```
---

local ffi = require "ffi"
local pl_path = require "pl.path"
local inspect = require "inspect"
local tablex = require "pl.tablex"
local stringx = require "pl.stringx"
local texpect = require "verilua.TypeExpect"

local next = next
local type = type
local assert = assert
local f = string.format
local table_insert = table.insert

local cfg = _G.cfg

---@alias verilua.utils.SignalInfo.signal_name string
---@alias verilua.utils.SignalInfo.bitwidth number
---@alias verilua.utils.SignalInfo.vpi_type "vpiNet" | "vpiReg"

---@class (exact) verilua.utils.SignalInfo
---@field [1] verilua.utils.SignalInfo.signal_name
---@field [2] verilua.utils.SignalInfo.bitwidth
---@field [3] verilua.utils.SignalInfo.vpi_type

---@alias verilua.utils.SignalDB.data.hier_path string

---@class (exact) verilua.utils.SignalDB.data
---
--- Example json file:
--- ```json
--- {
---     ["top"] = {
---         {"signal_1", 1, "vpiReg"},
---         {"signal_2", 256, "vpiNet"},
---         -- other signals
---
---         ["submodule"] = {
---             {"sub_signal_1", 8, "vpiNet"},
---             {"sub_signal_2", 1, "vpiReg"},
---             -- other signals
---
---             -- other hierarchies
---         },
---         -- other hierarchies
---     }
--- }
--- ```
---@field [verilua.utils.SignalDB.data.hier_path] verilua.utils.SignalDB.data
---@field [integer] verilua.utils.SignalInfo

---@class (exact) verilua.utils.SignalDB.auto_bundle.params
---@field name? string
---@field filter? fun(verilua.utils.SignalInfo.signal_name, verilua.utils.SignalInfo.bitwidth): boolean
---@field matches? string
---@field wildmatch? string
---@field startswith? string
---@field endswith? string
---@field prefix? string

---@class (exact) verilua.utils.SignalDB
--- SignalDB is a singleton class that manages RTL signal information database.
--- It provides methods to initialize, query, and search signals in the design hierarchy.
---
---@field private db_data verilua.utils.SignalDB.data The parsed signal database
---@field private top string? The top module name (can be set via DUT_TOP env var)
---@field private check_file string? File used to check if regeneration is needed
---@field private target_file string Path to store/load the generated database file (default: "./signal_db.ldb")
---@field private rtl_filelist string Path to the RTL filelist (default: "dut_file.f")
---@field private extra_signal_db_gen_args string Additional arguments for signal_db_gen tool
---@field private initialized boolean Whether the database has been initialized
---@field private regenerate boolean Force regeneration of the database
---@field init fun(self: verilua.utils.SignalDB, params?: table): verilua.utils.SignalDB Initialize the database (generates if needed)
---@field set_extra_args fun(self: verilua.utils.SignalDB, args_str: string): verilua.utils.SignalDB Set extra arguments for signal_db_gen (replaces existing)
---@field add_extra_args fun(self: verilua.utils.SignalDB, args_str: string): verilua.utils.SignalDB Add extra arguments for signal_db_gen (appends to existing)
---@field set_regenerate fun(self: verilua.utils.SignalDB, regenerate: boolean): verilua.utils.SignalDB Set whether to force regenerate the database
---@field set_target_file fun(self: verilua.utils.SignalDB, file_path: string): verilua.utils.SignalDB Set the target database file path
---@field set_rtl_filelist fun(self: verilua.utils.SignalDB, file_path: string): verilua.utils.SignalDB Set the RTL filelist path
---@field try_load_db fun(self: verilua.utils.SignalDB): verilua.utils.SignalDB Try to load existing database without generating
---@field set_enable_modules fun(self: verilua.utils.SignalDB, modules: table<integer, string>): verilua.utils.SignalDB Set modules to enable for signal extraction
---@field set_disable_modules fun(self: verilua.utils.SignalDB, modules: table<integer, string>): verilua.utils.SignalDB Set modules to disable for signal extraction
---@field private load_db fun(self: verilua.utils.SignalDB, file_path: string) Load database from file
---@field private generate_db fun(self: verilua.utils.SignalDB, args_str: string) Generate database using signal_db_gen tool
---@field get_db_data fun(self: verilua.utils.SignalDB): verilua.utils.SignalDB.data Get the raw database data
---@field get_top_module fun(self: verilua.utils.SignalDB): string Get the top module name from the database
---@field get_signal_info fun(self: verilua.utils.SignalDB, hier_path: verilua.utils.SignalDB.data.hier_path): verilua.utils.SignalInfo? Get signal info by full hierarchy path
---@field find_all fun(self: verilua.utils.SignalDB, pattern: string): string[] Find all signals and hierarchies matching wildcard pattern
---@field find_hier fun(self: verilua.utils.SignalDB, hier_pattern: string): string[] Find all hierarchies matching wildcard pattern
---@field find_signal fun(self: verilua.utils.SignalDB, signal_pattern: string, hier_pattern?: string, full_info?: boolean): string[] | verilua.utils.SignalInfo[] Find signals matching pattern, optionally filtered by hierarchy
---@field auto_bundle fun(self: verilua.utils.SignalDB, hier_path: string, params: verilua.utils.SignalDB.auto_bundle.params): verilua.handles.Bundle Automatically create a Bundle from signals matching criteria
local SignalDB = {
    db_data = {},
    top = os.getenv("DUT_TOP"),
    check_file = nil,
    target_file = "./signal_db.ldb",
    rtl_filelist = "dut_file.f",
    extra_signal_db_gen_args = "",
    initialized = false,
    regenerate = false,
}

local function get_check_file()
    if cfg.simulator == "nosim" then
        return nil
    else
        local SymbolHelper = require "verilua.utils.SymbolHelper"

        local check_file = nil
        if cfg.simulator == "iverilog" then
            local cmdline = SymbolHelper.get_self_cmdline()
            local ret_list = stringx.split(cmdline, " "):filter(function(str) return stringx.endswith(str, ".vvp") end)
            assert(#ret_list == 1)

            check_file = ret_list[1]
        else
            check_file = SymbolHelper.get_executable_name()
        end

        return check_file
    end
end

--- Initialize the SignalDB database.
--- This method will generate the database if it doesn't exist or if regenerate is set.
--- The database is generated using the signal_db_gen tool from RTL files.
---
--- @param _params table? Optional parameters (currently unused, reserved for future use)
--- @return verilua.utils.SignalDB Returns self for method chaining
---
--- Usage:
--- ```lua
--- SignalDB:set_rtl_filelist("my_rtl.f"):init()
--- ```
function SignalDB:init(_params)
    if self.initialized and not self.regenerate then
        return self
    end

    if not cfg.simulator == "nosim" then
        assert(cfg.simulator ~= "wave_vpi", "[SignalDB] wave_vpi is not supported yet!")
    end

    -- Try to find `rtl_filelist` in: `<check_file_dir>/../<rtl_filelist>`, `./<rtl_filelist>`, `<rtl_filelist>`
    local rtl_filelist = self.rtl_filelist
    if cfg.simulator ~= "nosim" then
        self.check_file = self.check_file or get_check_file()
        local dir, _ = pl_path.splitpath(self.check_file)
        if pl_path.isfile(rtl_filelist) then
            -- do nothing
        elseif pl_path.isfile("./" .. rtl_filelist) then
            rtl_filelist = "./" .. rtl_filelist
        elseif pl_path.isfile(dir .. "/../" .. rtl_filelist) then
            rtl_filelist = dir .. "/../" .. rtl_filelist
        else
            error("[SignalDB] can not find `" .. rtl_filelist .. "`")
        end

        self:generate_db(f(
            "--quiet --ignore-chisel-trivial-signals --ignore-underscore-signals -f %s -o %s %s",
            rtl_filelist,
            self.target_file,
            self.regenerate and "--no-cache" or ""
        ))
    else
        local nosim_cmdline_args_file = "./nosim_cmdline_args.lua"
        assert(pl_path.isfile(nosim_cmdline_args_file),
            f("[SignalDB] can not find `%s`", nosim_cmdline_args_file))

        local args_func = loadfile(nosim_cmdline_args_file)
        assert(type(args_func) == "function")

        local args_str = args_func()
        assert(type(args_str) == "string")

        local nosim_cmdline_args = stringx.replace(args_str, "--build", "")
        self:generate_db(nosim_cmdline_args)
    end

    self:load_db(self.target_file)

    self.initialized = true

    return self
end

--- Set extra arguments for the signal_db_gen tool (replaces existing arguments).
---
--- @param args_str string Arguments to pass to signal_db_gen tool
--- @return verilua.utils.SignalDB Returns self for method chaining
---
--- Usage:
--- ```lua
--- SignalDB:set_extra_args("--verbose --max-depth 5"):init()
--- ```
function SignalDB:set_extra_args(args_str)
    texpect.expect_string(args_str, "args_str")
    self.extra_signal_db_gen_args = args_str
    return self
end

--- Add extra arguments for the signal_db_gen tool (appends to existing arguments).
---
--- @param args_str string Arguments to append to signal_db_gen tool arguments
--- @return verilua.utils.SignalDB Returns self for method chaining
---
--- Usage:
--- ```lua
--- SignalDB:add_extra_args("--verbose"):add_extra_args("--max-depth 5"):init()
--- ```
function SignalDB:add_extra_args(args_str)
    texpect.expect_string(args_str, "args_str")
    self.extra_signal_db_gen_args = self.extra_signal_db_gen_args .. " " .. args_str
    return self
end

--- Set whether to force regenerate the database on next init() call.
--- When set to true, the database will be regenerated even if it already exists.
---
--- @param regenerate boolean If true, forces database regeneration
--- @return verilua.utils.SignalDB Returns self for method chaining
---
--- Usage:
--- ```lua
--- SignalDB:set_regenerate(true):init()  -- Forces regeneration
--- ```
function SignalDB:set_regenerate(regenerate)
    texpect.expect_boolean(regenerate, "regenerate")
    self.regenerate = regenerate
    return self
end

--- Set the target file path for storing/loading the database.
--- Default is "./signal_db.ldb".
---
--- @param file_path string Path to the database file
--- @return verilua.utils.SignalDB Returns self for method chaining
---
--- Usage:
--- ```lua
--- SignalDB:set_target_file("./my_signals.ldb"):init()
--- ```
function SignalDB:set_target_file(file_path)
    texpect.expect_string(file_path, "file_path")
    self.target_file = file_path
    return self
end

--- Try to load an existing database file without triggering generation.
--- If the database file exists, it will be loaded; otherwise, nothing happens.
--- This is useful when you want to use a pre-generated database.
---
--- @return verilua.utils.SignalDB Returns self for method chaining
---
--- Usage:
--- ```lua
--- SignalDB:set_target_file("./prebuilt.ldb"):try_load_db()
--- if SignalDB.initialized then
---     -- Database was loaded successfully
--- end
--- ```
function SignalDB:try_load_db()
    if pl_path.isfile(self.target_file) then
        self:load_db(self.target_file)
        self.initialized = true
    end
    return self
end

--- Set modules to be enabled for signal extraction.
--- Only signals within the specified modules will be included in the database.
---
--- @param modules table<integer, string> Array of module names to enable
--- @return verilua.utils.SignalDB Returns self for method chaining
---
--- Usage:
--- ```lua
--- SignalDB:set_enable_modules({"cpu_core", "memory_ctrl"}):init()
--- ```
function SignalDB:set_enable_modules(modules)
    texpect.expect_table(modules, "modules")
    texpect.expect_string(modules[1], "modules[1]")
    for _, module in ipairs(modules) do
        self.extra_signal_db_gen_args = self.extra_signal_db_gen_args .. " --enable-module " .. module
    end
    return self
end

--- Set modules to be disabled for signal extraction.
--- Signals within the specified modules will be excluded from the database.
---
--- @param modules table<integer, string> Array of module names to disable
--- @return verilua.utils.SignalDB Returns self for method chaining
---
--- Usage:
--- ```lua
--- SignalDB:set_disable_modules({"debug_module", "test_harness"}):init()
--- ```
function SignalDB:set_disable_modules(modules)
    texpect.expect_table(modules, "modules")
    texpect.expect_string(modules[1], "modules[1]")
    for _, module in ipairs(modules) do
        self.extra_signal_db_gen_args = self.extra_signal_db_gen_args .. " --disable-module " .. module
    end
    return self
end

--- Set the RTL filelist path used for database generation.
--- Default is "dut_file.f".
---
--- @param file_path string Path to the RTL filelist (typically a .f file)
--- @return verilua.utils.SignalDB Returns self for method chaining
---
--- Usage:
--- ```lua
--- SignalDB:set_rtl_filelist("./rtl/sources.f"):init()
--- ```
function SignalDB:set_rtl_filelist(file_path)
    texpect.expect_string(file_path, "file_path")
    self.rtl_filelist = file_path
    return self
end

--- Load the signal database from a file.
--- The database file is expected to be in LuaJIT string.buffer format.
---
--- @param file_path string Path to the database file
function SignalDB:load_db(file_path)
    local sb = require "string.buffer"
    local file = io.open(file_path, "r")
    if file then
        local data = file:read("*a")
        file:close()
        self.db_data = sb.decode(data) --[[@as table]]
    else
        error("[SignalDB] [load_db] Failed to open `" .. file_path .. "`")
    end
end

--- Get the raw database data.
--- Will auto-initialize if not already initialized.
---
--- @return verilua.utils.SignalDB.data The hierarchical signal database
---
--- Usage:
--- ```lua
--- local db = SignalDB:get_db_data()
--- for hier_name, hier_data in pairs(db) do
---     print("Hierarchy:", hier_name)
--- end
--- ```
function SignalDB:get_db_data()
    if not self.initialized then
        self:init()
    end

    return self.db_data
end

local SIGNALDB_SUCCESS = 0
local SIGNALDB_NO_NEED_GEN = 1
local SIGNALDB_EXCEPTION_OCCURRED = 2
function SignalDB:generate_db(args_str)
    local args = args_str .. " " .. self.extra_signal_db_gen_args

    local top_args = ""
    local extra_args_has_top = stringx.lfind(self.extra_signal_db_gen_args, "--top")
    if type(self.top) == "string" and not extra_args_has_top then
        top_args = " --top " .. self.top

        if not stringx.lfind(args_str, "--top") then
            args = args .. top_args
        else
            -- Has --top in args_str
            if not stringx.lfind(args_str, top_args) then
                -- Found conflict top args
                -- args_list is a pl.List object
                local args_list = stringx.split(args_str)
                local top_idx = args_list:index("--top")
                assert(args_list:contains("--top"))
                args_list[top_idx + 1] = self.top
                args = args_list:join(" ")
            else
                -- Identical top args, do nothing
            end
        end
    end

    if extra_args_has_top then
        assert(false, "TODO:")
    end

    local verilua_home = os.getenv("VERILUA_HOME")
    assert(verilua_home, "[SignalDB] environment variable `VERILUA_HOME` is not set!")

    -- Try to load .so library first
    local load_success, lib = pcall(function()
        return ffi.load(verilua_home .. "/shared/libsignal_db_gen.so")
    end)

    local cmd = load_success and ("signal_db_gen " .. args) or args

    -- Trim duplicate spaces
    local _cmd_list = stringx.split(cmd)
    cmd = _cmd_list:join(" ")


    local ret = nil
    if load_success then
        -- Successfully loaded .so library
        ffi.cdef [[
            int signal_db_gen_main(const char *argList);
        ]]

        print(f("[SignalDB] generate_db cmd: %s", cmd))
        ret = lib.signal_db_gen_main(cmd)
    else
        -- Failed to load .so (possibly GLIBC compatibility issue), fallback to binary
        print(f("[SignalDB] Failed to load libsignal_db_gen.so (reason: %s), falling back to binary", tostring(lib)))

        local binary_path = verilua_home .. "/tools/signal_db_gen"
        assert(pl_path.isfile(binary_path), f("[SignalDB] signal_db_gen binary not found at: %s", binary_path))

        print(f("[SignalDB] generate_db cmd: %s %s", binary_path, cmd))

        -- LuaJIT mode: need to parse the return code from $?
        -- Actually, let's use io.popen to get the exit code reliably
        print("[SignalDB] Executing signal_db_gen binary...")
        local handle = io.popen(binary_path .. " " .. cmd .. "; echo $?")
        assert(handle, "[SignalDB] Failed to execute signal_db_gen binary!")

        local output = handle:read("*a")
        handle:close()
        print("[SignalDB] signal_db_gen output:\n==============\n" .. output .. "==============")

        -- Extract the exit code from the last line
        local lines = stringx.splitlines(output)
        local last_line = lines[#lines]
        ret = tonumber(last_line)

        if not ret then
            error(f("[SignalDB] Failed to parse exit code from command output. Last line: %s", last_line))
        end
    end

    if ret == SIGNALDB_NO_NEED_GEN then
        print("[SignalDB] generate_db: no need to generate!")
    elseif ret == SIGNALDB_EXCEPTION_OCCURRED then
        assert(false, "[SignalDB] generate_db failed! Exception occurred!")
    else
        assert(ret == SIGNALDB_SUCCESS, "[SignalDB] generate_db failed! ret => " .. ret)
    end
end

--- Get the top module name from the database.
--- The top module is the first (and usually only) top-level key in the database.
---
--- @return string The top module name
---
--- Usage:
--- ```lua
--- local top = SignalDB:get_top_module()
--- print("Top module:", top)  -- e.g., "top" or "tb_top"
--- ```
function SignalDB:get_top_module()
    assert(self.initialized, "[SignalDB] SignalDB is not initialized! please call `SignalDB:init()` first!")

    local top_module, _ = next(self:get_db_data())
    assert(top_module, "[SignalDB] No top module found!")

    return top_module --[[@as string]]
end

--- Get signal information by full hierarchy path.
--- Returns the SignalInfo tuple containing signal name, bit width, and VPI type.
---
--- @param hier_path string Full hierarchy path (e.g., "top.submodule.my_signal")
--- @return verilua.utils.SignalInfo? The signal info or nil if not found
---
--- Usage:
--- ```lua
--- local info = SignalDB:get_signal_info("top.cpu.pc")
--- if info then
---     local name, width, vpi_type = info[1], info[2], info[3]
---     print(string.format("Signal %s: %d bits, type %s", name, width, vpi_type))
--- end
--- ```
function SignalDB:get_signal_info(hier_path)
    ---@type string[]
    local hier_vec = stringx.split(hier_path, ".")

    local curr = self:get_db_data()
    local end_idx = #hier_vec
    for i, v in ipairs(hier_vec) do
        if i == end_idx then
            -- @signal_info = { <signal_name>, <bitwidth>, <vpi_type> }
            for _, signal_info in ipairs(curr) do
                ---@cast signal_info verilua.utils.SignalInfo
                if signal_info[1] == v then
                    return signal_info
                end
            end
            return nil
        end

        curr = curr[v]
    end

    return nil
end

ffi.cdef [[
    int wildmatch(const char *pattern, const char *str);
]]

---@param pattern string
---@param str string
---@return boolean
local function wildmatch(pattern, str)
    if ffi.C.wildmatch(pattern, str) == 1 then
        return true
    else
        return false
    end
end

---Internal helper function to recursively find all signals and hierarchies matching the pattern
---
---@param hiers verilua.utils.SignalDB.data Current hierarchy level to search
---@param ret string[] result table Array to accumulate matched paths
---@param path string hierarchy path Current hierarchy path (e.g., "top.submodule")
---@param pattern string wildcard string to match Wildcard pattern for matching
local function _find_all(hiers, ret, path, pattern)
    for k, v in pairs(hiers) do
        local k_type = type(k)
        if k_type == "string" then
            if wildmatch(pattern, k) then
                table_insert(ret, path .. "." .. k)
            end

            if type(v) == "table" then
                ---@cast v verilua.utils.SignalDB.data
                _find_all(v, ret, path .. "." .. k, pattern)
            end
        elseif k_type == "number" then
            local signal_info = v
            local signal_name = signal_info[1]
            ---@cast signal_name string
            if wildmatch(pattern, signal_name) then
                table_insert(ret, path .. "." .. signal_name)
            end
        end
    end
end

---Internal helper function to recursively find all hierarchies matching the pattern
---Only matches hierarchy/module names, not individual signals
---
---@param hiers verilua.utils.SignalDB.data Current hierarchy level to search
---@param ret string[] result table Array to accumulate matched hierarchy paths
---@param path string hierarchy path Current hierarchy path (e.g., "top.submodule")
---@param hier_pattern string wildcard string to match Wildcard pattern for matching hierarchy names
local function _find_hier(hiers, ret, path, hier_pattern)
    for k, v in pairs(hiers) do
        local k_type = type(k)
        if k_type == "string" then
            if wildmatch(hier_pattern, k) then
                table_insert(ret, path .. "." .. k)
            end

            if type(v) == "table" then
                ---@cast v verilua.utils.SignalDB.data
                _find_hier(v, ret, path .. "." .. k, hier_pattern)
            end
        end
    end
end

---Internal helper function to recursively find all signals matching the pattern
---Can optionally filter by hierarchy pattern and return full signal info
---
---@param hiers verilua.utils.SignalDB.data Current hierarchy level to search
---@param ret string[] | verilua.utils.SignalInfo[] result table Array to accumulate matched signals (paths or SignalInfo objects)
---@param path string hierarchy path Current hierarchy path (e.g., "top.submodule")
---@param signal_pattern string wildcard string to match Wildcard pattern for matching signal names
---@param hier_pattern string? hierarchy wildcard string to match if not nil Optional wildcard pattern to filter by hierarchy path
---@param full_info boolean? whether to return full signal info If true, returns SignalInfo[]; otherwise returns signal paths as string[]
local function _find_signal(hiers, ret, path, signal_pattern, hier_pattern, full_info)
    for k, v in pairs(hiers) do
        local k_type = type(k)
        if k_type == "string" then
            if type(v) == "table" then
                ---@cast v verilua.utils.SignalDB.data
                _find_signal(v, ret, path .. "." .. k, signal_pattern, hier_pattern, full_info)
            end
        elseif k_type == "number" then
            ---@cast v verilua.utils.SignalInfo
            local signal_info = v
            local signal_name = signal_info[1]
            if wildmatch(signal_pattern, signal_name) then
                if hier_pattern then
                    if wildmatch(hier_pattern, path) then
                        if full_info then
                            table_insert(ret, tablex.deepcopy(signal_info))
                        else
                            table_insert(ret, path .. "." .. signal_name)
                        end
                    end
                else
                    if full_info then
                        table_insert(ret, tablex.deepcopy(signal_info))
                    else
                        table_insert(ret, path .. "." .. signal_name)
                    end
                end
            end
        end
    end
end

---Find all signals and hierarchies matching the wildcard pattern
---Searches through all levels of the hierarchy and returns full paths for both signals and sub-hierarchies
---
---@param pattern string Wildcard pattern to match (supports * and ? wildcards)
---@return string[] matched_paths Array of full hierarchy paths (e.g., "top.submodule.signal_name")
function SignalDB:find_all(pattern)
    local curr = self:get_db_data()
    local top = self:get_top_module()

    local ret = {}
    local hiers = assert(curr[top], "[SignalDB] No such top module! => " .. top)
    _find_all(hiers, ret, top, pattern)
    return ret
end

---Find all hierarchies matching the wildcard pattern
---Only searches for hierarchy/module names, not individual signals
---
---@param hier_pattern string Wildcard pattern to match hierarchy names (supports * and ? wildcards)
---@return string[] matched_hier_paths Array of full hierarchy paths (e.g., "top.submodule")
function SignalDB:find_hier(hier_pattern)
    local curr = self:get_db_data()
    local top = self:get_top_module()

    local ret = {}
    local hiers = assert(curr[top], "[SignalDB] No such top module! => " .. top)
    _find_hier(hiers, ret, top, hier_pattern)
    return ret
end

---Find all signals matching the wildcard pattern, optionally filtered by hierarchy pattern
---Returns either signal names or full signal info depending on the full_info parameter
---
---@param signal_pattern string Wildcard pattern to match signal names (supports * and ? wildcards)
---@param hier_pattern? string Optional wildcard pattern to filter by hierarchy path (supports * and ? wildcards)
---@param full_info? boolean If true, returns SignalInfo[] with {signal_name, bitwidth, vpi_type}; if false or nil, returns signal names as string[]
---@return string[] | verilua.utils.SignalInfo[] matched_signals Array of signal paths or SignalInfo objects
function SignalDB:find_signal(signal_pattern, hier_pattern, full_info)
    local curr = self:get_db_data()
    local top = self:get_top_module()

    local ret = {}
    local hiers = assert(curr[top], "[SignalDB] No such top module! => " .. top)
    _find_signal(hiers, ret, top, signal_pattern, hier_pattern, full_info)
    return ret
end

--- Default filter function for auto_bundle that accepts all signals.
---@param _signal_name string The signal name (unused)
---@param _signal_bitwidth number The signal bit width (unused)
---@return boolean Always returns true
local function default_filter(_signal_name, _signal_bitwidth)
    return true
end

--- Automatically create a Bundle from signals matching specified criteria.
--- This is a powerful method to quickly bundle related signals based on naming patterns.
---
--- @param hier_path string The hierarchy path to search for signals (e.g., "top.dut")
--- @param params verilua.utils.SignalDB.auto_bundle.params Configuration parameters:
---   - name: Optional name for the bundle
---   - filter: Custom filter function(signal_name, bitwidth) -> boolean
---   - matches: Lua pattern string to match signal names
---   - wildmatch: Wildcard pattern (* and ?) to match signal names
---   - startswith: String prefix to match signal names
---   - endswith: String suffix to match signal names
---   - prefix: Signal name prefix to strip when creating bundle
--- @return verilua.handles.Bundle A Bundle containing the matched signals
---
--- Usage Examples:
--- ```lua
--- -- Bundle all signals starting with "io_"
--- local io_bundle = SignalDB:auto_bundle("top.dut", {
---     prefix = "io_"
--- })
---
--- -- Bundle signals matching a wildcard pattern
--- local clk_bundle = SignalDB:auto_bundle("top", {
---     wildmatch = "*clk*"
--- })
---
--- -- Bundle with custom filter (only signals wider than 8 bits)
--- local wide_bundle = SignalDB:auto_bundle("top.dut", {
---     startswith = "data_",
---     filter = function(name, width) return width > 8 end
--- })
---
--- -- Bundle with Lua pattern matching
--- local numbered_bundle = SignalDB:auto_bundle("top", {
---     matches = "sig_%d+"
--- })
--- ```
function SignalDB:auto_bundle(hier_path, params)
    texpect.expect_table(params, "params", {
        "name",
        "filter",
        "matches",
        "wildmatch",
        "startswith",
        "endswith",
        "prefix",
    })

    ---@type string[]
    local signals = {}

    -- Check parameters
    assert(
        type(params.filter) == "function" or
        type(params.matches) == "string" or
        type(params.wildmatch) == "string" or
        type(params.startswith) == "string" or
        type(params.endswith) == "string" or
        type(params.prefix) == "string",
        "[auto_bundle] One of the `startswith`, `endswith`, `prefix`, `matches` or `filter` should be valid!"
    )

    -- Extract hierarchy vector
    ---@type string[]
    local hier_vec = stringx.split(hier_path, ".")

    -- Initialize signal_db
    local curr = self:get_db_data()

    -- Extract hierarchy vector
    for _, v in ipairs(hier_vec) do
        curr = curr[v]
    end
    assert(curr ~= nil, "[auto_bundle] No such hierarchy! => " .. hier_path)

    ---@cast curr verilua.utils.SignalDB.data

    local filter = params.filter or default_filter

    -- Remove hash part from the signal_db table
    for i = 1, #curr do
        ---@type verilua.utils.SignalInfo
        local signal_info = curr[i]
        local signal_name = signal_info[1]
        local signal_bitwidth = signal_info[2]

        if params.matches then
            if signal_name:match(params.matches) then
                if filter(signal_name, signal_bitwidth) then
                    table_insert(signals, signal_name)
                end
            end
        elseif params.wildmatch then
            if wildmatch(params.wildmatch, signal_name) then
                if filter(signal_name, signal_bitwidth) then
                    if params.prefix and stringx.startswith(signal_name, params.prefix) then
                        table_insert(signals, signal_name:sub(#params.prefix + 1))
                    else
                        table_insert(signals, signal_name)
                    end
                end
            end
        elseif params.startswith and params.endswith then
            if stringx.startswith(signal_name, params.startswith) and stringx.endswith(signal_name, params.endswith) then
                if filter(signal_name, signal_bitwidth) then
                    table_insert(signals, signal_name)
                end
            end
        elseif params.prefix then
            if stringx.startswith(signal_name, params.prefix) then
                if filter(signal_name, signal_bitwidth) then
                    table_insert(signals, signal_name:sub(#params.prefix + 1))
                end
            end
        elseif params.startswith then
            if stringx.startswith(signal_name, params.startswith) then
                if filter(signal_name, signal_bitwidth) then
                    table_insert(signals, signal_name)
                end
            end
        elseif params.endswith then
            if stringx.endswith(signal_name, params.endswith) then
                if filter(signal_name, signal_bitwidth) then
                    table_insert(signals, signal_name)
                end
            end
        elseif params.filter then
            if filter(signal_name, signal_bitwidth) then
                table_insert(signals, signal_name)
            end
        end
    end

    assert(#signals > 0, "[auto_bundle] No signals found! params: " .. inspect(params))

    local Bundle = require "verilua.handles.LuaBundle"
    local name = "auto_bundle"
    if params.name then
        assert(type(params.name) == "string", "[auto_bundle] `name` should be a string!")
        name = name .. "@" .. params.name
    end

    if params.prefix then
        return Bundle(signals, params.prefix, hier_path, name, false, {})
    else
        return Bundle(signals, "", hier_path, name, false, {})
    end
end

return SignalDB
