---@meta meta.lua
--- This file is used to provide some common type annotations used in Verilua.
--- It will be loaded automatically by Lua Language Server(LuaLS/EmmyLuaLs).

--- ComplexHandleRaw is a low-level handle to represent a hardware signal in libverilua.
--- It is an integer value representing the address of the internal Rust object in libverilua.
---@class ComplexHandleRaw: integer

---@class uint32_t: ffi.cdata*
---@class uint64_t: ffi.cdata*

---@class TaskName: string

--- Task function used in `fork`, `jfork`, `initial`, `final`.
--- It should be a function without parameters and return value.
---@alias TaskFunction fun()

_G.GLOBAL_VERILUA_ENV = {} --[[@as lightuserdata]]

---@param time integer
function await_time(time) end

---@param signal_str string
function await_posedge(signal_str) end

---@param signal_hdl ComplexHandleRaw
function await_posedge_hdl(signal_hdl) end

---@param signal_hdl ComplexHandleRaw
function always_await_posedge_hdl(signal_hdl) end

---@param signal_str string
function await_negedge(signal_str) end

---@param signal_hdl ComplexHandleRaw
function await_negedge_hdl(signal_hdl) end

---@param signal_str string
function await_edge(signal_str) end

---@param signal_hdl ComplexHandleRaw
function await_edge_hdl(signal_hdl) end

---@param event_id_integer integer
function await_event(event_id_integer) end

function await_noop() end

function await_step() end

function exit_task() end
