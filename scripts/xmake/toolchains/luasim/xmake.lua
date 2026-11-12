---@diagnostic disable: undefined-global, undefined-field

toolchain("luasim", function()
    set_description("Native virtual-time simulation with Lua models")

    on_check(function(toolchain)
        local home = assert(os.getenv("VERILUA_HOME"), "[toolchain] VERILUA_HOME is not set")
        local simulator = path.join(home, "tools", "luasim")
        assert(os.isfile(simulator),
            "[toolchain] native luasim simulator not found; run xmake build -P " .. home .. " luasim")
        toolchain:config_set("luasim", simulator)
        return true
    end)
end)
