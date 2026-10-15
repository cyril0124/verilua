---@diagnostic disable: unnecessary-assert, need-check-nil, access-invisible, unresolved-require, undefined-field

-- Must init before any mon chdl is constructed.
local DpiExporter = require "verilua.utils.DpiExporter"
assert(DpiExporter:try_init(), "[test_dpi_exporter_chdl] DpiExporter:try_init failed")
assert(not DpiExporter:dummy_vpi_linked(), "test_dpi_exporter_chdl must not link dummy_vpi")

local bit = require "bit"
local band = bit.band

fork {
    function()
        local clock = dut.clock:chdl()
        local reset = dut.reset:chdl()

        -- Exported mon signals: dpi-only construct (no VPI handle).
        local count = dut.u_top.count:chdl()
        local valid = dut.u_top.valid:chdl()
        local wide64 = dut.u_top.wide64:chdl()
        local wide128 = dut.u_top.wide128:chdl()

        -- meta_only signal: meta from the dpi table, no DPI accessor generated;
        -- value access falls back to the real VPI handle in this flow.
        local meta16 = dut.u_top.meta16:chdl()

        assert(count.hdl == nil and count.is_dpi_only, "count should be dpi-only (hdl nil)")
        assert(valid.hdl == nil and valid.is_dpi_only, "valid should be dpi-only (hdl nil)")
        assert(wide64.hdl == nil and wide64.is_dpi_only, "wide64 should be dpi-only (hdl nil)")
        assert(wide128.hdl == nil and wide128.is_dpi_only, "wide128 should be dpi-only (hdl nil)")

        assert(count:get_width() == 8, "count width")
        assert(valid:get_width() == 1, "valid width")
        assert(wide64:get_width() == 64, "wide64 width")
        assert(wide128:get_width() == 128, "wide128 width")
        assert(count.hdl_type == "vpiReg" or count.hdl_type == "vpiNet", count.hdl_type)
        assert(valid.hdl_type == "vpiReg" or valid.hdl_type == "vpiNet", valid.hdl_type)

        -- Clock still uses VPI (not exported for edge).
        assert(clock.hdl ~= nil and not clock.is_dpi_only, "clock should keep VPI handle")

        -- meta_only construct: dpi meta + VPI value path, never dpi-only.
        local SymbolHelper = require "verilua.utils.SymbolHelper"
        local meta16_info = DpiExporter:lookup(meta16.fullpath)
        assert(meta16_info ~= nil, "meta16 must be in the dpi meta table")
        assert(meta16_info.metaOnly == true, "meta16 must be marked metaOnly")
        assert(meta16.hdl ~= nil and not meta16.is_dpi_only, "meta16 should keep VPI handle")
        assert(meta16:get_width() == 16, "meta16 width from dpi meta")
        assert(
            SymbolHelper.get_global_symbol_addr("VERILUA_DPI_EXPORTER_top_meta16_GET") == 0,
            "meta16 must have no generated DPI accessor"
        )

        -- lookup: raw exporter path + normalized sim fullpath
        local info_norm = DpiExporter:lookup(count.fullpath)
        assert(info_norm ~= nil, "lookup(fullpath) miss: " .. count.fullpath)
        assert(info_norm.bitWidth == 8)
        assert(info_norm.hierPath == "top.count" or info_norm.hierPath:find("count", 1, true))

        local info_raw = DpiExporter:lookup(info_norm.hierPath)
        assert(info_raw == info_norm)

        assert(DpiExporter:lookup("tb_top.u_top.not_exported") == nil)

        -- Passed hdl is ignored for exported signals (dpi-only still).
        local fake_hdl = clock.hdl
        local count2 = require("verilua.handles.LuaCallableHDL")(count.fullpath, "count2", fake_hdl)
        assert(count2.hdl == nil and count2.is_dpi_only, "export hit must ignore passed hdl")

        -- dummy_vpi GET / GET64 / GET_VEC / GET_HEX_STR -> chdl get*
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
            local fails = {}
            local function check(name, fn)
                local ok, err = pcall(fn)
                if not ok then
                    fails[#fails + 1] = name .. ": " .. tostring(err)
                end
            end

            -- GET / GET64
            check("count get", function()
                assert(count:get() == count_v, "count get")
            end)
            check("count get64", function()
                assert(tonumber(count:get64()) == count_v, "count get64")
            end)
            check("valid get", function()
                assert(valid:get() == valid_v, "valid get")
            end)
            check("valid get64", function()
                assert(tonumber(valid:get64()) == valid_v, "valid get64")
            end)
            check("wide64 get", function()
                assert(tonumber(wide64:get()) == wide64_v, "wide64 get")
            end)
            check("wide64 get64", function()
                assert(tonumber(wide64:get64()) == wide64_v, "wide64 get64")
            end)
            check("wide128 get64", function()
                assert(tonumber(wide128:get64()) == wide128_v, "wide128 get64")
            end)

            -- GET_VEC
            check("wide64 get(true)", function()
                expect_beats(wide64, wide64:get(true), u32_words(wide64_v, 2))
            end)
            check("wide128 get", function()
                expect_beats(wide128, wide128:get(), u32_words(wide128_v, 4))
            end)

            -- GET_HEX_STR
            check("count get_hex_str", function()
                expect_hex(count, count_v, 8)
            end)
            check("valid get_hex_str", function()
                expect_hex(valid, valid_v, 1)
            end)
            check("wide64 get_hex_str", function()
                expect_hex(wide64, wide64_v, 64)
            end)
            check("wide128 get_hex_str", function()
                expect_hex(wide128, wide128_v, 128)
            end)

            if #fails > 0 then
                error("get* mapping failures:\n  " .. table.concat(fails, "\n  "), 0)
            end
        end

        -- Functional: reset, then get* tracks RTL via DPI.
        reset:set_imm(1)
        clock:posedge(3)
        check_get_maps(0, 0, 0, 0)

        reset:set_imm(0)
        clock:posedge()
        local c0 = count:get()
        local w0 = tonumber(wide64:get64())
        local w128_0 = tonumber(wide128:get64())
        local m0 = tonumber(meta16:get())
        assert(type(c0) == "number")

        clock:posedge()
        local c1 = count:get()
        local w1 = tonumber(wide64:get64())
        local w128_1 = tonumber(wide128:get64())
        local m1 = tonumber(meta16:get())
        assert(c1 == band(c0 + 1, 0xff), string.format("count %s -> %s", tostring(c0), tostring(c1)))
        assert(valid:get() == band(c1, 1), "valid == count[0]")
        assert(w1 == w0 + 3, string.format("wide64 %s -> %s", tostring(w0), tostring(w1)))
        assert(w128_1 == w128_0 + 5, string.format("wide128 %s -> %s", tostring(w128_0), tostring(w128_1)))
        assert(m1 == m0 + 2, string.format("meta16 %s -> %s (VPI value path)", tostring(m0), tostring(m1)))
        check_get_maps(c1, band(c1, 1), w1, w128_1)

        clock:posedge(5)
        local c_end = count:get()
        assert(c_end == band(c1 + 5, 0xff), string.format("count after 5: %s", tostring(c_end)))
        check_get_maps(
            c_end,
            band(c_end, 1),
            w1 + 15,
            w128_1 + 25
        )

        print("[test_dpi_exporter_chdl] PASS")
        sim.finish()
    end,
}
