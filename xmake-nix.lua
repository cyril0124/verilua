---@diagnostic disable: undefined-global

local lib_name   = "lua_vpi"
local prj_dir    = os.getenv("PWD")
local src_dir    = prj_dir .. "/src"
local build_dir  = prj_dir .. "/build"
local lua_dir    = prj_dir .. "/luajit-pro/luajit2.1"
local extern_dir = prj_dir .. "/extern"
local vcpkg_dir  = prj_dir .. "/vcpkg_installed"
local shared_dir = prj_dir .. "/shared"
local tools_dir  = prj_dir .. "/tools"
local wavevpi_dir = os.getenv("WAVEVPI_DIR") or prj_dir .. "/wave_vpi"
local iverilog_home = os.getenv("IVERILOG_HOME")

local function build_common_info()
    set_kind("shared")
    set_languages("c99", "c++20")
    set_targetdir(build_dir .. "/bin")
    set_objectdir(build_dir .. "/obj")

    -- shared lib link flags (! instead of add_ldflags)
    add_shflags(
        -- "-L".. lua_dir .. "/lib" .. " -lluajit-5.1", -- dynamic link luajit2.1
        "-lrt", -- support shm_open
        "-Wl,--no-as-needed",
        {force = true}
    )

    -- add_defines("DEBUG")
    add_defines("VL_DEF_ACCUMULATE_LUA_TIME")
    add_defines("VL_DEF_OPT_MERGE_CALLBACK")
    add_defines("VL_DEF_OPT_USE_BOOST_UNORDERED")
    -- add_defines("VL_DEF_OPT_VEC_SIMPLE_ACCESS")
    -- add_defines("VL_DEF_VPI_LEARN")
    -- add_defines("VL_DEF_VPI_LOCK_GUARD")
    
    add_files(
        src_dir .. "/verilua/lua_vpi.cpp",
        src_dir .. "/verilua/verilator_helper.cpp",
        src_dir .. "/verilua/vpi_access.cpp",
        src_dir .. "/verilua/vpi_callback.cpp"
    )

    add_includedirs(
        src_dir .. "/include",
        src_dir .. "/gen"
    )

    add_links("fmt", "mimalloc", "luajit-5.1")

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
        os.run("mkdir %s -p", shared_dir)
        print("---------------------------------------------------------- ")
    end)

    after_build(function (target)
        print("--------------------- [After Build] ---------------------- ")

        print("* copy " .. target:targetfile() .. " into " .. shared_dir)
            os.cp(target:targetfile(), shared_dir)
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
-- Build target for wave_vpi
-- 
target(lib_name.."_wave_vpi")

    add_defines("WAVE_VPI")

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

target("wave_vpi_main")
    set_kind("binary")
    set_languages("c99", "c++20")
    set_targetdir(build_dir .. "/bin")
    set_objectdir(build_dir .. "/obj")
    add_deps(lib_name .. "_wave_vpi")

    add_shflags(
        "-static-libstdc++ -static-libgcc",
        "-Wl,--no-as-needed"
    )

    add_files(
        src_dir .. "/wave_vpi/wave_vpi_main.cpp",
        wavevpi_dir .. "/src/wave_dpi.cc",
        wavevpi_dir .. "/src/wave_vpi.cc"
    )

    add_includedirs(
        lua_dir .. "/include/luajit-2.1",
        wavevpi_dir .. "/src"
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

    add_links("luajit-5.1")
    add_linkdirs(lua_dir .. "/lib")

    add_links("fmt", "mimalloc")
    add_links("assert", "cpptrace", "dwarf") -- libassert

    add_links("lua_vpi_wave_vpi")
    add_linkdirs(shared_dir)
    
    add_links("wave_vpi_wellen_impl")
    add_linkdirs(wavevpi_dir .. "/target/release")

    after_build(function (target)
        print("--------------------- [After Build] ---------------------- ")

        print("* copy " .. target:targetfile() .. " into " .. tools_dir)
            os.run("cp " .. target:targetfile() .. " " .. tools_dir)
        
        print("---------------------------------------------------------- ")
    end)


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
            lua_dir .. "/include/luajit-2.1"
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

        add_links("fmt", "mimalloc")

        add_links("lua_vpi_iverilog")
        add_linkdirs(shared_dir)

        after_build(function (target)
            print("--------------------- [After Build] ---------------------- ")

            print("* copy " .. target:targetfile() .. " into " .. tools_dir)
                os.run("cp " .. target:targetfile() .. " " .. tools_dir)
            
            print("---------------------------------------------------------- ")
        end)
end


target("testbench_gen")
    set_kind("binary")

    set_languages("c++20")

    set_plat("linux")
    set_arch("x86_64")
    
    add_files(
        src_dir .. "/testbench_gen/*.cpp",
        extern_dir .. "/slang-common/*.cc"
    )

    add_includedirs(
        src_dir .. "/include",
        extern_dir .. "/slang-common"
    )

    add_links("svlang", "fmt", "mimalloc")
    add_links("assert", "cpptrace", "zstd", "dwarf")

    after_build(function (target)
        print("--------------------- [After Build] ---------------------- ")

        print("* copy " .. target:targetfile() .. " into " .. tools_dir)
            os.run("cp " .. target:targetfile() .. " " .. tools_dir)
        print("---------------------------------------------------------- ")
    end)