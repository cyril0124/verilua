---@diagnostic disable: unnecessary-assert, need-check-nil, access-invisible, unresolved-require

-- Must init before any mon chdl is constructed.
local DpiExporter = require "verilua.utils.DpiExporter"
assert(DpiExporter:try_init(), "[test_dpi_exporter_chdl] DpiExporter:try_init failed")

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

        assert(count.hdl == nil, "count should be dpi-only (hdl nil)")
        assert(valid.hdl == nil, "valid should be dpi-only (hdl nil)")
        assert(wide64.hdl == nil, "wide64 should be dpi-only (hdl nil)")

        assert(count:get_width() == 8, "count width")
        assert(valid:get_width() == 1, "valid width")
        assert(wide64:get_width() == 64, "wide64 width")
        assert(count.hdl_type == "vpiReg" or count.hdl_type == "vpiNet", count.hdl_type)
        assert(valid.hdl_type == "vpiReg" or valid.hdl_type == "vpiNet", valid.hdl_type)

        -- Clock still uses VPI (not exported for edge).
        assert(clock.hdl ~= nil, "clock should keep VPI handle")

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
        assert(count2.hdl == nil, "export hit must ignore passed hdl")

        -- Functional: reset, then get() tracks RTL counter via DPI.
        reset:set_imm(1)
        clock:posedge(3)
        assert(count:get() == 0, "count under reset")
        assert(valid:get() == 0, "valid under reset")
        assert(tonumber(wide64:get64()) == 0, "wide64 under reset")

        reset:set_imm(0)
        clock:posedge()
        local c0 = count:get()
        local w0 = tonumber(wide64:get64())
        assert(type(c0) == "number")

        clock:posedge()
        local c1 = count:get()
        local w1 = tonumber(wide64:get64())
        assert(c1 == band(c0 + 1, 0xff), string.format("count %s -> %s", tostring(c0), tostring(c1)))
        assert(valid:get() == band(c1, 1), "valid == count[0]")
        assert(w1 == w0 + 3, string.format("wide64 %s -> %s", tostring(w0), tostring(w1)))

        clock:posedge(5)
        local c_end = count:get()
        assert(c_end == band(c1 + 5, 0xff), string.format("count after 5: %s", tostring(c_end)))

        print("[test_dpi_exporter_chdl] PASS")
        sim.finish()
    end,
}
