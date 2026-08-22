---@diagnostic disable

toolchain("xcelium", function()
    set_description("Cadence xcelium commercial SystemVerilog simulator")

    on_check(function(toolchain)
        import("lib.detect.find_file")

        local paths = {}
        for _, package in ipairs(toolchain:packages()) do
            local envs = package:get("envs")
            if envs then
                table.join2(paths, envs.PATH)
            end
        end

        local xrun = find_file("xrun", table.join2({ paths }, "$(env PATH)"))
        if xrun then
            toolchain:config_set("xrun", xrun)
            cprint("${dim}checking for xrun ... ${color.success}%s", path.filename(xrun))
        else
            cprint("${dim}checking for xrun ... ${color.nothing}${text.nothing}")
            raise("[toolchain] xrun not found!")
        end
        toolchain:configs_save()
        return true
    end)

    on_load(function(toolchain)
    end)
end)
