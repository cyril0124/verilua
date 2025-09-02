local ffi = require "ffi"

---@class (exact) verilua.utils.duckdb.params
---@field path string? Path to the library, e.g. /usr/lib/lib?.so
---@field name string? Name of the library, e.g. duckdb

---@class (exact) verilua.utils.duckdb.const
---@field OK 0
---@field ERROR 1

---@class verilua.utils.duckdb.clib

---@class verilua.utils.duckdb.duckdb_config
---@field set fun(self: verilua.utils.duckdb.duckdb_config, key: string, value: string): verilua.utils.duckdb.const
---@field set_and_check fun(self: verilua.utils.duckdb.duckdb_config, key: string, value: string)
---@field destroy fun(self: verilua.utils.duckdb.duckdb_config)

---@class verilua.utils.duckdb.duckdb_database
---@field errmsg fun(self: verilua.utils.duckdb.duckdb_database): string
---@field close fun(self: verilua.utils.duckdb.duckdb_database): verilua.utils.duckdb.const
---@field new_conn fun(self: verilua.utils.duckdb.duckdb_database): verilua.utils.duckdb.const, verilua.utils.duckdb.duckdb_connection

---@class verilua.utils.duckdb.duckdb_connection
---@field exec fun(self: verilua.utils.duckdb.duckdb_connection, sql_str: string): verilua.utils.duckdb.const
---@field new_appender fun(self: verilua.utils.duckdb.duckdb_connection, table_name: string): verilua.utils.duckdb.const, verilua.utils.duckdb.duckdb_appender

---@class verilua.utils.duckdb.duckdb_appender
---@field append_int64 fun(self: verilua.utils.duckdb.duckdb_appender, value: integer): verilua.utils.duckdb.const
---@field append_uint64 fun(self: verilua.utils.duckdb.duckdb_appender, value: integer): verilua.utils.duckdb.const
---@field append_string fun(self: verilua.utils.duckdb.duckdb_appender, value: string): verilua.utils.duckdb.const
---@field appand_values fun(self: verilua.utils.duckdb.duckdb_appender, ...: any)
---@field end_row fun(self: verilua.utils.duckdb.duckdb_appender): verilua.utils.duckdb.const
---@field flush fun(self: verilua.utils.duckdb.duckdb_appender): verilua.utils.duckdb.const
---@field destroy fun(self: verilua.utils.duckdb.duckdb_appender): verilua.utils.duckdb.const

---@class verilua.utils.duckdb
---@field const verilua.utils.duckdb.const
---@field clib any
---@field private err_msg_ptr table<integer, ffi.cdata*>
---@field new_config fun(): verilua.utils.duckdb.const, verilua.utils.duckdb.duckdb_config
---@field open fun(filename: string, config: verilua.utils.duckdb.duckdb_config?): verilua.utils.duckdb.const, verilua.utils.duckdb.duckdb_database
---@overload fun(params: verilua.utils.duckdb.params): verilua.utils.duckdb
local duckdb = {
    const = {
        OK = 0,
        ERROR = 1
    },
    clib = nil,
    err_msg_ptr = ffi.new("char *[1]")
}
---@type any
local duckdb_clib

local function new_class()
    local class = {}
    class.__index = class
    return class
end

---@return string?
local function wrap_string(c_str)
    if c_str ~= nil then
        return ffi.string(c_str)
    end
    return nil
end

function duckdb.new_config()
    assert(duckdb_clib ~= nil, "duckdb not initialized!")
    local config_ptr = ffi.new("duckdb_config[1]") --[[@as table<integer, ffi.cdata*>]]
    local ret_state = duckdb_clib.duckdb_create_config(config_ptr)
    local config_handle = ffi.cast("duckdb_config_handle*", config_ptr[0]) --[[@as verilua.utils.duckdb.duckdb_config]]
    return ret_state, config_handle
end

function duckdb.open(filename, config)
    assert(duckdb_clib ~= nil, "duckdb not initialized!")
    local db_ptr = ffi.new("duckdb_database[1]") --[[@as table<integer, ffi.cdata*>]]
    local ret_state = duckdb_clib.duckdb_open_ext(filename, db_ptr, config, duckdb.err_msg_ptr)
    local db_handle = ffi.cast("duckdb_database_handle*", db_ptr[0]) --[[@as verilua.utils.duckdb.duckdb_database]]
    return ret_state, db_handle
end

---@param self verilua.utils.duckdb
---@param params verilua.utils.duckdb.params
function duckdb.__call(self, params)
    if self.clib then
        -- duckdb already initialized
        return self
    end

    if type(params) == "table" then
        if type(params.name) == "string" then
            if type(params.path) == "string" then
                local lib = package.searchpath(params.name, params.path)
                assert(
                    lib,
                    "[duckdb.lua] library not found, name: " ..
                    tostring(params.name) .. ", path: " .. tostring(params.path)
                )
                self.clib = ffi.load(package.searchpath(params.name, params.path))
            else
                self.clib = ffi.load(params.name)
            end
        else
            -- If no library or name is provided, we just
            -- assume that the appropriate duckdb libraries
            -- are statically linked to the calling program
            self.clib = ffi.C
        end
    else
        -- If no library or name is provided, we just
        -- assume that the appropriate duckdb libraries
        -- are statically linked to the calling program
        self.clib = ffi.C
    end

    duckdb_clib = self.clib

    ffi.cdef [[
        typedef enum {
            DuckDBSuccess = 0,
            DuckDBError = 1
        } duckdb_state;

        typedef long long int64_t;
        typedef unsigned long long uint64_t;
        typedef uint64_t idx_t;

        typedef struct {} duckdb_database_handle;
        typedef struct {} duckdb_config_handle;
        typedef struct {} duckdb_connection_handle;
        typedef struct {} duckdb_appender_handle;

        typedef void* duckdb_database;
        typedef void* duckdb_config;
        typedef void* duckdb_connection;
        typedef void* duckdb_appender;

        typedef struct {} duckdb_column;

        typedef struct {
            idx_t deprecated_column_count;
            idx_t deprecated_row_count;
            idx_t deprecated_rows_changed;
            duckdb_column *deprecated_columns;
            char *deprecated_error_message;
            void *internal_data;
        } duckdb_result;

        duckdb_state duckdb_create_config(duckdb_config *out_config);
        duckdb_state duckdb_set_config(duckdb_config config, const char *name, const char *option);
        void duckdb_destroy_config(duckdb_config *config);

        duckdb_state duckdb_open_ext(const char *path, duckdb_database *out_database, duckdb_config config, char **out_error);
        void duckdb_close(duckdb_database *database);

        duckdb_state duckdb_connect(duckdb_database database, duckdb_connection *out_connection);
        void duckdb_disconnect(duckdb_connection *connection);

        duckdb_state duckdb_query(duckdb_connection connection, const char *query, duckdb_result *out_result);
        void duckdb_destroy_result(duckdb_result *result);
        const char *duckdb_result_error(duckdb_result *result);

        duckdb_state duckdb_appender_create(duckdb_connection connection, const char *schema, const char *table, duckdb_appender *out_appender);
        duckdb_state duckdb_append_int64(duckdb_appender appender, int64_t value);
        duckdb_state duckdb_append_uint64(duckdb_appender appender, uint64_t value);
        duckdb_state duckdb_append_varchar(duckdb_appender appender, const char *val);
        duckdb_state duckdb_appender_end_row(duckdb_appender appender);
        duckdb_state duckdb_appender_flush(duckdb_appender appender);
        duckdb_state duckdb_appender_destroy(duckdb_appender *appender);

        void duckdb_free(void *ptr);
    ]]

    do
        local duckdb_config_mt = new_class()

        duckdb_config_mt.set = function(this, name, value)
            assert(type(name) == "string")
            assert(type(value) == "string")
            return duckdb_clib.duckdb_set_config(this, name, value)
        end

        duckdb_config_mt.set_and_check = function(this, name, value)
            if duckdb_clib.duckdb_set_config(this, name, value) ~= duckdb_clib.DuckDBSuccess then
                assert(false, "[duckdb] Failed to set config " .. name .. " to " .. value)
            end
        end

        duckdb_config_mt.destroy = function(this)
            local config_handle_for_c = ffi.cast("duckdb_config", this)
            local config_ptr = ffi.new("duckdb_config[1]", config_handle_for_c)
            duckdb_clib.duckdb_destroy_config(config_ptr)
        end

        duckdb_config_mt.__gc = duckdb_config_mt.destroy

        ffi.metatype("duckdb_config_handle", duckdb_config_mt)
    end

    do
        local duckdb_database_mt = new_class()

        duckdb_database_mt.errmsg = function(this)
            local err_msg = "<Empty>"
            if duckdb.err_msg_ptr[0] == nil then
                return err_msg
            end
            err_msg = wrap_string(duckdb.err_msg_ptr[0]) --[[@as string]]
            duckdb_clib.duckdb_free(duckdb.err_msg_ptr[0])
            return err_msg
        end

        duckdb_database_mt.close = function(this)
            local database_handle_for_c = ffi.cast("duckdb_database", this)
            local database_ptr = ffi.new("duckdb_database[1]", database_handle_for_c)
            duckdb_clib.duckdb_close(database_ptr)
        end

        duckdb_database_mt.new_conn = function(this)
            local con_ptr = ffi.new("duckdb_connection[1]") --[[@as table<integer, ffi.cdata*>]]
            local ret_state = duckdb_clib.duckdb_connect(this, con_ptr)
            return ret_state, ffi.cast("duckdb_connection_handle*", con_ptr[0])
        end

        duckdb_database_mt.__gc = function(this)
            local database_handle_for_c = ffi.cast("duckdb_database", this)
            local database_ptr = ffi.new("duckdb_database[1]", database_handle_for_c)
            duckdb_clib.duckdb_close(database_ptr)
        end

        ffi.metatype("duckdb_database_handle", duckdb_database_mt)
    end

    do
        local duckdb_connection_mt = new_class()

        duckdb_connection_mt.exec = function(this, sql_str)
            local result_ptr = ffi.new("duckdb_result[1]")
            local ret_state = duckdb_clib.duckdb_query(this, sql_str, result_ptr)
            local err_msg = wrap_string(duckdb_clib.duckdb_result_error(result_ptr))
            return ret_state, err_msg
        end

        duckdb_connection_mt.new_appender = function(this, table_name)
            local appender_ptr = ffi.new("duckdb_appender[1]") --[[@as table<integer, ffi.cdata*>]]
            local ret_state = duckdb_clib.duckdb_appender_create(this, nil, table_name, appender_ptr)
            return ret_state, ffi.cast("duckdb_appender_handle*", appender_ptr[0])
        end

        ffi.metatype("duckdb_connection_handle", duckdb_connection_mt)
    end

    do
        local duckdb_appender_mt = new_class()

        duckdb_appender_mt.append_int64 = function(this, value)
            return duckdb_clib.duckdb_append_int64(this, value)
        end

        duckdb_appender_mt.append_uint64 = function(this, value)
            return duckdb_clib.duckdb_append_uint64(this, value)
        end

        duckdb_appender_mt.append_string = function(this, value)
            return duckdb_clib.duckdb_append_varchar(this, value)
        end

        duckdb_appender_mt.end_row = function(this)
            return duckdb_clib.duckdb_appender_end_row(this)
        end

        duckdb_appender_mt.flush = function(this)
            return duckdb_clib.duckdb_appender_flush(this)
        end

        duckdb_appender_mt.append_values = function(this, ...)
            local n = select("#", ...)
            for i = 1, n do
                local v = select(i, ...)
                local t = type(v)
                if t == "number" then
                    duckdb_clib.duckdb_append_uint64(this, v)
                elseif t == "string" then
                    duckdb_clib.duckdb_append_varchar(this, v)
                else
                    assert(false, "[duckdb.append_values] Unsupported data type: " .. t)
                end
            end
        end

        duckdb_appender_mt.destroy = function(this)
            local appender_handle_for_c = ffi.cast("duckdb_appender", this)
            local appender_ptr = ffi.new("duckdb_appender[1]", appender_handle_for_c)
            return duckdb_clib.duckdb_appender_destroy(appender_ptr)
        end

        duckdb_appender_mt.__gc = duckdb_appender_mt.destroy

        ffi.metatype("duckdb_appender_handle", duckdb_appender_mt)
    end

    return self
end

setmetatable(duckdb, {
    __call = duckdb.__call
})

return duckdb
