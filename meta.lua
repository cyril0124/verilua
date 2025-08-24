---@meta

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
