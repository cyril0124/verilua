---@diagnostic disable

local prj_dir = os.projectdir()
local curr_dir = os.scriptdir()
local build_dir = path.join(prj_dir, "build")
local libs_dir = path.join(prj_dir, "conan_installed")
local lua_dir = path.join(prj_dir, "luajit-pro", "luajit2.1")
local slang_common_dir = path.join(prj_dir, "extern", "slang-common")
local boost_unordered_dir = path.join(prj_dir, "extern", "boost_unordered")

local function signal_db_gen_common()
    if is_mode("debug") then
        -- add_defines("DEBUG")
        set_symbols("debug")
        set_optimize("none")
    end

    set_languages("c99", "c++20")
    set_targetdir(path.join(build_dir, "bin"))
    set_objectdir(path.join(build_dir, "obj"))

    add_files(
        path.join(curr_dir, "*.cpp"),
        path.join(slang_common_dir, "*.cpp")
    )

    add_defines("SLANG_BOOST_SINGLE_HEADER")

    add_includedirs(
        curr_dir,
        slang_common_dir,
        boost_unordered_dir,
        path.join(libs_dir, "include"),
        path.join(lua_dir, "include", "luajit-2.1")
    )

    add_links("svlang", "fmt", "mimalloc")
    add_links("assert", "cpptrace", "dwarf", "zstd", "z") -- libassert
    add_linkdirs(path.join(libs_dir, "lib"))
    add_rpathdirs(path.join(libs_dir, "lib"))

    add_links("luajit-5.1")
    add_linkdirs(path.join(lua_dir, "lib"))
    add_rpathdirs(path.join(lua_dir, "lib"))

    add_links("luajit_pro_helper")
    add_linkdirs(path.join(prj_dir, "luajit-pro", "target", "release"))
    add_rpathdirs(path.join(prj_dir, "luajit-pro", "target", "release"))
end


target("signal_db_gen")
    set_kind("binary")
    add_ldflags("-static")

    signal_db_gen_common()

    after_build(function (target)
        os.cp(target:targetfile(), path.join(prj_dir, "tools"))
    end)

target("libsignal_db_gen")
    set_kind("shared")
    set_filename("libsignal_db_gen.so")
    add_defines("SO_LIB")

    signal_db_gen_common()

    after_build(function (target)
        os.cp(target:targetfile(), path.join(prj_dir, "shared"))
    end)

