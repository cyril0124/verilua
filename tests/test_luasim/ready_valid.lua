---@diagnostic disable: unnecessary-assert

---@class LuasimTest.Ports
---@field clock verilua.handles.CallableHDL
---@field reset verilua.handles.CallableHDL
---@field request verilua.handles.Bundle
---@field response verilua.handles.Bundle

local source = assert(debug.getinfo(1, "S")).source
local fixture_dir = assert(source:match("^@(.*/)"))
local expected_file = assert(io.open(fixture_dir .. "expected-transactions.txt", "r"))
local expected_log = expected_file:read("*a")
expected_file:close()

---@return LuasimTest.Ports
local function build_luasim_ports()
    local luasim = require "verilua.luasim.Sim"

    ---@type verilua.handles.CallableHDL
    local clock
    ---@type verilua.handles.CallableHDL
    local reset
    luasim.declare(function()
        clock = luasim.signal("tb_top.clock", { width = 1, initial = 0 })
        reset = luasim.signal("tb_top.reset", { width = 1, initial = 1 })
        for _, prefix in ipairs({ "req_", "rsp_" }) do
            luasim.signal("tb_top." .. prefix .. "valid", { width = 1, initial = 0 })
            luasim.signal("tb_top." .. prefix .. "ready", { width = 1, initial = 0 })
            luasim.signal("tb_top." .. prefix .. "data", { width = 128, initial = 0 })
        end
    end)

    local request = ([[
        | valid
        | ready
        | data
    ]]):bdl {
        hier = "tb_top",
        prefix = "req_",
        name = "request",
        is_decoupled = false,
    }

    local response = ([[
        | valid
        | ready
        | data
    ]]):bdl {
        hier = "tb_top",
        prefix = "rsp_",
        name = "response",
        is_decoupled = false,
    }

    fork {
        responder = function()
            local stall_cycles = 3
            local response_delay = 0
            local pending_data = string.rep("0", 32)
            while true do
                clock:posedge()
                if reset:get() == 1 then
                    stall_cycles = 3
                    response_delay = 0
                    pending_data = string.rep("0", 32)
                    request.ready:set(0)
                    response.valid:set(0)
                    response.data:set({ 0, 0, 0, 0 })
                else
                    if stall_cycles > 0 then
                        stall_cycles = stall_cycles - 1
                        if stall_cycles == 0 then request.ready:set(1) end
                    end
                    if request.valid:get() == 1 and request.ready:get() == 1 then
                        request.ready:set(0)
                        pending_data = request.data:get_hex_str()
                        response_delay = 2
                    elseif response_delay > 0 then
                        response_delay = response_delay - 1
                        if response_delay == 0 then
                            response.data:set_hex_str(pending_data)
                            response.valid:set(1)
                        end
                    end
                    if response.valid:get() == 1 and response.ready:get() == 1 then
                        response.valid:set(0)
                        stall_cycles = 3
                    end
                end
            end
        end,
    }

    return { clock = clock, reset = reset, request = request, response = response }
end

---@return LuasimTest.Ports
local function build_rtl_ports()
    -- The normal simulator rule wraps top in tb_top, so the DUT sits under u_top there.
    local root = "tb_top"
    local request = ([[
        | valid
        | ready
        | data
    ]]):bdl {
        hier = root .. ".u_top",
        prefix = "req_",
        name = "request",
        is_decoupled = false,
    }

    local response = ([[
        | valid
        | ready
        | data
    ]]):bdl {
        hier = root .. ".u_top",
        prefix = "rsp_",
        name = "response",
        is_decoupled = false,
    }
    return {
        clock = (root .. ".clock"):chdl(),
        reset = (root .. ".reset"):chdl(),
        request = request,
        response = response,
    }
end

---@param ports LuasimTest.Ports
local function run_component(ports)
    local clock = ports.clock
    local reset = ports.reset
    local request = ports.request
    local response = ports.response
    local final_count = 0
    final {
        function()
            final_count = final_count + 1
            assert(final_count == 1)
            print("FINAL ready_valid 1")
        end,
    }

    fork {
        clock = function()
            while true do
                await_time_ns(5)
                clock:set(1)
                await_time_ns(5)
                clock:set(0)
            end
        end,
        driver = function()
            print("CASE_READY ready_valid")
            clock:negedge()
            reset:set(1)
            request.valid:set(0)
            request.data:set({ 0, 0, 0, 0 })
            response.ready:set(0)
            clock:posedge(2)

            ---@type string[]
            local transactions = {}
            local request_stalls = 0
            local response_stalls = 0
            ---@type string?
            local held_response
            for cycle = 1, 34 do
                -- Drive on falling edges and sample pre-update state on rising edges.
                clock:negedge()
                local in_reset = cycle == 15 or cycle == 16
                reset:set(in_reset and 1 or 0)
                response.ready:set(cycle >= 10 and not in_reset and 1 or 0)
                local payload
                if cycle <= 4 then
                    payload = "0123456789abcdeffedcba9876543210"
                elseif cycle >= 11 and cycle <= 14 then
                    payload = "fedcba98765432100123456789abcdef"
                elseif cycle >= 17 and cycle <= 20 then
                    payload = "80000000000000010000000000000003"
                elseif cycle >= 24 and cycle <= 27 then
                    payload = "ffffffff00000000aaaaaaaa55555555"
                end
                request.valid:set(payload and 1 or 0)
                if payload then request.data:set_hex_str(payload) end

                clock:posedge()
                if cycle == 15 then
                    transactions[#transactions + 1] = "TXN 15 RESET"
                end
                if not in_reset then
                    if request.valid:get() == 1 then
                        if request.ready:get() == 1 then
                            transactions[#transactions + 1] = string.format("TXN %02d REQ %s", cycle,
                                request.data:get_hex_str():lower())
                        elseif cycle <= 3 then
                            request_stalls = request_stalls + 1
                        end
                    end
                    if held_response then
                        assert(response.valid:get() == 1, "valid dropped while backpressured")
                        assert(response.data:get_hex_str() == held_response, "payload changed while backpressured")
                    end
                    if response.valid:get() == 1 then
                        if response.ready:get() == 1 then
                            transactions[#transactions + 1] = string.format("TXN %02d RSP %s", cycle,
                                response.data:get_hex_str():lower())
                            held_response = nil
                        else
                            response_stalls = response_stalls + 1
                            held_response = response.data:get_hex_str()
                            assert(cycle >= 7 and cycle <= 9, "response delay/backpressure cycle mismatch")
                        end
                    end
                else
                    held_response = nil
                    await_rw()
                    assert(response.valid:get() == 0 and request.ready:get() == 0,
                        "reset did not cancel in-flight response")
                end
            end
            assert(request_stalls == 3, "request must see exactly 3 initial stall cycles")
            assert(response_stalls == 3, "response must be held for exactly 3 cycles")
            local actual_log = table.concat(transactions, "\n") .. "\n"
            io.write(actual_log)
            assert(actual_log == expected_log, "fixed transaction log mismatch\nExpected:\n" .. expected_log)
            print("PASS ready_valid")
            sim.finish()
        end,
    }
end

local is_luasim = _G.cfg.simulator == "luasim"
run_component(is_luasim and build_luasim_ports() or build_rtl_ports())
