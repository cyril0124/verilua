local utils = require "LuaUtils"

local clock = dut.clock:chdl()

if os.getenv("NO_INTERNAL_CLOCK") then
    fork {
        function()
            while true do
                clock:set(1)
                await_time(1)
                clock:set(0)
                await_time(1)
            end
        end
    }
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
            assert(vec_reg:at(i):is(i))
        end

        -- TODO: 2D vec
        -- local three_dim_reg = dut.u_top.three_dim_reg:chdl()
        -- for i = 0, three_dim_reg.array_size - 1 do
        --     for j = 0, three_dim_reg.array_size - 1 do
        --         assert(three_dim_reg:at(i, j):is(i * 4 + j))
        --     end
        -- end

        -- Test set_shuffled
        local function test_set_shuffled(is_imm)
            local reg4 = dut.u_top.reg4:chdl()
            local values = {}
            for _ = 1, 200 do
                if not is_imm then
                    reg4:set_shuffled()
                    clock:posedge()
                else
                    reg4:set_imm_shuffled()
                end
                values[reg4:get()] = true
            end
            -- All possible values should be set
            assert(table.nkeys(values) == 16)
        end
        test_set_shuffled()
        test_set_shuffled(true)

        local function test_set_shuffled_with_shuffle_range_u32(is_imm)
            local reg4 = dut.u_top.reg4:chdl()
            reg4:shuffled_range_u32({ 4, 1 })
            reg4:shuffled_range_u32({ 4, 1, 3, 2, 10 }) -- Newer range will overwrite the previous one
            local values = {}
            for _ = 1, 200 do
                if not is_imm then
                    reg4:set_shuffled()
                    clock:posedge()
                else
                    reg4:set_imm_shuffled()
                end
                values[reg4:get()] = true
            end
            assert(table.nkeys(values) == 5)

            -- shuffled range with single value
            local full_mask = tonumber(utils.bitmask(#reg4))
            reg4:shuffled_range_u32({ full_mask })
            table.clear(values)
            for _ = 1, 50 do
                reg4:set_shuffled()
                clock:posedge()
                values[reg4:get()] = true
            end
            assert(table.nkeys(values) == 1)
            local v, _ = next(values)
            assert(v == full_mask)
        end
        test_set_shuffled_with_shuffle_range_u32()
        test_set_shuffled_with_shuffle_range_u32(true)

        dut.u_top.reg4:chdl():reset_shuffled_range()
        test_set_shuffled()

        local function test_set_shuffled_with_shuffle_range_u64(is_imm)
            local reg64 = dut.u_top.reg64:chdl()
            reg64:shuffled_range_u64({ 64, 1, 3, 2, 10ULL, 0xFFFFFFFFFFFFFFFFULL })
            local values = {}
            for _ = 1, 200 do
                if not is_imm then
                    reg64:set_shuffled()
                    clock:posedge()
                else
                    reg64:set_imm_shuffled()
                end
                values[reg64:get_hex_str()] = true
            end
            assert(table.nkeys(values) == 6)

            -- shuffled range with single value
            local full_mask = utils.bitmask(#reg64)
            reg64:shuffled_range_u64({ full_mask })
            table.clear(values)
            for _ = 1, 50 do
                reg64:set_shuffled()
                clock:posedge()
                values[reg64:get_hex_str()] = true
            end
            assert(table.nkeys(values) == 1)
            local v_hex_str, _ = next(values)
            assert(v_hex_str == utils.to_hex_str(full_mask))
        end
        test_set_shuffled_with_shuffle_range_u64()
        test_set_shuffled_with_shuffle_range_u64(true)

        local function test_set_shuffled_with_shuffle_range_hex_str(is_imm)
            local reg64 = dut.u_top.reg64:chdl()
            reg64:shuffled_range_hex_str({ "1", "2", "3", "deadbeef", "40", "ffffffffffffffff" })
            local values = {}
            for _ = 1, 200 do
                if not is_imm then
                    reg64:set_shuffled()
                    clock:posedge()
                else
                    reg64:set_imm_shuffled()
                end
                values[reg64:get_hex_str()] = true
            end
            assert(table.nkeys(values) == 6)
        end
        test_set_shuffled_with_shuffle_range_hex_str()
        test_set_shuffled_with_shuffle_range_hex_str(true)


        -- TODO: Freeze/Force/Release signal

        sim.finish()
    end
}
