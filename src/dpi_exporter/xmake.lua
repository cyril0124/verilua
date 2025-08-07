---@diagnostic disable

local prj_dir = os.projectdir()
local curr_dir = os.scriptdir()
local build_dir = path.join(prj_dir, "build")
local libs_dir = path.join(prj_dir, "conan_installed")
local lua_dir = path.join(prj_dir, "luajit-pro", "luajit2.1")
local slang_common_dir = path.join(prj_dir, "extern", "slang-common")
local boost_unordered_dir = path.join(prj_dir, "extern", "boost_unordered")

target("dpi_exporter", function()
    set_kind("binary")
    add_ldflags("-static")

    set_languages("c99", "c++20")
    set_targetdir(path.join(build_dir, "bin"))
    set_objectdir(path.join(build_dir, "obj"))

    if is_mode("debug") then
        -- add_defines("DEBUG")
        set_symbols("debug")
        set_optimize("none")
    end

    add_files(
        path.join(curr_dir, "*.cpp"),
        path.join(curr_dir, "src", "*.cpp"),
        path.join(slang_common_dir, "*.cpp")
    )

    add_defines("SLANG_BOOST_SINGLE_HEADER")

    add_includedirs(
        slang_common_dir,
        boost_unordered_dir,
        path.join(libs_dir, "include"),
        path.join(curr_dir, "include"),
        path.join(lua_dir, "include", "luajit-2.1")
    )

    add_links("luajit-5.1")
    add_linkdirs(path.join(lua_dir, "lib"))
    add_rpathdirs(path.join(lua_dir, "lib"))

    add_links("svlang", "fmt", "mimalloc")
    add_linkdirs(path.join(libs_dir, "lib"))
    add_rpathdirs(path.join(libs_dir, "lib"))

    add_links("luajit_pro_helper")
    add_linkdirs(path.join(prj_dir, "luajit-pro", "target", "release"))
    add_rpathdirs(path.join(prj_dir, "luajit-pro", "target", "release"))

    add_links("assert", "cpptrace", "dwarf", "zstd", "z") -- libassert
    add_linkdirs(path.join(libs_dir, "lib"))
    add_rpathdirs(path.join(libs_dir, "lib"))

    before_build(function(target)
        -- Add version info
        target:add("defines", format([[VERILUA_VERSION="%s"]], io.readfile(path.join(prj_dir, "VERSION"))))
    end)

    after_build(function(target)
        os.cp(target:targetfile(), path.join(prj_dir, "tools"))
    end)
end)
