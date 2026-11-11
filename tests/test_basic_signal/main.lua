local utils = require "verilua.LuaUtils"

local clock = dut.clock:chdl()

if os.getenv("VL_XMK_NO_INTERNAL_CLOCK") then
    if os.getenv("VL_XMK_USE_NATIVE_CLOCK") then
        local NativeClock = require "verilua.utils.NativeClock"
        NativeClock(clock):start(2, "ns")
    else
        fork {
            function()
                while true do
                    clock:set(1)
                    await_time(1)
                    clock:set(0)
                    await_time(1)
                end
            end,
        }
    end
end

fork {
    function()
        local test = function()
            local type_vec = { "reg", "bit", "logic" }
            local bitwidth_vec = { 1, 8, 16, 32, 64, 68, 128 }
            local value_type_vec = { "number", "number", "number", "number", "cdata", "cdata", "cdata" }
            for _, typ in ipairs(type_vec) do
                for i, bitwidth in ipairs(bitwidth_vec) do
                    local s = dut.u_top[typ .. bitwidth]:chdl()
                    local v = s:get()

                    assert(s:get_width() == bitwidth)
                    assert(type(v) == value_type_vec[i],
                        "type(v) == " .. type(v) .. " for " .. typ .. bitwidth .. " " .. bitwidth)

                    if bitwidth <= 64 then
                        assert(v == bitwidth, tonumber(v) .. " != " .. bitwidth .. " for " .. typ .. bitwidth)
                    else
                        local v = s:get()
                        local v_hex_str = s:get_hex_str()
                        assert(ffi.istype("uint32_t[]", v))
                        assert(utils.compare_value_str("0x" .. v_hex_str, "0x" .. bit.tohex(bitwidth)))
                    end
                end
            end
        end

        -- Skip initial phase
        clock:posedge()
        test()

        clock:posedge()
        test()

        clock:posedge(100)
        test()

        local reg8 = dut.u_top.reg8:chdl()
        reg8:set(0x12)
        reg8:expect(8)
        clock:posedge()
        reg8:expect(0x12) -- value is not updated until the next clock cycle for <chdl>:set()

        reg8:set_imm(0x10)
        reg8:expect(0x10) -- value is updated immediately for <chdl>:set_imm()
        clock:posedge()
        reg8:expect(0x10)

        reg8:set_imm(0xaa)
        reg8:expect(0xaa)
        reg8:set_imm(0xbb)
        reg8:expect(0xbb) -- newly set value is updated immediately for <chdl>:set_imm()
        reg8:set(0xbb)
        clock:posedge()
        reg8:expect(0xbb)

        for i = 1, 10 do
            reg8:set(i)
        end

        local vec_reg = dut.u_top.vec_reg:chdl()
        for i = 0, vec_reg.array_size - 1 do
            assert(vec_reg[i]:is(i))
        end

        -- TODO: 2D vec
        -- local three_dim_reg = dut.u_top.three_dim_reg:chdl()
        -- for i = 0, three_dim_reg.array_size - 1 do
        --     for j = 0, three_dim_reg.array_size - 1 do
        --         assert(three_dim_reg[i][j]:is(i * 4 + j))
        --     end
        -- end

        -- Test randomize
        local function test_randomize(is_imm)
            local reg4 = dut.u_top.reg4:chdl()
            local values = {}
            for _ = 1, 200 do
                if not is_imm then
                    reg4:randomize()
                    clock:posedge()
                else
                    reg4:randomize_imm()
                end
                values[reg4:get()] = true
            end
            -- All possible values should be set
            assert(table.nkeys(values) == 16)
        end
        test_randomize()
        test_randomize(true)

        local function test_randomize_with_shuffle_range_u32(is_imm)
            local reg4 = dut.u_top.reg4:chdl()
            reg4:shuffled_range_u32({ 4, 1 })
            reg4:shuffled_range_u32({ 4, 1, 3, 2, 10 }) -- Newer range will overwrite the previous one
            local values = {}
            for _ = 1, 200 do
                if not is_imm then
                    reg4:randomize()
                    clock:posedge()
                else
                    reg4:randomize_imm()
                end
                values[reg4:get()] = true
            end
            assert(table.nkeys(values) == 5)

            -- shuffled range with single value
            local full_mask = tonumber(utils.bitmask(#reg4))
            reg4:shuffled_range_u32({ full_mask })
            table.clear(values)
            for _ = 1, 50 do
                reg4:randomize()
                clock:posedge()
                values[reg4:get()] = true
            end
            assert(table.nkeys(values) == 1)
            local v, _ = next(values)
            assert(v == full_mask)
        end
        test_randomize_with_shuffle_range_u32()
        test_randomize_with_shuffle_range_u32(true)

        dut.u_top.reg4:chdl():reset_shuffled_range()
        test_randomize()

        local function test_randomize_with_shuffle_range_u64(is_imm)
            local reg64 = dut.u_top.reg64:chdl()
            reg64:shuffled_range_u64({ 64, 1, 3, 2, 10ULL, 0xFFFFFFFFFFFFFFFFULL })
            local values = {}
            for _ = 1, 200 do
                if not is_imm then
                    reg64:randomize()
                    clock:posedge()
                else
                    reg64:randomize_imm()
                end
                values[reg64:get_hex_str()] = true
            end
            assert(table.nkeys(values) == 6)

            -- shuffled range with single value
            local full_mask = utils.bitmask(#reg64)
            reg64:shuffled_range_u64({ full_mask })
            table.clear(values)
            for _ = 1, 50 do
                reg64:randomize()
                clock:posedge()
                values[reg64:get_hex_str()] = true
            end
            assert(table.nkeys(values) == 1)
            local v_hex_str, _ = next(values)
            assert(v_hex_str == utils.to_hex_str(full_mask))
        end
        test_randomize_with_shuffle_range_u64()
        test_randomize_with_shuffle_range_u64(true)

        local function test_randomize_with_shuffle_range_hex_str(is_imm)
            local reg64 = dut.u_top.reg64:chdl()
            reg64:shuffled_range_hex_str({ "1", "2", "3", "deadbeef", "40", "ffffffffffffffff" })
            local values = {}
            for _ = 1, 200 do
                if not is_imm then
                    reg64:randomize()
                    clock:posedge()
                else
                    reg64:randomize_imm()
                end
                values[reg64:get_hex_str()] = true
            end
            assert(table.nkeys(values) == 6)
        end
        test_randomize_with_shuffle_range_hex_str()
        test_randomize_with_shuffle_range_hex_str(true)


        -- TODO: Freeze/Force/Release signal

        -- await_edge_hdl() must wake on any value change of a multi-bit signal.
        -- A registered callback is installed at the next write/sync, so every wake
        -- gets one extra clock edge before the next write.
        local function test_await_edge_any_change()
            local reg32 = dut.u_top.reg32:chdl()
            local values = { 3, 0x80000000, 0xffffffff }
            local woke = 0
            local waiters = {}
            for i = 1, 17 do -- 17 waiters split the chunked registration into 16 + 1
                waiters[i] = jfork { function()
                    for _, v in ipairs(values) do
                        await_edge_hdl(reg32.hdl)
                        reg32:expect(v)
                        woke = woke + 1
                    end
                end }
            end
            clock:posedge() -- install the pending edge callbacks
            for round, v in ipairs(values) do
                reg32:set(v)
                clock:posedge() -- change lands, waiters wake and re-register
                clock:posedge() -- re-registration installs
                assert(woke == 17 * round, "multi-bit change missed")

                reg32:set(v) -- same value: no change, no wakeup
                clock:posedge()
                clock:posedge()
                assert(woke == 17 * round, "unchanged value woke waiter")
            end
            join(waiters)

            -- Upper-word-only change: the low 32 bits stay unchanged.
            local reg128 = dut.u_top.reg128:chdl()
            reg128:set_hex_str("80000000000000000000000000000003")
            clock:posedge()
            local wide_woke = false
            local wide_waiter = jfork { function()
                await_edge_hdl(reg128.hdl)
                reg128:expect_hex_str("40000000000000000000000100000003")
                wide_woke = true
            end }
            clock:posedge()
            reg128:set_hex_str("40000000000000000000000100000003")
            clock:posedge()
            clock:posedge()
            assert(wide_woke, "upper-bit change missed")
            join(wide_waiter)

            -- posedge must still filter by value on a multi-bit signal.
            local posedges = 0
            local posedge_waiter = jfork { function()
                await_posedge_hdl(reg32.hdl)
                posedges = posedges + 1
            end }
            clock:posedge()
            reg32:set(0xff) -- not 1: no posedge
            clock:posedge()
            clock:posedge()
            assert(posedges == 0, "posedge fired on a non-1 value")
            reg32:set(1)
            clock:posedge()
            clock:posedge()
            assert(posedges == 1, "posedge missed value 1")
            join(posedge_waiter)
        end
        test_await_edge_any_change()

        sim.finish()
    end
}
