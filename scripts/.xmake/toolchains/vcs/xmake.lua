---@diagnostic disable

toolchain("vcs")
    set_description("Synopsys VCS commercial SystemVerilog simulator")
 
    on_check(function (toolchain)
        import("lib.detect.find_file")

        local paths = {}
        for _, package in ipairs(toolchain:packages()) do
            local envs = package:get("envs")
            if envs then
                table.join2(paths, envs.PATH)
            end
        end

        local vcs = find_file("vcs", table.join2({paths}, "$(env PATH)"))
        if vcs then
            toolchain:config_set("vcs", vcs)
            cprint("${dim}checking for vcs ... ${color.success}%s", path.filename(vcs))
        else
            cprint("${dim}checking for vcs ... ${color.nothing}${text.nothing}")
            raise("[toolchain] vcs not found!")
        end
        toolchain:configs_save()
        return true
    end)

    on_load(function (toolchain)
    end)
