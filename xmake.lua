---@diagnostic disable: undefined-global

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

local build_libverilua_wave_vpi_cmd = [[cargo build --release --features "wave_vpi chunk_task debug acc_time"]]
local build_iverilog_vpi_module_cmd = [[cargo build --release --features "iverilog iverilog_vpi_mod chunk_task merge_cb debug acc_time"]]

local function build_lib_common(simulator)
    set_kind("phony")
    on_build(function (target)
        -- try { function () os.vrun("cargo clean") end }
        if simulator == "verilator" then
            os.vrun([[cargo build --release --features "%s chunk_task debug acc_time"]], simulator)
        elseif simulator == "wave_vpi" then
            os.vrun(build_libverilua_wave_vpi_cmd)
        elseif simulator == "iverilog" then
            os.vrun(build_iverilog_vpi_module_cmd)
        else
            os.vrun([[cargo build --release --features "%s chunk_task merge_cb debug acc_time"]], simulator)
        end
        os.cp(prj_dir .. "/target/release/libverilua.so", shared_dir .. "/libverilua_" .. simulator .. ".so")
    end)
end

for _, simulator in ipairs({"verilator", "vcs", "iverilog", "wave_vpi"}) do
    -- libverilua_verilator
    -- libverilua_vcs
    -- libverilua_iverilog
    -- libverilua_wave_vpi
    target("libverilua_" .. simulator)
        build_lib_common(simulator)
end

-- Build all libverilua libraries
target("build_libverilua")
    set_kind("phony")
    on_run(function (target)
        print("--------------------- [Build libverilua] ---------------------- ")
        try { function () os.vrun("cargo clean") end }
        cprint("* Build ${green}libverilua_verilator${reset}")
            os.vrun("xmake build libverilua_verilator")
        cprint("* Build ${green}libverilua_vcs${reset}")
            os.vrun("xmake build libverilua_vcs")
        cprint("* Build ${green}libverilua_iverilog${reset}")
            os.vrun("xmake build libverilua_iverilog")
        cprint("* Build ${green}libverilua_wave_vpi${reset}")
            os.vrun("xmake build libverilua_wave_vpi")
        cprint("* Build ${green}iverilog_vpi_module${reset}")
            os.vrun(build_iverilog_vpi_module_cmd)
        print("---------------------------------------------------------- ")
    end)

local function build_common()
    set_languages("c99", "c++20")
    set_targetdir(build_dir .. "/bin")
    set_objectdir(build_dir .. "/obj")
end

local function wave_vpi_main_common()
    set_kind("binary")
    build_common()

    before_build(function (target)
        os.vrun(build_libverilua_wave_vpi_cmd)
    end)

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
        extern_dir .. "/boost_unordered",
        vcpkg_dir .. "/x64-linux/include"
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
    add_links("assert", "cpptrace", "dwarf", "zstd", "z") -- libassert
    add_linkdirs(vcpkg_dir .. "/x64-linux/lib")

    add_links("verilua_wave_vpi")
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
        set_kind("phony")
        on_build(function (target)
            try { function () os.vrun("cargo clean") end }
            os.vrun(build_iverilog_vpi_module_cmd)

            os.cp(prj_dir .. "/target/release/libverilua.so", shared_dir .. "/libverilua_iverilog.vpi")
        end)

    target("vvp_wrapper")
        set_kind("binary")
        build_common()
        
        add_deps("libverilua_iverilog")

        add_files(
            src_dir .. "/vvp_wrapper/vvp_wrapper.cpp"
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
        add_rpathdirs(iverilog_home .. "/lib")

        add_links("luajit-5.1")
        add_linkdirs(lua_dir .. "/lib")
        add_rpathdirs(lua_dir .. "/lib")

        add_links("verilua_iverilog")
        add_linkdirs(shared_dir)
        add_rpathdirs(shared_dir)

        after_build(function (target)
            print("--------------------- [After Build] ---------------------- ")

            os.vrun("wget -P $(tmpdir) https://github.com/NixOS/patchelf/releases/download/0.18.0/patchelf-0.18.0-x86_64.tar.gz")
            os.vrun("tar -zxvf $(tmpdir)/patchelf-0.18.0-x86_64.tar.gz -C $(tmpdir)")

            os.vrun("$(tmpdir)/bin/patchelf --add-needed libverilua_iverilog.so " .. target:targetfile())

            print("* copy " .. target:targetfile() .. " into " .. tools_dir)
                os.run("cp " .. target:targetfile() .. " " .. tools_dir)
            
            print("---------------------------------------------------------- ")
        end)
end

target("testbench_gen")
    set_kind("binary")
    add_ldflags("-static")

    build_common()
    
    add_files(
        src_dir .. "/testbench_gen/*.cpp",
        extern_dir .. "/slang-common/*.cc"
    )

    local slang_dir = extern_dir .. "/slang-prebuild/install_static"
    add_includedirs(
        src_dir .. "/testbench_gen",
        extern_dir .. "/slang-common",
        slang_dir .. "/include",
        extern_dir .. "/boost_unordered/include",
        vcpkg_dir .. "/x64-linux/include"
    )

    add_links("svlang")
    add_linkdirs(slang_dir .. "/lib")

    add_links("fmt", "mimalloc")
    add_links("assert", "cpptrace", "dwarf", "zstd", "z") -- libassert
    add_linkdirs(vcpkg_dir .. "/x64-linux/lib")

    after_build(function (target)
        print("--------------------- [After Build] ---------------------- ")

        print("* copy " .. target:targetfile() .. " into " .. tools_dir)
            os.run("cp " .. target:targetfile() .. " " .. tools_dir)
        print("---------------------------------------------------------- ")
    end)

target("dpi_exporter")
    set_kind("binary")
    add_ldflags("-static")

    build_common()

    if is_mode("debug") then
        -- add_defines("DEBUG")
        set_symbols("debug")
        set_optimize("none")
    end
    
    add_files(
        src_dir .. "/dpi_exporter/*.cpp",
        extern_dir .. "/slang-common/*.cc"
    )

    local slang_dir = extern_dir .. "/slang-prebuild/install_static"
    add_includedirs(
        src_dir .. "/dpi_exporter",
        slang_dir .. "/include",
        extern_dir .. "/slang-common",
        extern_dir .. "/boost_unordered/include",
        lua_dir .. "/include/luajit-2.1",
        vcpkg_dir .. "/x64-linux/include"
    )

    add_links("svlang", "luajit-5.1")
    add_linkdirs(slang_dir .. "/lib", lua_dir .. "/lib")
    add_rpathdirs(slang_dir .. "/lib", lua_dir .. "/lib")

    add_links("luajit_pro_helper")
    add_linkdirs(prj_dir .. "/luajit-pro/target/release")
    add_rpathdirs(prj_dir .. "/luajit-pro/target/release")

    add_links("fmt", "mimalloc")
    add_links("assert", "cpptrace", "dwarf", "zstd", "z") -- libassert
    add_linkdirs(vcpkg_dir .. "/x64-linux/lib")

    after_build(function (target)
        print("--------------------- [After Build] ---------------------- ")

        print("* copy " .. target:targetfile() .. " into " .. tools_dir)
            os.run("cp " .. target:targetfile() .. " " .. tools_dir)
        print("---------------------------------------------------------- ")
    end)


local function signal_db_gen_common(is_static)
    if is_mode("debug") then
        -- add_defines("DEBUG")
        set_symbols("debug")
        set_optimize("none")
    end
    
    add_files(
        src_dir .. "/signal_db_gen/signal_db_gen.cpp",
        extern_dir .. "/slang-common/*.cc"
    )

    local slang_dir = extern_dir .. "/slang-prebuild/install_" .. (is_static and "static" or "shared")
    add_includedirs(
        src_dir .. "/include",
        src_dir .. "/signal_db_gen",
        slang_dir .. "/include",
        extern_dir .. "/slang-common",
        extern_dir .. "/boost_unordered/include",
        lua_dir .. "/include/luajit-2.1",
        vcpkg_dir .. "/x64-linux/include"
    )

    add_links("svlang", "luajit-5.1")
    add_linkdirs(slang_dir .. "/lib", lua_dir .. "/lib")
    add_rpathdirs(slang_dir .. "/lib", lua_dir .. "/lib")

    add_links("luajit_pro_helper")
    add_linkdirs(prj_dir .. "/luajit-pro/target/release")
    add_rpathdirs(prj_dir .. "/luajit-pro/target/release")

    add_links("fmt", "mimalloc")
    add_links("assert", "cpptrace", "dwarf", "zstd", "z") -- libassert
    add_linkdirs(vcpkg_dir .. "/x64-linux/lib")
end

target("signal_db_gen")
    set_kind("binary")
    add_ldflags("-static")

    build_common()
    signal_db_gen_common(true)

    after_build(function (target)
        print("--------------------- [After Build] ---------------------- ")

        print("* copy " .. target:targetfile() .. " into " .. tools_dir)
            os.run("cp " .. target:targetfile() .. " " .. tools_dir)
        print("---------------------------------------------------------- ")
    end)

target("signal_db_gen_lib")
    set_kind("shared")
    set_filename("libsignal_db_gen.so")
    add_defines("SO_LIB")
    build_common()
    signal_db_gen_common()

    after_build(function (target)
        print("--------------------- [After Build] ---------------------- ")

        print("* copy " .. target:targetfile() .. " into " .. shared_dir)
            os.run("cp " .. target:targetfile() .. " " .. shared_dir)
        print("---------------------------------------------------------- ")
    end)

target("update_submodules")
    set_kind("phony")
    on_run(function (target)
        local execute = os.exec
        execute("git submodule update --init --recursive")
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

        -- build luajit_pro_helper
        os.cd(luajit_pro_dir)
        execute("cargo build --release")
        
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

        -- build luajit_pro_helper
        os.cd(luajit_pro_dir)
        execute("cargo build --release")

        os.cd(curr_dir)
    end)

target("reinstall_luajit")
    set_kind("phony")
    on_run(function (target)
        local execute = os.exec
        local curr_dir = os.workingdir()
        local luajit_pro_dir = curr_dir .. "/luajit-pro"
        local luajit_dir = luajit_pro_dir .. "/luajit2.1"

        -- build luajit_pro_helper
        os.cd(luajit_pro_dir)
        execute("cargo build --release")

        -- execute("git reset --hard origin/master")
        -- execute("git pull origin master")
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
            "linenoise", 
        }

        os.addenvs({PATH = luajit_dir .. "/bin"})
        for i, lib in ipairs(libs) do
            cprint("\t${💥} ${yellow}[5.%d]${reset} install ${green}%s${reset}", i, lib)
            execute("luarocks install --force-lock %s", lib)
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

        execute("xmake run -y -v build_libverilua")
        execute("xmake build -y -v testbench_gen")
        execute("xmake build -y -v dpi_exporter")
        execute("xmake build -y -v signal_db_gen")
        execute("xmake build -y -v signal_db_gen_lib")
        execute("xmake build -y -v wave_vpi_main")
        execute("xmake build -y -v wave_vpi_main_fsdb")

        try { function () execute("xmake build -y -v iverilog_vpi_module") end }
        try { function () execute("xmake build -y -v vvp_wrapper") end }
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
        cprint("${💥} ${yellow}[1/8]${reset} Update git submodules...") do
            execute("xmake run update_submodules")
        end

        cprint("${💥} ${yellow}[2/8]${reset} Install other libs...") do
            execute("xmake run install_other_libs")
        end
        
        cprint("${💥} ${yellow}[3/8]${reset} Install LuaJIT-2.1...") do
            execute("xmake run install_luajit")
        end

        cprint("${💥} ${yellow}[4/8]${reset} Install lua modules...") do
            execute("xmake run install_lua_modules")
        end

        cprint("${💥} ${yellow}[5/8]${reset} Install tinycc...") do
            execute("xmake run install_tinycc")
        end

        cprint("${💥} ${yellow}[6/8]${reset} Setup verilua home on ${green}%s${reset}...", os.shell()) do
            execute("xmake run setup_verilua")
        end
        
        cprint("${💥} ${yellow}[7/8]${reset} Install wave vpi...") do
            execute("xmake run install_wave_vpi")
        end

        cprint("${💥} ${yellow}[8/8]${reset} Applying verilua patch for xmake...") do
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
        os.exec("xmake build -v -y libverilua_vcs")
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

        local simulators = {}

        if try { function () return os.iorun("which vvp_wrapper") end } then
            table.insert(simulators, "iverilog")
        end
        if try { function () return os.iorun("which verilator") end } then
            table.insert(simulators, "verilator")
        end
        if try { function () return os.iorun("which vcs") end } then
            table.insert(simulators, "vcs")
        end

        assert(#simulators > 0, "No simulators found!")

        for _, sim in ipairs(simulators) do
            os.setenv("SIM", sim)
            os.exec("rm build -rf")
            os.exec("xmake build -v -P .")
            if sim == "vcs" then
                -- ignore error
                try { function () os.exec("xmake run -v -P .") end }
            else
                os.exec("xmake run -v -P .")
            end
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

        os.cd(prj_dir .. "/tests/test_bitvec_signal")
        os.exec("xmake run -v -P . test_all")

        cprint([[${green}
  _____         _____ _____ 
 |  __ \ /\    / ____/ ____|
 | |__) /  \  | (___| (___  
 |  ___/ /\ \  \___ \\___ \ 
 | |  / ____ \ ____) |___) |
 |_| /_/    \_\_____/_____/ 
${reset}]])
    end)
