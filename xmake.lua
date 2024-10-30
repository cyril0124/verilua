---@diagnostic disable: undefined-global

local lib_name   = "lua_vpi"
local prj_dir    = os.curdir()
local src_dir    = prj_dir .. "/src"
local build_dir  = prj_dir .. "/build"
local lua_dir    = prj_dir .. "/luajit-pro/luajit2.1"
local extern_dir = prj_dir .. "/extern"
local vcpkg_dir  = prj_dir .. "/vcpkg_installed"
local shared_dir = prj_dir .. "/shared"
local tools_dir  = prj_dir .. "/tools"
local wavevpi_dir = prj_dir .. "/wave_vpi"
local iverilog_home = os.getenv("IVERILOG_HOME")

add_requires("conan::fmt/10.2.1", {alias = "fmt"})
add_requires("conan::mimalloc/2.1.7", {alias = "mimalloc"})
add_requires("conan::libassert/2.1.0", {alias = "libassert"})
add_requires("conan::argparse/3.1", {alias = "argparse"})
add_requires("conan::elfio/3.12", {alias = "elfio"})
add_requires("conan::inja/3.4.0", {alias = "inja"})

local function build_common_info()
    set_kind("shared")
    set_languages("c99", "c++20")
    set_targetdir(build_dir .. "/bin")
    set_objectdir(build_dir .. "/obj")

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
        extern_dir .. "/boost_unordered",
        vcpkg_dir .. "/x64-linux/include"
    )

    add_packages("fmt", "mimalloc", "elfio")
    
    -- add_links("luajit-5.1")
    -- add_linkdirs(lua_dir .. "/lib")
    -- add_rpathdirs(lua_dir .. "/lib")

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

local function wave_vpi_main_common()
    set_kind("binary")
    set_languages("c99", "c++20")
    set_targetdir(build_dir .. "/bin")
    set_objectdir(build_dir .. "/obj")
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

    add_packages("fmt", "mimalloc", "libassert", "argparse")

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
        local has_vcpkg = try { function () return os.iorun("vcpkg --version") end }
        local install_using_git = function ()
            if not os.exists("vcpkg") then
                execute("git clone https://github.com/microsoft/vcpkg")
            end
            local success = try {
                function ()
                    execute("./vcpkg/bootstrap-vcpkg.sh")
                    execute("./vcpkg/vcpkg x-update-baseline --add-initial-baseline")
                    execute("./vcpkg/vcpkg install")
                end
            }
        end

        if has_vcpkg then
            local success = try {
                function ()
                    execute("vcpkg x-update-baseline --add-initial-baseline")
                    execute("vcpkg install --x-install-root ./vcpkg_installed")
                end
            }
            if not success then
                install_using_git()
            end
        else
            install_using_git()
        end
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

target("install_vcs_patch_lib")
    set_kind("phony")
    on_run(function (target)
        if not os.isfile(lua_dir .. "/lib/libluajit-5.1.so") then
            os.exec("xmake run install_luajit")
        end
        os.exec("xmake run -v install_other_libs")
        os.exec("git submodule update --init extern/boost_unordered")
        os.exec("xmake build -v -y lua_vpi_vcs")
    end)

target("verilua-nix")
    set_kind("phony")
    on_install(function (target)
        local execute = os.vrun
        execute("git submodule update --init wave_vpi")
        execute("git submodule update --init extern/slang-common")
        execute("git submodule update --init extern/debugger.lua")
        execute("git submodule update --init extern/LuaPanda")
        execute("git submodule update --init extern/luafun")
        execute("rm .xmake -rf")
        execute("rm build -rf")
        -- ! The vcs lib should be built with the local gcc toolchain.
        execute("nix-shell --run \"\
            unset XMAKE_GLOBALDIR \
            xmake run -F xmake.lua -v -y install_vcs_patch_lib \
        \"")
        local verdi_home = os.getenv("VERDI_HOME")
        if verdi_home then
            local fsdb_reader_dir = prj_dir .. "/FsdbReader"
            os.mkdir(fsdb_reader_dir)
            os.trycp(verdi_home .. "/share/FsdbReader/ffrAPI.h", fsdb_reader_dir)
            os.trycp(verdi_home .. "/share/FsdbReader/ffrKit.h", fsdb_reader_dir)
            os.trycp(verdi_home .. "/share/FsdbReader/fsdbShr.h", fsdb_reader_dir)
            os.trycp(verdi_home .. "/share/FsdbReader/LINUX64/libnffr.so", fsdb_reader_dir)
            os.trycp(verdi_home .. "/share/FsdbReader/LINUX64/libnsys.so", fsdb_reader_dir)
        end
        execute("nix-env -f . -i")
    end)

target("test")
    set_kind("phony")
    on_run(function (target)
        local old_env = os.getenvs()
        os.cd(prj_dir .. "/examples/tutorial_example")

        local simulators = {"iverilog", "verilator"}
        for _, sim in ipairs(simulators) do
            os.setenv("SIM", sim)
            os.exec("rm build -rf")
            os.exec("xmake build -v -P .")
            os.exec("xmake run -v -P .")
        end

        os.setenvs(old_env)
        os.cd(prj_dir .. "/examples/wave_vpi")
        os.setenv("SIM", "iverilog")
        os.exec("rm build -rf")
        os.exec("xmake build -v -P . gen_wave")
        os.exec("xmake run -v -P . gen_wave")
        os.exec("xmake build -v -P . sim_wave")
        os.exec("xmake run -v -P . sim_wave")
        
        os.setenvs(old_env)
        os.cd(prj_dir .. "/tests/wave_vpi_padding_issue")
        os.exec("rm build -rf")
        os.exec("xmake build -v -P . test")
        os.exec("xmake run -v -P . test")
        os.exec("xmake build -v -P . test_wave")
        os.exec("xmake run -v -P . test_wave")

        cprint([[${green}
  _____         _____ _____ 
 |  __ \ /\    / ____/ ____|
 | |__) /  \  | (___| (___  
 |  ___/ /\ \  \___ \\___ \ 
 | |  / ____ \ ____) |___) |
 |_| /_/    \_\_____/_____/ 
${reset}]])
    end)
