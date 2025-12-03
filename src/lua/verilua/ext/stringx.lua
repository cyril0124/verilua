---@diagnostic disable: unnecessary-assert

--------------------------------------------------------------------------------
--- String Literal Constructor Pattern (SLCP)
--------------------------------------------------------------------------------
---
--- SLCP is a design pattern in Verilua that extends the Lua string library,
--- allowing users to construct various Verilua data structures directly from
--- string literals without explicitly requiring the corresponding modules.
---
--- This pattern leverages the fact that all strings in Lua share the same
--- metatable. By adding methods to the string table, all string literals
--- can call these methods.
---
--- ## Supported Constructors
---
--- | Method           | Return Type       | Description                    |
--- |------------------|-------------------|--------------------------------|
--- | `:chdl()`        | CallableHDL       | Signal handle constructor      |
--- | `:hdl()`         | ComplexHandleRaw  | Low-level VPI handle           |
--- | `:bdl{...}`      | Bundle            | Signal bundle constructor      |
--- | `:abdl{...}`     | AliasBundle       | Aliased bundle constructor     |
--- | `:ehdl()`        | EventHandle       | Event handle constructor       |
--- | `:bv()`          | BitVec            | Bit vector constructor         |
--- | `:auto_bundle{}` | Bundle            | Auto bundle constructor        |
--- | `:fake_chdl{}`   | CallableHDL       | Virtual signal constructor     |
---
--- ## Usage Examples
---
--- ```lua
--- -- Traditional way
--- local CallableHDL = require "LuaCallableHDL"
--- local chdl = CallableHDL("signal", "tb_top.clock")
---
--- -- SLCP way
--- local chdl = ("tb_top.clock"):chdl()
---
--- -- Bundle construction
--- local bdl = ("valid | ready | data"):bdl { hier = "tb_top.dut" }
---
--- -- BitVec construction
--- local bv = ("deadbeef"):bv(128)
--- ```
---
--- ## Implementation Principle
---
--- All strings in Lua share the same metatable, whose __index points to the
--- string table. Therefore, any function added to the string table can be
--- called by all string literals.
---
--- ```lua
--- -- This is why "hello":upper() works
--- string.upper = function(s) ... end
---
--- -- SLCP works the same way
--- string.chdl = function(hierpath, hdl) ... end
--- ```
---
--- For more details about SLCP, see: docs/reference/slcp.md
--------------------------------------------------------------------------------

local f = string.format
local vpiml = require "vpiml"
local stringx = require "pl.stringx"
local utils = require "verilua.LuaUtils"
local BitVec = require "verilua.utils.BitVec"
local Bundle = require "verilua.handles.LuaBundle"
local CallableHDL = require "verilua.handles.LuaCallableHDL"
local AliasBundle = require "verilua.handles.LuaAliasBundle"
local scheduler = require "verilua.scheduler.LuaScheduler"

---@class (exact) string.abdl.params
---@field hier string
---@field prefix string
---@field name string
---@field [string] string|number

---@class (exact) string.bdl.params
---@field hier string Hierachy path of the bundle, e.g. `tb_top.u_top.path.to.module`
---@field prefix? string Default is `""`
---@field is_decoupled? boolean Default is `true`
---@field name? string
---@field optional_signals? table<integer, string>

---@class (exact) string.tcc_compile.sym_ptr_tbl
---@field sym string
---@field ptr string

---@class string.fake_chdl.overload_func_tbl
---@field get? fun(self: verilua.handles.CallableHDL, force_multi_beat?: boolean): number|verilua.handles.MultiBeatData
---@field get64? fun(self: verilua.handles.CallableHDL): uint64_t
---@field set? fun(self: verilua.handles.CallableHDL, value: number|uint64_t|table<number>, force_single_beat?: boolean)
---@field set_force? fun(self: verilua.handles.CallableHDL, value: number|uint64_t|table<number>, force_single_beat?: boolean)
---@field set_imm? fun(self: verilua.handles.CallableHDL, value: number|uint64_t|table<number>, force_single_beat?: boolean)
---@field get_hex_str? fun(self: verilua.handles.CallableHDL): string
---@field is? fun(self: verilua.handles.CallableHDL, value: number|ffi.cdata*): boolean
---@field is_not? fun(self: verilua.handles.CallableHDL, value: number|ffi.cdata*): boolean

---@class string.ext
---
---@field render fun(template: string, vars: table): string
---@field strip fun(str: string, suffix: string): string
---@field join fun(str: string, list: table): string
---@field number fun(str: string): integer
---@field contains fun(str: string, target: string): boolean
---@field tcc_compile fun(str: string, sym_ptr_tbls: string.tcc_compile.sym_ptr_tbl[]): table<any, any>
---@field bv fun(init_hex_str: string, bitwidth?: integer): verilua.utils.BitVec
---@field bit_vec fun(init_hex_str: string, bitwidth?: integer): verilua.utils.BitVec
---
---@field hdl fun(hierpath: string): verilua.handles.ComplexHandleRaw
---@field hdl_safe fun(hierpath: string): verilua.handles.ComplexHandleRaw
---@field chdl fun(hierpath: string, hdl?: verilua.handles.ComplexHandleRaw): verilua.handles.CallableHDL
---@field fake_chdl fun(hierpath: string, overload_func_tbl: string.fake_chdl.overload_func_tbl): verilua.handles.CallableHDL
---@field bundle fun(str: string, params: string.bdl.params): verilua.handles.Bundle
---@field bdl fun(str: string, params: string.bdl.params): verilua.handles.Bundle
---@field abdl fun(str: string, params_table: string.bdl.params): verilua.handles.AliasBundle
---@field ehdl fun(this: string, event_id_integer?: integer): verilua.handles.EventHandle
---@field auto_bundle fun(str: string, params: verilua.utils.SignalDB.auto_bundle.params): verilua.handles.Bundle

---@class string: string.ext Compatible with EmmyluaLS
---@class stringlib: string.ext


--- Render a template string with variables.
--- The template syntax is `{{key}}`, where `key` is a key in the `vars` table.
--- If a key is not found in the `vars` table, an assertion error is raised.
--- The value of the key is converted to a string using `tostring.
--- e.g.
--- ```lua
---      local template = "Hello {{name}}!"
---      local rendered_template = template:render({name = "Bob"})
---      assert(rendered_template == "Hello Bob!")
--- ```
string.render = function(template, vars)
    assert(type(template) == "string", "[render] template must be a `string`")
    assert(type(vars) == "table", "[render] vars must be a `table`")
    return (template:gsub("{{(.-)}}", function(key)
        if vars[key] == nil then
            assert(false, f("[render] key not found: %s\n\ttemplate_str is: %s\n", key, template))
        end
        return tostring(vars[key] or "")
    end))
end

--- Strip the given suffix from the end of the string if it exists.
--- If the string does not end with the suffix, return the original string.
--- e.g.
--- ```lua
---      local str = "hello_world"
---      local stripped = str:strip("_world")
---      assert(stripped == "hello")
---      local not_stripped = str:strip("_moon")
---      assert(not_stripped == "hello_world")
--- ```
string.strip = function(str, suffix)
    assert(type(suffix) == "string", "suffix must be a string")
    if str:sub(- #suffix) == suffix then
        return str:sub(1, - #suffix - 1)
    else
        return str
    end
end

--- Join a list of strings with a separator.
--- e.g.
--- ```lua
---      local list = {"a", "b", "c"}
---      local joined = (","):join(list)
---      assert(joined == "a,b,c")
--- ```
string.join = function(str, list)
    return stringx.join(str, list)
end

--- Convert a string to a number, supporting binary (0b prefix) and hexadecimal (0x prefix) formats.
--- If the string does not have a prefix, it is treated as a decimal number.
--- e.g.
--- ```lua
---      assert(("0b1010"):number() == 10)
---      assert(("0x1A"):number() == 26)
---      assert(("42"):number() == 42)
--- ```
string.number = function(str)
    if str:sub(1, 2) == "0b" then
        -- binary transform
        return tonumber(str:sub(3), 2) --[[@as integer]]
    elseif str:sub(1, 2) == "0x" then
        -- hex transform
        return tonumber(str:sub(3), 16) --[[@as integer]]
    else
        return tonumber(str) --[[@as integer]]
    end
end

--- Check if the string contains the target substring.
--- e.g.
--- ```lua
---      assert(("hello world"):contains("world") == true)
---      assert(("hello world"):contains("moon") == false)
--- ```
string.contains = function(str, target)
    local startIdx, _ = str:find(target)
    if startIdx then
        return true
    else
        return false
    end
end

---@generic T
---@param str string
---@param enum_table table<string, T>
---@return table<string, T>
--- Define an enumeration with a name and a table of key-value pairs.
--- The `enum_table` must be a table where keys are strings and values are of the same type.
--- The function adds a `name` field to the `enum_table` with the value of `str`.
--- e.g.
--- ```lua
---      local Color = ("Color"):enum_define { Red = 1, Green = 2, Blue = 3 }
---      assert(Color == "Color")
---      assert(Color.Red == 1)
---      assert(Color.Green == 2)
---      assert(Color.Blue == 3)
---      assert(Color(1) == "Red")
--- ```
string.enum_define = function(str, enum_table)
    assert(type(enum_table) == "table")
    enum_table.name = str
    return utils.enum_define(enum_table)
end

--- Convert a string to a `BitVec` object.
--- The string should be a hexadecimal representation (without the `0x` prefix).
--- An optional `bitwidth` can be provided to specify the width of the bit vector.
--- If `bitwidth` is not provided, it defaults to the minimum width required to represent
--- the hexadecimal value.
--- e.g.
--- ```lua
---    local bv = ("dead"):bv(32)
---    assert(bv:get_bitfield(0, 31) == 0xdead)
---    assert(bv:get_bitfield_hex_str(0, 31) == "0000dead")
---
---    local bv2 = ("beef"):bv()
---    assert(bv2:get_bitfield(0, 31) == 0xbeef)
---    assert(bv2:get_bitfield_hex_str(0, 31) == "0000beef")
--- ```
string.bv = function(init_hex_str, bitwidth)
    return BitVec(init_hex_str, bitwidth)
end
string.bit_vec = string.bv -- Alias of `string.bv`

--- Compile a C code string using Tiny C Compiler (TCC) and return a table of function pointers.
--- The C code can include special comments to specify which symbols to extract and their corresponding function pointer types.
--- The special comment format is `// $sym<SymbolName> $ptr<SymbolPtrPattern>`.
--- Alternatively, a table of symbol and pointer type pairs can be provided as the second argument.
--- The function returns a table where keys are symbol names and values are function pointers cast to the specified types.
--- e.g.
--- ```lua
---    local lib = ([[
---        #include "stdio.h"
---
---        int count = 0;
---
---        // $sym<hello> $ptr<void (*)(void)>
---        void hello() {
---            printf("hello %d\n", count);
---            count++;
---        }
---
---        // $sym<get_count> $ptr<int (*)(void)>
---        int get_count() {
---            return count;
---        }
---    ]]):tcc_compile()
---
--- ----- OR -------
---
---    local lib = ([[
---        #include "stdio.h"
---
---        int count = 0;
---
---        void hello() {
---            printf("hello %d\n", count);
---            count++;
---        }
---
---        int get_count() {
---            return count;
---        }
---    ]]):tcc_compile({ {sym = "hello", ptr = "void (*)(void)"}, {sym = "get_count", ptr = "int (*)(void)"} })
---
---     lib.hello()
---     assert(lib.get_count() == 1)
--- ```
string.tcc_compile = function(str, sym_ptr_tbls)
    local tcc = require "TccWrapper"
    local state = tcc.new()
    assert(state:set_output_type(tcc.OUTPUT.MEMORY))
    assert(state:compile_string(str))
    assert(state:relocate(tcc.RELOCATE.AUTO))

    local verilua_debug = _G.verilua_debug

    local count = 0
    local lib = { _state = state } -- keep `state` alive to prevent GC

    for line in string.gmatch(str, "[^\r\n]+") do
        local symbol_name = line:match("%$sym<%s*([^>]+)%s*>")
        local symbol_ptr_pattern = line:match("%$ptr%s*<%s*([^>]+)%s*>")
        if symbol_name or symbol_ptr_pattern then
            count = count + 1
            verilua_debug("[tcc_compile] [" .. count .. "] find symbol_name => \"" .. (symbol_name or "nil") .. "\"")
            verilua_debug("[tcc_compile] [" ..
                count .. "] find symbol_ptr_pattern = \"" .. (symbol_ptr_pattern or "nil") .. "\"")
            local sym = assert(state:get_symbol(symbol_name))
            lib[symbol_name] = ffi.cast(symbol_ptr_pattern --[[@as ffi.ct*]], sym)
        end
    end

    if sym_ptr_tbls ~= nil then
        assert(type(sym_ptr_tbls) == "table")
        assert(type(sym_ptr_tbls[1]) == "table")
        for _, sym_ptr_tbl in ipairs(sym_ptr_tbls) do
            local symbol_name = assert(sym_ptr_tbl.sym)
            local symbol_ptr_pattern = assert(sym_ptr_tbl.ptr)
            count = count + 1
            verilua_debug("[tcc_compile] [" ..
                count .. "] [sym_ptr_tbls] find symbol_name => \"" .. (symbol_name or "nil") .. "\"")
            verilua_debug("[tcc_compile] [" ..
                count .. "] [sym_ptr_tbls] find symbol_ptr_pattern = \"" .. (symbol_ptr_pattern or "nil") .. "\"")
            local sym = assert(state:get_symbol(symbol_name))
            lib[symbol_name] = ffi.cast(symbol_ptr_pattern, sym)
        end
    end

    assert(count > 0,
        f(
            "\n[tcc_compile] Did not find any symbols! Please specify symbol_name or symbol_ptr_pattern in tcc code by a custom C comment: \"// $sym<SymbolName> $ptr<SymbolPtrPattern>\"! Or you could specify this info by the input table \"<string>:tcc_compile({{sym = <symbol_name>, ptr = <symbol_ptr_pattern>}, <other...>})\"\nThe tcc code is:\n%s",
            str))

    return lib
end


--- Get the `ComplexHandleRaw` of a signal by its hierarchical path.
--- If the handle is not found, an assertion error is raised.
--- e.g.
--- ```lua
---      local hdl = ("top.module.signal"):hdl()
--- ```
string.hdl = function(str)
    ---@diagnostic disable-next-line: need-check-nil
    local hdl = vpiml.vpiml_handle_by_name_safe(str)

    if hdl == -1 then
        assert(false, f("[hdl] no handle found => %s", str))
    end

    return hdl
end

--- Get the `ComplexHandleRaw` of a signal by its hierarchical path.
--- If the handle is not found, return -1.
--- e.g.
--- ```lua
---      local hdl = ("top.module.signal"):hdl_safe()
--- ```
string.hdl_safe = function(str)
    ---@diagnostic disable-next-line: need-check-nil
    local hdl = vpiml.vpiml_handle_by_name_safe(str)
    return hdl
end

--- Get the `CallableHDL` of a signal by its hierarchical path.
--- An optional `ComplexHandleRaw` can be provided to avoid redundant lookups.
--- If the handle is not found, an assertion error is raised.
--- e.g.
--- ```lua
---      local chdl = ("top.module.signal"):chdl()
---      -- or with a pre-obtained handle
---      local hdl = ("top.module.signal"):hdl()
---      local chdl = ("top.module.signal"):chdl(hdl)
--- ```
string.chdl = function(hierpath, hdl)
    return CallableHDL(hierpath, "", hdl)
end

--- Create a fake `CallableHDL` with user-defined overloaded functions.
--- This is useful when some of the signal does not exist in the design and
--- you still want to use the same signal interface to access it.
--- e.g.
--- ```lua
---      local fake_signal = string.fake_chdl("top.module.fake_signal", {
---          get = function(self)
---              return 42
---          end,
---          set = function(self, value)
---              print("Setting fake_signal to", value)
---          end,
---      })
---      assert(fake_signal:get() == 42)
---      fake_signal:set(100)  -- prints "Setting fake_signal to 100"
--- ```
--- Note: Accessing any method or property not defined in `overload_func_tbl` will
--- raise an assertion error.
string.fake_chdl = function(hierpath, overload_func_tbl)
    ---@type verilua.handles.CallableHDL
    ---@diagnostic disable-next-line: missing-fields
    local chdl = {
        __type = "CallableHDL",
        name = "fake_chdl__" .. hierpath,
        fullpath = hierpath,
    }

    for k, v in pairs(overload_func_tbl) do
        chdl[k] = v
    end

    setmetatable(chdl, {
        __index = function(_self, key)
            assert(false, f("[fake_chdl] Cannot access key: %s, key no found!", key))
        end,
    })

    return chdl
end

---@generic T
---@param org_tbl table<integer|string, T>
---@return table<integer, T>
local function to_normal_table(org_tbl)
    local ret = {}
    for _key, value in pairs(org_tbl) do
        table.insert(ret, value)
    end
    return ret
end

--- Create a `Bundle` from a string of signal names separated by `|`.
--- The `params_table` must contain the following fields:
--- - `hier` (string, mandatory): The hierarchical path of the bundle.
--- - `prefix` (string, optional): A prefix to add to each signal name in the bundle.
--- - `is_decoupled` (boolean, optional, default=true): Whether the bundle follows the decoupled interface convention.
--- - `name` (string, optional, default="Unknown"): A name for the bundle.
--- - `optional_signals` (table of strings, optional): A list of optional signal names that may or may not be present in the bundle.
--- e.g.
--- ```lua
---      local bdl = ("field1|field2|field3"):bundle {hier = "tb_top"} -- hier is the only one mandatory params to be passed into this constructor
---      local bdl = ("valid | ready | opcode | data"):bundle {hier = "tb_top", is_decoupled = true}
---      local bdl = ("| valid | ready | opcode | data"): bundle {hier = "tb_top"}
---      local bdl = ("| valid | ready | opcode | data |"): bundle {hier = "tb_top"}
---      local strange_bdl = ([[
---          field1 |
---          field2     |
---          field3
---      ]]):bundle {hier = "tb_top", name = "strange hdl name"}
---      local beautiful_bdl = ([[
---          field1  |
---          field2  |
---          field3  |
---          field4
---      ]]):bundle {hier = "tb_top", prefix = "p_"}
---      local beautiful_bdl_1 = ([[
---          | field1 |
---          | field2 |
---          | field3 |
---      ]]):bundle {hier = "tb_top", prefix = "p_"}
---
---      local bdl_str = ("|"):join {"valid", "ready", "address", "opcode", "param", "source", "data"} -- bdl_str ==> "valid|ready|address|opcode|param|source|data"
---      local bdl = bdl_str:bundle {hier = cfg.top .. ".u_TestTop_fullSys_1Core.l2", is_decoupled = true, name = "Channel A", prefix = "auto_in_a_"}
--- ```
---@param str string
---@param params_table string.bdl.params
---@return verilua.handles.Bundle
local process_bundle = function(str, params_table)
    local signals_table = stringx.split(str, "|")
    local will_remove_idx = {}

    for i = 1, #signals_table do
        -- remove trivial characters
        signals_table[i] = stringx.replace(signals_table[i], " ", "")
        signals_table[i] = stringx.replace(signals_table[i], "\n", "")
        signals_table[i] = stringx.replace(signals_table[i], "\t", "")

        if signals_table[i] == "" then
            -- not a valid signal
            table.insert(will_remove_idx, i)
        end
    end

    -- remove invalid signal
    for _, value in ipairs(will_remove_idx) do
        signals_table[value] = nil
    end

    assert(type(params_table) == "table")

    -- turn into simple lua table
    local _signals_table = to_normal_table(signals_table)

    local hier = params_table.hier
    local hier_type = type(hier)

    assert(hier ~= nil, "[bundle] hierachy is not set! please set by `hier` field ")
    assert(hier_type == "string", "[bundle] invalid hierarchy type => " .. hier_type)

    local prefix = ""
    local is_decoupled = true
    local name = "Unknown"
    local optional_signals = nil
    for key, value in pairs(params_table) do
        if key == "prefix" then
            assert(type(value) == "string")
            prefix = value
        elseif key == "is_decoupled" then
            assert(type(value) == "boolean")
            is_decoupled = value
        elseif key == "name" then
            assert(type(value) == "string")
            name = value
        elseif key == "optional_signals" then
            assert(type(value) == "table")
            if #value > 0 then
                assert(type(value[1]) == "string")
            end
            optional_signals = value
        elseif key == "hier" then
            -- pass
        else
            assert(false,
                "[bundle] unkonwn key => " ..
                tostring(key) ..
                " value => " ..
                tostring(value) .. ", available keys: `prefix`, `is_decoupled`, `name`, `optional_signals`, `hier`")
        end
    end

    return Bundle(_signals_table, prefix, hier, name, is_decoupled, optional_signals)
end
string.bundle = process_bundle
string.bdl = process_bundle

--- Create an `AliasBundle` from a string of signal alias definitions separated by `|`.
--- Each signal alias definition can be in the form of `origin_signal_name => alias_name` or just `origin_signal_name`.
--- The `params_table` must contain the following fields:
--- - `hier` (string, mandatory): The hierarchical path of the bundle.
--- - `prefix` (string, optional): A prefix to add to each origin signal name in the bundle.
--- - `name` (string, optional, default="Unknown"): A name for the alias bundle.
--- - Additional fields can be used for string interpolation in the signal names,
---   where `{key}` in the signal name will be replaced by the value of `params_table[key]`.
--- e.g.
--- ```lua
---      local abdl = ([[
---          | origin_signal_name => alias_name
---          | origin_signal_name_1 => alias_name_1
---      ]]):abdl {hier = "path.to.hier", perfix = "some_prefix_", name = "name of alias bundle"}
---      local value = abdl.alias_name:get()    -- real signal is <path.to.hier.some_prefix_origin_signal_name>
---      abdl.alias_name_1:set(123)
---
---      -- Multiple alias name, seperate by `/`
---      local abdl = ([[
---          | origin_signal_name => alias_name/alias_name_1/alias_name_2
---      ]]):abdl {hier = "path.to.hier", perfix = "some_prefix_", name = "name of alias bundle"}
---      local value = abdl.alias_name:get()     -- real signal is <path.to.hier.some_prefix_origin_signal_name>
---      local value_1 = abdl.alias_name_1:get() -- using another alias name to access the same signal
---      assert(value == value_1)
---
---      abdl.alias_name_1:set(123)
---      local abdl = ([[
---          | origin_signal_name
---          | origin_signal_name_1 => alias_name_1
---      ]]):abdl {hier = "top", prefix = "prefix"}
---      local value = abdl.origin_signal_name:get()
---      abdl.alias_name_1:set(123)
---
---      local abdl = ([[
---          | {p}_value => val_{b}
---          | {b}_opcode => opcode
---      ]]):abdl {hier ="hier", prefix = "prefix_", p = "hello", b = 123}
---      local value = abdl.val_123:get()     -- real signal is <hier.prefix_hello_value>
--- ```
string.abdl = function(str, params_table)
    ---@cast str string

    local signals_table = stringx.split(str, "|")
    local will_remove_idx = {}

    for i = 1, #signals_table do
        -- remove trivial characters
        signals_table[i] = stringx.replace(signals_table[i], " ", "")
        signals_table[i] = stringx.replace(signals_table[i], "\n", "")
        signals_table[i] = stringx.replace(signals_table[i], "\t", "")

        if signals_table[i] == "" then
            -- not a valid signal
            table.insert(will_remove_idx, i)
        end
    end

    -- remove invalid signal
    for _, value in ipairs(will_remove_idx) do
        signals_table[value] = nil
    end

    assert(type(params_table) == "table")

    -- turn into simple lua table
    local _signals_table = to_normal_table(signals_table)

    -- replace some string literal with other <value>
    local pattern = "{[^%{%}%(%)]*}"
    for i = 1, #_signals_table do
        local matchs = string.gmatch(_signals_table[i], pattern)
        for match in matchs do
            local repl_key = string.gsub(string.gsub(match, "{", ""), "}", "")
            local repl_value = params_table[repl_key]
            local repl_value_str = tostring(repl_value)
            assert(repl_value ~= nil, f("[abdl] replace key: <%s> not found in <params_table>!", repl_key))

            _signals_table[i] = string.gsub(_signals_table[i], match, repl_value_str)
        end
    end

    local alias_tbl = {}
    for i = 1, #_signals_table do
        local alias_name_vec = stringx.split(_signals_table[i], "=>")
        assert(type(alias_name_vec[1]) == "string")

        if alias_name_vec[2] ~= nil then
            assert(#alias_name_vec == 2)
            assert(type(alias_name_vec[2]) == "string")

            local maybe_multiple_alias_name_vec = stringx.split(alias_name_vec[2], "/")
            local n = #maybe_multiple_alias_name_vec
            assert(n >= 1)

            local final_alias_name_vec = { alias_name_vec[1] }
            for _, v in ipairs(maybe_multiple_alias_name_vec) do
                table.insert(final_alias_name_vec, v)
            end
            table.insert(alias_tbl, final_alias_name_vec)
        else
            assert(#alias_name_vec == 1)
            table.insert(alias_tbl, { alias_name_vec[1] })
        end
    end

    local hier = params_table.hier
    local hier_type = type(hier)

    assert(hier ~= nil, "[abdl] hierachy is not set! please set by `hier` field ")
    assert(hier_type == "string", "[abdl] invalid hierarchy type => " .. hier_type)

    local prefix = ""
    local name = "Unknown"
    local optional_signals = nil
    for key, value in pairs(params_table) do
        if key == "prefix" then
            assert(type(value) == "string", "[abdl] invalid type for the `prefix` field, valid type: `string`")
            prefix = value
        elseif key == "name" then
            assert(type(value) == "string", "[abdl] invalid type for the `name` field, valid type: `string`")
            name = value
        elseif key == "optional_signals" then
            assert(type(value) == "table")
            if #value > 0 then
                assert(type(value[1]) == "string")
            end
            optional_signals = value
        end
    end

    return AliasBundle(alias_tbl, prefix, hier, name, optional_signals)
end

--- Create an event handle from a string identifier.
--- An optional integer event ID can be provided to distinguish between multiple events with the same name.
--- e.g.
--- ```lua
---      local ehdl = ("my_event"):ehdl() -- event_id will be randomly allocated
---      local ehdl_with_id = ("my_event"):ehdl(1)
--- ```
string.ehdl = function(this, event_id_integer)
    return scheduler:get_event_hdl(this, event_id_integer)
end

--- Automatically create a `Bundle` by filtering signals in the design based on specified criteria.
--- The `params` table can contain the following fields:
--- - `startswith` (string, optional): Only include signals that start with this prefix.
--- - `endswith` (string, optional): Only include signals that end with this suffix
--- - `matches` (string, optional): A Lua pattern to match signal names.
--- - `wildmatch` (string, optional): A wildcard pattern (using `*`) to match signal names.
--- - `filter` (function, optional): A custom filter function that takes a signal name and width as arguments and returns a boolean.
--- - `prefix` (string, optional): A prefix to add to each signal name in the bundle.
--- The `params` table must contain at least one of the filtering criteria (`startswith`, `endswith`, `matches`, `wildmatch`, or `filter`).
--- e.g.
--- ```lua
---      local bdl = ("tb_top.path.to.mod"):auto_bundle { startswith = "io_in_", endswith = "_value" }
---      local bdl = ("tb_top.path.to.mod"):auto_bundle { startswith = "io_in_" }
---      local bdl = ("tb_top.path.to.mod"):auto_bundle { endswith = "_value" }
---      local bdl = ("tb_top.path.to.mod"):auto_bundle { matches = "^io_" }
---      local bdl = ("tb_top.path.to.mod"):auto_bundle { wildmatch = "*_value_*" }
---      local bdl = ("tb_top.path.to.mod"):auto_bundle { filter = function (name, width)
---          return width == 32 and name:endswith("_value")
---      end }
--- ```
---
--- Priority:
---      filter > matches > wildmatch > startswith > prefix > endswith
--- Available combinations:
---      - matches + filter
---      - wildmatch + filter
---      - wildmatch + filter + prefix
---      - startswith + endswith
---      - startswith + endswith + filter
---      - prefix + filter
---      - startswith + filter
---      - endswith + filter
string.auto_bundle = function(str, params)
    return require("SignalDB"):auto_bundle(str, params)
end
