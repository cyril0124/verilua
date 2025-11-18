local vpiml = require "vpiml"
local tablex = require "pl.tablex"
local class = require "pl.class"
local texpect = require "TypeExpect"
local table_new = require "table.new"
local table_clear = require "table.clear"
local CallableHDL = require "verilua.handles.LuaCallableHDL"

local type = type
local rawset = rawset
local assert = assert
local f = string.format
local table_insert = table.insert
local table_concat = table.concat

local verilua_debug = _G.verilua_debug

---@class (exact) verilua.handles.AliasBundle.alias_signal_pair
---@field [1] string
---@field [2] string
---@field [integer] string other alias name

---@class (exact) verilua.handles.AliasBundle
---@overload fun(alias_signal_tbl: verilua.handles.AliasBundle.alias_signal_pair[], prefix: string, hierarchy: string, name: string, optional_signals?: table<string>): verilua.handles.AliasBundle
---@field __type string
---@field prefix string
---@field hierarchy string
---@field name string
---@field signals_tbl table<integer, string>
---@field alias_tbl table<integer, table<integer, string>>
---@field __dump_parts table<integer, string>
---@field valid verilua.handles.CallableHDL
---@field ready verilua.handles.CallableHDL
---@field dump_str fun(self: verilua.handles.AliasBundle): string
---@field format_dump_str fun(self: verilua.handles.AliasBundle, format_func: fun(chdl: verilua.handles.CallableHDL, name: string, alias_name: string): string): string
---@field dump fun(self: verilua.handles.AliasBundle)
---@field format_dump fun(self: verilua.handles.AliasBundle, format_func: fun(chdl: verilua.handles.CallableHDL, name: string, alias_name: string): string)
---@field [string] verilua.handles.CallableHDL
local AliasBundle = class()

--
-- Access signal using alias name
--
-- @alias_signal_tbl: {
--      {<org_name>, <alias_name_0>, <alias_name_1>, ...}, -- alias_name can be set as `nil`, then no alias name available for signal accessing
--      ...
-- }
--
-- @prefix   :
-- @hierarchy :
--      signal_name => <hierarchy>.<prefix>_<org_name>
-- @name: bundle name
--
--
-- Example:
--      local abdl = AliasBundle(
--          {
--              {"origin_signal_name",   "alias_name"  },
--              {"origin_signal_name_1"  "alias_name_1"},
--          },
--          "some_prefix",
--          "path.to.hier",
--          "name of alias bundle"
--      )
--
--      local value = abdl.alias_name:get()
--      abdl.alias_name_1:set(123)
--
---@param alias_signal_tbl verilua.handles.AliasBundle.alias_signal_pair[]
---@param prefix string
---@param hierarchy string
---@param name string
---@param optional_signals? table<string>
function AliasBundle:_init(alias_signal_tbl, prefix, hierarchy, name, optional_signals)
    texpect.expect_table(alias_signal_tbl, "alias_signal_tbl")
    texpect.expect_table(alias_signal_tbl[1] --[[@as table]], "alias_signal_tbl[1]")
    texpect.expect_string(prefix, "prefix")
    texpect.expect_string(hierarchy, "hierarchy")

    self.__type = "AliasBundle"
    self.prefix = prefix
    self.hierarchy = hierarchy
    self.name = name or "Unknown"

    self.signals_tbl = table_new(#alias_signal_tbl, 0) --[[@as table<integer, string>]]
    for _, x in ipairs(alias_signal_tbl) do
        assert(x[1] ~= nil)
        assert(type(x[1]) == "string")

        table_insert(self.signals_tbl, x[1])
    end

    if optional_signals then
        texpect.expect_table(optional_signals, "optional_signals")
    end
    ---@cast optional_signals table
    optional_signals = optional_signals or {} -- optional signals are allowed to be empty

    self.alias_tbl = table_new(#alias_signal_tbl, 0) --[[@as table<integer, table<integer, string>>]]
    for i, alias_name_vec in ipairs(alias_signal_tbl) do
        local nr_alias_name = #alias_name_vec

        if not self.alias_tbl[i] then
            self.alias_tbl[i] = {} --[[@as table<integer, string>]]
        end

        if nr_alias_name == 1 then
            table_insert(self.alias_tbl[i], alias_name_vec[1])
        end

        for j = 2, nr_alias_name do
            table_insert(self.alias_tbl[i], alias_name_vec[j])
        end
    end

    verilua_debug(
        "New AliasBundle => ",
        "name: " .. self.name,
        "signals: {" .. table_concat(self.signals_tbl, ", ") .. "}",
        "prefix: " .. prefix,
        "hierarchy: ",
        hierarchy
    )

    -- Construct CallableHDL bundle
    local num_signals = #self.signals_tbl
    for i = 1, num_signals do
        local alias_name_vec = self.alias_tbl[i]
        local real_name = self.signals_tbl[i]
        local fullpath = hierarchy .. "." .. prefix .. real_name

        ---@type verilua.handles.CallableHDL
        local chdl
        for _, alias_name in ipairs(alias_name_vec) do
            if not tablex.find(optional_signals, alias_name) then
                if not chdl then
                    chdl = CallableHDL(fullpath, real_name, nil)
                end
                rawset(self, alias_name, chdl)
            else
                ---@diagnostic disable-next-line: need-check-nil
                local hdl = vpiml.vpiml_handle_by_name_safe(fullpath)
                if hdl ~= -1 then
                    if not chdl then
                        chdl = CallableHDL(fullpath, real_name, nil)
                    end
                    -- optional are allowed to be empty
                    rawset(self, alias_name, chdl)
                end
            end
        end
    end

    -- Used for saving dump parts
    self.__dump_parts = table_new(num_signals, 0) --[[@as table<integer, string>]]

    self.dump_str = function(this)
        local parts = this.__dump_parts
        table_clear(parts)

        if this.name ~= "Unknown" then
            table_insert(parts, f("[%s]", this.name))
        end

        if this.valid ~= nil then
            table_insert(parts, "valid: " .. this.valid:get())
        end

        if this.ready ~= nil then
            table_insert(parts, "ready: " .. this.ready:get())
        end

        for i = 1, #self.signals_tbl do
            local alias_name_vec = self.alias_tbl[i]
            local alias_name_1 = alias_name_vec[1]
            local real_name = self.signals_tbl[i]
            if real_name ~= "valid" and real_name ~= "ready" then
                table_insert(parts, f("%s -> %s: 0x%s",
                    real_name,
                    table_concat(alias_name_vec, "/"),
                    this[alias_name_1]:get_hex_str()
                ))
            end
        end

        return table_concat(parts, " | ")
    end

    self.format_dump_str = function(this, format_func)
        local parts = this.__dump_parts
        table_clear(parts)

        if this.name ~= "Unknown" then
            table_insert(parts, f("[%s]", this.name))
        end

        if this.valid ~= nil then
            table_insert(parts, format_func(this.valid, "valid", "valid") or ("valid: " .. this.valid:get()))
        end

        if this.ready ~= nil then
            table_insert(parts, format_func(this.ready, "ready", "ready") or ("ready: " .. this.ready:get()))
        end

        for i = 1, #self.signals_tbl do
            local alias_name_vec = self.alias_tbl[i]
            local alias_name_1 = alias_name_vec[1]
            local real_name = self.signals_tbl[i]
            if real_name ~= "valid" and real_name ~= "ready" then
                table_insert(parts, format_func(this[alias_name_1], real_name, alias_name_1) or f("%s -> %s: 0x%s",
                    real_name,
                    table_concat(alias_name_vec, "/"),
                    this[alias_name_1]:get_hex_str()
                ))
            end
        end

        return table_concat(parts, " | ")
    end

    self.dump = function(this)
        print(this:dump_str())
    end

    ---@param format_func fun(chdl, name: string, alias_name: string): string
    self.format_dump = function(this, format_func)
        print(this:format_dump_str(format_func))
    end
end

return AliasBundle
