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
local wavevpi_dir = prj_dir .. "/wave_vpi"
local iverilog_home = os.getenv("IVERILOG_HOME")

-- local toolchains = "clang-18"
local toolchains = "gcc"

add_requires("conan::fmt/10.2.1", {alias = "fmt"})
add_requires("conan::mimalloc/2.1.7", {alias = "mimalloc"})
add_requires("conan::libassert/2.1.0", {alias = "libassert"})
add_requires("conan::argparse/3.1", {alias = "argparse"})
add_requires("conan::elfio/3.12", {alias = "elfio"})
add_requires("conan::inja/3.4.0", {alias = "inja"})

local function build_common_info()
    set_kind("shared")
    set_toolchains(toolchains)
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
        extern_dir .. "/boost_unordered",
        vcpkg_dir .. "/x64-linux/include"
    )

    add_packages("fmt", "mimalloc", "elfio")

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
    set_toolchains(toolchains)
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

    add_packages("fmt", "mimalloc", "libassert", "argparse")

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
        set_toolchains(toolchains)
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

        add_packages("fmt", "mimalloc")

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

    local slang_dir = extern_dir .. "/slang-prebuild/install_static"
    add_includedirs(
        src_dir .. "/include",
        extern_dir .. "/slang-common",
        slang_dir .. "/include",
        extern_dir .. "/boost_unordered/include"
    )

    add_links("svlang")
    add_linkdirs(slang_dir .. "/lib")

    add_packages("fmt", "mimalloc", "libassert", "argparse", "inja")

    after_build(function (target)
        print("--------------------- [After Build] ---------------------- ")

        print("* copy " .. target:targetfile() .. " into " .. tools_dir)
            os.run("cp " .. target:targetfile() .. " " .. tools_dir)
        print("---------------------------------------------------------- ")
    end)

target("update_submodules")
    set_kind("phony")
    on_run(function (target)
        local execute = os.exec
        execute("git submodule update --init --recursive")
    end)

target("install_python_depends")
    set_kind("phony")
    on_run(function (target)
        local execute = os.exec
        execute("python3 -m pip install -r requirements.txt")
    end)

target("install_luajit")
    set_kind("phony")
    on_run(function (target)
        local execute = os.exec
        local curr_dir = os.workingdir()
        local luajit_pro_dir = curr_dir .. "/luajit-pro"
        local luajit_dir = luajit_pro_dir .. "/luajit2.1"
        local luarocks_version = "3.11.1"

        execute("rm -rf " .. luajit_pro_dir)

        execute("git clone https://github.com/cyril0124/luajit-pro.git " .. luajit_pro_dir)
        os.cd(luajit_pro_dir)
        execute("bash init.sh")
        os.trycp(luajit_dir .. "/bin/luajit", luajit_dir .. "/bin/lua")
        
        os.addenvs({PATH = luajit_dir .. "/bin"})
        
        execute("wget -P %s https://luarocks.github.io/luarocks/releases/luarocks-%s.tar.gz", luajit_pro_dir, luarocks_version)
        execute("tar -zxvf luarocks-%s.tar.gz", luarocks_version)
        os.cd("luarocks-" .. luarocks_version)
        
        execute("make clean")
        execute("./configure --with-lua=%s --prefix=%s", luajit_dir, luajit_dir)
        execute("make")
        execute("make install")

        os.cd(curr_dir)
    end)

target("reinstall_luajit")
    set_kind("phony")
    on_run(function (target)
        local execute = os.exec
        local curr_dir = os.workingdir()
        local luajit_pro_dir = curr_dir .. "/luajit-pro"
        local luajit_dir = luajit_pro_dir .. "/luajit2.1"

        os.cd(luajit_pro_dir)
        -- execute("git reset --hard origin/master")
        execute("git pull origin master")
        execute("bash init.sh")
        os.trycp(luajit_dir .. "/bin/luajit", luajit_dir .. "/bin/lua")

        os.cd(curr_dir)
    end)

target("install_other_libs")
    set_kind("phony")
    on_run(function (target)
        local execute = os.exec
        execute("git clone https://github.com/microsoft/vcpkg")
        execute("./vcpkg/bootstrap-vcpkg.sh")
        execute("./vcpkg/vcpkg x-update-baseline --add-initial-baseline")
        execute("./vcpkg/vcpkg install")
    end)

target("install_lua_modules")
    set_kind("phony")
    on_run(function (target)
        local execute = os.exec
        local curr_dir = os.workingdir()
        local luajit_pro_dir = curr_dir .. "/luajit-pro"
        local luajit_dir = luajit_pro_dir .. "/luajit2.1"
        local libs = {
            "penlight", 
            "luasocket", 
            "lsqlite3", 
            "argparse", 
            "busted", 
            "linenoise", 
            "luafilesystem",
        }

        os.addenvs({PATH = luajit_dir .. "/bin"})
        for i, lib in ipairs(libs) do
            cprint("\t${💥} ${yellow}[5.%d]${reset} install ${green}%s${reset}", i, lib)
            execute("luarocks install %s", lib)
        end
        execute("luarocks list")
    end)

target("install_tinycc")
    set_kind("phony")
    on_run(function (target)
        local execute = os.exec
        os.cd("extern/luajit_tcc")
        execute("make init")
        execute("make")
        os.cd(os.workingdir())
    end)

target("setup_verilua")
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
                file:print("export PATH=$VERILUA_HOME/tools:$PATH")
                file:print("export PATH=$VERILUA_HOME/luajit-pro/luajit2.1/bin:$PATH")
                file:print("export LD_LIBRARY_PATH=$VERILUA_HOME/shared:$LD_LIBRARY_PATH")
                file:print("export LD_LIBRARY_PATH=$VERILUA_HOME/luajit-pro/luajit2.1/lib:$LD_LIBRARY_PATH")
                file:print("source $VERILUA_HOME/activate_verilua.sh")
                file:print("# <<< verilua <<<")
                file:close()
            end
        end

        -- generate libwwave_vpi_wellen_impl
        os.cd("wave_vpi")
        execute("cargo build --release")
        os.cd(os.workingdir())

        execute("xmake -y -P .")
    end)

target("install_wave_vpi")
    set_kind("phony")
    on_run(function (target)
        local execute = os.exec
        os.cd("wave_vpi")
        execute("bash init.sh")
        os.cd(os.workingdir())
    end)

target("apply_xmake_patch")
    set_kind("phony")
    on_run(function (target)
        local execute = os.exec
        execute("bash apply_xmake_patch.sh")
    end)

target("verilua")
    set_kind("phony")
    on_install(function (target)
        local execute = os.exec
        cprint("${💥} ${yellow}[1]${reset} Update git submodules...") do
            execute("xmake run update_submodules")
        end

        cprint("${💥} ${yellow}[2]${reset} Install python dependency...") do
            execute("xmake run install_python_depends")
        end

        cprint("${💥} ${yellow}[3]${reset} Install other libs...") do
            execute("xmake run install_other_libs")
        end
        
        cprint("${💥} ${yellow}[4]${reset} Install LuaJIT-2.1...") do
            execute("xmake run install_luajit")
        end

        cprint("${💥} ${yellow}[5]${reset} Install lua modules...") do
            execute("xmake run install_lua_modules")
        end

        cprint("${💥} ${yellow}[6]${reset} Install tinycc...") do
            execute("xmake run install_tinycc")
        end

        cprint("${💥} ${yellow}[7]${reset} Setup verilua home on ${green}%s${reset}...", os.shell()) do
            execute("xmake run setup_verilua")
        end
        
        cprint("${💥} ${yellow}[8]${reset} Install wave vpi...") do
            execute("xmake run install_wave_vpi")
        end

        cprint("${💥} ${yellow}[9]${reset} Applying verilua patch for xmake...") do
            execute("xmake run apply_xmake_patch")
        end
    end)