---@diagnostic disable: need-check-nil
local ffi = require "ffi"
local math = require "math"
local vpiml = require "vpiml"
local debug = require "debug"
local utils = require "LuaUtils"
local class = require "pl.class"
local texpect = require "TypeExpect"
local table_new = require "table.new"

local BeatWidth = 32

local type = type
local print = print
local rawset = rawset
local assert = assert
local f = string.format
local tonumber = tonumber
local bit_tohex = bit.tohex
local setmetatable = setmetatable

local ffi_new = ffi.new
local ffi_string = ffi.string

local HexStr = _G.HexStr
local BinStr = _G.BinStr
local DecStr = _G.DecStr
local verilua_debug = _G.verilua_debug
local await_posedge_hdl = _G.await_posedge_hdl
local await_negedge_hdl = _G.await_negedge_hdl
local always_await_posedge_hdl = _G.always_await_posedge_hdl
local await_noop = _G.await_noop

local DpiExporter

---@class CallableHDL.mt: CallableHDL
---@field __value any
---@field __verbose boolean
---@field __stop_on_fail boolean
local __chdl_mt

local post_init_mt = setmetatable({
    _post_init = function(obj)
        if not __chdl_mt then
            __chdl_mt = setmetatable(
                {
                    __value = 0,
                    __verbose = false,
                    __stop_on_fail = false
                },
                getmetatable(obj)
            )
        end
    end
}, {})

---@class MultiBeatData.size: integer
---@class MultiBeatData: {[0]: MultiBeatData.size, [integer]: uint32_t}

---@class (exact) CallableHDL
---@overload fun(fullpath: string, name: string, hdl?: ComplexHandleRaw): CallableHDL
---@field __type string
---@field fullpath string
---@field name string
---@field private always_fired boolean
---@field private width integer
---@field private hdl ComplexHandleRaw
---@field private hdl_type string
---@field is_array boolean
---@field array_size integer
---@field private array_hdls table<integer, ComplexHandleRaw>
---@field private array_bitvecs table<integer, BitVec>
---@field private beat_num integer
---@field private is_multi_beat boolean
---@field private cached_value any
---@field reset_set_cached fun(self: CallableHDL) Reset the cached value to `nil`
---@field private c_results ffi.cdata*
---@field value any Used for assign value based on value type
---
---@field get fun(self: CallableHDL, force_multi_beat?: boolean): integer|MultiBeatData
---@field get64 fun(self: CallableHDL): uint64_t
---@field get_bitvec fun(self: CallableHDL): BitVec
---@field set fun(self: CallableHDL, value: integer|uint64_t|integer[], force_single_beat?: boolean)
---@field set_unsafe fun(self: CallableHDL, value: integer|uint64_t|integer[], force_single_beat?: boolean)
---@field set_cached fun(self: CallableHDL, value: integer|uint64_t|integer[], force_single_beat?: boolean)
---@field set_bitfield fun(self: CallableHDL, s: integer, e: integer, v: integer)
---@field set_bitfield_hex_str fun(self: CallableHDL, s: integer, e: integer, hex_str: string)
---@field set_force fun(self: CallableHDL, value: integer|uint64_t|integer[], force_single_beat?: boolean)
---@field set_release fun(self: CallableHDL)
---@field set_imm fun(self: CallableHDL, value: integer|uint64_t|integer[], force_single_beat?: boolean)
---@field set_imm_unsafe fun(self: CallableHDL, value: integer|uint64_t|integer[], force_single_beat?: boolean)
---@field set_imm_cached fun(self: CallableHDL, value: integer|uint64_t|integer[], force_single_beat?: boolean)
---@field set_imm_bitfield fun(self: CallableHDL, s: integer, e: integer, v: integer)
---@field set_imm_bitfield_hex_str fun(self: CallableHDL, s: integer, e: integer, hex_str: string)
---@field set_imm_force fun(self: CallableHDL, value: integer|uint64_t|integer[], force_single_beat?: boolean)
---@field set_imm_release fun(self: CallableHDL)
---
---@field at fun(self: CallableHDL, index: integer): CallableHDL
---@field get_index fun(self: CallableHDL, index: integer, force_multi_beat?: boolean): integer|MultiBeatData
---@field get_index_all fun(self: CallableHDL, force_multi_beat?: boolean): integer|MultiBeatData
---@field get_index_bitvec fun(self: CallableHDL, index: integer): BitVec
---@field set_index fun(self: CallableHDL, index: integer, value: integer|uint64_t|MultiBeatData, force_single_beat?: boolean)
---@field set_index_bitfield fun(self: CallableHDL, index: integer, s: integer, e: integer, v: integer)
---@field set_index_bitfield_hex_str fun(self: CallableHDL, index: integer, s: integer, e: integer, hex_str: string)
---@field set_index_all fun(self: CallableHDL, values: table<integer|uint64_t|integer[]>, force_single_beat?: boolean)
---@field set_index_unsafe_all fun(self: CallableHDL, values: table<integer|uint64_t|integer[]>, force_single_beat?: boolean)
---@field set_imm_index fun(self: CallableHDL, index: integer, value: integer|uint64_t|integer[], force_single_beat?: boolean)
---@field set_imm_index_unsafe fun(self: CallableHDL, index: integer, value: integer|uint64_t|integer[], force_single_beat?: boolean)
---@field set_imm_index_bitfield fun(self: CallableHDL, index: integer, s: integer, e: integer, v: integer)
---@field set_imm_index_bitfield_hex_str fun(self: CallableHDL, index: integer, s: integer, e: integer, hex_str: string)
---@field set_imm_index_all fun(self: CallableHDL, values: table<integer|uint64_t|integer[]>, force_single_beat?: boolean)
---@field set_imm_index_unsafe_all fun(self: CallableHDL, values: table<integer|uint64_t|integer[]>, force_single_beat?: boolean)
---
---@field get_str fun(self: CallableHDL, fmt: integer): string
---@field get_hex_str fun(self: CallableHDL): string
---@field get_bin_str fun(self: CallableHDL): string
---@field get_dec_str fun(self: CallableHDL): string
---@field set_str fun(self: CallableHDL, str: string)
---@field set_hex_str fun(self: CallableHDL, str: string)
---@field set_bin_str fun(self: CallableHDL, str: string)
---@field set_dec_str fun(self: CallableHDL, str: string)
---@field set_freeze fun(self: CallableHDL)
---@field set_imm_str fun(self: CallableHDL, str: string)
---@field set_imm_hex_str fun(self: CallableHDL, str: string)
---@field set_imm_bin_str fun(self: CallableHDL, str: string)
---@field set_imm_dec_str fun(self: CallableHDL, str: string)
---@field set_imm_freeze fun(self: CallableHDL)
---
---@field set_shuffled fun(self: CallableHDL) Randomly set the value according to the shuffled range(if shuffled range is set) or bitwidth
---@field set_imm_shuffled fun(self: CallableHDL)
---@field shuffled_range_u32 fun(self: CallableHDL, u32_vec: table<integer, integer>)
---@field shuffled_range_u64 fun(self: CallableHDL, u64_vec: table<integer, integer|uint64_t>)
---@field shuffled_range_hex_str fun(self: CallableHDL, hex_str_vec: table<integer, string>)
---@field reset_shuffled_range fun(self: CallableHDL)
---
---@field get_index_str fun(self: CallableHDL, index: integer, fmt: integer): string
---@field get_index_hex_str fun(self: CallableHDL, index: integer): string
---@field set_index_str fun(self: CallableHDL, index: integer, str: string)
---@field set_index_hex_str fun(self: CallableHDL, index: integer, str: string)
---@field set_index_bin_str fun(self: CallableHDL, index: integer, str: string)
---@field set_index_dec_str fun(self: CallableHDL, index: integer, str: string)
---
---@field posedge fun(self: CallableHDL, cycles?: integer, action_func?: fun(count: integer))
---@field negedge fun(self: CallableHDL, cycles?: integer, action_func?: fun(count: integer))
---@field always_posedge fun(self: CallableHDL)
---@field posedge_until fun(self: CallableHDL, max_limit: integer, func: fun(count: integer): boolean): boolean
---@field negedge_until fun(self: CallableHDL, max_limit: integer, func: fun(count: integer): boolean): boolean
---
---@field dump_str fun(self: CallableHDL): string
---@field dump fun(self: CallableHDL)
---@field get_width fun(self: CallableHDL): integer
---@field expect fun(self: CallableHDL, value: integer|ffi.cdata*)
---@field expect_not fun(self: CallableHDL, value: integer|ffi.cdata*)
---@field expect_hex_str fun(self: CallableHDL, hex_value_str: string)
---@field expect_bin_str fun(self: CallableHDL, bin_value_str: string)
---@field expect_dec_str fun(self: CallableHDL, dec_value_str: string)
---@field expect_not_hex_str fun(self: CallableHDL, hex_value_str: string)
---@field expect_not_bin_str fun(self: CallableHDL, bin_value_str: string)
---@field expect_not_dec_str fun(self: CallableHDL, dec_value_str: string)
---@field is fun(self: CallableHDL, value: integer|ffi.cdata*): boolean
---@field is_not fun(self: CallableHDL, value: integer|ffi.cdata*): boolean
---@field is_hex_str fun(self: CallableHDL, hex_value_str: string): boolean
---@field is_bin_str fun(self: CallableHDL, bin_value_str: string): boolean
---@field is_dec_str fun(self: CallableHDL, dec_value_str: string): boolean
---@field _if fun(self: CallableHDL, condition_func: fun(): boolean): CallableHDL
---
---@field private __vpi_get function
---@field private __dpi_get function
---@field private __dpi_get64 function
---@field private __dpi_get_vec function
---@field private __vpi_get_hex_str function
---@field private __dpi_get_hex_str function
---@field private hex_buffer ffi.cdata*
local CallableHDL = class(post_init_mt)

function CallableHDL:_init(fullpath, name, hdl)
    texpect.expect_string(fullpath, "fullpath")

    self.__type = "CallableHDL"
    self.fullpath = fullpath
    self.name = name or "Unknown"
    self.always_fired = false -- used by <chdl>:always_posedge()

    local tmp_hdl = hdl or vpiml.vpiml_handle_by_name_safe(fullpath)
    if tmp_hdl == -1 then
        local err = f(
            "[CallableHDL:_init] No handle found! fullpath: %s name: %s\t\n%s\n",
            fullpath,
            self.name == "" and "Unknown" or self.name,
            debug.traceback()
        )
        verilua_debug(err)
        assert(false, err)
    end
    self.hdl = tmp_hdl
    self.hdl_type = ffi_string(vpiml.vpiml_get_hdl_type(self.hdl))

    self.is_array = false
    self.array_size = 0
    if self.hdl_type == "vpiReg" or self.hdl_type == "vpiNet" or self.hdl_type == "vpiLogicVar" or self.hdl_type == "vpiBitVar" then
        self.is_array = false
    elseif self.hdl_type == "vpiRegArray" or self.hdl_type == "vpiArrayVar" or self.hdl_type == "vpiNetArray" or self.hdl_type == "vpiMemory" then
        --
        -- for multidimensional reg array, VCS vpi treat it as "vpiRegArray" while
        -- Verilator treat it as "vpiMemory"
        --
        self.is_array = true
        self.array_size = tonumber(vpiml.vpiml_get_signal_width(self.hdl)) --[[@as integer]]
        self.array_hdls = table_new(self.array_size, 0)
        self.array_bitvecs = table_new(self.array_size, 0)
        for i = 1, self.array_size do
            self.array_hdls[i] = vpiml.vpiml_handle_by_index(self.hdl, i - 1)
        end

        self.hdl = self.array_hdls[1] -- Point to the first hdl
    else
        assert(false, f("Unknown hdl_type => %s fullpath => %s name => %s", self.hdl_type, self.fullpath, self.name))
    end

    self.width = tonumber(vpiml.vpiml_get_signal_width(self.hdl)) --[[@as integer]]
    self.beat_num = math.ceil(self.width / BeatWidth)
    self.is_multi_beat = not (self.beat_num == 1)
    self.cached_value = nil
    self.reset_set_cached = function(this)
        this.cached_value = nil
    end

    self.c_results = ffi_new("uint32_t[?]", self.beat_num + 1) -- create a new array to store the result
    -- c_results[0] is the lenght of the beat data since a normal lua table use 1 as the first index of array while ffi cdata still use 0

    verilua_debug(
        "New CallableHDL => ",
        "name: " .. self.name,
        "fullpath: " .. self.fullpath,
        "width: " .. self.width,
        "beat_num: " .. self.beat_num,
        "is_multi_beat: " .. tostring(self.is_multi_beat)
    )

    if self.beat_num == 1 then
        for k, func in pairs(require("verilua.handles.ChdlAccessSingle")(self.is_array)) do
            self[k] = func
        end
    elseif self.beat_num == 2 then
        for k, func in pairs(require("verilua.handles.ChdlAccessDouble")(self.is_array)) do
            self[k] = func
        end
    else
        for k, func in pairs(require("verilua.handles.ChdlAccessMulti")(self.is_array)) do
            self[k] = func
        end
    end

    --
    -- #define vpiBinStrVal          1
    -- #define vpiOctStrVal          2
    -- #define vpiDecStrVal          3
    -- #define vpiHexStrVal          4
    --
    self.get_str = function(this, fmt)
        return ffi_string(vpiml.vpiml_get_value_str(this.hdl, fmt))
    end

    self.get_hex_str = function(this)
        return ffi_string(vpiml.vpiml_get_value_hex_str(this.hdl))
    end

    self.get_bin_str = function(this)
        return ffi_string(vpiml.vpiml_get_value_bin_str(this.hdl))
    end

    self.get_dec_str = function(this)
        return ffi_string(vpiml.vpiml_get_value_dec_str(this.hdl))
    end

    self.set_str = function(this, str)
        vpiml.vpiml_set_value_str(this.hdl, str)
    end

    self.set_hex_str = function(this, str)
        vpiml.vpiml_set_value_hex_str(this.hdl, str)
    end

    self.set_bin_str = function(this, str)
        vpiml.vpiml_set_value_bin_str(this.hdl, str)
    end

    self.set_dec_str = function(this, str)
        vpiml.vpiml_set_value_dec_str(this.hdl, str)
    end

    self.set_shuffled = function(this)
        vpiml.vpiml_set_shuffled(this.hdl)
    end

    self.set_freeze = function(this)
        vpiml.vpiml_set_freeze(this.hdl)
    end

    self.set_imm_str = function(this, str)
        vpiml.vpiml_set_imm_value_str(this.hdl, str)
    end

    self.set_imm_hex_str = function(this, str)
        vpiml.vpiml_set_imm_value_hex_str(this.hdl, str)
    end

    self.set_imm_bin_str = function(this, str)
        vpiml.vpiml_set_imm_value_bin_str(this.hdl, str)
    end

    self.set_imm_dec_str = function(this, str)
        vpiml.vpiml_set_imm_value_dec_str(this.hdl, str)
    end

    self.set_imm_shuffled = function(this)
        vpiml.vpiml_set_imm_shuffled(this.hdl)
    end

    self.set_imm_freeze = function(this)
        vpiml.vpiml_set_imm_freeze(this.hdl)
    end

    self.shuffled_range_u32 = function(this, u32_vec)
        assert(type(u32_vec) == "table", "`u32_vec` must be a table")

        local v_type = type(u32_vec[1])
        assert(v_type == "number", "`u32_vec` must be a table of `number` type")

        local u32_vec_len = #u32_vec
        local u32_vec_cdata = ffi_new("uint32_t[?]", u32_vec_len) --[[@as table<integer, integer>]]
        for i = 1, u32_vec_len do
            u32_vec_cdata[i - 1] = u32_vec[i]
        end
        vpiml.vpiml_shuffled_range_u32(this.hdl, u32_vec_cdata --[[@as table<integer, ffi.cdata*>]], u32_vec_len)
    end

    self.shuffled_range_u64 = function(this, u64_vec)
        assert(type(u64_vec) == "table", "`u64_vec` must be a table")

        local v_type = type(u64_vec[1])
        assert(v_type == "number" or v_type == "cdata", "`u64_vec` must be a table of `number` or `cdata` type")

        local u64_vec_len = #u64_vec
        local u64_vec_cdata = ffi_new("uint64_t[?]", u64_vec_len) --[[@as table<integer, integer>]]
        for i = 1, u64_vec_len do
            u64_vec_cdata[i - 1] = u64_vec[i] --[[@as integer]]
        end
        vpiml.vpiml_shuffled_range_u64(this.hdl, u64_vec_cdata --[[@as table<integer, ffi.cdata*>]], u64_vec_len)
    end

    self.shuffled_range_hex_str = function(this, hex_str_vec)
        assert(type(hex_str_vec) == "table", "`hex_str_vec` must be a table")
        assert(type(hex_str_vec[1]) == "string", "`hex_str_vec` must be a table of `string` type")

        local hex_str_vec_len = #hex_str_vec
        local hex_str_vec_cdata = ffi_new("const char *[" .. hex_str_vec_len .. "]", hex_str_vec)
        ---@cast hex_str_vec_cdata ffi.cdata*[][]
        vpiml.vpiml_shuffled_range_hex_str(this.hdl, hex_str_vec_cdata, hex_str_vec_len)
    end

    self.reset_shuffled_range = function(this)
        vpiml.vpiml_reset_shuffled_range(this.hdl)
    end

    if self.is_array then
        self.get_index_str = function(this, index, fmt)
            local chosen_hdl = this.array_hdls[index + 1]
            return ffi_string(vpiml.vpiml_get_value_str(chosen_hdl, fmt))
        end

        self.get_index_hex_str = function(this, index)
            local chosen_hdl = this.array_hdls[index + 1]
            return ffi_string(vpiml.vpiml_get_value_hex_str(chosen_hdl))
        end

        self.set_index_str = function(this, index, str)
            local chosen_hdl = this.array_hdls[index + 1]
            vpiml.vpiml_set_value_str(chosen_hdl, str)
        end

        self.set_index_hex_str = function(this, index, str)
            local chosen_hdl = this.array_hdls[index + 1]
            vpiml.vpiml_set_value_hex_str(chosen_hdl, str)
        end

        self.set_index_bin_str = function(this, index, str)
            local chosen_hdl = this.array_hdls[index + 1]
            vpiml.vpiml_set_value_bin_str(chosen_hdl, str)
        end

        self.set_index_dec_str = function(this, index, str)
            local chosen_hdl = this.array_hdls[index + 1]
            vpiml.vpiml_set_value_dec_str(chosen_hdl, str)
        end
    end

    if not DpiExporter and cfg.enable_dpi_exporter then
        DpiExporter = require "DpiExporter"
    end

    -- Check if DPI exporter is enabled
    -- Notice: Call `DpiExporter:init()` before creating any `CallableHDL` if you want to access the signal by dpi_exporter API.
    if cfg.enable_dpi_exporter then
        ---@cast DpiExporter DpiExporter
        local is_exported = DpiExporter:is_exported(self.fullpath)
        if is_exported then
            verilua_debug(f("[CallableHDL] %s is exported by dpi_exporter!", self.fullpath))

            -- Assign new `get`
            if self.width <= 32 then
                self.__vpi_get = self.get
                self.__dpi_get = DpiExporter:fetch_get_value_func(self.fullpath)
                self.get = function(this)
                    return this.__dpi_get()
                end
            else
                self.__vpi_get = self.get
                self.__dpi_get = DpiExporter:fetch_get_value_func(self.fullpath)
                self.__dpi_get64 = DpiExporter:fetch_get64_value_func(self.fullpath)
                self.__dpi_get_vec = DpiExporter:fetch_get_vec_value_func(self.fullpath)
                if self.width <= 64 then
                    self.get = function(this, force_multi_beat)
                        if force_multi_beat then
                            this.__dpi_get_vec(this.c_results)
                            return this.c_results --[[@as MultiBeatData]]
                        else
                            return this.__dpi_get64()
                        end
                    end
                else
                    self.get = function(this)
                        this.__dpi_get_vec(this.c_results)
                        return this.c_results --[[@as MultiBeatData]]
                    end
                end

                self.get64 = function(this)
                    return this.__dpi_get64()
                end
            end

            -- TODO: has some problem with PLDM
            -- Assign new `get_hex_str`
            -- self.__vpi_get_hex_str = self.get_hex_str
            -- self.__dpi_get_hex_str = DpiExporter:fetch_get_hex_str_value_func(self.fullpath)
            -- self.hex_buffer = ffi.new("char[?]", utils.cover_with_n(self.width, 4))
            -- self.get_hex_str = function (this)
            --     this.__dpi_get_hex_str(this.hex_buffer)
            --     return ffi_string(this.hex_buffer)
            -- end
        end
    end

    if self.width == 1 then
        --
        -- Example:
        --      local clock = ("tb_top.clock"):chdl()
        --      clock:posedge()
        --
        --      local clock = CallableHDL("tb_top.clock", "name of clock chdl")
        --      clock:posedge()
        --
        --      clock:posedge(10)
        --      clock:posedge(123, function (c)
        --          -- body
        --          print("current is => " .. c)
        --       end)
        --
        self.posedge = function(this, times, func)
            local _times = times or 1
            if _times == 1 then
                await_posedge_hdl(this.hdl)
            else
                local has_func = func ~= nil
                for i = 1, _times do
                    if has_func then
                        func(i)
                    end
                    await_posedge_hdl(this.hdl)
                end
            end
        end

        --
        -- Example: the same as posedge
        --
        self.negedge = function(this, times, func)
            local _times = times or 1
            if _times == 1 then
                await_negedge_hdl(this.hdl)
            else
                local has_func = func ~= nil
                for i = 1, _times do
                    if has_func then
                        func(i)
                    end
                    await_negedge_hdl(this.hdl)
                end
            end
        end

        --
        -- Example:
        --      local clock = ("tb_top.clock"):chdl()
        --      clodk:always_posedge()
        --
        self.always_posedge = function(this)
            if this.always_fired == false then
                this.always_fired = true
                always_await_posedge_hdl(this.hdl)
            else
                await_noop()
            end
        end

        --
        -- Example:
        --      local clock_chdl = ("tb_top.clock"):chdl()
        --          |_  or  local clock_chdl = dut.clock:chdl()
        --      local condition_meet = clock_chdl:posedge_until(100, function func()
        --          return dut.cycles() >= 100
        --      end)
        --
        self.posedge_until = function(this, max_limit, func)
            assert(max_limit ~= nil)
            assert(type(max_limit) == "number")
            assert(max_limit >= 1)

            assert(func ~= nil)
            assert(type(func) == "function")

            local condition_meet = false
            for i = 1, max_limit do
                condition_meet = func(i)
                assert(condition_meet ~= nil and type(condition_meet) == "boolean")

                if not condition_meet then
                    await_posedge_hdl(this.hdl)
                else
                    break
                end
            end

            return condition_meet
        end

        self.negedge_until = function(this, max_limit, func)
            assert(max_limit ~= nil)
            assert(type(max_limit) == "number")
            assert(max_limit >= 1)

            assert(func ~= nil)
            assert(type(func) == "function")

            local condition_meet = false
            for i = 1, max_limit do
                condition_meet = func(i)
                assert(condition_meet ~= nil and type(condition_meet) == "boolean")

                if not condition_meet then
                    await_negedge_hdl(this.hdl)
                else
                    break
                end
            end

            return condition_meet
        end
    else
        self.posedge = function(this, times)
            assert(false, f("hdl bit width == %d > 1, <chdl>:posedge() only support 1-bit hdl", this.width))
        end

        self.negedge = function(this, times)
            assert(false, f("hdl bit width == %d > 1, <chdl>:negedge() only support 1-bit hdl", this.width))
        end

        self.always_posedge = function(this)
            assert(false, f("hdl bit width == %d > 1, <chdl>:always_posedge() only support 1-bit hdl", this.width))
        end

        self.posedge_until = function(this, max_limit, func)
            ---@diagnostic disable-next-line: missing-return
            assert(false, f("hdl bit width == %d > 1, <chdl>:posedge_until() only support 1-bit hdl", this.width))
            ---@diagnostic disable-next-line: missing-return
        end

        self.negedge_until = function(this, max_limit, func)
            ---@diagnostic disable-next-line: missing-return
            assert(false, f("hdl bit width == %d > 1, <chdl>:negedge_until() only support 1-bit hdl", this.width))
            ---@diagnostic disable-next-line: missing-return
        end
    end

    if self.is_array then
        self.dump_str = function(this)
            local s = f("[%s] => ", this.fullpath)

            for i = 1, this.array_size do
                s = s .. f("(%d): 0x%s ", i - 1, this:get_index_str(i - 1, HexStr))
            end

            return s
        end
    else
        self.dump_str = function(this)
            return f("[%s] => 0x%s", this.fullpath, this:get_hex_str())
        end
    end

    self.dump = function(this)
        print(this:dump_str())
    end

    self.get_width = function(this)
        return this.width
    end

    self.expect = function(this, value)
        local typ = type(value)
        assert(typ == "number" or typ == "cdata")

        if this.is_multi_beat and this.beat_num > 2 then
            assert(
                false,
                "`<CallableHDL>:expect(value)` can only be used for hdl with 1 or 2 beat, use `<CallableHDL>:expect_[hex/bin/dec]_str(value_str)` instead! beat_num => " ..
                this.beat_num
            )
        end

        if this:get() ~= value then
            assert(false, f("[%s] expect => %d, but got => %d", this.fullpath, value, this:get()))
        end
    end

    self.expect_not = function(this, value)
        local typ = type(value)
        assert(typ == "number" or typ == "cdata")

        if this.is_multi_beat and this.beat_num > 2 then
            assert(
                false,
                "`<CallableHDL>:expect_not(value)` can only be used for hdl with 1 or 2 beat, use `<CallableHDL>:expect_not_[hex/bin/dec]_str(value_str)` instead! beat_num => " ..
                this.beat_num
            )
        end

        if this:get() == value then
            assert(false, f("[%s] expect not => %d, but got => %d", this.fullpath, value, this:get()))
        end
    end

    self.expect_hex_str = function(this, hex_value_str)
        assert(type(hex_value_str) == "string")
        if this:get_hex_str():lower():gsub("^0*", "") ~= hex_value_str:lower():gsub("^0*", "") then
            assert(false, f("[%s] expect => %s, but got => %s", this.fullpath, hex_value_str, this:get_str(HexStr)))
        end
    end

    self.expect_bin_str = function(this, bin_value_str)
        assert(type(bin_value_str) == "string")
        ---@diagnostic disable-next-line: missing-parameter
        if this:get_str(BinStr):gsub("^0*", "") ~= bin_value_str:gsub("^0*") then
            assert(false, f("[%s] expect => %s, but got => %s", this.fullpath, bin_value_str, this:get_str(BinStr)))
        end
    end

    self.expect_dec_str = function(this, dec_value_str)
        assert(type(dec_value_str) == "string")
        if this:get_str(DecStr):gsub("^0*", "") ~= dec_value_str:gsub("^0*", "") then
            assert(false, f("[%s] expect => %s, but got => %s", this.fullpath, dec_value_str, this:get_str(DecStr)))
        end
    end

    self.expect_not_hex_str = function(this, hex_value_str)
        assert(type(hex_value_str) == "string")
        if this:get_hex_str():lower():gsub("^0*", "") == hex_value_str:lower():gsub("^0*", "") then
            assert(false, f("[%s] expect not => %s, but got => %s", this.fullpath, hex_value_str, this:get_str(HexStr)))
        end
    end

    self.expect_not_bin_str = function(this, bin_value_str)
        assert(type(bin_value_str) == "string")
        ---@diagnostic disable-next-line: missing-parameter
        if this:get_str(BinStr):gsub("^0*", "") == bin_value_str:gsub("^0*") then
            assert(false, f("[%s] expect not => %s, but got => %s", this.fullpath, bin_value_str, this:get_str(BinStr)))
        end
    end

    self.expect_not_dec_str = function(this, dec_value_str)
        assert(type(dec_value_str) == "string")
        if this:get_str(DecStr):gsub("^0*", "") == dec_value_str:gsub("^0*", "") then
            assert(false, f("[%s] expect not => %s, but got => %s", this.fullpath, dec_value_str, this:get_str(DecStr)))
        end
    end

    self._if = function(this, condition)
        local _condition = false
        if type(condition) == "boolean" then
            _condition = condition
        elseif type(condition) == "function" then
            _condition = condition()

            local _condition_type = type(_condition)
            if _condition_type ~= "boolean" then
                assert(false, "invalid condition function return type: " .. _condition_type)
            end
        else
            assert(false, "invalid condition type: " .. type(condition))
        end

        if _condition then
            return this
        else
            return setmetatable({}, {
                __index = function(t, k)
                    return function()
                        -- an empty function
                    end
                end
            })
        end
    end

    if self.is_multi_beat and self.beat_num > 2 then
        self.is = function(this, value)
            ---@diagnostic disable-next-line: missing-return
            assert(false, "<CallableHDL>:is(value) can only be used for hdl with 1 or 2 beat")
            ---@diagnostic disable-next-line: missing-return
        end

        self.is_not = function(this, value)
            ---@diagnostic disable-next-line: missing-return
            assert(false, "<CallableHDL>:is_not(value) can only be used for hdl with 1 or 2 beat")
            ---@diagnostic disable-next-line: missing-return
        end
    else
        self.is = function(this, value)
            local typ = type(value)
            assert(typ == "number" or typ == "cdata")
            return this:get() == value
        end

        self.is_not = function(this, value)
            local typ = type(value)
            assert(typ == "number" or typ == "cdata")
            return this:get() ~= value
        end
    end

    self.is_hex_str = function(this, hex_value_str)
        assert(type(hex_value_str) == "string")
        return this:get_hex_str():lower():gsub("^0*", "") == hex_value_str:lower():gsub("^0*", "")
    end

    self.is_bin_str = function(this, bin_value_str)
        assert(type(bin_value_str) == "string")
        return this:get_str(BinStr):gsub("^0*", "") == bin_value_str:gsub("^0*", "")
    end

    self.is_dec_str = function(this, dec_value_str)
        assert(type(dec_value_str) == "string")
        return this:get_str(DecStr):gsub("^0*", "") == dec_value_str:gsub("^0*", "")
    end
end

function CallableHDL:__call(force_multi_beat)
    --
    -- This method is deprecated, invoke <CallableHDL>:get() to get the signal value
    --
    assert(self.is_array == false, "For multidimensional array use <CallableHDL>:get_index()")

    force_multi_beat = force_multi_beat or false

    if self.is_multi_beat then
        if self.beat_num <= 2 and not force_multi_beat then
            return tonumber(vpiml.vpiml_get_value64(self.hdl))
        else
            vpiml.vpiml_get_value_multi(self.hdl, self.c_results, self.beat_num)
            return self.c_results
        end
    else
        return vpiml.vpiml_get_value(self.hdl)
    end
end

--
-- Handles assignment to CallableHDL objects. If key is "value".
-- Processes based on value type:
--      - number
--      - string(with prefix)
--      - table(u32_vec)
--      - cdata (uint64_t or uint32_t[])
--      - boolean
-- Auto-type-based value assignment.
--
-- Example:
--      <chdl>.value = 123
--      <chdl>.value = 0x123
--      <chdl>.value = 0x112233ULL
--      <chdl>.value = "0x123"
--      <chdl>.value = "0b01011"
--      <chdl>.value = "123"
--      <chdl>.value = {0x123, 0x456}
--      <chdl>.value = true
--      <chdl>.value = false
--
function CallableHDL:__newindex(k, v)
    if k == "value" then
        assert(not self.is_array, "TODO: not implemented for array type <chdl>")

        local v_type = type(v)

        if v_type == "number" then
            self:set_unsafe(v, true)
        elseif v_type == "string" then
            self:set_str(v)
        elseif v_type == "table" then
            if v.__type and v.__type == "BitVec" then
                self:set_hex_str(v:to_hex_str())
            else
                if self.beat_num == 1 then
                    self:set_unsafe(v[1], true)
                else
                    self:set(v)
                end
            end
        elseif v_type == "cdata" then
            if ffi.istype("uint64_t", v) then
                self:set_unsafe(v, true)
            elseif ffi.istype("uint32_t[]", v) then
                if self.beat_num == 1 then
                    self:set_unsafe(v[1], true)
                else
                    self:set_unsafe(v)
                end
            else
                assert(false, "[CallableHDL.__newindex] invalid value type: " .. v_type)
            end
        elseif v_type == "boolean" then
            if v then
                self:set_unsafe(1, true)
            else
                self:set_unsafe(0, true)
            end
        else
            assert(false, "[CallableHDL.__newindex] invalid value type: " .. v_type)
        end
    elseif k == "value_imm" then
        assert(not self.is_array, "TODO: not implemented for array type <chdl>")

        local v_type = type(v)

        if v_type == "number" then
            self:set_imm_unsafe(v, true)
        elseif v_type == "string" then
            self:set_imm_str(v)
        elseif v_type == "table" then
            if v.__type and v.__type == "BitVec" then
                self:set_imm_hex_str(v:to_hex_str())
            else
                if self.beat_num == 1 then
                    self:set_imm_unsafe(v[1], true)
                else
                    self:set(v)
                end
            end
        elseif v_type == "cdata" then
            if ffi.istype("uint64_t", v) then
                self:set_imm_unsafe(v, true)
            elseif ffi.istype("uint32_t[]", v) then
                if self.beat_num == 1 then
                    self:set_imm_unsafe(v[1], true)
                else
                    self:set_imm_unsafe(v)
                end
            else
                assert(false, "[CallableHDL.__newindex] invalid value type: " .. v_type)
            end
        elseif v_type == "boolean" then
            if v then
                self:set_imm_unsafe(1, true)
            else
                self:set_imm_unsafe(0, true)
            end
        else
            assert(false, "[CallableHDL.__newindex] invalid value type: " .. v_type)
        end
    else
        rawset(self, k, v)
    end
end

--
-- Auto-type-based value comparison.
--
-- Example:
--      Note: the compared value MUST be enclosed in a special function named `v`, otherwise it will not be treated as a `__eq` overload.
--      assert(<chdl> == v(123))
--      assert(<chdl> == v("0x123"))
--      assert(<chdl> == v(123ULL))
--      assert(<chdl> == v({0x123, 0})
--      assert(<chdl> == v(true))
--      assert(<chdl> == v(BitVec(123)))
--      assert(<chdl> == v(BitVec("123")))
--
function CallableHDL:__eq_impl(other)
    local v_type = type(other.__value)
    local value = other.__value

    if v_type == "number" then
        return self:is_hex_str(bit_tohex(value))
    elseif v_type == "string" then
        local prefix = value:sub(1, 2)
        if prefix == "0x" then
            return self:is_hex_str(value:sub(3))
        elseif prefix == "0b" then
            return self:is_bin_str(value:sub(3))
        else
            return self:is_dec_str(value)
        end
    elseif v_type == "table" then
        if value.__type and value.__type == "BitVec" then
            return self:is_hex_str(value:to_hex_str())
        else
            local result = self:get(true) -- force_multi_beat = true
            if self.beat_num == 1 then
                if #value == 1 then
                    return result == value[1]
                else
                    if result ~= value[1] then
                        return false
                    else
                        for i = 2, #value do
                            if value[i] ~= 0 then
                                return false
                            end
                        end
                    end
                end
            else
                for i = 1, self.beat_num do
                    if value[i] then
                        if value[i] ~= result[i] then
                            return false
                        end
                    else
                        if result[i] ~= 0 then
                            return false
                        end
                    end
                end

                if self.beat_num < #value then
                    for i = self.beat_num + 1, #value do
                        if value[i] ~= 0 then
                            return false
                        end
                    end
                end
            end

            return true
        end
    elseif v_type == "cdata" then
        if ffi.istype("uint64_t", value) then
            return self:is_hex_str(bit_tohex(value))
        elseif ffi.istype("uint32_t[]", value) then
            local result = self:get(true) -- force_multi_beat = true
            if self.beat_num == 1 then
                if value[0] == 1 then
                    return result == value[1]
                else
                    if result ~= value[1] then
                        return false
                    else
                        for i = 2, value[0] do
                            if value[i] ~= 0 then
                                return false
                            end
                        end
                    end
                end
            else
                for i = 1, self.beat_num do
                    if value[i] then
                        if value[i] ~= result[i] then
                            return false
                        end
                    else
                        if result[i] ~= 0 then
                            return false
                        end
                    end
                end

                if self.beat_num < value[0] then
                    for i = self.beat_num + 1, #value do
                        if value[i] ~= 0 then
                            return false
                        end
                    end
                end
            end

            return true
        else
            assert(false, "[CallableHDL.__eq] invalid value type: " .. v_type)
        end
    elseif v_type == "boolean" then
        if value then
            return self:is_hex_str("1")
        else
            return self:is_hex_str("0")
        end
    else
        assert(false, "[CallableHDL.__eq] invalid value type: " .. v_type)
    end
end

function CallableHDL:__eq(other)
    assert(not self.is_array, "TODO: not implemented for array type <chdl>")

    local result = self:__eq_impl(other)
    if (not result) and other.__verbose then
        local value_str
        if type(other.__value) == "boolean" then
            value_str = other.__value and "1" or "0"
        elseif type(other.__value) == "string" then
            value_str = other.__value
        else
            value_str = utils.to_hex_str(other.__value)
        end

        local err_str = f("[%s] expect => %s, but got => %s", self.fullpath, value_str, self:get_hex_str())
        if other.__stop_on_fail then
            assert(false, err_str)
        else
            print(err_str)
        end
    end

    return result
end

function CallableHDL:__len()
    return self.width
end

function CallableHDL:__tostring()
    if self.is_array then
        return f(
            "<[CallableHDL] fullpath: %s, width: %d, beat_num: %d, array_size: %d>",
            self.fullpath,
            self.width,
            self.beat_num,
            self.array_size
        )
    else
        return f(
            "<[CallableHDL] fullpath: %s, width: %d, beat_num: %d>",
            self.fullpath,
            self.width,
            self.beat_num
        )
    end
end

--
-- These methods are used with `__eq`.
--      `v`: a special wrapper function for the value being compared since the `__eq` only allow to compare two metatables with each other.
--      `vv`: verbose(print error message when the compared value mismatch)
--      `vs`: verbose and stop on fail
--
_G.v = function(value)
    -- return setmetatable({__value = value, __verbose = false}, _G.cfg.__chdl_mt)

    __chdl_mt.__value = value
    __chdl_mt.__verbose = false
    __chdl_mt.__stop_on_fail = false
    return __chdl_mt
end

_G.vv = function(value)
    __chdl_mt.__value = value
    __chdl_mt.__verbose = true
    __chdl_mt.__stop_on_fail = false
    return __chdl_mt
end

_G.vs = function(value)
    __chdl_mt.__value = value
    __chdl_mt.__verbose = true
    __chdl_mt.__stop_on_fail = true
    return __chdl_mt
end

return CallableHDL
