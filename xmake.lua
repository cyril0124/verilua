---@diagnostic disable: undefined-global

local lib_name   = "lua_vpi"
local prj_dir    = os.getenv("PWD")
local src_dir    = prj_dir .. "/src"
local build_dir  = prj_dir .. "/build"
local lua_dir    = prj_dir .. "/luajit2.1"
local extern_dir = prj_dir .. "/extern"
local shared_dir = prj_dir .. "/shared"


local function build_common_info()
    before_build(function (target)
        print("--------------------- [Before Build] ---------------------- ")
        os.run(string.format("mkdir %s -p", shared_dir))
        print("---------------------------------------------------------- ")
    end)

    set_kind("shared")

    set_toolchains("clang")
    set_languages("c99", "c++20")
    
    set_targetdir(build_dir .. "/bin")
    set_objectdir(build_dir .. "/obj")


    add_cxflags(
        "-O2 -funroll-loops -march=native -fomit-frame-pointer",
        {force = true}
    )

    -- shared lib link flags (! instead of add_ldflags)
    add_shflags(
        "-L".. lua_dir .. "/lib" .. " -lluajit-5.1",
        "-L".. extern_dir .. "/fmt/build" .. " -lfmt",
        "-lrt", -- support shm_open
        "-Wl,--no-as-needed",
        {force = true}
    )

    add_defines("ACCUMULATE_LUA_TIME")

    add_files(
        src_dir .. "/verilua/*.cpp"
    )

    add_includedirs(
        src_dir .. "/include",
        lua_dir .. "/include",
        extern_dir .. "/fmt/include",
        extern_dir .. "/LuaBridge/Source",
        extern_dir .. "/LuaBridge/Source/LuaBridge"
    )

    -- on install
    add_headerfiles(
        src_dir .. "/include/lua_vpi.h"
    )

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
