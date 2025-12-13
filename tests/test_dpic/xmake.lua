---@diagnostic disable

local sim = os.getenv("SIM") or "verilator"

target("top", function()
    add_rules("verilua")
    set_default(false)

    on_config(function(target)
        if sim == "vcs" then
            target:set("toolchains", "@vcs")
        elseif sim == "xcelium" then
            target:set("toolchains", "@xcelium")
        elseif sim == "verilator" then
            target:set("toolchains", "@verilator")
            -- else
            --     raise("unknown simulator: %s", sim)
        end
    end)

    if sim == "verilator" then
        add_ldflags("-u sv_func")
    end

    add_files("top.sv")
    add_files("dpic.cpp")

    set_values("cfg.top", "top")
    set_values("cfg.lua_main", "./main.lua")
end)

target("test", function()
    set_kind("phony")
    set_default(true)

    on_build(function(target)
        -- Do nothing
    end)

    on_run(function()
        if sim ~= "vcs" and sim ~= "xcelium" and sim ~= "verilator" then
            return
        end

        os.exec("xmake b -P . top")
        local ret = os.iorun("xmake r -P . top")

        local function find_and_check(content)
            if not ret:find(content, 1, true) then
                raise("test failed, not found <%s>, output: %s", content, ret)
            end
        end
        find_and_check("[dpic_func] got: 1111")
        find_and_check("[dpic_func2] got: 2222")
        find_and_check("[sv_func] got: 3333")
        find_and_check("[dpic_func] got: 4444")

        print(ret)
    end)
end)
