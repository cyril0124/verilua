---@diagnostic disable: unnecessary-assert, need-check-nil, access-invisible, unresolved-require, undefined-field

-- Must init before any exported chdl is constructed.
local DpiExporter = require "verilua.utils.DpiExporter"
assert(DpiExporter:try_init(), "[test_dummy_vpi] DpiExporter:try_init failed")
assert(DpiExporter:dummy_vpi_linked(), "[test_dummy_vpi] dummy_vpi must be linked")

local bit = require "bit"
local band = bit.band

fork {
    function()
        local clock = dut.clock:chdl()
        local count = dut.u_top.count:chdl()
        local valid = dut.u_top.valid:chdl()
        local wide64 = dut.u_top.wide64:chdl()
        local wide128 = dut.u_top.wide128:chdl()

        assert(clock.hdl ~= nil and not clock.is_dpi_only, "clock should keep dummy_vpi hdl")
        assert(count.hdl ~= nil and not count.is_dpi_only, "count should keep dummy_vpi hdl")
        assert(valid.hdl ~= nil and not valid.is_dpi_only, "valid should keep dummy_vpi hdl")
        assert(wide64.hdl ~= nil and not wide64.is_dpi_only, "wide64 should keep dummy_vpi hdl")
        assert(wide128.hdl ~= nil and not wide128.is_dpi_only, "wide128 should keep dummy_vpi hdl")

        assert(count:get_width() == 8, "count width")
        assert(valid:get_width() == 1, "valid width")
        assert(wide64:get_width() == 64, "wide64 width")
        assert(wide128:get_width() == 128, "wide128 width")

        local function u32_words(value, nwords)
            local words = {}
            local v = math.floor(assert(tonumber(value)))
            for i = 1, nwords do
                words[i] = band(v, 0xffffffff)
                v = math.floor(v / 2 ^ 32)
            end
            return words
        end

        local function expect_hex(chdl, value, width)
            local hex = chdl:get_hex_str()
            local want_len = math.max(1, math.ceil(width / 4))
            assert(type(hex) == "string", chdl.fullpath .. " get_hex_str type")
            assert(
                #hex == want_len,
                string.format("%s get_hex_str %q len=%d want=%d", chdl.fullpath, hex, #hex, want_len)
            )
            assert(
                tonumber(hex, 16) == tonumber(value),
                string.format("%s get_hex_str %s want %s", chdl.fullpath, hex, tostring(value))
            )
        end

        local function expect_beats(chdl, beats, words)
            assert(
                tonumber(beats[0]) == #words,
                string.format("%s beat len %s want %d", chdl.fullpath, tostring(beats[0]), #words)
            )
            for i, w in ipairs(words) do
                assert(
                    tonumber(beats[i]) == w,
                    string.format("%s beat[%d] %s want %s", chdl.fullpath, i, tostring(beats[i]), tostring(w))
                )
            end
        end

        local function check_get_maps(count_v, valid_v, wide64_v, wide128_v)
            assert(count:get() == count_v, "count get")
            assert(tonumber(count:get64()) == count_v, "count get64")
            assert(valid:get() == valid_v, "valid get")
            assert(tonumber(valid:get64()) == valid_v, "valid get64")
            assert(tonumber(wide64:get()) == wide64_v, "wide64 get")
            assert(tonumber(wide64:get64()) == wide64_v, "wide64 get64")
            assert(tonumber(wide128:get64()) == wide128_v, "wide128 get64")
            expect_beats(wide64, wide64:get(true), u32_words(wide64_v, 2))
            expect_beats(wide128, wide128:get(), u32_words(wide128_v, 4))
            expect_hex(count, count_v, 8)
            expect_hex(valid, valid_v, 1)
            expect_hex(wide64, wide64_v, 64)
            expect_hex(wide128, wide128_v, 128)
        end

        -- C++ holds reset for a few half-cycles; skip until count leaves 0 after release.
        local saw_reset = false
        local c0 = 0
        for _ = 1, 32 do
            clock:posedge()
            local c = math.floor(assert(tonumber(count:get())))
            if c == 0 then
                saw_reset = true
            elseif saw_reset then
                c0 = c
                break
            end
        end
        assert(saw_reset, "never saw count==0 under reset")
        assert(c0 > 0, "count did not increment after reset")

        local w0 = tonumber(wide64:get64())
        local w128_0 = tonumber(wide128:get64())
        check_get_maps(c0, band(c0, 1), w0, w128_0)

        clock:posedge()
        local c1 = math.floor(assert(tonumber(count:get())))
        local w1 = tonumber(wide64:get64())
        local w128_1 = tonumber(wide128:get64())
        assert(c1 == band(c0 + 1, 0xff), string.format("count %s -> %s", tostring(c0), tostring(c1)))
        assert(valid:get() == band(c1, 1), "valid == count[0]")
        assert(w1 == w0 + 3, string.format("wide64 %s -> %s", tostring(w0), tostring(w1)))
        assert(w128_1 == w128_0 + 5, string.format("wide128 %s -> %s", tostring(w128_0), tostring(w128_1)))
        check_get_maps(c1, band(c1, 1), w1, w128_1)

        print("[test_dummy_vpi] PASS")
        sim.finish()
    end,
}
