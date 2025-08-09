if os.getenv("JIT_V") == "off" then
    jit.off()
end

local clock = dut.clock:chdl()

local top = dut.u_top
local reg32 = top.reg32:chdl()
local reg64 = top.reg64:chdl()
local reg128 = top.reg128:chdl()

fork {
    function()
        clock:posedge()
        local s = os.clock()

        -- Get value
        do
            local times = 10000 * 10
            for _ = 1, times do
                local v1 = reg32:get()
                local v1_u64 = reg32:get64()
                local v1_hex_str = reg32:get_hex_str()
                assert(v1 == 32)
                assert(v1_u64 == 32)
                assert(v1_hex_str)

                local v2 = reg64:get()
                local v2_u64 = reg64:get64()
                local v2_hex_str = reg64:get_hex_str()
                assert(v2 == 64)
                assert(v2_u64 == 64)
                assert(v2_hex_str)

                local v3 = reg128:get()
                local v3_u64 = reg128:get64()
                local v3_hex_str = reg128:get_hex_str()
                assert(v3)
                assert(v3_u64)
                assert(v3_hex_str)
            end
        end

        -- Set value
        do
            local times = 10000 * 10
            for i = 1, times do
                do
                    local v1 = i % 32
                    reg32:set(v1)
                    clock:posedge()
                    assert(reg32:get() == v1)

                    v1 = v1 + 1
                    reg32:set_hex_str(tostring(v1))
                    clock:posedge()
                end

                do
                    local v2 = i % 64
                    reg64:set(v2, true)
                    clock:posedge()
                    assert(reg64:get() == v2)

                    v2 = v2 + 1
                    reg64:set({ v2, 0 })
                    clock:posedge()
                    assert(reg64:get() == v2)

                    v2 = v2 + 1
                    reg64:set_hex_str(tostring(v2))
                    clock:posedge()
                end

                do
                    local v3 = i % 128
                    reg128:set(v3, true)
                    clock:posedge()
                    assert(reg128:get64() == v3)

                    v3 = v3 + 1
                    reg128:set({ v3, 0, 0, 0 })
                    clock:posedge()
                    assert(reg128:get64() == v3)

                    v3 = v3 + 1
                    reg128:set_hex_str(tostring(v3))
                    clock:posedge()
                end
            end
        end

        local e = os.clock()
        -- TODO: without startup time
        print(e - s)
        sim.finish()
    end
}
