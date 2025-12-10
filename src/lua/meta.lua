---@meta meta.lua
--- This file is used to provide some common type annotations used in Verilua.
--- It will be loaded automatically by Lua Language Server(LuaLS/EmmyLuaLs).

--- ComplexHandleRaw is a low-level handle to represent a hardware signal in libverilua.
--- It is an integer value representing the address of the internal Rust object in libverilua.
---@class verilua.handles.ComplexHandleRaw: integer

---@class uint32_t: ffi.cdata*
---@class uint64_t: ffi.cdata*

_G.GLOBAL_VERILUA_ENV = {} --[[@as lightuserdata]]

--- Set by the scheduler when there is an error while executing a task
_G.VERILUA_GOT_ERROR = false --[[@as boolean]]

--- Wait for a specified number of simulation time.
--- By default, the simulation time precision is 1ps(the default timescale is `1ns/1ps`),
--- so `await_time(100)` will wait for 100ps.
--- The `time` value depends on the simulation time precision. If your timescale config is `1ms/1ns`,
--- then `await_time(100)` will wait for 100ns, and `await_time(1000)` will wait for 1ms.
---@param time integer
function await_time(time) end

---@param signal_hdl verilua.handles.ComplexHandleRaw
function await_posedge_hdl(signal_hdl) end

---@param signal_hdl verilua.handles.ComplexHandleRaw
function always_await_posedge_hdl(signal_hdl) end

---@param signal_hdl verilua.handles.ComplexHandleRaw
function await_negedge_hdl(signal_hdl) end

---@param signal_hdl verilua.handles.ComplexHandleRaw
function await_edge_hdl(signal_hdl) end

---@param event_id_integer integer
function await_event(event_id_integer) end

function await_noop() end

function await_step() end

--- Exit the current task
function exit_task() end

--- Await cbReadWrite callback
function await_rw() end

--- Await cbReadOnly callback
function await_rd() end

--- Await cbNextSimTime callback
function await_nsim() end

---------------------------------------------------
--- Xmake related functions
---------------------------------------------------
---@alias verilua.xmake.toolchains
--- | "@verilator"
--- | "@iverilog"
--- | "@vcs"
--- | "@xcelium"
--- | "@wave_vpi"
--- | "@nosim"

---@alias verilua.xmake.set_values.yes_or_not
--- | "1"
--- | "0"

---@alias verilua.xmake.set_values.cmd
--- | "verilator.flags"
--- | "verilator.run_prefix"
--- | "verilator.run_flags"
--- | "vcs.flags"
--- | "vcs.run_prefix"
--- | "vcs.run_flags"
--- | "iverilog.flags"
--- | "iverilog.run_prefix"
--- | "iverilog.run_flags"
--- | "wave_vpi.flags"
--- | "wave_vpi.run_prefix"
--- | "wave_vpi.run_flags"
--- | "cfg.top" <Required>
--- | "cfg.lua_main" <Required>
--- | "cfg.tb_top"
--- | "cfg.version_required"
--- | "cfg.vcs_no_initreg"
--- | "cfg.not_gen_tb"
--- | "cfg.build_dir"
--- | "cfg.build_dir_path"
--- | "cfg.build_dir_name"
--- | "cfg.user_cfg"
--- | "cfg.tb_gen_flags"
--- | "cfg.tb_top_file"
--- | "cfg.no_internal_clock"
--- | "cfg.use_inertial_put"

---@param cmd verilua.xmake.set_values.cmd
---@param ... verilua.xmake.set_values.yes_or_not|string
function set_values(cmd, ...) end

---@param cmd verilua.xmake.add_values.cmd
---@param ... verilua.xmake.set_values.yes_or_not|string
function add_values() end

---@param toolchain verilua.xmake.toolchains
function add_toolchain(toolchain) end

---@param toolchain verilua.xmake.toolchains
function set_toolchain(toolchain) end

---@param rule "verilua"
function add_rules(rule) end
