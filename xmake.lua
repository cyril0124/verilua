---@diagnostic disable: undefined-global

local prj_dir    = os.curdir()
local src_dir    = prj_dir .. "/src"
local build_dir  = prj_dir .. "/build"
local lua_dir    = prj_dir .. "/luajit-pro/luajit2.1"
local extern_dir = prj_dir .. "/extern"
local libs_dir   = prj_dir .. "/conan_installed"
local shared_dir = prj_dir .. "/shared"
local tools_dir  = prj_dir .. "/tools"
local wavevpi_dir = prj_dir .. "/wave_vpi"

local verilator_features = "chunk_task debug acc_time"
local vcs_features = "chunk_task merge_cb debug acc_time"
local wave_vpi_features = "chunk_task debug acc_time"
local iverilog_features = "chunk_task merge_cb debug acc_time"

local build_libverilua_wave_vpi_cmd = string.format([[cargo build --release --features "wave_vpi %s"]], wave_vpi_features)
local build_iverilog_vpi_module_cmd = string.format([[cargo build --release --features "iverilog iverilog_vpi_mod %s"]], iverilog_features)

local function build_lib_common(simulator)
    set_kind("phony")
    on_build(function (target)
        local vpi_funcs = {
            "vpi_put_value",
            "vpi_scan",
            "vpi_control",
            "vpi_free_object",
            "vpi_get",
            "vpi_get_str",
            "vpi_get_value",
            "vpi_handle_by_name",
            "vpi_handle_by_index",
            "vpi_iterate",
            "vpi_register_cb",
            "vpi_remove_cb"
        }

        -- try { function () os.vrun("cargo clean") end }
        if simulator == "verilator" then
            os.vrun([[cargo build --release --features "verilator %s"]], verilator_features)
        elseif simulator == "verilator_dpi" then
            os.setenv("RUSTFLAGS", "-Clink-arg=-Wl,--wrap=" .. table.concat(vpi_funcs, ",--wrap="))
            os.vrun([[cargo build --release --features "verilator dpi %s"]], verilator_features)
            os.setenv("RUSTFLAGS", "")
        elseif simulator == "vcs" then
            os.vrun([[cargo build --release --features "vcs %s"]], vcs_features)
        elseif simulator == "vcs_dpi" then
            os.setenv("RUSTFLAGS", "-Clink-arg=-Wl,--wrap=" .. table.concat(vpi_funcs, ",--wrap="))
            os.vrun([[cargo build --release --features "vcs dpi %s"]], vcs_features)
            os.setenv("RUSTFLAGS", "")
        elseif simulator == "wave_vpi" then
            os.vrun(build_libverilua_wave_vpi_cmd)
        elseif simulator == "iverilog" then
            os.vrun(build_iverilog_vpi_module_cmd)
        else
            raise("Unknown simulator => " .. simulator)
        end
        os.cp(prj_dir .. "/target/release/libverilua.so", shared_dir .. "/libverilua_" .. simulator .. ".so")
    end)
end

for _, simulator in ipairs({"verilator", "verilator_dpi", "vcs", "vcs_dpi", "iverilog", "wave_vpi"}) do
    -- libverilua_verilator
    -- libverilua_verilator_dpi
    -- libverilua_vcs
    -- libverilua_vcs_dpi
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
        cprint("* Build ${green}libverilua_verilator_dpi${reset}")
            os.vrun("xmake build libverilua_verilator_dpi")
        cprint("* Build ${green}libverilua_vcs${reset}")
            os.vrun("xmake build libverilua_vcs")
        cprint("* Build ${green}libverilua_vcs_dpi${reset}")
            os.vrun("xmake build libverilua_vcs_dpi")
        cprint("* Build ${green}libverilua_iverilog${reset}")
            os.vrun("xmake build libverilua_iverilog")
        cprint("* Build ${green}libverilua_wave_vpi${reset}")
            os.vrun("xmake build libverilua_wave_vpi")
        cprint("* Build ${green}iverilog_vpi_module${reset}")
            os.vrun(build_iverilog_vpi_module_cmd)
            os.cp(prj_dir .. "/target/release/libverilua.so", shared_dir .. "/libverilua_iverilog.vpi")
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
        libs_dir .. "/include"
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

    add_linkgroups("luajit-5.1", {static = true, whole = true})
    add_linkdirs(lua_dir.. "/lib")

    add_links("luajit_pro_helper")
    add_linkdirs(prj_dir .. "/luajit-pro/target/release")
    add_rpathdirs(prj_dir .. "/luajit-pro/target/release")

    add_links("fmt", "mimalloc")
    add_links("assert", "cpptrace", "dwarf", "zstd", "z") -- libassert
    add_linkdirs(libs_dir.. "/lib")

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

target("iverilog_vpi_module")
    set_kind("phony")
    on_build(function (target)
        try { function () os.vrun("cargo clean") end }
        os.vrun(build_iverilog_vpi_module_cmd)

        os.cp(prj_dir .. "/target/release/libverilua.so", shared_dir .. "/libverilua_iverilog.vpi")
    end)

target("testbench_gen")
    set_kind("binary")
    add_ldflags("-static")

    build_common()

    add_files(
        src_dir .. "/testbench_gen/*.cpp",
        extern_dir .. "/slang-common/*.cpp"
    )

    add_defines("SLANG_BOOST_SINGLE_HEADER")

    add_includedirs(
        src_dir .. "/testbench_gen",
        extern_dir .. "/slang-common",
        libs_dir .. "/include"
    )

    add_links("svlang", "fmt", "mimalloc") -- order is important 
    add_links("assert", "cpptrace", "dwarf", "zstd", "z") -- libassert
    add_linkdirs(libs_dir.. "/lib")

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
        src_dir .. "/dpi_exporter/src/*.cpp",
        extern_dir .. "/slang-common/*.cpp"
    )

    add_defines("SLANG_BOOST_SINGLE_HEADER")

    add_includedirs(
        src_dir .. "/dpi_exporter",
        src_dir .. "/dpi_exporter/include",
        extern_dir .. "/slang-common",
        lua_dir .. "/include/luajit-2.1",
        libs_dir .. "/include"
    )

    add_links("luajit-5.1")
    add_linkdirs(lua_dir .. "/lib")
    add_rpathdirs(lua_dir .. "/lib")

    add_links("svlang", "fmt", "mimalloc")
    add_linkdirs(libs_dir.. "/lib")
    add_rpathdirs(libs_dir.. "/lib")

    add_links("luajit_pro_helper")
    add_linkdirs(prj_dir .. "/luajit-pro/target/release")
    add_rpathdirs(prj_dir .. "/luajit-pro/target/release")

    add_links("assert", "cpptrace", "dwarf", "zstd", "z") -- libassert
    add_linkdirs(libs_dir.. "/lib")
    add_rpathdirs(libs_dir.. "/lib")

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
        extern_dir .. "/slang-common/*.cpp"
    )

    add_defines("SLANG_BOOST_SINGLE_HEADER")

    add_includedirs(
        src_dir .. "/include",
        src_dir .. "/signal_db_gen",
        libs_dir .. "/include",
        extern_dir .. "/slang-common",
        lua_dir .. "/include/luajit-2.1"
    )

    add_links("svlang", "fmt", "mimalloc")
    add_links("assert", "cpptrace", "dwarf", "zstd", "z") -- libassert
    add_linkdirs(libs_dir.. "/lib")
    add_rpathdirs(libs_dir.. "/lib")

    add_links("luajit-5.1")
    add_linkdirs(lua_dir.. "/lib")
    add_rpathdirs(lua_dir.. "/lib")

    add_links("luajit_pro_helper")
    add_linkdirs(prj_dir .. "/luajit-pro/target/release")
    add_rpathdirs(prj_dir .. "/luajit-pro/target/release")
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

target("libsignal_db_gen")
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

target("verilua_prebuild")
    set_kind("phony")
    on_build(function (target)
        os.exec("cargo build --release --features verilua_prebuild_bin")
    end)

    after_build(function (target)
        print("--------------------- [After Build] ---------------------- ")

        local bin = prj_dir .. "/target/release/verilua_prebuild"
        print("* copy " .. bin .. " into " .. tools_dir)
            os.run("cp " .. bin .. " " .. tools_dir)
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
        local conan_cmd = "conan"
        local has_conan = try { function () return os.iorun("conan --version") end }

        if not has_conan then
            os.mkdir(prj_dir .. "/build")
            os.cd(prj_dir.. "/build")
            os.exec("wget https://github.com/conan-io/conan/releases/download/2.14.0/conan-2.14.0-linux-x86_64.tgz")
            os.mkdir("./conan")
            os.exec("tar -xvf conan-2.14.0-linux-x86_64.tgz -C ./conan")
            conan_cmd = prj_dir .. "/build/conan/bin/conan"
        end

        os.cd(prj_dir .. "/scripts/conan/slang")
        os.exec(conan_cmd .. " create . --build=missing")

        os.cd(prj_dir)
        os.exec(conan_cmd .. " install . --output-folder=%s --build=missing", libs_dir)
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
        execute("xmake build -y -v libsignal_db_gen")
        execute("xmake build -y -v wave_vpi_main")
        execute("xmake build -y -v wave_vpi_main_fsdb")
        execute("xmake build -y -v verilua_prebuild")

        try { function () execute("xmake build -y -v iverilog_vpi_module") end }
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
        cprint("${💥} ${yellow}[1/7]${reset} Update git submodules...") do
            execute("xmake run update_submodules")
        end

        cprint("${💥} ${yellow}[2/7]${reset} Install other libs...") do
            execute("xmake run install_other_libs")
        end
        
        cprint("${💥} ${yellow}[3/7]${reset} Install LuaJIT-2.1...") do
            execute("xmake run install_luajit")
        end

        cprint("${💥} ${yellow}[4/7]${reset} Install lua modules...") do
            execute("xmake run install_lua_modules")
        end

        cprint("${💥} ${yellow}[5/7]${reset} Install tinycc...") do
            execute("xmake run install_tinycc")
        end

        cprint("${💥} ${yellow}[6/7]${reset} Setup verilua home on ${green}%s${reset}...", os.shell()) do
            execute("xmake run setup_verilua")
        end

        cprint("${💥} ${yellow}[7/7]${reset} Applying verilua patch for xmake...") do
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

        local simulators = {}
        local has_vcs = false

        if try { function () return os.iorun("which vvp") end } then
            table.insert(simulators, "iverilog")
        end
        if try { function () return os.iorun("which verilator") end } then
            table.insert(simulators, "verilator")
        end
        if try { function () return os.iorun("which vcs") end } then
            has_vcs = true
            table.insert(simulators, "vcs")
        end

        assert(#simulators > 0, "No simulators found!")

        do
            os.cd(path.join(prj_dir, "examples", "tutorial_example"))

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
        end

        do
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "examples", "WAL"))
            os.setenv("SIM", "iverilog")
            os.exec("rm build -rf")
            os.exec("xmake build -v -P . gen_wave")
            os.exec("xmake run -v -P . gen_wave")
            os.exec("xmake build -v -P . sim_wave")
            os.exec("xmake run -v -P . sim_wave")
        end

        do
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "examples", "HSE"))
            os.tryrm("csrc")
            os.tryrm("simv*")
            os.tryrm("sim_build*")
            os.execv(os.shell(), {"run_verilator.sh"})
            os.execv(os.shell(), {"run_verilator_p.sh"})

            if has_vcs then
                os.execv(os.shell(), {"run_vcs.sh"})
            end
        end

        do
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "examples", "HSE_dummy_vpi"))
            os.tryrm("csrc")
            os.tryrm("simv*")
            os.tryrm("sim_build*")
            os.execv(os.shell(), {"run_verilator.sh"})
            os.execv(os.shell(), {"run_verilator_dpi.sh"})

            if has_vcs then
                os.execv(os.shell(), {"run_vcs.sh"})
                os.execv(os.shell(), {"run_vcs_dpi.sh"})
            end
        end

        do
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "examples", "HSE_virtual_rtl"))
            os.tryrm("sim_build_dpi")
            os.execv(os.shell(), {"run_verilator_dpi.sh"})

            if has_vcs then
                os.tryrm("csrc")
                os.tryrm("simv_dpi")
                os.tryrm("simv_dpi.daidir")
                os.execv(os.shell(), {"run_vcs_dpi.sh"})
            end
        end

        do
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "examples", "simple_ut_env"))
            os.tryrm("build")
            os.exec("xmake build -P . test_counter")
            os.exec("xmake run -v -P . test_counter")
        end

        do
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "tests", "wave_vpi_padding_issue"))
            os.exec("rm build -rf")
            os.exec("xmake build -v -P . test")
            os.exec("xmake run -v -P . test")
            os.exec("xmake build -v -P . test_wave")
            os.exec("xmake run -v -P . test_wave")
        end

        do
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "tests", "test_bitvec_signal"))
            os.exec("xmake run -v -P . test_all")
        end

        do
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "tests", "test_edge"))

            for _, sim in ipairs(simulators) do
                os.setenv("SIM", sim)
                os.tryrm("build")
                os.exec("xmake build -v -P .")
                if sim == "vcs" then
                    -- ignore error
                    try { function () os.exec("xmake run -v -P .") end }
                else
                    os.exec("xmake run -v -P .")
                end
            end
        end

        do
            os.setenvs(old_env)
            os.cd(path.join(prj_dir, "tests"))
            os.exec("xmake run -P . test_all")
        end

        cprint([[${green}
  _____         _____ _____ 
 |  __ \ /\    / ____/ ____|
 | |__) /  \  | (___| (___  
 |  ___/ /\ \  \___ \\___ \ 
 | |  / ____ \ ____) |___) |
 |_| /_/    \_\_____/_____/ 
${reset}]])
    end)
