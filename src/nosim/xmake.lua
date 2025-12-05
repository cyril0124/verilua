---@diagnostic disable: undefined-global, undefined-field

local prj_dir = os.projectdir()
local curr_dir = os.scriptdir()
local build_dir = path.join(prj_dir, "build")
local libs_dir = path.join(prj_dir, "conan_installed")
local lua_dir = path.join(prj_dir, "luajit-pro", "luajit2.1")
local shared_dir = path.join(prj_dir, "shared")

target("nosim", function()
    set_kind("binary")

    add_deps("libverilua_nosim", "libsignal_db_gen")

    if is_mode("debug") then
        -- add_defines("DEBUG")
        set_symbols("debug")
        set_optimize("none")
    end

    set_languages("c99", "c++20")
    set_targetdir(path.join(build_dir, "bin"))
    set_objectdir(path.join(build_dir, "obj"))

    add_files(
        path.join(curr_dir, "*.cpp")
    )

    add_includedirs(
        curr_dir,
        path.join(prj_dir, "src", "include"),
        path.join(libs_dir, "include")
    )

    add_shflags(
        "-static-libstdc++ -static-libgcc",
        "-Wl,--no-as-needed"
    )

    add_links("assert", "cpptrace", "dwarf", "zstd", "z") -- libassert
    add_linkdirs(path.join(libs_dir, "lib"))
    add_rpathdirs(path.join(libs_dir, "lib"))

    add_linkgroups("luajit-5.1", { static = true, whole = true })
    add_linkdirs(path.join(lua_dir, "lib"))

    add_links("luajit_pro_helper")
    add_linkdirs(path.join(prj_dir, "luajit-pro", "target", "release"))
    add_rpathdirs(path.join(prj_dir, "luajit-pro", "target", "release"))

    add_links("signal_db_gen")
    add_linkgroups("verilua_nosim", { as_needed = false })
    add_linkdirs(shared_dir)
    add_rpathdirs(shared_dir)

    before_build(function(target)
        -- Add version info
        local version = io.readfile(path.join(prj_dir, "VERSION")):trim()
        target:add("defines", format([[VERILUA_VERSION="%s"]], version))
    end)

    after_build(function(target)
        os.cp(target:targetfile(), path.join(prj_dir, "tools"))
    end)
end)
