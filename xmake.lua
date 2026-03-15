---@diagnostic disable: undefined-global, undefined-field, unnecessary-if

local prj_dir  = os.projectdir()
local libs_dir = path.join(prj_dir, "conan_installed")

includes(path.join(prj_dir, "libverilua", "xmake.lua"))
includes(path.join(prj_dir, "src", "cov_exporter", "xmake.lua"))
includes(path.join(prj_dir, "src", "dpi_exporter", "xmake.lua"))
includes(path.join(prj_dir, "src", "signal_db_gen", "xmake.lua"))
includes(path.join(prj_dir, "src", "testbench_gen", "xmake.lua"))
includes(path.join(prj_dir, "src", "wave_vpi", "xmake.lua"))
includes(path.join(prj_dir, "src", "nosim", "xmake.lua"))

local CC = os.getenv("CC")
local CXX = os.getenv("CXX")
if CC then
    set_toolset("cc", CC)
end
if CXX then
    set_toolset("cxx", CXX)
    set_toolset("ld", CXX)
end

target("update_submodules", function()
    set_kind("phony")
    set_default(false)
    on_run(function()
        os.exec("git submodule update --init --recursive")
    end)
end)

target("install_luarocks", function()
    set_kind("phony")
    set_default(false)
    on_run(function()
        local luajit_pro_dir = path.join(prj_dir, "luajit-pro")
        local luarocks_version = "3.12.2"

        -- Add luajit to PATH
        local luajit_dir = path.join(luajit_pro_dir, "luajit2.1")
        os.addenvs({ PATH = path.join(luajit_dir, "bin") })

        -- Build luarocks
        do
            os.cd(luajit_pro_dir)
            os.exec(
                "wget -P %s https://luarocks.github.io/luarocks/releases/luarocks-%s.tar.gz",
                luajit_pro_dir,
                luarocks_version
            )
            os.exec("tar -zxvf luarocks-%s.tar.gz", luarocks_version)
            os.cd("luarocks-" .. luarocks_version)

            os.exec("make clean")
            os.exec("./configure --with-lua=%s --prefix=%s", luajit_dir, luajit_dir)
            os.exec("make")
            os.exec("make install")
        end

        os.cd(prj_dir)
    end)
end)

target("install_luajit", function()
    set_kind("phony")
    set_default(false)
    on_run(function()
        local luajit_pro_dir = path.join(prj_dir, "luajit-pro")
        local luajit_dir = path.join(luajit_pro_dir, "luajit2.1")

        -- Build luajit_pro_helper
        os.cd(luajit_pro_dir)
        os.exec("git submodule update --init")
        os.exec("cargo build --release")
        -- Build luajit
        os.exec("bash init.sh")
        os.trycp(path.join(luajit_dir, "bin", "luajit"), path.join(luajit_dir, "bin", "lua"))

        -- Add luajit to PATH
        os.addenvs({ PATH = path.join(luajit_dir, "bin") })

        -- Install luarocks
        os.exec("xmake run install_luarocks")

        -- Rebuild luajit_pro_helper
        os.cd(luajit_pro_dir)
        os.exec("cargo build --release")

        os.cd(prj_dir)
    end)
end)

target("reinstall_luajit", function()
    set_kind("phony")
    set_default(false)
    on_run(function()
        local luajit_pro_dir = path.join(prj_dir, "luajit-pro")
        local luajit_dir = path.join(luajit_pro_dir, "luajit2.1")

        -- build luajit_pro_helper
        os.cd(luajit_pro_dir)
        os.exec("cargo build --release")

        -- execute("git reset --hard origin/master")
        -- execute("git pull origin master")
        os.exec("bash init.sh")
        os.trycp(path.join(luajit_dir, "bin", "luajit"), path.join(luajit_dir, "bin", "lua"))

        -- Add luajit to PATH
        os.addenvs({ PATH = path.join(luajit_dir, "bin") })

        os.cd(prj_dir)
    end)
end)

target("install_libgmp", function()
    set_kind("phony")
    set_default(false)
    on_run(function()
        if os.getenv("CI_USE_CONAN_CACHE") and os.isfile(libs_dir, "lib", "libgmp.so") then
            print("[xmake.lua] [install_libgmp] Using cached libgmp...")
            return
        end

        local build_dir = path.join(prj_dir, "build")
        local shared_gmp_dir = path.join(prj_dir, "shared", "gmp")
        if not os.isdir(build_dir) then
            os.mkdir(build_dir)
        end
        if not os.isdir(shared_gmp_dir) then
            os.mkdir(shared_gmp_dir)
        end

        local libgmp_xz = "gmp-6.3.0.tar.xz"
        local libgmp_dir = path.join(build_dir, "gmp-6.3.0")
        os.cd(build_dir)
        os.tryrm(libgmp_dir)
        os.tryrm(libgmp_xz)
        os.exec("wget https://ftp.gnu.org/gnu/gmp/" .. libgmp_xz)
        os.exec("tar xJf " .. libgmp_xz)
        os.cd(libgmp_dir)
        os.exec("./configure --prefix=%s --disable-static", libs_dir)
        os.exec("make -j" .. os.cpuinfo().ncpu)
        os.exec("make install")

        -- Copy libgmp into shared dir
        os.cp(path.join(libs_dir, "lib", "libgmp.so*"), shared_gmp_dir)
    end)
end)

target("install_other_libs", function()
    set_kind("phony")
    set_default(false)
    on_run(function()
        -- Environment variable `CI_USE_CONAN_CACHE` is set by `.github/workflows/regression.yml`(Check conan libs)
        if os.getenv("CI_USE_CONAN_CACHE") then
            print("[xmake.lua] [install_other_libs] Using cached conan libs...")

            local shared_gmp_dir = path.join(prj_dir, "shared", "gmp")
            os.mkdir(shared_gmp_dir)
            os.cp(path.join(libs_dir, "lib", "libgmp.so*"), shared_gmp_dir)
            return
        end

        local conan_cmd = "conan"
        local build_dir = path.join(prj_dir, "build")
        local has_conan = try { function() return os.iorun("conan --version") end }

        if not os.isdir(build_dir) then
            os.mkdir(build_dir)
        end

        if not has_conan then
            os.cd(build_dir)
            os.exec("wget https://github.com/conan-io/conan/releases/download/2.14.0/conan-2.14.0-linux-x86_64.tgz")
            os.mkdir("./conan")
            os.exec("tar -xvf conan-2.14.0-linux-x86_64.tgz -C ./conan")
            conan_cmd = path.join(prj_dir, "build", "conan", "bin", "conan")
        end

        os.cd(path.join(prj_dir, "scripts", "conan", "slang"))
        try {
            function()
                os.exec(conan_cmd .. " create . --build=missing")
            end,
            catch
            {
                function(e)
                    os.exec(conan_cmd .. " profile detect --force")
                    os.exec(conan_cmd .. " create . --build=missing")
                end
            }
        }

        os.cd(prj_dir)
        os.exec(conan_cmd .. " install . --output-folder=%s --build=missing", libs_dir)

        -- Install libgmp
        os.exec("xmake run install_libgmp")
    end)
end)

target("install_lua_modules", function()
    set_kind("phony")
    set_default(false)
    on_run(function()
        local luajit_pro_dir = path.join(prj_dir, "luajit-pro")
        local luajit_dir = path.join(luajit_pro_dir, "luajit2.1")
        local libs = {
            "penlight",
            "luasocket",
            -- "lsqlite3",
            "linenoise",
            "argparse", -- Used by teal-language
            "cluacov"
        }

        os.addenvs({ PATH = path.join(luajit_dir, "bin") })
        for i, lib in ipairs(libs) do
            cprint("\t${💥} ${yellow}[5.%d]${reset} install ${green}%s${reset}", i, lib)
            os.exec("luarocks install --force-lock %s", lib)
        end

        -- Workaround install failure for lsqlite3 on 2025.8.16
        os.cd("/tmp")
        os.tryrm("/tmp/lsqlite-src")
        os.exec("git clone https://github.com/cyril0124/lsqlite-src.git")
        os.cd("lsqlite-src")
        os.exec("unzip lsqlite3_v096.zip")
        os.cd("lsqlite3_v096")
        os.exec("luarocks make --force-lock lsqlite3complete-0.9.6-1.rockspec")
        os.exec("luarocks make --force-lock lsqlite3-0.9.6-1.rockspec")

        os.exec("luarocks list")
    end)
end)

target("install_tinycc", function()
    set_kind("phony")
    set_default(false)
    on_run(function()
        os.cd(path.join(prj_dir, "extern", "luajit_tcc"))
        os.exec("make init")
        os.exec("make")
        os.cd(os.workingdir())
    end)
end)

target("build_all_tools", function()
    set_kind("phony")
    set_default(false)
    on_run(function()
        local tools_target = {
            "testbench_gen",
            "dpi_exporter",
            "cov_exporter",
            "signal_db_gen",
            "wave_vpi_main",
            "nosim"
        }
        for _, target in ipairs(tools_target) do
            os.exec("xmake build -y -v %s", target)
        end

        import("lib.detect.find_file")
        if find_file("verdi", { "$(env PATH)" }) and os.getenv("VERDI_HOME") then
            os.exec("xmake build -y -v wave_vpi_main_fsdb")
        end
    end)
end)

target("lsp-check-lua", function()
    set_kind("phony")
    set_default(false)
    on_run(function()
        import("lib.detect.find_file")
        local lua_checker = "emmylua_check"
        if not find_file(lua_checker, { "$(env PATH)" }) then
            raise("emmylua_check tool is not found! Please install it via `cargo install emmylua_check`")
        end

        local emmyrc = path.join(prj_dir, ".emmyrc-lsp-check.json")
        local F = os.getenv("F") -- F is the filename to check
        if F then
            local is_absolute_f = path.is_absolute(F)
            local has_slash = F:find("/") ~= nil

            local src_lua_dir = path.join(prj_dir, "src", "lua")
            local src_gen_dir = path.join(prj_dir, "src", "gen")
            local tests_lua_dir = path.join(prj_dir, "tests")
            local search_dirs = { path.join(src_lua_dir, "**"), src_gen_dir, tests_lua_dir }

            local file = nil
            if is_absolute_f then
                file = F
            elseif has_slash then
                file = path.absolute(F)
            else
                file = find_file(F, search_dirs)
                assert(file ~= nil, "file not found: " .. F)
                assert(type(file) == "string", "multiple files found for: " .. F)
            end
            assert(os.isfile(file), "file not found: " .. file)
            print("[lsp-check-lua] Checking file: " .. file)

            local tmp_file_dir = path.join(prj_dir, "tmp_lua_file_dir")
            local tmp_lib_dir = path.join(prj_dir, "tmp_lua_lib_dir")
            os.mkdir(tmp_file_dir)
            os.cp(file, tmp_file_dir)

            os.mkdir(tmp_lib_dir)
            os.cp(path.join(src_lua_dir, "*"), tmp_lib_dir)
            os.cp(path.join(src_gen_dir, "*.lua"), tmp_lib_dir)
            os.cp(path.join(tests_lua_dir, "*.lua"), tmp_lib_dir)

            local file_name = path.filename(file)
            local _file = find_file(file_name, { path.join(tmp_lib_dir, "**"), tmp_lib_dir })
            if _file then
                assert(type(_file) == "string", "multiple files found in tmp_lib_dir: " .. file_name)
                os.rm(_file)
            end

            try {
                function()
                    os.exec(lua_checker .. " --config " .. emmyrc .. " " .. tmp_file_dir)
                end
            }

            os.exec("rm -rf " .. tmp_file_dir)
            os.exec("rm -rf " .. tmp_lib_dir)
        else
            os.exec(lua_checker .. " --config " .. emmyrc .. " " .. prj_dir)
        end
    end)
end)

target("format-lua", function()
    set_kind("phony")
    set_default(false)
    on_run(function()
        import("lib.detect.find_file")
        if not find_file("CodeFormat", { "$(env PATH)" }) then
            raise("CodeFormat tool is not found! Please install it from https://github.com/CppCXY/EmmyLuaCodeStyle")
        end

        local lua_files = {}
        table.join2(lua_files, os.files(path.join(prj_dir, "*.lua")))
        table.join2(lua_files, os.files(path.join(prj_dir, "tests", "**", "*.lua")))
        table.join2(lua_files, os.files(path.join(prj_dir, "scripts", ".xmake", "**", "*.lua")))
        table.join2(lua_files, os.files(path.join(prj_dir, "src", "lua", "verilua", "**", "*.lua")))
        for _, file in ipairs(lua_files) do
            local filename = path.filename(file)
            if not filename:startswith("ChdlAccess") and
                not filename:startswith("LuaEdgeStepScheduler") and
                not filename:startswith("LuaStepScheduler") and
                not filename:startswith("LuaNormalScheduler")
            then
                cprint("${blue}Formatting: ${green}%s${reset}", file)
                os.exec("CodeFormat format -f " .. file .. " -ow")
            end
        end
    end)
end)

target("format-cpp", function()
    set_kind("phony")
    set_default(false)
    on_run(function()
        import("lib.detect.find_file")
        if not find_file("clang-format", { "$(env PATH)" }) then
            raise("clang-format tool is not found!")
        end

        -- Find all C++ source and header files in src directory
        local cpp_patterns = { "*.cpp", "*.hpp", "*.h", "*.cc", "*.cxx", "*.hxx" }
        local files = {}

        -- Try to use fd first, fallback to find
        local use_fd = find_file("fd", { "$(env PATH)" }) ~= nil

        for _, pattern in ipairs(cpp_patterns) do
            local found
            if use_fd then
                found = os.iorunv("fd", { "--glob", pattern, "src" })
            else
                found = os.iorunv("find", { "src", "-name", pattern, "-type", "f" })
            end

            if found then
                for file in found:gmatch("[^\r\n]+") do
                    table.insert(files, file)
                end
            end
        end

        for _, file in ipairs(files) do
            file = path.absolute(file)
            local filename = path.filename(file)
            if not filename:startswith("svdpi") and not filename:startswith("vpi_user") and not filename:startswith("lightsss") then
                cprint("${blue}Formatting: ${green}%s${reset}", file)
                os.exec("clang-format -i %s", file)
            end
        end
    end)
end)

target("format", function()
    set_kind("phony")
    set_default(false)
    on_run(function()
        os.exec("xmake run format-lua")
        os.exec("xmake run format-cpp")
        os.exec("cargo fmt")
    end)
end)

target("setup_verilua", function()
    set_kind("phony")
    on_run(function()
        local shell_rc = path.join(os.getenv("HOME"), "." .. os.shell() .. "rc")
        local has_match = false

        for line in io.lines(shell_rc) do
            if line:match("^[^#]*export VERILUA_HOME=") then
                has_match = true
            end
        end
        if not has_match then
            local file = io.open(shell_rc, "a")
            if file then
                file:print("")
                file:print("# >>> verilua setup >>>")
                file:print("export VERILUA_HOME=$(curdir)")
                file:print("source $VERILUA_HOME/activate_verilua.sh")
                file:print("# <<< verilua setup <<<")
                file:close()
            end
        end

        cprint("[setup_verilua] shell_rc: ${green underline}%s${reset}, has_match: %s", shell_rc, tostring(has_match))

        os.exec("xmake run -y -v build_libverilua")
        os.exec("xmake build -y -v libsignal_db_gen")
        os.exec("xmake run -y -v build_all_tools")

        import("lib.detect.find_file")
        if find_file("iverilog", { "$(env PATH)" }) then
            os.exec("xmake build -y -v iverilog_vpi_module")
        end
    end)
end)

target("apply_xmake_patch", function()
    set_kind("phony")
    on_run(function()
        local verilua_xmake_dir = path.join(prj_dir, "scripts", ".xmake")

        os.mkdir(path.join("~", ".xmake", "rules", "verilua"))
        os.cp(
            path.join(verilua_xmake_dir, "rules", "verilua", "xmake.lua"),
            path.join("~", ".xmake", "rules", "verilua", "xmake.lua")
        )

        for _, toolchain_dir in ipairs(os.dirs(path.join(verilua_xmake_dir, "toolchains", "*"))) do
            local toolchain_name = path.basename(toolchain_dir)
            os.mkdir(path.join("~", ".xmake", "toolchains", toolchain_name))
            os.cp(
                path.join(toolchain_dir, "*"),
                path.join("~", ".xmake", "toolchains", toolchain_name)
            )
        end
    end)
end)

target("clean_all", function()
    set_kind("phony")
    on_run(function()
        local function rm_common(dir)
            os.tryrm(path.join(dir, "build"))
            os.tryrm(path.join(dir, ".xmake"))
            os.tryrm(path.join(dir, "sim_build"))
            os.tryrm(path.join(dir, "sim_build_*"))
            os.tryrm(path.join(dir, ".dpi_exporter"))
            os.tryrm(path.join(dir, "ucli.key"))
            os.tryrm(path.join(dir, "simv"))
            os.tryrm(path.join(dir, "simv_dpi"))
            os.tryrm(path.join(dir, "simv.daidir"))
            os.tryrm(path.join(dir, "simv_dpi.daidir"))
            os.tryrm(path.join(dir, "csrc"))
            os.tryrm(path.join(dir, "vc_hdrs.h"))
        end

        local examples_dir = path.join(prj_dir, "examples")
        for _, dir in ipairs(os.dirs(path.join(examples_dir, "*"))) do
            rm_common(dir)
        end

        local tests_dir = path.join(prj_dir, "tests")
        for _, dir in ipairs(os.dirs(path.join(tests_dir, "*"))) do
            rm_common(dir)
        end
    end)
end)

target("verilua", function()
    set_kind("phony")
    on_install(function()
        cprint("${💥} ${yellow}[1/7]${reset} Update git submodules...")
        os.exec("xmake run update_submodules")

        cprint("${💥} ${yellow}[2/7]${reset} Install other libs...")
        os.exec("xmake run install_other_libs")

        cprint("${💥} ${yellow}[3/7]${reset} Install LuaJIT-2.1...")
        os.exec("xmake run install_luajit")

        cprint("${💥} ${yellow}[4/7]${reset} Install lua modules...")
        os.exec("xmake run install_lua_modules")

        cprint("${💥} ${yellow}[5/7]${reset} Install tinycc...")
        os.exec("xmake run install_tinycc")

        cprint("${💥} ${yellow}[6/7]${reset} Setup verilua home on ${green}%s${reset}...", os.shell())
        os.exec("xmake run setup_verilua")

        cprint("${💥} ${yellow}[7/7]${reset} Applying verilua patch for xmake...")
        os.exec("xmake run apply_xmake_patch")
    end)
end)

target("test", function()
    set_kind("phony")
    set_default(false)
    on_run(function()
        import("async.runjobs")
        import("lib.detect.find_file")

        local verbose = os.getenv("VERBOSE") == "1" or os.getenv("V") == "1"
        local stop_on_fail = os.getenv("STOP_ON_FAIL") == "1"
        local list_only = os.getenv("VL_TEST_LIST") == "1"
        local keep_workdir = os.getenv("VL_TEST_KEEP_WORKDIR") == "1"
        local filter_expr = os.getenv("VL_TEST_FILTER")
        local max_jobs = tonumber(os.getenv("VL_TEST_JOBS")) or 4

        if max_jobs == nil or max_jobs < 1 then
            max_jobs = 1
        end

        local function format_duration(seconds)
            if seconds < 60 then
                return string.format("%.1fs", seconds)
            elseif seconds < 3600 then
                local min = math.floor(seconds / 60)
                local sec = seconds % 60
                return string.format("%dm %ds", min, sec)
            else
                local hr = math.floor(seconds / 3600)
                local min = math.floor((seconds % 3600) / 60)
                return string.format("%dh %dm", hr, min)
            end
        end

        local function shell_quote(value)
            return "'" .. tostring(value):gsub("'", [['"'"']]) .. "'"
        end

        local function sanitize_name(name)
            local sanitized = name:gsub("[^%w%._%-]+", "_")
            if sanitized == "" then
                sanitized = "job"
            end
            return sanitized
        end

        local function join_case_parts(...)
            local parts = {}
            for _, part in ipairs({ ... }) do
                if part and part ~= "" then
                    table.insert(parts, tostring(part))
                end
            end
            return table.concat(parts, "/")
        end

        local function split_filter_tokens(raw)
            if not raw or raw == "" then
                return nil
            end

            local tokens = {}
            for token in raw:gmatch("[^,]+") do
                token = token:lower():gsub("^%s+", ""):gsub("%s+$", "")
                if token ~= "" then
                    table.insert(tokens, token)
                end
            end

            if #tokens == 0 then
                return nil
            end

            return tokens
        end

        local filter_tokens = split_filter_tokens(filter_expr)
        local case_event_prefix = "@@VL_TEST_CASE@@"

        local function matches_filter(spec)
            if not filter_tokens then
                return true
            end

            local haystack = string.lower(spec.name)
            for _, token in ipairs(filter_tokens) do
                if haystack:find(token, 1, true) then
                    return true
                end
            end

            return false
        end

        ---@class VeriluaTestParallelJobContext
        ---@field run fun(cwd: string, cmd: string, envs?: table<string, string>, opt?: { allow_fail?: boolean }): boolean
        ---@field clean fun(...: string)
        ---@field emit_case_event fun(status: string, case_name: string, duration?: number)
        ---@field run_case fun(case_name: string, runner: fun(): (boolean|nil), opt?: { false_status?: string })
        ---
        ---@param log_file string
        ---@return VeriluaTestParallelJobContext
        local function new_job_context(log_file)
            local function run(cwd, cmd, envs, opt)
                local merged_envs = {
                    VL_TEST_EVENT_LOG = log_file,
                }
                if envs then
                    for key, value in pairs(envs) do
                        merged_envs[key] = value
                    end
                end
                local env_prefix = ""
                if merged_envs then
                    for key, value in pairs(merged_envs) do
                        env_prefix = env_prefix .. key .. "=" .. shell_quote(value) .. " "
                    end
                end
                local shell_cmd = "cd " .. shell_quote(cwd)
                    .. " && "
                    .. env_prefix
                    .. cmd
                    .. " "
                    .. ">>"
                    .. " "
                    .. shell_quote(log_file)
                    .. " 2>&1"
                local ok = true
                try {
                    function()
                        os.execv(os.shell(), { "-c", shell_cmd })
                    end,
                    catch {
                        function(e)
                            ok = false
                            if not (opt and opt.allow_fail) then
                                raise(e)
                            end
                        end
                    }
                }
                return ok
            end

            local function clean(...)
                for _, path_to_remove in ipairs({ ... }) do
                    os.tryrm(path_to_remove)
                end
            end

            local function emit_case_event(status, case_name, duration)
                local file = assert(io.open(log_file, "a"))
                file:write(string.format("%s\t%s\t%s\t%s\n", case_event_prefix, status, case_name,
                    duration ~= nil and tostring(duration) or ""))
                file:close()
            end

            local function run_case(case_name, runner, opt)
                emit_case_event("start", case_name)
                local start_time = os.time()
                local success = true
                local err = nil
                local result = nil
                try {
                    function()
                        result = runner()
                    end,
                    catch {
                        function(e)
                            success = false
                            err = e
                        end
                    }
                }

                local duration = os.time() - start_time
                if success then
                    if result == false then
                        if opt and opt.false_status then
                            emit_case_event(opt.false_status, case_name, duration)
                            return false
                        end
                        emit_case_event("fail", case_name, duration)
                        raise(string.format("case `%s` returned false", case_name))
                    end
                    emit_case_event("pass", case_name, duration)
                    return result
                end

                emit_case_event("fail", case_name, duration)
                raise(err)
            end

            return {
                run = run,
                clean = clean,
                emit_case_event = emit_case_event,
                run_case = run_case,
            }
        end

        local simulators = {}
        local has_verilator = false
        local has_vcs = false
        if find_file("iverilog", { "$(env PATH)" }) then
            table.insert(simulators, "iverilog")
        end
        if find_file("verilator", { "$(env PATH)" }) then
            has_verilator = true
            table.insert(simulators, "verilator")
        end
        if find_file("vcs", { "$(env PATH)" }) then
            has_vcs = true
            table.insert(simulators, "vcs")
        end
        if find_file("xrun", { "$(env PATH)" }) then
            table.insert(simulators, "xcelium")
        end
        assert(#simulators > 0, "No simulators found!")

        local verilator_version
        if has_verilator then
            local version_output = os.iorun("verilator --version")
            local version = version_output:match("Verilator%s+([%d.]+)")
            verilator_version = tonumber(version)
            assert(verilator_version ~= nil, "Failed to parse Verilator version from `verilator --version`")
        end

        ---@class VeriluaTestParallelJobSpec
        ---@field name string
        ---@field run fun(ctx: VeriluaTestParallelJobContext)

        local tests_dir = path.join(prj_dir, "tests")
        local examples_dir = path.join(prj_dir, "examples")
        local suite_start_time = os.time()
        ---@type VeriluaTestParallelJobSpec[]
        local jobspecs = {}
        local job_log_states = {}

        ---@param spec VeriluaTestParallelJobSpec
        local function push_job(spec)
            if matches_filter(spec) then
                jobspecs[#jobspecs + 1] = spec
            end
        end

        local function print_case_event(job_name, status, case_name, duration)
            if status == "start" then
                cprint("    ${dim}[%s]${reset} ${cyan}RUN${reset} ${white}%s${reset}", job_name, case_name)
                return
            end

            local formatted_duration = format_duration(tonumber(duration) or 0)
            if status == "pass" then
                cprint("    ${dim}[%s]${reset} ${green}PASS${reset} ${white}%s${reset} ${dim}(%s)${reset}",
                    job_name, case_name, formatted_duration)
            elseif status == "allow_fail" then
                cprint("    ${dim}[%s]${reset} ${yellow}ALLOW_FAIL${reset} ${white}%s${reset} ${dim}(%s)${reset}",
                    job_name, case_name, formatted_duration)
            elseif status == "fail" then
                cprint("    ${dim}[%s]${reset} ${red}FAIL${reset} ${white}%s${reset} ${dim}(%s)${reset}",
                    job_name, case_name, formatted_duration)
            end
        end

        local function drain_job_log_events(job_name)
            local state = job_log_states[job_name]
            if not state then
                return
            end

            local file = io.open(state.log_file, "r")
            if not file then
                return
            end

            file:seek("set", state.offset)
            local chunk = file:read("*a") or ""
            state.offset = file:seek() or state.offset
            file:close()

            if chunk == "" and state.remainder == "" then
                return
            end

            local buffer = state.remainder .. chunk
            while true do
                local newline_index = buffer:find("\n", 1, true)
                if not newline_index then
                    break
                end

                local line = buffer:sub(1, newline_index - 1):gsub("\r$", "")
                buffer = buffer:sub(newline_index + 1)

                local status, case_name, duration = line:match("^" .. case_event_prefix .. "\t([^\t]+)\t([^\t]+)\t?(.*)$")
                if status and case_name then
                    print_case_event(job_name, status, case_name, duration)
                end
            end

            state.remainder = buffer
        end

        -- =====================================================================
        -- Job Registration (add/remove tests here)
        -- =====================================================================

        -- Core examples: build+run for all sims + cfg_use_inertial_put variant
        local core_examples = {
            "guided_tour",
            "simple_mux",
            "async_queue_native",
            "async_queue_lua",
        }
        push_job({
            name = "examples-core",
            run = function(ctx)
                for _, name in ipairs(core_examples) do
                    local dir = path.join(examples_dir, name)
                    for _, sim in ipairs(simulators) do
                        ctx.run_case(join_case_parts(name, sim), function()
                            ctx.clean(path.join(dir, "build"))
                            ctx.run(dir, "xmake build -v -P .", { SIM = sim })
                            ctx.run(dir, "xmake run -v -P .", { SIM = sim })
                        end)
                    end
                    if has_verilator then
                        ctx.run_case(join_case_parts(name, "verilator", "cfg_use_inertial_put"), function()
                            ctx.clean(path.join(dir, "build"))
                            ctx.run(dir, "xmake build -v -P .", { SIM = "verilator", CFG_USE_INERTIAL_PUT = "1" })
                            ctx.run(dir, "xmake run -v -P .", { SIM = "verilator", CFG_USE_INERTIAL_PUT = "1" })
                        end)
                    end
                end
            end,
        })

        push_job({
            name = "tutorial-example",
            run = function(ctx)
                local dir = path.join(examples_dir, "tutorial_example")
                for _, sim in ipairs(simulators) do
                    local allow_fail = sim == "vcs"
                    ctx.run_case(join_case_parts("tutorial_example", sim), function()
                        ctx.clean(path.join(dir, "build"))
                        ctx.run(dir, "xmake build -v -P .", { SIM = sim })
                        return ctx.run(dir, "xmake run -v -P .", { SIM = sim }, { allow_fail = allow_fail })
                    end, allow_fail and { false_status = "allow_fail" } or nil)
                end
            end,
        })

        push_job({
            name = "simple-ut-env",
            run = function(ctx)
                local dir = path.join(examples_dir, "simple_ut_env")
                for _, sim in ipairs(simulators) do
                    ctx.run_case(join_case_parts("simple_ut_env", sim), function()
                        ctx.clean(path.join(dir, "build"))
                        ctx.run(dir, "xmake build -P . test_counter", { SIM = sim })
                        ctx.run(dir, "xmake run -v -P . test_counter", { SIM = sim })
                    end)
                end
            end,
        })

        push_job({
            name = "wal",
            run = function(ctx)
                local dir = path.join(examples_dir, "WAL")
                for _, sim in ipairs(simulators) do
                    if sim ~= "xcelium" then
                        ctx.clean(path.join(dir, "build"))
                        ctx.run_case(join_case_parts("wal", "gen_wave", sim), function()
                            ctx.run(dir, "xmake build -v -P . gen_wave", { SIM = sim })
                            ctx.run(dir, "xmake run -v -P . gen_wave", { SIM = sim })
                        end)
                        ctx.run_case(join_case_parts("wal", "sim_wave", sim), function()
                            ctx.run(dir, "xmake build -v -P . sim_wave", { SIM = sim })
                            ctx.run(dir, "xmake run -v -P . sim_wave", { SIM = sim })
                        end)
                    end
                end
            end,
        })

        push_job({
            name = "hse",
            run = function(ctx)
                local dir = path.join(examples_dir, "HSE")
                ctx.clean(path.join(dir, "csrc"), path.join(dir, "simv*"), path.join(dir, "sim_build*"))
                if has_verilator then
                    ctx.run_case("hse/run_verilator", function() ctx.run(dir, "./run_verilator.sh") end)
                    ctx.run_case("hse/run_verilator_p", function() ctx.run(dir, "./run_verilator_p.sh") end)
                end
                if has_vcs then
                    ctx.run_case("hse/run_vcs", function() ctx.run(dir, "./run_vcs.sh") end)
                end
            end,
        })

        push_job({
            name = "hse-dummy-vpi",
            run = function(ctx)
                local dir = path.join(examples_dir, "HSE_dummy_vpi")
                ctx.clean(path.join(dir, "csrc"), path.join(dir, "simv*"), path.join(dir, "sim_build*"),
                    path.join(dir, ".dpi_exporter"))
                if has_verilator then
                    ctx.run_case("hse_dummy_vpi/run_verilator", function() ctx.run(dir, "./run_verilator.sh") end)
                    ctx.run_case("hse_dummy_vpi/run_verilator_dpi", function() ctx.run(dir, "./run_verilator_dpi.sh") end)
                end
                if has_vcs then
                    ctx.run_case("hse_dummy_vpi/run_vcs", function() ctx.run(dir, "./run_vcs.sh") end)
                    ctx.run_case("hse_dummy_vpi/run_vcs_dpi", function() ctx.run(dir, "./run_vcs_dpi.sh") end)
                end
            end,
        })

        push_job({
            name = "hse-virtual-rtl",
            run = function(ctx)
                local dir = path.join(examples_dir, "HSE_virtual_rtl")
                ctx.clean(path.join(dir, "sim_build_dpi"), path.join(dir, "csrc"), path.join(dir, "simv_dpi"),
                    path.join(dir, "simv_dpi.daidir"), path.join(dir, ".dpi_exporter"))
                if has_verilator then
                    ctx.run_case("hse_virtual_rtl/run_verilator_dpi",
                        function() ctx.run(dir, "./run_verilator_dpi.sh") end)
                end
                if has_vcs then
                    ctx.run_case("hse_virtual_rtl/run_vcs_dpi", function() ctx.run(dir, "./run_vcs_dpi.sh") end)
                end
            end,
        })

        -- Test targets defined in tests/xmake.lua (add/remove entries to register)
        local test_targets = {
            -- Sim-based tests (one per directory)
            "test-edge",
            "test-set-value",
            "test-basic-signal",
            "test-scheduler",
            "test-comb",
            "test-comb-1",
            "test-bitvec-signal",
            "test-no-internal-clock",
            "test-handles",
            "test-native-clock",
            "test-queue-waitable",
            "test-dpic",
            -- Wave VPI tests (one per directory)
            "test-wave-vpi",
            "test-wave-vpi-x",
            "test-wave-vpi-print-hier",
            "test-wave-vpi-module-name",
            -- Benchmarks
            "test-benchmarks",
            "test-benchmarks-wave-vpi",
            -- Testbench gen
            "test-testbench-gen",
            -- Tool tests (one per directory)
            "test-dpi-exporter",
            "test-cov-exporter",
            "test-signal-db",
            -- Standalone Lua tests
            "test-all-lua",
        }
        for _, name in ipairs(test_targets) do
            push_job({
                name = "tests/" .. name,
                run = function(ctx) ctx.run(tests_dir, "xmake run -P . " .. name) end,
            })
        end

        local border_line = string.rep("=", 78)
        cprint("")
        cprint("${bright}%s${reset}", border_line)
        cprint("${cyan}VERILUA${reset} ${white}PARALLEL TEST SUITE${reset}")
        cprint("${bright}%s${reset}", border_line)
        cprint("${white}Configuration:${reset}")
        cprint("  ${dim}•${reset} Simulators: ${cyan}%s${reset}", table.concat(simulators, ", "))
        cprint("  ${dim}•${reset} Max jobs: ${cyan}%d${reset}", max_jobs)
        cprint("  ${dim}•${reset} Verbose: ${cyan}%s${reset}", verbose and "yes" or "no")
        cprint("  ${dim}•${reset} Stop on fail: ${cyan}%s${reset}", stop_on_fail and "yes" or "no")
        cprint("  ${dim}•${reset} Filter: ${cyan}%s${reset}", filter_expr or "<none>")
        cprint("  ${dim}•${reset} Keep workdir: ${cyan}%s${reset}", keep_workdir and "yes" or "no")
        cprint("  ${dim}•${reset} Started at: ${cyan}%s${reset}", os.date("%Y-%m-%d %H:%M:%S"))

        assert(#jobspecs > 0, string.format("No test jobs matched VL_TEST_FILTER=%s", filter_expr or "<none>"))

        if list_only then
            cprint("")
            cprint("${white}Matched Jobs (${bright}%d${reset}${white}):${reset}", #jobspecs)
            for idx, spec in ipairs(jobspecs) do
                cprint("  ${dim}%2d.${reset} ${green}%s${reset}", idx, spec.name)
            end
            return
        end

        math.randomseed(os.time())
        local run_tag = os.date("%Y%m%d-%H%M%S") .. "-" .. tostring(math.random(100000, 999999))
        local log_root = path.join(prj_dir, ".xmake", "test", run_tag)
        os.mkdir(path.join(prj_dir, ".xmake", "test"))
        os.mkdir(log_root)

        local job_results = {}
        local stop_requested = false

        local function execute_job(spec, index, total)
            local start_time = os.time()
            if stop_requested then
                job_results[spec.name] = { name = spec.name, skipped = true, success = false, duration = 0 }
                cprint("  ${bright}=${reset} ${yellow}- SKIPPED${reset} ${white}%s${reset} ${dim}(STOP_ON_FAIL)${reset}",
                    spec.name)
                return
            end

            cprint("  ${bright}=${reset} ${white}[%d/%d]${reset} ${green}%s${reset}", index, total, spec.name)

            local log_file = path.join(log_root, sanitize_name(spec.name) .. ".log")
            local log_handle = assert(io.open(log_file, "w"))
            log_handle:close()
            job_log_states[spec.name] = {
                log_file = log_file,
                offset = 0,
                remainder = "",
            }
            local success = true
            local failure_reason = nil
            try {
                function()
                    local ctx = new_job_context(log_file)
                    spec.run(ctx)
                end,
                catch {
                    function(e)
                        success = false
                        failure_reason = e
                    end
                }
            }
            drain_job_log_events(spec.name)

            if not success and stop_on_fail then
                stop_requested = true
            end

            local duration = os.time() - start_time
            job_results[spec.name] = {
                name = spec.name,
                skipped = false,
                success = success,
                duration = duration,
                log_file = log_file,
                error = failure_reason,
            }

            if success then
                cprint("  ${bright}=${reset} ${green}✓ PASSED${reset} ${white}%s${reset} ${dim}(%s)${reset}", spec.name,
                    format_duration(duration))
            else
                cprint(
                    "  ${bright}=${reset} ${red}✗ FAILED${reset} ${white}%s${reset} ${dim}(%s)${reset} ${dim}[log: %s]${reset}",
                    spec.name, format_duration(duration), log_file)
            end
        end

        runjobs("verilua-test", function(index, total, _opt)
            execute_job(jobspecs[index], index, total)
        end, {
            total = #jobspecs,
            comax = max_jobs,
            timeout = 500,
            on_timer = function(running_job_indices)
                for _, job_index in ipairs(running_job_indices or {}) do
                    local spec = jobspecs[job_index]
                    if spec then
                        drain_job_log_events(spec.name)
                    end
                end
            end,
            isolate = true,
            waiting_indicator = true,
            progress_refresh = true,
        })

        for _, spec in ipairs(jobspecs) do
            drain_job_log_events(spec.name)
        end

        local stats = { total = #jobspecs, passed = 0, failed = 0, skipped = 0, duration = os.time() - suite_start_time }
        local failed_jobs = {}
        for _, spec in ipairs(jobspecs) do
            local result = job_results[spec.name]
            if not result or result.skipped then
                stats.skipped = stats.skipped + 1
            elseif result.success then
                stats.passed = stats.passed + 1
            else
                stats.failed = stats.failed + 1
                failed_jobs[#failed_jobs + 1] = result
            end
        end

        cprint("")
        cprint("${bright}%s${reset}", border_line)
        cprint("${cyan}PARALLEL TEST SUMMARY${reset}")
        cprint("${bright}%s${reset}", border_line)
        cprint("  ${white}Total Jobs:${reset} ${bright}%d${reset}", stats.total)
        cprint("  ${green}Passed:${reset}     ${green}%d${reset}", stats.passed)
        if stats.failed > 0 then
            cprint("  ${red}Failed:${reset}     ${red}%d${reset}", stats.failed)
        else
            cprint("  ${dim}Failed:${reset}     ${dim}%d${reset}", stats.failed)
        end
        if stats.skipped > 0 then
            cprint("  ${yellow}Skipped:${reset}    ${yellow}%d${reset}", stats.skipped)
        else
            cprint("  ${dim}Skipped:${reset}    ${dim}%d${reset}", stats.skipped)
        end
        cprint("  ${white}Duration:${reset}   ${bright}%s${reset}", format_duration(stats.duration))
        cprint("${bright}%s${reset}", border_line)

        -- Per-group timing breakdown (sorted by duration, longest first)
        local sorted_results = {}
        for _, spec in ipairs(jobspecs) do
            local result = job_results[spec.name]
            if result then
                sorted_results[#sorted_results + 1] = result
            end
        end
        table.sort(sorted_results, function(a, b) return a.duration > b.duration end)

        local max_name_len = 0
        for _, result in ipairs(sorted_results) do
            if #result.name > max_name_len then
                max_name_len = #result.name
            end
        end

        cprint("")
        cprint("${cyan}PER-GROUP TIMING${reset}")
        for _, result in ipairs(sorted_results) do
            local padded_name = result.name .. string.rep(" ", max_name_len - #result.name)
            if result.skipped then
                cprint("  ${yellow}-${reset} %s  ${yellow}SKIPPED${reset}", padded_name)
            elseif result.success then
                cprint("  ${green}✓${reset} %s  ${bright}%s${reset}", padded_name, format_duration(result.duration))
            else
                cprint("  ${red}✗${reset} %s  ${bright}%s${reset}", padded_name, format_duration(result.duration))
            end
        end
        cprint("")

        if #failed_jobs > 0 then
            cprint("${red}Failed jobs:${reset}")
            for _, result in ipairs(failed_jobs) do
                cprint("  ${red}•${reset} ${white}%s${reset} ${dim}[log: %s]${reset}", result.name, result.log_file)
            end
            if verbose then
                for _, result in ipairs(failed_jobs) do
                    local log_content = result.log_file and io.readfile(result.log_file) or nil
                    if log_content and log_content ~= "" then
                        cprint("")
                        cprint("${bright}%s${reset}", border_line)
                        cprint("${red}LOG:${reset} ${white}%s${reset}", result.name)
                        cprint("${bright}%s${reset}", border_line)
                        print(log_content)
                    end
                end
            end
        end

        if stats.failed > 0 or keep_workdir then
            cprint("${white}Log root:${reset} ${cyan}%s${reset}", log_root)
        else
            os.tryrm(log_root)
        end

        if stats.failed > 0 then
            raise("test failed: %d job(s) failed", stats.failed)
        end
    end)
end)
