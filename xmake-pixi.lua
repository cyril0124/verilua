---@diagnostic disable: undefined-global

local lib_name   = "lua_vpi"
local prj_dir    = os.curdir()
local src_dir    = prj_dir .. "/src"
local build_dir  = prj_dir .. "/build"
local lua_dir    = prj_dir .. "/luajit-pro/luajit2.1"
local extern_dir = prj_dir .. "/extern"
local shared_dir = prj_dir .. "/shared"
local tools_dir  = prj_dir .. "/tools"
local wavevpi_dir = prj_dir .. "/wave_vpi"
local iverilog_home = os.getenv("IVERILOG_HOME")

local library_paths = os.getenv("LIBRARY_PATH"):split(":")

local function build_common()
    set_languages("c99", "c++20")
    set_targetdir(build_dir .. "/bin")
    set_objectdir(build_dir .. "/obj")
end

local function build_lib_common()
    set_kind("shared")
    build_common()

    -- shared lib link flags (! instead of add_ldflags)
    add_shflags(
        "-lrt", -- support shm_open
        "-static-libstdc++ -static-libgcc",
        "-Wl,--no-as-needed",
        -- "-Wl,-Bstatic", "-lluajit-5.1", "-Wl,-Bdynamic",
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
        lua_dir .. "/lib/libluajit-5.1.a",
        src_dir .. "/verilua/lua_vpi.cpp",
        src_dir .. "/verilua/verilator_helper.cpp",
        src_dir .. "/verilua/vpi_access.cpp",
        src_dir .. "/verilua/vpi_callback.cpp"
    )

    add_includedirs(
        src_dir .. "/include",
        src_dir .. "/gen",
        lua_dir .. "/include/luajit-2.1",
        extern_dir .. "/boost_unordered"
    )

    add_links("fmt")
    add_linkdirs(table.unpack(library_paths))
    add_rpathdirs(table.unpack(library_paths))
    
    -- add_links("luajit-5.1")
    -- add_linkdirs(lua_dir .. "/lib")
    -- add_rpathdirs(lua_dir .. "/lib")

    if is_mode("debug") then
        add_defines("DEBUG")
        set_symbols("debug")
        set_optimize("none")
        -- add_cxflags("-fsanitize=address", "-fno-omit-frame-pointer", "-fno-optimize-sibling-calls")
        -- add_ldflags("-fsanitize=address")
    else
        add_cxflags("-O2 -funroll-loops -march=native -fomit-frame-pointer")
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
-- Build lua_vpi libraries
-- 
for sim, name in pairs({
    ["VERILATOR"] = lib_name,
    ["VCS"]       = lib_name .. "_vcs",
    ["WAVE_VPI"]  = lib_name .. "_wave_vpi",
    ["IVERILOG"]  = iverilog_home and lib_name .. "_iverilog" or "",
}) do
    if name ~= "" then
        target(name) do
            add_defines(sim)
            build_lib_common()
        end
    end
end

local function wave_vpi_main_common()
    set_kind("binary")
    build_common()

    add_deps(lib_name .. "_wave_vpi")

    add_shflags(
        "-static-libstdc++ -static-libgcc",
        "-Wl,--no-as-needed"
    )

    add_defines("VL_DEF_OPT_USE_BOOST_UNORDERED")

    add_files(
        src_dir .. "/wave_vpi/wave_vpi_main.cpp",
        wavevpi_dir .. "/src/wave_dpi.cc",
        wavevpi_dir .. "/src/wave_vpi.cc"
    )

    add_includedirs(
        lua_dir .. "/include/luajit-2.1",
        wavevpi_dir .. "/src",
        extern_dir .. "/boost_unordered"
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
    add_rpathdirs(lua_dir .. "/lib")

    add_links("fmt", "mimalloc")
    add_links("assert", "cpptrace", "dwarf") -- libassert
    add_linkdirs(table.unpack(library_paths))
    add_rpathdirs(table.unpack(library_paths))

    add_links("lua_vpi_wave_vpi")
    add_linkdirs(shared_dir)
    add_rpathdirs(shared_dir)
    
    add_links("wave_vpi_wellen_impl")
    add_linkdirs(wavevpi_dir .. "/target/release")

    after_build(function (target)
        print("--------------------- [After Build] ---------------------- ")

        print("* copy " .. target:targetfile() .. " into " .. tools_dir)
            os.run("cp " .. target:targetfile() .. " " .. tools_dir)
        
        print("---------------------------------------------------------- ")
    end)
end

target("wave_vpi_main")
    wave_vpi_main_common()

target("wave_vpi_main_fsdb")
    if os.getenv("VERDI_HOME") then
        wave_vpi_main_common()

        local verdi_home = os.getenv("VERDI_HOME")
        -- print("[wave_vpi_main_fsdb] verdi_home is " .. verdi_home)
        add_includedirs(verdi_home .. "/share/FsdbReader")
        add_linkdirs(verdi_home .. "/share/FsdbReader/LINUX64")
        add_rpathdirs(verdi_home .. "/share/FsdbReader/LINUX64")
        add_links("nffr", "nsys", "z")

        add_defines("USE_FSDB")
    else
        set_kind("phony")
        on_build(function(target)
            raise("[wave_vpi_main_fsdb] VERDI_HOME is not defined!")
        end)
    end

-- 
-- Build target for Iverilog
-- 
if iverilog_home ~= nil then
    target("iverilog_vpi_module")
        add_defines("IVERILOG")
        set_filename(lib_name .. ".vpi")

        build_lib_common()

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
        build_common()
        
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
        add_linkdirs(table.unpack(library_paths))
        add_rpathdirs(table.unpack(library_paths))

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
    build_common()
    
    add_files(
        src_dir .. "/testbench_gen/*.cpp",
        extern_dir .. "/slang-common/*.cc"
    )

    local slang_dir = extern_dir .. "/slang-prebuild/install_static"
    add_includedirs(
        src_dir .. "/include",
        extern_dir .. "/slang-common",
        slang_dir .. "/include",
        extern_dir .. "/boost_unordered/include"
    )

    add_links("svlang")
    add_linkdirs(slang_dir .. "/lib")
    add_rpathdirs(slang_dir .. "/lib")

    add_links("fmt", "mimalloc")
    add_links("assert", "cpptrace", "dwarf") -- libassert
    add_linkdirs(table.unpack(library_paths))
    add_rpathdirs(table.unpack(library_paths))

    after_build(function (target)
        print("--------------------- [After Build] ---------------------- ")

        print("* copy " .. target:targetfile() .. " into " .. tools_dir)
            os.run("cp " .. target:targetfile() .. " " .. tools_dir)
        print("---------------------------------------------------------- ")
    end)

target("dpi_exporter")
    set_kind("binary")
    build_common()

    if is_mode("debug") then
        -- add_defines("DEBUG")
        set_symbols("debug")
        set_optimize("none")
    end
    
    add_files(
        src_dir .. "/dpi_exporter/dpi_exporter.cpp",
        extern_dir .. "/slang-common/*.cc"
    )

    local slang_dir = extern_dir .. "/slang-prebuild/install_static"
    add_includedirs(
        src_dir .. "/include",
        src_dir .. "/dpi_exporter",
        slang_dir .. "/include",
        extern_dir .. "/slang-common",
        extern_dir .. "/boost_unordered/include"
    )

    add_links("svlang")
    add_linkdirs(slang_dir .. "/lib")

    add_links("fmt", "mimalloc")
    add_links("assert", "cpptrace", "dwarf") -- libassert
    add_linkdirs(table.unpack(library_paths))
    add_rpathdirs(table.unpack(library_paths))

    after_build(function (target)
        print("--------------------- [After Build] ---------------------- ")

        print("* copy " .. target:targetfile() .. " into " .. tools_dir)
            os.run("cp " .. target:targetfile() .. " " .. tools_dir)
        print("---------------------------------------------------------- ")
    end)

target("init")
    set_kind("phony")
    on_run(function (target)
        local execute = os.exec
        execute("mv vcpkg.json vcpkg.json.bak")
        execute('vcpkg install sol2')
        execute("mv vcpkg.json.bak vcpkg.json")

        execute("xmake run update_submodules")
        execute("xmake run install_luajit")
        execute("xmake run install_lua_modules")
        execute("xmake run install_tinycc")
        
        os.cd("wave_vpi")
        execute("git submodule update --init --recursive")
        execute('cargo build --release')
        os.cd(os.workingdir())
    end)

target("install")
    set_kind("phony")
    on_run(function (target)
        local execute = os.exec
        
        local shell_rc = os.getenv("HOME") .. "/." .. os.shell() .. "rc"
        local content = io.readfile(shell_rc)
        local has_match = false
        local lines = io.lines(shell_rc)
        for line in lines do
            if line:match("^[^#]*export VERILUA_HOME=") then
                has_match = true
            end
        end
        if not has_match then
            local file = io.open(shell_rc, "a")
            if file then
                file:print("")
                file:print("# >>> verilua >>>")
                file:print("export VERILUA_HOME=$(curdir)")
                file:print("source $VERILUA_HOME/activate_verilua.sh")
                file:print("# <<< verilua <<<")
                file:close()
            end
        end

        execute("xmake run apply_xmake_patch")
    end)