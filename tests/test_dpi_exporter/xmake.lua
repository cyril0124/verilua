---@diagnostic disable

target("test", function()
    set_kind("phony")
    on_run(function(target)
        local rtl = path.join(os.scriptdir(), "top.sv")
        local cfgs = os.files(path.join(os.scriptdir(), "dpi_cfgs", "*.lua"))
        for _, cfg in ipairs(cfgs) do
            local cmd = format("dpi_exporter %s -c %s --no-cache", rtl, cfg)
            os.exec(cmd)
            os.exec(cmd .. " -q")

            -- Another clock signal
            os.exec(cmd .. " -q --top-clock clk")

            -- Another sample edge
            os.exec(cmd .. " -q --sample-edge negedge")

            -- PLDM gfifo
            os.exec(cmd .. " -q --pldm-gfifo-dpi")
        end
    end)
end)
