local ffi = require "ffi"
local path = require "pl.path"
local stringx = require "pl.stringx"
local texcpect = require "TypeExpect"
local Bundle = require "verilua.handles.LuaBundle"

local type = type
local assert = assert
local f = string.format
local table_insert = table.insert

local cfg = _G.cfg

local SignalDB = {
    db_data = nil,
    check_file = nil,
    target_file = "./signal_db.ldb",
    rtl_filelist = "dut_file.f",
    extra_signal_db_gen_args = "",
    initialized = false,
    regenerate = false,
}

local function get_check_file()
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

function SignalDB:init(params)
    local regen = self.regenerate

    if self.initialized and not regen then
        return self
    end

    if cfg.simulator == "wave_vpi" then
        assert(false, "[SignalDB] wave_vpi is not supported yet!")
    end
    
    -- Try to find `rtl_filelist` in: `<check_file_dir>/../<rtl_filelist>`, `./<rtl_filelist>`, `<rtl_filelist>`
    local rtl_filelist = self.rtl_filelist
    do
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
                    if path.getmtime(rtl_file) > path.getmtime(self.target_file) then
                        regen = true
                        break
                    end
                end
                file:close()
            else
                error("[SignalDB] can not find `" .. self.rtl_filelist .. "`")
            end
        end
    end

    if regen then
        self:generate_db(f("signal_db_gen -q --it --iu -f %s -o %s", rtl_filelist, self.target_file))
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
    local lib = ffi.load("signal_db_gen")
    ffi.cdef[[
        void signal_db_gen_main(const char *argList);
    ]]

    local args = args_str .. " " .. self.extra_signal_db_gen_args
    print(f("[SignalDB] generate_db: %s", args))
    lib.signal_db_gen_main(args)
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

    if params.prefix then
        return Bundle(signals, params.prefix, hier_path, "auto_bundle", false, {})
    else
        return Bundle(signals, "", hier_path, "auto_bundle", false, {})
    end
end


return SignalDB