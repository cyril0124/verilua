---@diagnostic disable: undefined-global

local lib_name   = "lua_vpi"
local prj_dir    = os.getenv("PWD")
local src_dir    = prj_dir .. "/src"
local build_dir  = prj_dir .. "/build"
local lua_dir    = prj_dir .. "/luajit2.1"
local extern_dir = prj_dir .. "/extern"
local shared_dir = prj_dir .. "/shared"
local vcpkg_dir  = prj_dir .. "/vcpkg"
local tools_dir  = prj_dir .. "/tools"
local iverilog_home = os.getenv("IVERILOG_HOME")

local function build_common_info()
    set_kind("shared")
    set_toolchains("gcc")
    set_languages("c99", "c++20")
    set_targetdir(build_dir .. "/bin")
    set_objectdir(build_dir .. "/obj")

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
        vcpkg_dir .. "/installed/x64-linux/include"
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

    if is_mode("debug") then
        add_defines("DEBUG")
        set_symbols("debug")
        set_optimize("none")
        -- add_cxflags("-fsanitize=address", "-fno-omit-frame-pointer", "-fno-optimize-sibling-calls")
        -- add_ldflags("-fsanitize=address")
    else
        add_cxflags("-O2 -funroll-loops -march=native -fomit-frame-pointer")
    end

    build_common_info()


-- 
-- Build target for VCS
-- 
target(lib_name.."_vcs")
    add_defines("VCS")

    if is_mode("debug") then
        add_defines("DEBUG")
        set_symbols("debug")
        set_optimize("none")
        -- add_cxflags("-fsanitize=address", "-fno-omit-frame-pointer", "-fno-optimize-sibling-calls")
        -- add_ldflags("-fsanitize=address")
    else
        add_cxflags("-O2 -funroll-loops -march=native -fomit-frame-pointer")
    end

    build_common_info()


-- 
-- Build target for Iverilog
-- 
if iverilog_home ~= nil then
    target(lib_name .. "_iverilog")
        add_defines("IVERILOG")

        if is_mode("debug") then
            add_defines("DEBUG")
            set_symbols("debug")
            set_optimize("none")
            -- add_cxflags("-fsanitize=address", "-fno-omit-frame-pointer", "-fno-optimize-sibling-calls")
            -- add_ldflags("-fsanitize=address")
        else
            -- Notice: can only use -O0 in iverilog otherwise there will be a segmentation fault!
            add_cxflags("-O0 -funroll-loops -march=native -fomit-frame-pointer")
        end

        build_common_info()

    target("iverilog_vpi_module")
        add_defines("IVERILOG")
        set_filename(lib_name .. ".vpi")
        
        if is_mode("debug") then
            add_defines("DEBUG")
            set_symbols("debug")
            set_optimize("none")
            -- add_cxflags("-fsanitize=address", "-fno-omit-frame-pointer", "-fno-optimize-sibling-calls")
            -- add_ldflags("-fsanitize=address")
        else
            add_cxflags("-O2 -funroll-loops -march=native -fomit-frame-pointer")
        end

        build_common_info()

        add_links("vpi", "veriuser")
        add_linkdirs(iverilog_home .. "/lib")

        after_build(function (target)
            print("--------------------- [After Build] ---------------------- ")
    
            print("* copy " .. target:targetfile() .. " into " .. shared_dir)
                os.run("cp " .. target:targetfile() .. " " .. shared_dir)
            
            print("---------------------------------------------------------- ")
        end)


    target("vvp_wrapper")
        set_kind("binary")
        set_toolchains("gcc")
        set_languages("c99", "c++20")
        set_targetdir(build_dir .. "/bin")
        set_objectdir(build_dir .. "/obj")
        add_deps(lib_name .. "_iverilog")

        add_files(
            src_dir .. "/iverilog/vvp_wrapper.cpp"
        )

        add_includedirs(
            iverilog_home .. "/include",
            src_dir .. "/include",
            lua_dir .. "/include",
            vcpkg_dir .. "/installed/x64-linux/include"
        )

        if is_mode("debug") then
            add_defines("DEBUG")
            set_symbols("debug")
            set_optimize("none")
            -- add_cxflags("-fsanitize=address", "-fno-omit-frame-pointer", "-fno-optimize-sibling-calls")
            -- add_ldflags("-fsanitize=address")
        else
            add_cxflags("-O2 -funroll-loops -march=native -fomit-frame-pointer")
        end

        add_links("vvp")
        add_linkdirs(iverilog_home .. "/lib")

        add_links("luajit-5.1")
        add_linkdirs(lua_dir .. "/lib")

        add_links("fmt")
        add_linkdirs(vcpkg_dir .. "/installed/x64-linux/lib")

        add_links("lua_vpi_iverilog")
        add_linkdirs(shared_dir)

        after_build(function (target)
            print("--------------------- [After Build] ---------------------- ")

            print("* copy " .. target:targetfile() .. " into " .. tools_dir)
                os.run("cp " .. target:targetfile() .. " " .. tools_dir)
            
            print("---------------------------------------------------------- ")
        end)
end
