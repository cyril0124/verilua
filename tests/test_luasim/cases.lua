---@diagnostic disable: unnecessary-assert

local case_name = assert(os.getenv("VL_TEST_LUASIM_CASE"), "runner must select a case")

local luasim = require "verilua.luasim.Sim"
local root = cfg.top

---@type verilua.handles.CallableHDL
local signal
---@type verilua.handles.CallableHDL
local clock
---@type verilua.handles.CallableHDL
local wide
---@type verilua.handles.CallableHDL?
local auxiliary_clock

local final_count = 0
final {
    function()
        final_count = final_count + 1
        print("FINAL " .. case_name .. " " .. final_count)
        assert(final_count == 1, "final called twice")
    end,
}

luasim.declare(function()
    signal = luasim.signal(root .. ".value", { width = 32, initial = 0 })
    clock = luasim.signal(root .. ".clock", { width = 1, initial = 0 })
    wide = luasim.signal(root .. ".wide", { width = 129, initial = 0 })

    if case_name == "native_clock" then
        auxiliary_clock = luasim.signal(root .. ".auxiliary_clock", { width = 1, initial = 0 })
    end

    if case_name == "wave_before_tasks" then
        luasim.signal(root .. ".late", { width = 1, initial = 0 })
    end

    -- The declarations below must be rejected by the backend.
    if case_name == "duplicate_path" then
        luasim.signal(root .. ".value", { width = 32, initial = 0 })
    elseif case_name == "width_zero" then
        luasim.signal(root .. ".invalid", { width = 0, initial = 0 })
    elseif case_name == "width_negative" then
        luasim.signal(root .. ".invalid", { width = -1, initial = 0 })
    elseif case_name == "width_fraction" then
        ---@diagnostic disable-next-line: param-type-mismatch, assign-type-mismatch
        luasim.signal(root .. ".invalid", { width = 1.5, initial = 0 })
    end

    if case_name == "declaration_validation" then
        local invalid_options = {
            { width = 1, initial = false },
            { width = 8, initial = "0xG" },
            { width = 1, unexpected = true },
        }
        for index, options in ipairs(invalid_options) do
            local name = root .. ".validated_" .. index
            ---@diagnostic disable-next-line: param-type-mismatch
            local accepted = pcall(luasim.signal, name, options)
            assert(not accepted, "invalid declaration must be rejected")

            -- The rejected name must stay reusable.
            local replacement = luasim.signal(name, { width = 1, initial = 1 })
            replacement:expect(1)
        end
    end
end)

print("CASE_READY " .. case_name)

--- Every waiter must wake on a multi-bit change, and only on a real change.
local function run_any_change()
    local values = { 3, 255, 0x12345678, 0x800000ff, 0xffffffff, 0, 1, 2 }
    local wide_values = {
        "80000000000000000000000000000003",
        "40000000000000000000000000000003",
        "40000000000000000000000100000003",
    }

    local woke = 0
    local waiters = {}
    for _ = 1, 17 do
        waiters[#waiters + 1] = jfork { function()
            for index = 1, #values do
                await_edge_hdl(signal.hdl)
                signal:expect(values[index])
                woke = woke + 1
            end
        end }
    end

    for index, value in ipairs(values) do
        await_time_ns(100)
        signal:set(value)
        await_rw()
        assert(woke == index * 17, "multi-bit change did not wake every waiter")

        signal:set(value)
        await_rw()
        assert(woke == index * 17, "unchanged value woke a waiter")
    end
    join(waiters)

    local wide_index = 0
    local wide_waiter = jfork { function()
        for index, value in ipairs(wide_values) do
            await_edge_hdl(wide.hdl)
            wide:expect_hex_str(value)
            wide_index = index
        end
    end }
    for index, value in ipairs(wide_values) do
        await_time_ns(100)
        wide:set_hex_str(value)
        await_rw()
        assert(wide_index == index, "upper-word change was not reported")
    end
    join { wide_waiter }
    print("ANY_CHANGE: 17 waiters, eight 32-bit values and three wide values passed")

    -- Posedge and negedge waiters must stay filtered to their own edge.
    clock:set(0)
    await_rw()
    local rising, falling = 0, 0
    local posedge_task = jfork { function()
        for _ = 1, 3 do
            clock:posedge()
            clock:expect(1)
            rising = rising + 1
        end
    end }
    local negedge_task = jfork { function()
        for _ = 1, 3 do
            clock:negedge()
            clock:expect(0)
            falling = falling + 1
        end
    end }
    for index = 1, 3 do
        await_time_ns(100)
        clock:set(1)
        await_rw()
        assert(rising == index and falling == index - 1, "posedge filter changed")

        await_time_ns(100)
        clock:set(0)
        await_rw()
        assert(rising == index and falling == index, "negedge filter changed")
    end
    join { posedge_task, negedge_task }
    print("EDGE_FILTER: three rising and three falling edges passed")
end

--- Two NativeClocks at different periods, then the stop/restart/destroy lifecycle.
local function run_native_clock()
    local NativeClock = require "verilua.utils.NativeClock"
    local second_clock = assert(auxiliary_clock)

    local driver = NativeClock(clock)
    local second_driver = NativeClock(second_clock)
    local duplicate = NativeClock(clock)
    assert(not driver:is_running())
    assert(not pcall(driver.start, driver, 1, "step"), "invalid clock period accepted")

    driver:start(10, "step", { high = 3, start_high = false })
    second_driver:start(14, "step", { high = 5, start_high = false })
    assert(driver:is_running() and second_driver:is_running())
    assert(not pcall(driver.start, driver, 10, "step"), "double start accepted")
    assert(not pcall(duplicate.start, duplicate, 10, "step"), "duplicate signal driver accepted")

    local observer = jfork { function()
        for _, expected in ipairs({ 9, 23, 37 }) do
            second_clock:posedge()
            assert(sim.get_sim_time() == expected, "second clock edge time mismatch")
        end
    end }
    for cycle = 1, 5 do
        clock:posedge()
        assert(sim.get_sim_time() == cycle * 10 - 3, "clock rising edge time mismatch")
        clock:expect(1)

        clock:negedge()
        assert(sim.get_sim_time() == cycle * 10, "clock falling edge time mismatch")
        clock:expect(0)
    end
    join(observer)
    print("NATIVE_CLOCK timing: 10/3 and 14/5 step clocks passed")

    driver:stop()
    second_driver:stop()
    assert(not driver:is_running() and not second_driver:is_running())
    duplicate:destroy()

    local stopped_value = clock:get()
    local stopped_second_value = second_clock:get()
    await_time(30)
    await_rw()
    assert(clock:get() == stopped_value and second_clock:get() == stopped_second_value,
        "stopped NativeClock changed a signal")

    local restarted_at = sim.get_sim_time()
    driver:restart(12, "step", { high = 4, start_high = true })
    assert(clock:get() == stopped_value, "NativeClock start must use deferred writes")
    await_rw()
    clock:expect(1)
    clock:negedge()
    assert(sim.get_sim_time() == restarted_at + 4, "restart high duration mismatch")
    clock:posedge()
    assert(sim.get_sim_time() == restarted_at + 12, "restart period mismatch")

    driver:destroy()
    second_driver:destroy()
    assert(not driver:is_running() and not second_driver:is_running())
    assert(not pcall(driver.start, driver, 10, "step"), "destroyed NativeClock restarted")
    await_time(30)
    await_rw()
    clock:expect(1)

    local replacement = NativeClock(clock)
    local start_time = sim.get_sim_time()
    replacement:start(2, "ns", { start_high = false })
    await_rw()
    clock:expect(0)
    clock:posedge()
    local steps_per_ns = require("verilua.utils.TimeUtils").time_to_steps(1, "ns")
    assert(sim.get_sim_time() == start_time + steps_per_ns, "NativeClock time-unit conversion mismatch")
    replacement:destroy()
    print("NATIVE_CLOCK lifecycle: stop, restart, destroy and replacement passed")
end

--- The backend must dispatch through the common entries, one batch per chunk callback.
local function run_common_dispatcher()
    local ffi = require "ffi"
    ffi.cdef [[
        const char *luasim_backend_kind(void);
        const char *vpiml_get_simulator_auto(void);
        int verilua_host_pcall(void *state, int nargs, int phase);
    ]]
    assert(ffi.string(ffi.C.luasim_backend_kind()) == "cpp", "luasim must use the C++ kernel")
    assert(ffi.string(ffi.C.vpiml_get_simulator_auto()) == "luasim", "native backend detection mismatch")
    assert(not pcall(function() return ffi.C.verilua_host_pcall end),
        "native backend must use standard VPI without host hooks")
    assert(package.loaded["verilua.luasim.Runtime"] == nil, "Lua simulation kernel must not be loaded")
    assert(package.loaded["verilua.vpiml.VpimlLuasim"] == nil, "Lua VPIML backend must not be loaded")

    local dispatch = assert(rawget(_G, "sim_event"))
    local dispatch_info = assert(debug.getinfo(dispatch, "S"))
    assert(dispatch_info.what == "Lua" and dispatch_info.source:match("/verilua/Verilua%.lua$"),
        "luasim must use the common task dispatcher")

    for count = 1, 16 do
        local chunk = assert(rawget(_G, "sim_event_chunk_" .. count))
        local chunk_info = assert(debug.getinfo(chunk, "S"))
        assert(chunk_info.what == "Lua" and chunk_info.source == dispatch_info.source,
            "luasim must use the common callback batch entries")

        local completed = 0
        local workers = {}
        clock:set_imm(0)
        for _ = 1, count do
            workers[#workers + 1] = jfork { function()
                clock:posedge()
                completed = completed + 1
            end }
        end
        await_time(1)
        collectgarbage("collect")
        clock:set(1)
        await_rw()
        assert(completed == count, "common dispatcher lost a task in the batch")
        join(workers)
    end
end

--- Cancelling a task and reusing its ID must not deliver the cancelled work.
local function run_task_reuse_stress()
    local stale_callbacks = 0
    local completed = 0
    local task_id = 10001

    for iteration = 1, 500 do
        scheduler:append_task(task_id, "cancelled_timer", function()
            await_time(2)
            stale_callbacks = stale_callbacks + 1
        end, true)
        scheduler:remove_task(task_id)
        scheduler:append_task(task_id, "replacement_timer", function()
            await_time(3)
            completed = completed + 1
        end, true)

        await_time(4)
        assert(stale_callbacks == 0 and completed == iteration, "stale timer survived task reuse")
    end

    completed = 0
    for iteration = 1, 500 do
        scheduler:append_task(task_id, "cancelled_edge", function()
            clock:posedge()
            stale_callbacks = stale_callbacks + 1
        end, true)
        clock:set_imm(1)
        scheduler:remove_task(task_id)
        scheduler:append_task(task_id, "replacement_edge", function()
            clock:negedge()
            completed = completed + 1
        end, true)
        clock:set_imm(0)

        await_rw()
        assert(stale_callbacks == 0 and completed == iteration, "queued edge survived task reuse")
        await_time(1)
    end
end

-- Cases that fail or finish while the script loads, before any task is scheduled.
if case_name == "declaration_validation" then
    print("PASS " .. case_name)

    return
elseif case_name == "finish_top" then
    print("PASS " .. case_name)
    sim.finish()
    error("sim.finish returned in the main thread")
elseif case_name == "finish_initial" then
    initial { function()
        print("PASS " .. case_name)
        sim.finish()
        error("sim.finish returned in an initial callback")
    end }
elseif case_name == "wave_before_tasks" then
    sim.dump_wave("wave.vcd")
    signal:set_imm(17)
    initial { function()
        dut.late:chdl():set_imm(1)
        print("PASS " .. case_name)
    end }
elseif case_name == "duplicate_path" or case_name == "width_zero"
    or case_name == "width_negative" or case_name == "width_fraction" then
    error("[luasim] invalid declaration was accepted")
elseif case_name == "missing_signal" then
    (root .. ".missing"):chdl()
elseif case_name == "module_error" then
    error("injected module failure")
elseif case_name == "initial_error" then
    initial { function() error("injected initial failure") end }
elseif case_name == "declare_initial" then
    fork { function() await_time(10) end }
    initial { function() luasim.signal(root .. ".late", { width = 1, initial = 0 }) end }
elseif case_name == "initial_declaration" then
    -- Signals declared inside the block stay reachable by path from callbacks.
    initial { function()
        assert(dut.value:chdl():get() == 0, "declared signal lost its handle")
        print("PASS " .. case_name)
    end }
end

if case_name == "initial_error"
    or case_name == "declare_initial"
    or case_name == "initial_declaration"
    or case_name == "finish_initial"
    or case_name == "wave_before_tasks" then
    return
end

fork {
    function()
        if case_name == "finish_twice" then
            -- The only case whose body is empty: it checks that finishing twice is allowed.
        elseif case_name == "task_error" then
            error("injected task failure")
        elseif case_name == "declare_task" then
            luasim.signal(root .. ".late", { width = 1, initial = 0 })
        elseif case_name == "unknown_x" then
            signal:set_hex_str("x")
        elseif case_name == "unknown_z" then
            signal:set_bin_str("z")
        elseif case_name == "force" then
            signal:force(1)
        elseif case_name == "release" then
            signal:release()
        elseif case_name == "freeze" then
            signal:freeze()
        elseif case_name == "freeze_imm" then
            signal:freeze_imm()
        elseif case_name == "array" then
            -- Scalar CHDL handles do not expose :at(), so probe the array lookup directly.
            local vpiml = require "verilua.vpiml.vpiml"
            vpiml.vpiml_handle_by_index(signal.hdl, 0)
        elseif case_name == "any_change" then
            run_any_change()
        elseif case_name == "native_clock" then
            run_native_clock()
        elseif case_name == "randomize" then
            local deferred_wide = "1ffffffffffffffffffffffffffffffff"
            local immediate_wide = "100000000000000000000000000000001"
            signal:shuffled_range_u32({ 0xa5a5a5a5 })
            wide:shuffled_range_hex_str({ deferred_wide })
            signal:randomize()
            wide:randomize()
            signal:expect(0)
            wide:expect_hex_str("0")
            await_rw()
            signal:expect(0xa5a5a5a5)
            wide:expect_hex_str(deferred_wide)

            signal:shuffled_range_u32({ 0x5a5a5a5a })
            wide:shuffled_range_hex_str({ immediate_wide })
            signal:randomize_imm()
            wide:randomize_imm()
            signal:expect(0x5a5a5a5a)
            wide:expect_hex_str(immediate_wide)

            await_rd()
            for _, handle in ipairs({ signal, wide }) do
                local accepted, err = pcall(handle.randomize, handle)
                assert(not accepted and tostring(err):find("read-only phase", 1, true), tostring(err))
                accepted, err = pcall(handle.randomize_imm, handle)
                assert(not accepted and tostring(err):find("read-only phase", 1, true), tostring(err))
            end
            signal:expect(0x5a5a5a5a)
            wide:expect_hex_str(immediate_wide)
        elseif case_name == "collect_signals_rejected" or case_name == "auto_bundle_rejected" then
            local accepted, err
            if case_name == "collect_signals_rejected" then
                accepted, err = pcall(sim.collect_signals, root)
            else
                accepted, err = pcall(sim.auto_bundle_via_hierarchy, root, { prefix = "v" })
            end
            assert(not accepted and tostring(err):find("hierarchy discovery are unsupported", 1, true), tostring(err))
            signal:set(7)
            await_rw()
            signal:expect(7)
        elseif case_name == "readonly_set" then
            await_rd()
            signal:set(1)
        elseif case_name == "readonly_immediate" then
            await_rd()
            signal:set_imm(1)
        elseif case_name == "readonly_hex" then
            await_rd()
            signal:set_hex_str("1")
        elseif case_name == "readonly_rw" then
            await_rd()
            await_rw()
            signal:set(1)
        elseif case_name == "readonly_delta" then
            await_rd()
            await_time(0)
            signal:set_imm(1)
        elseif case_name == "negative_time" then
            await_time(-1)
        elseif case_name == "fractional_step" then
            -- Deliberately pass a fractional step to check runtime validation.
            ---@diagnostic disable-next-line: param-type-mismatch
            await_time(1.5)
        elseif case_name == "queue_empty_edge" or case_name == "queue_empty_nsim" then
            -- No event sits behind the wait, so the run ends with an empty queue and
            -- this task must never resume.
            fork {
                function()
                    if case_name == "queue_empty_edge" then
                        clock:posedge()
                    else
                        await_nsim()
                    end
                    print("UNEXPECTED_RESUME " .. case_name)
                end,
            }
        elseif case_name == "max_time" then
            luasim.configure { max_time = 8 }
            await_time(9)
        elseif case_name == "max_delta" or case_name == "default_delta_limit" then
            if case_name == "max_delta" then
                luasim.configure { max_delta_cycles = 12 }
            end
            while true do
                await_time(0)
            end
        elseif case_name == "invalid_max_time_zero" then
            luasim.configure { max_time = 0 }
        elseif case_name == "invalid_max_time_false" then
            ---@diagnostic disable-next-line: param-type-mismatch
            luasim.configure { max_time = false }
        elseif case_name == "invalid_delta_false" then
            ---@diagnostic disable-next-line: param-type-mismatch
            luasim.configure { max_delta_cycles = false }
        elseif case_name == "native_backend" then
            run_common_dispatcher()
        elseif case_name == "ull_limits" then
            -- `uint64_t` limits bypass the Lua-number precision guard and reach the engine exactly.
            luasim.configure { max_time = 1000ULL, max_delta_cycles = 100ULL }
            await_time(999)
            assert(sim.get_sim_time() == 999, "uint64 max_time did not reach the engine")
        elseif case_name == "config" then
            assert(cfg.top == "custom_tb" and cfg.time_precision == -9)
            assert(dut.value:chdl().hdl == signal.hdl)
            await_time_ns(3)
            assert(sim.get_sim_time() == 3)
        elseif case_name == "no_default_time_limit" then
            await_time(1000000000000)
            assert(sim.get_sim_time() == 1000000000000)
        elseif case_name == "readonly_future" then
            local future = jfork { function() await_time(5) end }
            await_rd()
            await_nsim()
            assert(sim.get_sim_time() == 5)
            signal:set(7)
            await_rw()
            assert(signal:get() == 7)
            join(future)
        elseif case_name == "try_restart_completed" or case_name == "append_completed" then
            local starts, completed = 0, 0
            local function body()
                starts = starts + 1
                if starts == 1 then
                    return
                end
                clock:posedge()
                completed = completed + 1
            end

            local id = scheduler:append_task(1001, "restart", body, true)
            assert(not scheduler:check_task_exists(id))
            if case_name == "try_restart_completed" then
                scheduler:try_wakeup_task(id)
            else
                scheduler:append_task(id, "replacement", body, true)
            end

            assert(starts == 2 and scheduler:check_task_exists(id), "restarted task lost its running entry")
            scheduler:remove_task(id)
            clock:set(1)
            await_rw()
            assert(completed == 0, "removed replacement resumed")
        elseif case_name == "batch_task_reuse" then
            local stale, replacement = false, false
            scheduler:append_task(101, "batch_first", function()
                clock:posedge()
                scheduler:remove_task(102)
                scheduler:append_task(102, "batch_replacement", function()
                    await_time(10)
                    assert(sim.get_sim_time() == 11, "old batch resumed the replacement task")
                    replacement = true
                end, true)
            end, true)
            scheduler:append_task(102, "batch_second", function()
                clock:posedge()
                stale = true
            end, true)

            await_time(1)
            clock:set(1)
            await_rw()
            assert(not stale and not replacement)

            await_time(11)
            assert(replacement and not stale)
        elseif case_name == "next_time_before_timer" then
            local observed = false
            local driver = jfork { function()
                await_time(10)
                clock:set_imm(1)
            end }
            local listener = jfork { function()
                await_time(5)
                await_rw()
                clock:posedge()
                assert(sim.get_sim_time() == 10, "edge delivered at the wrong time")
                observed = true
            end }

            await_time(11)
            assert(observed, "timer ran before next-time installed the edge subscription")
            join { driver, listener }
        elseif case_name == "inflight_cancel" then
            local completed = false
            scheduler:append_task(101, "self_cancel", function()
                clock:posedge()
                scheduler:remove_task(101)
                scheduler:append_task(102, "replacement", function()
                    clock:negedge()
                    completed = true
                end, true)
            end, true)

            clock:set(1)
            await_rw()
            clock:set(0)
            await_rw()
            assert(completed, "replacement callback lost after in-flight cancellation")
        elseif case_name == "callback_reuse_stress" then
            run_task_reuse_stress()
        elseif case_name == "wave" then
            sim.dump_wave("wave.vcd")
            wide:set_hex_str("10123456789abcdeffedcba9876543210")
            await_rw()
            await_time(5)

            clock:set(1)
            signal:set(17)
            await_rw()
            await_time(5)

            wide:set_hex_str("100000000000000000000000000000001")
            clock:set(0)
            await_rw()
            await_time(1)
        else
            error("NEGATIVE_CASE_RETURNED")
        end

        print("PASS " .. case_name)
        sim.finish()
        if case_name == "finish_twice" then
            -- A second finish must stay harmless.
            sim.finish()
        end
    end,
}
