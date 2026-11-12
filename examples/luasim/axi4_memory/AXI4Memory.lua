local AXI4Memory = {}

---@class AXI4MemoryOptions
---@field size_bytes integer Memory capacity in bytes, a multiple of four.
---@field stall_every? integer Deassert request ready every N cycles; zero disables stalls.

---@class AXI4MemoryBurst
---@field address integer
---@field beats integer
---@field id integer
---@field index integer

---@param bus table<string, verilua.handles.CallableHDL>
---@param channel string
---@param size_bytes integer
---@return AXI4MemoryBurst
local function capture_burst(bus, channel, size_bytes)
    local address = bus[channel .. "addr"]:get() --[[@as integer]]
    local beats = (bus[channel .. "len"]:get() + 1) --[[@as integer]]
    assert(bus[channel .. "size"]:is(2), "AXI4Memory supports 4-byte beats only")
    assert(bus[channel .. "burst"]:is(1), "AXI4Memory supports INCR bursts only")
    assert(address % 4 == 0, "AXI4Memory requires word-aligned addresses")
    assert(address + beats * 4 <= size_bytes, "AXI4Memory address out of range")
    assert(math.floor(address / 4096) == math.floor((address + beats * 4 - 1) / 4096),
        "AXI4 burst crosses a 4 KiB boundary")
    local id = bus[channel .. "id"]:get() --[[@as integer]]
    return {
        address = address,
        beats = beats,
        id = id,
        index = 0,
    }
end

--- Start a 32-bit, little-endian AXI4 memory with one outstanding burst per direction.
--- Reset aborts in-flight transactions and preserves stored bytes.
---@param clock verilua.handles.CallableHDL
---@param reset_n verilua.handles.CallableHDL
---@param bus table<string, verilua.handles.CallableHDL>
---@param options AXI4MemoryOptions
function AXI4Memory.start(clock, reset_n, bus, options)
    local size_bytes = options.size_bytes
    local stall_every = options.stall_every or 0
    assert(size_bytes > 0 and size_bytes % 4 == 0, "size_bytes must be a positive multiple of four")
    assert(stall_every == 0 or (stall_every >= 2 and stall_every == math.floor(stall_every)),
        "stall_every must be zero or an integer >= 2")

    ---@type table<integer, integer>
    local bytes = {}
    ---@type AXI4MemoryBurst?
    local write_burst
    ---@type AXI4MemoryBurst?
    local read_burst
    local response_pending = false
    local cycle = 0

    fork {
        axi4_memory = function()
            while true do
                clock:posedge()

                if reset_n:is(0) then
                    write_burst = nil
                    read_burst = nil
                    response_pending = false
                    cycle = 0
                    for _, name in ipairs({ "awready", "wready", "bvalid", "arready", "rvalid", "rlast" }) do
                        bus[name]:set(0)
                    end
                else
                    cycle = cycle + 1
                    if response_pending and bus.bready:is(1) then
                        response_pending = false
                        bus.bvalid:set(0)
                    end

                    if bus.awvalid:is(1) and bus.awready:is(1) then
                        write_burst = capture_burst(bus, "aw", size_bytes)
                    end

                    if bus.wvalid:is(1) and bus.wready:is(1) then
                        local burst = assert(write_burst)
                        local last = burst.index == burst.beats - 1
                        assert(bus.wlast:is(last and 1 or 0), "AXI4 WLAST does not match AWLEN")
                        local address = burst.address + burst.index * 4
                        local data = bus.wdata:get()
                        local strobe = bus.wstrb:get()
                        for lane = 0, 3 do
                            if math.floor(strobe / 2 ^ lane) % 2 == 1 then
                                bytes[address + lane] = math.floor(data / 256 ^ lane) % 256
                            end
                        end
                        burst.index = burst.index + 1
                        if last then
                            bus.bid:set(burst.id)
                            bus.bresp:set(0)
                            bus.bvalid:set(1)
                            response_pending = true
                            write_burst = nil
                        end
                    end

                    local publish_read = false

                    if read_burst and bus.rvalid:is(1) and bus.rready:is(1) then
                        read_burst.index = read_burst.index + 1
                        if read_burst.index == read_burst.beats then
                            read_burst = nil
                            bus.rvalid:set(0)
                            bus.rlast:set(0)
                        else
                            publish_read = true
                        end
                    end

                    if bus.arvalid:is(1) and bus.arready:is(1) then
                        read_burst = capture_burst(bus, "ar", size_bytes)
                        publish_read = true
                    end

                    if publish_read then
                        local burst = assert(read_burst)
                        local address = burst.address + burst.index * 4
                        local data = 0
                        for lane = 0, 3 do
                            data = (data + (bytes[address + lane] or 0) * 256 ^ lane) --[[@as integer]]
                        end
                        bus.rid:set(burst.id)
                        bus.rdata:set(data)
                        bus.rresp:set(0)
                        bus.rlast:set(burst.index == burst.beats - 1 and 1 or 0)
                        bus.rvalid:set(1)
                    end

                    -- All handshakes above sample the previous cycle's outputs.
                    local ready = stall_every == 0 or cycle % stall_every ~= 0
                    local accept_address = ready and write_burst == nil and not response_pending
                    local accept_data = ready and write_burst ~= nil
                    local accept_read = ready and read_burst == nil

                    bus.awready:set(accept_address and 1 or 0)
                    bus.wready:set(accept_data and 1 or 0)
                    bus.arready:set(accept_read and 1 or 0)
                end
            end
        end,
    }
end

return AXI4Memory
