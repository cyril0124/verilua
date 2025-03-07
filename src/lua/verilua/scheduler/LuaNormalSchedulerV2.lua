----------------------------------------------------
-- Auto generated by gen_scheduler.tl
-- DO NOT edit this file!
----------------------------------------------------

 local _tl_compat
if (tonumber((_VERSION or ""):match("[%d.]*$")) or 0) < 5.3 then
	local p, m = pcall(require, "compat53.module")
	if p then
		_tl_compat = m
	end
end
local assert = _tl_compat and _tl_compat.assert or assert
local _ = _tl_compat and _tl_compat.coroutine or coroutine
local _ = _tl_compat and _tl_compat.debug or debug
local ipairs = _tl_compat and _tl_compat.ipairs or ipairs
local _ = _tl_compat and _tl_compat.math or math
local _ = _tl_compat and _tl_compat.os or os
local pairs = _tl_compat and _tl_compat.pairs or pairs
local string = _tl_compat and _tl_compat.string or string
local table = _tl_compat and _tl_compat.table or table

local ffi = require("ffi")
local math = require("math")
local debug = require("debug")
local class = require("pl.class")
local coroutine = require("coroutine")
local table_clear = require("table.clear")

local C = ffi.C
local f = string.format
local random = math.random
local table_insert = table.insert
local coro_yield = coroutine.yield
local coro_resume = coroutine.resume
local coro_create = coroutine.create

local Timer = 0
local Posedge = 1
local PosedgeHDL = 2
local Negedge = 3
local NegedgeHDL = 4
local PosedgeAlwaysHDL = 6
local Event = 12
local NOOP = 44
local EarlyExit = 11

ffi.cdef([[
    void vpiml_register_time_callback(uint64_t time, int id);
    void vpiml_register_posedge_callback(const char *path, int id);
    void vpiml_register_posedge_callback_hdl(long long handle, int id);
    void vpiml_register_negedge_callback(const char *path, int id);
    void vpiml_register_negedge_callback_hdl(long long handle, int id);
    void vpiml_register_edge_callback(const char *path, int id);
    void vpiml_register_edge_callback_hdl(long long handle, int id);
    void vpiml_register_posedge_callback_hdl_always(long long handle, int id);
    void vpiml_register_negedge_callback_hdl_always(long long handle, int id);
]])

local Scheduler = class()

local SCHEDULER_TASK_ID_MIN_COROUTINE = 0
local SCHEDULER_TASK_ID_MAX_COROUTINE = 99999

local SCHEDULER_TASK_ID_MIN_FUNCTION = 100000
local SCHEDULER_TASK_ID_MAX_FUNCTION = 199999

local SCHEDULER_TASK_MAX_COUNT = 100000
local SCHEDULER_MIN_EVENT_ID = 0
local SCHEDULER_MAX_EVENT_ID = 999

function Scheduler:_init()
	self.task_count = 0

	self.task_coroutine_map = {}
	self.task_name_map = {}
	self.task_fired_status_map = {}
	self.task_execution_count_map = {}
	self.pending_removal_tasks = {}

	self.event_task_id_list_map = {}
	self.event_name_map = {}
	self.has_wakeup_event = false
	self.pending_wakeup_event = {}
	do
		verilua_debug("[Scheduler]", "Using NORMAL scheduler")
	end
end

function Scheduler:_is_coroutine_task(id)
	return id <= SCHEDULER_TASK_ID_MAX_COROUTINE and id >= SCHEDULER_TASK_ID_MIN_COROUTINE
end

function Scheduler:check_task_exists(id)
	return self.task_name_map[id] ~= nil
end

function Scheduler:_alloc_coroutine_task_id()
	local id = random(SCHEDULER_TASK_ID_MIN_COROUTINE, SCHEDULER_TASK_ID_MAX_COROUTINE)
	while self:check_task_exists(id) do
		id = random(SCHEDULER_TASK_ID_MIN_COROUTINE, SCHEDULER_TASK_ID_MAX_COROUTINE)
	end
	return id
end

function Scheduler:_alloc_function_task_id()
	local id = random(SCHEDULER_TASK_ID_MIN_FUNCTION, SCHEDULER_TASK_ID_MAX_FUNCTION)
	while self:check_task_exists(id) do
		id = random(SCHEDULER_TASK_ID_MIN_FUNCTION, SCHEDULER_TASK_ID_MAX_FUNCTION)
	end
	return id
end

function Scheduler:_remove_task(id)
	self.task_count = self.task_count - 1
	table_insert(self.pending_removal_tasks, id)
end

function Scheduler:_register_callback(id, cb_type, str_value, integer_value)
	if cb_type == PosedgeHDL then
		C.vpiml_register_posedge_callback_hdl(integer_value, id)
	elseif cb_type == Posedge then
		C.vpiml_register_posedge_callback(str_value, id)
	elseif cb_type == PosedgeAlwaysHDL then
		C.vpiml_register_posedge_callback_hdl_always(integer_value, id)
	elseif cb_type == NegedgeHDL then
		C.vpiml_register_negedge_callback_hdl(integer_value, id)
	elseif cb_type == Negedge then
		C.vpiml_register_negedge_callback(str_value, id)
	elseif cb_type == Timer then
		C.vpiml_register_time_callback(integer_value, id)
	elseif cb_type == Event then
		if self.event_name_map[integer_value] == nil then
			assert(false, "Unknown event => " .. integer_value)
		end
		table_insert(self.event_task_id_list_map[integer_value], id)
	elseif cb_type == NOOP then
	else
		assert(false, "Unknown YieldType => " .. tostring(cb_type))
	end
end

function Scheduler:append_task(id, name, task_body, start_now)
	do
		assert(self.task_count <= SCHEDULER_TASK_MAX_COUNT, "[Normal Scheduler] Too many tasks!")
	end

	local task_id = id
	if id then
		if not self:_is_coroutine_task(id) then
			assert(false, "[Scheduler] Invalid coroutine task id!")
		end

		if self:check_task_exists(id) then
			local task_name = self.task_name_map[id]
			assert(false, "[Scheduler] Task already exists! task_id: " .. id .. ", task_name: " .. task_name)
		end
	else
		task_id = self:_alloc_coroutine_task_id()
	end

	self.task_name_map[task_id] = name
	self.task_fired_status_map[task_id] = false
	self.task_coroutine_map[task_id] = coro_create(task_body)
	self.task_execution_count_map[task_id] = 0

	self.task_count = self.task_count + 1

	if true and start_now then
		self.task_fired_status_map[task_id] = true
		self:schedule_task(task_id)
	end

	return task_id
end

function Scheduler:schedule_task(id)
	for _, remove_id in ipairs(self.pending_removal_tasks) do
		self.task_name_map[remove_id] = nil
		self.task_execution_count_map[remove_id] = 0
		self.task_fired_status_map[remove_id] = false
	end
	table_clear(self.pending_removal_tasks)

	local task_cnt = self.task_execution_count_map[id]
	self.task_execution_count_map[id] = task_cnt + 1

	local ok, cb_type_or_err, str_value, integer_value
	do
		ok, cb_type_or_err, str_value, integer_value = coro_resume(self.task_coroutine_map[id])

		if not ok then
			print(
				f(
					"[Scheduler] Error while executing task(id: %d, name: %s)\n\t%s",
					id,
					self.task_name_map[id],
					debug.traceback(self.task_coroutine_map[id], cb_type_or_err)
				)
			)

			_G.verilua_get_error = true
			assert(false)
		end
	end

	if cb_type_or_err == nil or cb_type_or_err == EarlyExit then
		self:_remove_task(id)
	else
		self:_register_callback(id, cb_type_or_err, str_value, integer_value)
	end

	if self.has_wakeup_event then
		self.has_wakeup_event = false
		for _, event_id in ipairs(self.pending_wakeup_event) do
			local wakeup_task_id_list = self.event_task_id_list_map[event_id]
			for _, wakeup_task_id in ipairs(wakeup_task_id_list) do
				self:schedule_task(wakeup_task_id)
			end
			table_clear(self.event_task_id_list_map[event_id])
		end
		table_clear(self.pending_wakeup_event)
	end
end

function Scheduler:schedule_tasks(id)
	self:schedule_task(id)
end

function Scheduler:schedule_all_tasks()
	for id, _ in pairs(self.task_name_map) do
		do
			local fired = self.task_fired_status_map[id]
			if not fired then
				self:schedule_task(id)
				self.task_fired_status_map[id] = true
			end
		end
	end
end

function Scheduler:list_tasks()
	print("[scheduler list tasks]:")
	print("-------------------------------------------------------------")

	local max_name_str_len = 0
	for _, name in pairs(self.task_name_map) do
		local len = #name
		if len > max_name_str_len then
			max_name_str_len = len
		end
	end

	local idx = 0
	for id, name in pairs(self.task_name_map) do
		print(
			f(
				"[%2d] name: %" .. max_name_str_len .. "s    id: %5d    cnt:%8d",
				idx,
				name,
				id,
				self.task_execution_count_map[id]
			)
		)
		idx = idx + 1
	end
	print("-------------------------------------------------------------")
	print()
end

function Scheduler:send_event(event_id)
	table_insert(self.pending_wakeup_event, event_id)
	self.has_wakeup_event = true
end

function Scheduler:new_event_hdl(name, user_event_id)
	local event_id = user_event_id
	if not event_id then
		event_id = random(SCHEDULER_MIN_EVENT_ID, SCHEDULER_MAX_EVENT_ID)
		while self.event_name_map[event_id] do
			event_id = random(SCHEDULER_MIN_EVENT_ID, SCHEDULER_MAX_EVENT_ID)
		end
	else
		assert(math.type(user_event_id) == "integer")
	end

	self.event_name_map[event_id] = name
	self.event_task_id_list_map[event_id] = {}

	return {
		_scheduler = self,
		name = name,
		event_id = event_id,
		wait = function(this)
			coro_yield(Event, "", this.event_id)
		end,
		send = function(this)
			this._scheduler:send_event(this.event_id)
		end,
	}
end

function Scheduler:get_event_hdl(name, user_event_id)
	return self:new_event_hdl(name, user_event_id)
end

return Scheduler()
