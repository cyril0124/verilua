---@diagnostic disable: undefined-global, undefined-field

toolchain("nosim", function()
    -- TODO: add description
    set_description("`nosim`")

    on_check(function(toolchain)
        import("lib.detect.find_file")

        local paths = {}
        for _, package in ipairs(toolchain:packages()) do
            local envs = package:get("envs")
            if envs then
                table.join2(paths, envs.PATH)
            end
        end

        local nosim = find_file("nosim", table.join2({ paths }, "$(env PATH)"))
        if nosim then
            toolchain:config_set("nosim", nosim)
            cprint("${dim}checking for nosim ... ${color.success}%s", path.filename(wave_vpi_main))
        else
            cprint("${dim}checking for nosim ... ${color.nothing}${text.nothing}")
            raise("[toolchain] nosim not found!")
        end
        toolchain:configs_save()
        return true
    end)

    on_load(function(toolchain)
    end)
end)
