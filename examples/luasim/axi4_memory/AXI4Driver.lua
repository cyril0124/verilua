local NativeClock = require "verilua.utils.NativeClock"

---@param clock verilua.handles.CallableHDL
---@param reset_n verilua.handles.CallableHDL
---@param axi table<string, verilua.handles.CallableHDL>
local function run(clock, reset_n, axi)
    local trace = assert(io.open("axi4_trace.csv", "w"))
    local fields = {}
    for name in pairs(axi) do
        fields[#fields + 1] = name
    end
    table.sort(fields)
    trace:write("cycle,time,reset_n,", table.concat(fields, ","), "\n")

    fork {
        trace_axi = function()
            local cycle = 0
            while true do
                clock:posedge()
                cycle = cycle + 1

                local values = {
                    tostring(cycle),
                    tostring(sim.get_sim_time()),
                    tostring(reset_n:get()),
                }
                for _, name in ipairs(fields) do
                    values[#values + 1] = tostring(axi[name]:get())
                end
                trace:write(table.concat(values, ","), "\n")
            end
        end,
    }

    local clock_driver = NativeClock(clock)
    clock_driver:start(10, "ns", { start_high = false })

    final {
        function()
            clock_driver:destroy()
            trace:close()
        end,
    }

    ---@param valid verilua.handles.CallableHDL
    ---@param ready verilua.handles.CallableHDL
    local function handshake(valid, ready)
        repeat
            clock:posedge()
        until valid:is(1) and ready:is(1)
    end

    ---@param address integer
    ---@param words integer[]
    ---@param id integer
    ---@param strobes? integer[]
    ---@param address_delay? integer
    local function write_burst(address, words, id, strobes, address_delay)
        clock:negedge()
        axi.bready:set(0)

        local address_task = jfork {
            function()
                if address_delay then
                    clock:negedge(address_delay)
                end

                axi.awid:set(id)
                axi.awaddr:set(address)
                axi.awlen:set(#words - 1)
                axi.awsize:set(2)
                axi.awburst:set(1)
                axi.awvalid:set(1)

                handshake(axi.awvalid, axi.awready)
                clock:negedge()
                axi.awvalid:set(0)
            end,
        }

        local data_task = jfork {
            function()
                for index, word in ipairs(words) do
                    local strobe = 15
                    if strobes then
                        strobe = strobes[index] or 15
                    end

                    axi.wdata:set(word)
                    axi.wstrb:set(strobe)
                    axi.wlast:set(index == #words and 1 or 0)
                    axi.wvalid:set(1)

                    handshake(axi.wvalid, axi.wready)
                    clock:negedge()
                end

                axi.wvalid:set(0)
            end,
        }

        join { address_task, data_task }

        repeat
            clock:posedge()
        until axi.bvalid:is(1)

        for _ = 1, 3 do
            axi.bvalid:expect(1)
            axi.bid:expect(id)
            axi.bresp:expect(0)
            clock:posedge()
        end

        clock:negedge()
        axi.bready:set(1)
        handshake(axi.bvalid, axi.bready)

        clock:negedge()
        axi.bready:set(0)
        print(string.format("WRITE id=%d address=0x%03x beats=%d", id, address, #words))
    end

    ---@param address integer
    ---@param expected integer[]
    ---@param id integer
    local function read_burst(address, expected, id)
        clock:negedge()
        axi.arid:set(id)
        axi.araddr:set(address)
        axi.arlen:set(#expected - 1)
        axi.arsize:set(2)
        axi.arburst:set(1)
        axi.arvalid:set(1)
        axi.rready:set(0)

        handshake(axi.arvalid, axi.arready)
        clock:negedge()
        axi.arvalid:set(0)

        for index, word in ipairs(expected) do
            repeat
                clock:posedge()
            until axi.rvalid:is(1)

            for _ = 1, 2 do
                axi.rvalid:expect(1)
                axi.rid:expect(id)
                axi.rresp:expect(0)
                axi.rdata:expect(word)
                axi.rlast:expect(index == #expected and 1 or 0)
                clock:posedge()
            end

            clock:negedge()
            axi.rready:set(1)
            handshake(axi.rvalid, axi.rready)
            axi.rdata:expect(word)

            clock:negedge()
            axi.rready:set(0)
        end

        print(string.format("READ  id=%d address=0x%03x beats=%d", id, address, #expected))
    end

    fork {
        test = function()
            if cfg.simulator ~= "luasim" then
                sim.dump_wave("axi4_memory.vcd")
            end

            reset_n:set(0)
            clock:negedge(3)
            reset_n:set(1)
            read_burst(0, { 0, 0, 0, 0 }, 1)

            local original = { 0x11223344, 0x55667788, 0x99aabbcc, 0xddeeff00 }
            write_burst(0x40, original, 2, nil, 3)
            read_burst(0x40, original, 3)

            local update = { 0xffeeddcc, 0xffffffff, 0x12345678, 0x01020304 }
            local strobes = { 5, 0, 10, 15 }
            local merged = { 0x11ee33cc, 0x55667788, 0x12aa56cc, 0x01020304 }
            write_burst(0x40, update, 4, strobes)
            read_burst(0x40, merged, 5)

            local words = {}
            for index = 1, 32 do
                words[index] = index * 0x01010101
            end

            local writer = jfork {
                function()
                    write_burst(0x100, words, 6)
                end,
            }
            local reader = jfork {
                function()
                    read_burst(0x40, merged, 7)
                end,
            }

            join { writer, reader }
            read_burst(0x100, words, 8)

            write_burst(0xffc, { 0xdeadbeef }, 9)
            read_burst(0xffc, { 0xdeadbeef }, 10)

            clock:negedge()
            reset_n:set(0)
            clock:negedge(2)
            reset_n:set(1)
            read_burst(0xffc, { 0xdeadbeef }, 11)

            print("PASS: AXI4Memory bursts, WSTRB, channel backpressure, concurrent read/write and reset")
            sim.finish()
        end,

        watchdog = function()
            await_time_ns(20000)
            error("AXI4Memory example timed out")
        end,
    }
end

return run
