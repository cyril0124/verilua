---@diagnostic disable: undefined-global

local lib_name   = "lua_vpi"
local prj_dir    = os.getenv("PWD")
local src_dir    = prj_dir .. "/src"
local build_dir  = prj_dir .. "/build"
local lua_dir    = prj_dir .. "/luajit2.1"
local extern_dir = prj_dir .. "/extern"
local shared_dir = prj_dir .. "/shared"
local vcpkg_dir  = prj_dir .. "/vcpkg"

local function build_common_info()
    set_kind("shared")
    set_toolchains("gcc")
    set_languages("c99", "c++20")
    set_targetdir(build_dir .. "/bin")
    set_objectdir(build_dir .. "/obj")

    add_cxflags(
        "-O2 -funroll-loops -march=native -fomit-frame-pointer",
        -- "-g -funroll-loops -march=native -fomit-frame-pointer",
        {force = true}
    )

    -- shared lib link flags (! instead of add_ldflags)
    add_shflags(
        -- "-L".. lua_dir .. "/lib" .. " -lluajit-5.1", -- dynamic link luajit2.1
        "-lrt", -- support shm_open
        "-static-libstdc++ -static-libgcc",
        "-Wl,--no-as-needed",
        {force = true}
    )

    add_defines("ACCUMULATE_LUA_TIME")

    add_files(
        lua_dir .. "/lib/libluajit-5.1.a",
        src_dir .. "/verilua/lua_vpi.cpp",
        src_dir .. "/verilua/verilator_helper.cpp",
        src_dir .. "/verilua/vpi_access.cpp",
        src_dir .. "/verilua/vpi_callback.cpp"
    )

    add_includedirs(
        src_dir .. "/include",
        lua_dir .. "/include",
        vcpkg_dir .. "/installed/x64-linux/include",
        extern_dir .. "/LuaBridge/Source",
        extern_dir .. "/LuaBridge/Source/LuaBridge"
    )

    add_links("fmt")
    add_linkdirs(vcpkg_dir .. "/installed/x64-linux/lib")

    if is_mode("debug") then
        add_defines("DEBUG")
        set_symbols("debug")
        set_optimize("none")
    end

    -- on install
    add_headerfiles(
        src_dir .. "/include/lua_vpi.h"
    )

    before_build(function (target)
        print("--------------------- [Before Build] ---------------------- ")
        os.run(string.format("mkdir %s -p", shared_dir))
        print("---------------------------------------------------------- ")
    end)

    after_build(function (target)
        print("--------------------- [After Build] ---------------------- ")

        print("* copy " .. target:targetfile() .. " into " .. shared_dir)
            os.run("cp " .. target:targetfile() .. " " .. shared_dir)
        
        print("---------------------------------------------------------- ")
    end)
end

-- 
-- Build target for VERILATOR
-- 
target(lib_name)
    add_defines("VERILATOR")
    build_common_info()


-- 
-- Build target for VCS
-- 
target(lib_name.."_vcs")
    add_defines("VCS")
    build_common_info()
