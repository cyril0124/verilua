---@diagnostic disable: unnecessary-assert

local luasim = require "verilua.luasim.Sim"
local ffi = require "ffi"

---@type integer[]
local widths = { 1, 32, 33, 64, 65, 128, 129, 1024, 1025, 2049 }
---@type string[]
local values = {
    "1", "fedcba98", "1fedcba98", "fedcba9876543210",
    "1fedcba9876543210", "0123456789abcdeffedcba9876543210",
    "10123456789abcdeffedcba9876543210",
    string.rep("f", 256),
    "1" .. string.rep("a", 256),
    "1" .. string.rep("01234567", 64),
}
---@type table<integer, verilua.handles.CallableHDL>
local signals = {}
---@type verilua.handles.CallableHDL
local alias_data
---@type verilua.handles.CallableHDL
local pulse
---@type verilua.handles.CallableHDL
local fanout
---@type verilua.handles.CallableHDL
local settled
---@type verilua.handles.CallableHDL
local pipeline_clock
---@type verilua.handles.CallableHDL
local first_stage
---@type verilua.handles.CallableHDL
local second_stage
---@type verilua.handles.CallableHDL
local stale_clock
---@type verilua.handles.CallableHDL
local replacement_clock
---@type verilua.handles.CallableHDL
local clock_a
---@type verilua.handles.CallableHDL
local clock_b
---@type verilua.handles.CallableHDL
local count_a
---@type verilua.handles.CallableHDL
local count_b
luasim.declare(function()
    for _, width in ipairs(widths) do
        signals[width] = luasim.signal("tb_top.width_" .. width, { width = width, initial = 0 })
    end
    alias_data = luasim.signal("tb_top.bus_data", { width = 128, initial = 0 })
    luasim.signal("tb_top.bus_valid", { width = 1, initial = 0 })
    luasim.signal("tb_top.bus_ready", { width = 1, initial = 0 })
    pulse = luasim.signal("tb_top.pulse", { width = 1, initial = 0 })
    fanout = luasim.signal("tb_top.fanout", { width = 1, initial = 0 })
    settled = luasim.signal("tb_top.settled", { width = 1, initial = 0 })
    pipeline_clock = luasim.signal("tb_top.pipeline_clock", { width = 1, initial = 0 })
    first_stage = luasim.signal("tb_top.first_stage", { width = 32, initial = 0 })
    second_stage = luasim.signal("tb_top.second_stage", { width = 32, initial = 0 })
    stale_clock = luasim.signal("tb_top.stale_clock", { width = 1, initial = 0 })
    replacement_clock = luasim.signal("tb_top.replacement_clock", { width = 1, initial = 0 })
    clock_a = luasim.signal("tb_top.clock_a", { width = 1, initial = 0 })
    clock_b = luasim.signal("tb_top.clock_b", { width = 1, initial = 0 })
    count_a = luasim.signal("tb_top.count_a", { width = 32, initial = 0 })
    count_b = luasim.signal("tb_top.count_b", { width = 32, initial = 0 })
end)

local bus = ([[
    | data
    | valid
    | ready
]]):bdl {
    hier = "tb_top",
    prefix = "bus_",
    name = "bus",
    is_decoupled = false,
}

local aliases = ([[
    | data => payload/mirror
]]):abdl {
    hier = "tb_top",
    prefix = "bus_",
    name = "aliases",
}
local initial_called = false
local final_count = 0

initial { function() initial_called = true end }
final {
    function()
        final_count = final_count + 1
        assert(final_count == 1, "final callback ran more than once")
        print("FINAL main 1")
    end,
}

---@param value string
---@return string
local function normalize_hex(value)
    local normalized = value:lower():gsub("^0+", "")
    return normalized == "" and "0" or normalized
end

---@param signal verilua.handles.CallableHDL
---@param expected string
local function expect_hex(signal, expected)
    assert(normalize_hex(signal:get_hex_str()) == normalize_hex(expected),
        signal.fullpath .. ": expected " .. expected .. ", got " .. signal:get_hex_str())
end

---@param reverse boolean
local function check_pipeline(reverse)
    first_stage:set_imm(0)
    second_stage:set_imm(0)
    local producer = function()
        for _ = 1, 4 do
            pipeline_clock:posedge()
            first_stage:set((first_stage:get() + 1) --[[@as integer]])
        end
    end
    local consumer = function()
        for _ = 1, 4 do
            pipeline_clock:posedge()
            second_stage:set(first_stage:get() --[[@as integer]])
        end
    end
    local first = jfork { reverse and consumer or producer }
    local second = jfork { reverse and producer or consumer }
    await_time(0)
    for cycle = 1, 4 do
        pipeline_clock:set(1)
        await_rw()
        assert(first_stage:get() == cycle, "pipeline producer did not settle")
        assert(second_stage:get() == cycle - 1, "same-edge consumer observed a new value")
        pipeline_clock:set(0)
        await_rw()
        await_time(1)
    end
    join { first, second }
end

fork {
    function()
        assert(cfg.top == "tb_top", "default top must be tb_top")
        assert(cfg.time_precision == -12, "default precision must be 1 ps")
        -- Identity comes from the linked backend, not from the launcher environment.
        assert(cfg.simulator == "luasim", "cfg.simulator must resolve to luasim")
        assert(sim.get_sim_time() == 0, "new process must start at time zero")
        print("CASE_READY main")
        -- fork starts eagerly; initial callbacks run when the launcher starts simulation.
        await_time(0)
        assert(initial_called, "initial callback did not run at simulation start")

        for i, width in ipairs(widths) do
            local signal = signals[width]
            local expected = assert(values[i])
            assert(signal.__type == "CallableHDL")
            assert(signal:get_width() == width)
            expect_hex(signal, "0")
            signal:set_hex_str(expected)
            expect_hex(signal, "0")
            await_rw()
            expect_hex(signal, expected)
            if width <= 32 then
                assert(signal:get() == tonumber(expected, 16))
            elseif width <= 64 then
                assert(type(signal:get64()) == "cdata")
            else
                assert(ffi.istype("uint32_t[]", signal:get()), "wide get must preserve real CHDL representation")
            end
        end
        assert(signals[33]:get64() == 0x1fedcba98ULL)
        assert(signals[64]:get64() == 0xfedcba9876543210ULL)
        local value128 = assert(values[6])
        local value129 = assert(values[7])
        signals[128]:set({ 0x76543210, 0xfedcba98, 0x89abcdef, 0x01234567 })
        await_rw()
        expect_hex(signals[128], value128)
        signals[128]:set_bits(28, 35, 0xa5)
        await_rw()
        assert(signals[128]:get_bitvec():get_bitfield(28, 35) == 0xa5)
        signals[129]:set_imm({ 0x76543210, 0xfedcba98, 0x89abcdef, 0x01234567, 0 })
        signals[129]:set_bits_imm(128, 128, 1)
        expect_hex(signals[129], value129)
        ---@type integer[]
        local wide_words = {}
        for i = 1, 65 do wide_words[i] = 0 end
        wide_words[1] = 0x1234
        wide_words[65] = 1
        signals[2049]:set(wide_words)
        await_rw()
        expect_hex(signals[2049], "1" .. string.rep("0", 508) .. "1234")
        signals[2049]:set_bits_imm(2048, 2048, 0)
        expect_hex(signals[2049], "1234")
        signals[32]:set_imm(5)
        signals[32]:set(11)
        signals[32]:set(19)
        assert(signals[32]:get() == 5, "set must not commit inline")
        await_rw()
        assert(signals[32]:get() == 19, "last queued write must win")
        print("PASS widths_and_values")

        local proxy = dut.bus_data:chdl()
        local named = ("tb_top.bus_data"):chdl()
        assert(proxy.hdl == alias_data.hdl and named.hdl == alias_data.hdl)
        assert(getmetatable(alias_data) == getmetatable(proxy), "declaration must return a real CallableHDL")
        aliases.payload:set_hex_str(value128)
        await_rw()
        expect_hex(bus.data, value128)
        expect_hex(aliases.mirror, value128)
        expect_hex(proxy, value128)
        bus.data:set_imm({ 1, 2, 3, 4 })
        expect_hex(alias_data, "00000004000000030000000200000001")
        expect_hex(named, "00000004000000030000000200000001")
        print("PASS aliases_and_bundles")

        local callback_ran = false
        local first_fanout = jfork {
            function()
                pulse:posedge()
                callback_ran = true
                fanout:set(1)
            end,
        }
        local last_fanout = jfork {
            function()
                fanout:posedge()
                settled:set(1)
            end,
        }
        await_time(0)
        pulse:set_imm(1)
        assert(pulse:get() == 1 and not callback_ran, "immediate write must queue, not inline, callbacks")
        local same_time = sim.get_sim_time()
        await_rw()
        assert(callback_ran and settled:get() == 1, "RW must drain cascading writes")
        join { first_fanout, last_fanout }
        for round = 1, 5 do
            signals[32]:set(round)
            await_rw()
            assert(signals[32]:get() == round)
            assert(sim.get_sim_time() == same_time, "RW settling must not advance time")
        end
        local left = jfork { function()
            signals[32]:set(91)
            await_rw()
        end }
        local right = jfork { function()
            signals[1]:set(0)
            await_rw()
        end }
        join { left, right }
        assert(signals[32]:get() == 91 and signals[1]:get() == 0)
        print("PASS immediate_callbacks_and_rw")

        check_pipeline(false)
        check_pipeline(true)
        print("PASS pipeline_both_registration_orders")

        local edge_count = 0
        local edge_waiter = jfork {
            function()
                pipeline_clock:posedge(2, function() edge_count = edge_count + 1 end)
                pipeline_clock:negedge()
                edge_count = edge_count + 1
            end,
        }
        await_time(0)
        for _ = 1, 2 do
            pipeline_clock:set(1)
            await_rw()
            pipeline_clock:set(1)
            await_rw()
            pipeline_clock:set(0)
            await_rw()
        end
        join(edge_waiter)
        assert(edge_count == 3, "same-value writes must not trigger edges")
        local before_units = sim.get_sim_time()
        await_time_ns(2)
        await_time_unit(3, "ps")
        await_time_us(1)
        assert(sim.get_sim_time() == before_units + 1002003)
        local before_delta = sim.get_sim_time()
        signals[32]:set(77)
        await_time(0)
        assert(sim.get_sim_time() == before_delta and signals[32]:get() == 77)
        local future = jfork { function() await_time(7) end }
        await_nsim()
        assert(sim.get_sim_time() == before_delta + 7, "nsim must visit the next scheduled future time")
        join(future)
        signals[32]:set(88)
        await_rd()
        assert(signals[32]:get() == 88, "RO must observe settled writes")
        await_time(1)
        signals[32]:set(89)
        await_rw()
        assert(signals[32]:get() == 89, "future time must reopen writable phase")
        print("PASS edges_and_waits")

        local stale_timer_ran = false
        local timer_id = scheduler:append_task(nil, "cancelled_timer", function()
            await_time(11)
            stale_timer_ran = true
        end, true)
        await_time(1)
        scheduler:remove_task(timer_id)
        await_time(0)
        assert(not scheduler:check_task_exists(timer_id))
        local replacement_start = sim.get_sim_time()
        local replacement_ran = false
        local reused_timer_id = scheduler:append_task(timer_id, "replacement_timer", function()
            await_time(20)
            assert(sim.get_sim_time() == replacement_start + 20, "stale timer woke reused task ID")
            replacement_ran = true
        end, true)
        assert(reused_timer_id == timer_id, "test must actually reuse the cancelled task ID")
        await_time(12)
        assert(not stale_timer_ran and not replacement_ran)
        await_time(9)
        assert(replacement_ran and not stale_timer_ran)

        local stale_edge_ran = false
        local edge_id = scheduler:append_task(nil, "cancelled_edge", function()
            stale_clock:posedge()
            stale_edge_ran = true
        end, true)
        scheduler:remove_task(edge_id)
        await_time(0)
        assert(not scheduler:check_task_exists(edge_id))
        local replacement_edges = 0
        local reused_edge_id = scheduler:append_task(edge_id, "replacement_edge", function()
            replacement_clock:posedge()
            replacement_edges = replacement_edges + 1
        end, true)
        assert(reused_edge_id == edge_id)
        stale_clock:set(1)
        await_rw()
        assert(not stale_edge_ran and replacement_edges == 0, "stale edge woke reused task ID")
        replacement_clock:set(1)
        await_rw()
        assert(not stale_edge_ran and replacement_edges == 1)
        print("PASS cancellation_and_id_reuse")

        local collision_start = sim.get_sim_time()
        ---@type table<string, integer>
        local snapshots = {}
        local observer_a = jfork {
            function()
                for _ = 1, 6 do
                    clock_a:posedge()
                    local elapsed_steps = tonumber(sim.get_sim_time() - collision_start)
                    snapshots["a" .. tostring(elapsed_steps)] = count_b:get() --[[@as integer]]
                    count_a:set((count_a:get() + 1) --[[@as integer]])
                end
            end,
        }
        local observer_b = jfork {
            function()
                for _ = 1, 2 do
                    clock_b:posedge()
                    local elapsed_steps = tonumber(sim.get_sim_time() - collision_start)
                    snapshots["b" .. tostring(elapsed_steps)] = count_a:get() --[[@as integer]]
                    count_b:set((count_b:get() + 1) --[[@as integer]])
                end
            end,
        }
        local generator_a = jfork {
            function()
                for _ = 1, 6 do
                    await_time(2)
                    clock_a:set(1)
                    await_time(2)
                    clock_a:set(0)
                end
            end,
        }
        local generator_b = jfork {
            function()
                for _ = 1, 2 do
                    await_time(6)
                    clock_b:set(1)
                    await_time(6)
                    clock_b:set(0)
                end
            end,
        }
        join { observer_a, observer_b, generator_a, generator_b }
        assert(count_a:get() == 6 and count_b:get() == 2)
        assert(snapshots.a6 == 0 and snapshots.b6 == 1, "first clock collision exposed new values")
        assert(snapshots.a18 == 1 and snapshots.b18 == 4, "second clock collision exposed new values")
        print("PASS multiclock_collisions")
        print("PASS main")
        sim.finish()
    end,
}
