local ffi = require "ffi"
local path = require "pl.path"
local inspect = require "inspect"
local stringx = require "pl.stringx"
local texcpect = require "TypeExpect"

local next = next
local type = type
local assert = assert
local f = string.format
local table_insert = table.insert

local cfg = _G.cfg

local is_prebuild = os.getenv("VL_PREBUILD")

local SignalDB = {
    db_data = nil,
    top = os.getenv("DUT_TOP"),
    check_file = nil,
    target_file = "./signal_db.ldb",
    is_prebuild = is_prebuild,
    rtl_filelist = is_prebuild and assert(os.getenv("VL_PREBUILD_FILELIST"), "[SignalDB] `VL_PREBUILD_FILELIST` is not set when `VL_PREBUILD` is true!") or "dut_file.f",
    extra_signal_db_gen_args = "",
    initialized = false,
    regenerate = false,
}

local function get_check_file()
    if is_prebuild then
        return nil
    else
        local SymbolHelper = require "SymbolHelper"

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

function SignalDB:init(params)
    local regen = self.regenerate

    if self.initialized and not regen then
        return self
    end

    if not self.is_prebuild then
        assert(cfg.simulator ~= "wave_vpi", "[SignalDB] wave_vpi is not supported yet!")
    end

    -- Try to find `rtl_filelist` in: `<check_file_dir>/../<rtl_filelist>`, `./<rtl_filelist>`, `<rtl_filelist>`
    local rtl_filelist = self.rtl_filelist
    if not self.is_prebuild then
        self.check_file = self.check_file or get_check_file()
        local dir, _ = path.splitpath(self.check_file)
        if path.isfile(dir .. "/../" .. rtl_filelist) then
            rtl_filelist = dir .. "/../" .. rtl_filelist
        elseif path.isfile("./" .. rtl_filelist) then
            rtl_filelist = "./" .. rtl_filelist
        elseif path.isfile(rtl_filelist) then
            -- do nothing
        else
            error("[SignalDB] can not find `" .. rtl_filelist .. "`")
        end
    end

    if not regen then
        if not path.isfile(self.target_file) then
            regen = true
        else
            -- Read `rtl_filelist` to get the rtl files and check if any of them is newer than `self.target_file`
            -- If so, regenerate the SignalDB
            local file = io.open(rtl_filelist, "r")
            if file then
                for rtl_file in file:lines() do
                    if not path.isfile(rtl_file) then
                        assert(false, "[SignalDB] can not find `" .. rtl_file .. "`")
                    end

                    if path.getmtime(rtl_file) > path.getmtime(self.target_file) then
                        regen = true
                        break
                    end
                end
                file:close()
            else
                assert(false, "[SignalDB] can not find `" .. self.rtl_filelist .. "`")
            end
        end
    end

    if regen then
        self:generate_db(f("-q --it --iu -f %s -o %s", rtl_filelist, self.target_file))
    end

    self:load_db(self.target_file)

    self.initialized = true

    return self
end

function SignalDB:set_extra_args(args_str)
    texcpect.expect_string(args_str, "args_str")
    self.extra_signal_db_gen_args = args_str
    return self
end

function SignalDB:add_extra_args(args_str)
    texcpect.expect_string(args_str, "args_str")
    self.extra_signal_db_gen_args = self.extra_signal_db_gen_args .. " " .. args_str
    return self
end

function SignalDB:set_regenerate(regenerate)
    texcpect.expect_boolean(regenerate, "regenerate")
    self.regenerate = regenerate
    return self
end

function SignalDB:set_target_file(file_path)
    texcpect.expect_string(file_path, "file_path")
    self.target_file = file_path
    return self
end

function SignalDB:set_rtl_filelist(file_path)
    texcpect.expect_string(file_path, "file_path")
    self.rtl_filelist = file_path
    return self
end

function SignalDB:load_db(file_path)
    local sb = require "string.buffer"
    local file = io.open(file_path, "r")
    if file then
        local data = file:read("*a")
        file:close()
        self.db_data = sb.decode(data)
    else
        error("[SignalDB] [load_db] Failed to open `" .. file_path .. "`")
    end
end

function SignalDB:get_db_data()
    if not self.initialized then
        self:init()
    end

    return self.db_data
end

function SignalDB:generate_db(args_str)
    local top_args = ""
    if type(self.top) == "string" and not self.extra_signal_db_gen_args:find("--top") then
        top_args = " --top " .. self.top
    end

    local args = args_str .. " " .. self.extra_signal_db_gen_args .. top_args
    local cmd = "signal_db_gen " .. args

    if not self.is_prebuild then
        local lib = ffi.load("signal_db_gen")
        ffi.cdef[[
            void signal_db_gen_main(const char *argList);
        ]]
        print(f("[SignalDB] generate_db: %s", cmd))
        lib.signal_db_gen_main(cmd)
    else
        print(f("[SignalDB] generate_db: %s", cmd))
        os.execute(cmd)
    end
end

function SignalDB:get_top_module()
    assert(self.initialized, "[SignalDB] SignalDB is not initialized! please call `SignalDB:init()` first!")
    
    local top_module, _ =  next(self:get_db_data())
    assert(top_module, "[SignalDB] No top module found!")

    return top_module
end

function SignalDB:get_signal_info(hier_path)
    local hier_vec = stringx.split(hier_path, ".")

    local curr = self:get_db_data()
    local end_idx = #hier_vec
    for i, v in ipairs(hier_vec) do
        if i == end_idx then
            -- @signal_info = { <signal_name>, <bitwidth>, <vpi_type> }
            for i, signal_info in ipairs(curr) do
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

local function _find_all(hiers, ret, path, str)
    for k, v in pairs(hiers) do
        local k_type = type(k)
        if k_type == "string" then
            if stringx.lfind(k, str) ~= nil then
                table_insert(ret, path .. "." .. k)
            end

            if type(v) == "table" then
                _find_all(v, ret, path .. "." .. k, str)
            end
        elseif k_type == "number" then
            local signal_info = v
            local signal_name = signal_info[1]
            if stringx.lfind(signal_name, str) ~= nil then
                table_insert(ret, path .. "." .. signal_name)
            end
        end
    end
end

local function _find_hier(hiers, ret, path, str)
    for k, v in pairs(hiers) do
        local k_type = type(k)
        if k_type == "string" then
            if stringx.lfind(k, str) ~= nil then
                table_insert(ret, path .. "." .. k)
            end

            if type(v) == "table" then
                _find_hier(v, ret, path .. "." .. k, str)
            end
        end
    end
end

local function _find_signal(hiers, ret, path, str)
    for k, v in pairs(hiers) do
        local k_type = type(k)
        if k_type == "string" then
            if type(v) == "table" then
                _find_signal(v, ret, path .. "." .. k, str)
            end
        elseif k_type == "number" then
            local signal_info = v
            local signal_name = signal_info[1]
            if stringx.lfind(signal_name, str) ~= nil then
                table_insert(ret, path .. "." .. signal_name)
            end
        end
    end
end

function SignalDB:find_all(str)
    local curr = self:get_db_data()
    local top = self:get_top_module()

    local ret = {}
    _find_all(assert(curr[top], "[SignalDB] No such top module! => " .. top), ret, top, str)
    return ret
end

function SignalDB:find_hier(str)
    local curr = self:get_db_data()
    local top = self:get_top_module()

    local ret = {}
    _find_hier(assert(curr[top], "[SignalDB] No such top module! => " .. top), ret, top, str)
    return ret
end

function SignalDB:find_signal(str)
    local curr = self:get_db_data()
    local top = self:get_top_module()

    local ret = {}
    _find_signal(assert(curr[top], "[SignalDB] No such top module! => " .. top), ret, top, str)
    return ret
end

function SignalDB:auto_bundle(hier_path, params)
    local signals = {}

    -- Check parameters
    assert(
        type(params.filter) == "function" or
        type(params.matches) == "string" or
        type(params.startswith) == "string" or 
        type(params.endswith) == "string" or 
        type(params.prefix) == "string",
        "[auto_bundle] One of the `startswith`, `endswith`, `prefix`, `matches` or `filter` should be valid!"
    )

    -- Extract hierarchy vector
    local hier_vec = stringx.split(hier_path, ".")

    -- Initialize signal_db
    local curr = self:get_db_data()

    -- Extract hierarchy vector
    for i, v in ipairs(hier_vec) do
        curr = curr[v]
    end
    assert(curr ~= nil, "[auto_bundle] No such hierarchy! => " .. hier_path)

    -- Remove hash part from the signal_db table
    for i = 1, #curr do
        local signal_info = curr[i] -- { <signal_name>, <bitwidth>, <vpi_type> }
        local signal_name = signal_info[1]
        local signal_bitwidth = signal_info[2]

        if params.filter then
            if params.filter(signal_name, signal_bitwidth) then
                table_insert(signals, signal_name)
            end
        elseif params.matches then
            if signal_name:match(params.matches) then
                table_insert(signals, signal_name)
            end
        elseif params.startswith and params.endswith then
            if stringx.startswith(signal_name, params.startswith) and stringx.endswith(signal_name, params.endswith) then
                table_insert(signals, signal_name)
            end
        elseif params.prefix then
            if stringx.startswith(signal_name, params.prefix) then
                table_insert(signals, signal_name:sub(#params.prefix + 1))
            end
        elseif params.startswith then
            if stringx.startswith(signal_name, params.startswith) then
                table_insert(signals, signal_name)
            end
        elseif params.endswith then
            if stringx.endswith(signal_name, params.endswith) then
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