---@diagnostic disable: undefined-global, undefined-field

local root = os.projectdir()
local current = os.scriptdir()

target("luasim", function()
    set_kind("binary")
    set_languages("c++20")
    add_deps("libverilua_luasim")
    if is_mode("release") then
        set_optimize("fastest")
    end

    set_targetdir(path.join(root, "build", "bin"))
    set_objectdir(path.join(root, "build", "obj"))

    add_files(path.join(current, "*.cpp"))
    add_includedirs(current, path.join(root, "src", "include"))

    add_ldflags("-rdynamic", "-Wl,--no-as-needed", { force = true })
    add_links("verilua_luasim", "luajit-5.1", "dl", "pthread")
    add_linkdirs(path.join(root, "shared"), path.join(root, "luajit", "lib"))
    add_rpathdirs(path.join(root, "shared"), path.join(root, "luajit", "lib"))

    before_build(function(target)
        local version = io.readfile(path.join(root, "VERSION")):trim()
        target:add("defines", format([[VERILUA_VERSION="%s"]], version))
    end)

    after_build(function(target)
        os.cp(target:targetfile(), path.join(root, "tools", "luasim"))
    end)
end)
