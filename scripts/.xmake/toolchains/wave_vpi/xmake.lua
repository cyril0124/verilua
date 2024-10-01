
toolchain("wave_vpi")
    set_description("wave_vpi waveform simulator(for now only support VCD, FST)")
 
    on_check(function (toolchain)
        import("lib.detect.find_tool")
        local paths = {}
        for _, package in ipairs(toolchain:packages()) do
            local envs = package:get("envs")
            if envs then
                table.join2(paths, envs.PATH)
            end
        end

        local wave_vpi_main = try {
            function ()
                return os.iorun("which wave_vpi_main")
            end
        }
        
        if wave_vpi_main then
            toolchain:config_set("wave_vpi", wave_vpi_main)
            cprint("${dim}checking for wave_vpi_main ... ${color.success}%s", path.filename(wave_vpi_main))
        else
            cprint("${dim}checking for wave_vpi_main ... ${color.nothing}${text.nothing}")
            raise("[toolchain] wave_vpi_main not found!")
        end
        toolchain:configs_save()
        return true
    end)

    on_load(function (toolchain)
    end)
