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
includes(path.join(prj_dir, "src", "sv_lint", "xmake.lua"))
includes(path.join(prj_dir, "src", "turso_ffi", "xmake.lua"))

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
        os.exec("git -C %s submodule update --init --recursive", prj_dir)
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
            import("net.http")
            import("utils.archive")

            local tarball = path.join(luajit_pro_dir, "luarocks-" .. luarocks_version .. ".tar.gz")
            if not os.isfile(tarball) then
                local url = "https://luarocks.github.io/luarocks/releases/luarocks-" .. luarocks_version .. ".tar.gz"
                print("[xmake.lua] [install_luarocks] Downloading luarocks...")
                http.download(url, tarball)
            end
            archive.extract(tarball, luajit_pro_dir)

            local luarocks_src_dir = path.join(luajit_pro_dir, "luarocks-" .. luarocks_version)
            os.cd(luarocks_src_dir)

            os.exec("make clean")
            os.exec("./configure --with-lua=%s --prefix=%s", luajit_dir, luajit_dir)
            os.exec("make -j%d", os.cpuinfo().ncpu or 4)
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
        os.exec("git -C %s submodule update --init", luajit_pro_dir)
        os.cd(luajit_pro_dir)
        os.exec("cargo build --release")
        -- Build luajit
        os.exec("bash init.sh")
        os.trycp(path.join(luajit_dir, "bin", "luajit"), path.join(luajit_dir, "bin", "lua"))

        -- Add luajit to PATH
        os.addenvs({ PATH = path.join(luajit_dir, "bin") })

        -- Install luarocks
        os.exec("xmake run -P %s install_luarocks", prj_dir)

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
        local libgmp_tarball = path.join(build_dir, libgmp_xz)

        if not os.isdir(libgmp_dir) then
            import("net.http")
            import("utils.archive")

            if not os.isfile(libgmp_tarball) then
                print("[xmake.lua] [install_libgmp] Downloading libgmp...")
                http.download("https://ftp.gnu.org/gnu/gmp/" .. libgmp_xz, libgmp_tarball)
            end

            print("[xmake.lua] [install_libgmp] Extracting libgmp...")
            archive.extract(libgmp_tarball, build_dir)
        end

        os.cd(libgmp_dir)
        os.exec("./configure --prefix=%s --disable-static", libs_dir)
        os.exec("make -j%d", os.cpuinfo().ncpu or 4)
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
        local conan_dir = path.join(build_dir, "conan")
        local conan_bin = path.join(conan_dir, "bin", "conan")

        local has_conan = try { function() return os.iorun("conan --version") end }

        if not os.isdir(build_dir) then
            os.mkdir(build_dir)
        end

        if not has_conan then
            if os.isexec(conan_bin) then
                conan_cmd = conan_bin
            else
                import("net.http")
                import("utils.archive")

                local url = "https://github.com/conan-io/conan/releases/download/2.14.0/conan-2.14.0-linux-x86_64.tgz"
                local tgz_path = path.join(build_dir, "conan-2.14.0.tgz")

                print("[xmake.lua] [install_other_libs] Downloading conan...")
                local downloaded = false
                for attempt = 1, 3 do
                    local ok = try {
                        function()
                            http.download(url, tgz_path)
                            return true
                        end
                    }
                    if ok and os.isfile(tgz_path) then
                        downloaded = true
                        break
                    else
                        print(string.format("[xmake.lua] [install_other_libs] Download failed (attempt %d/3), retrying...", attempt))
                        os.tryrm(tgz_path)
                        os.sleep(1000)
                    end
                end
                if not downloaded then
                    raise("[xmake.lua] [install_other_libs] Failed to download conan after 3 attempts.")
                end

                print("[xmake.lua] [install_other_libs] Extracting conan...")
                archive.extract(tgz_path, conan_dir)
                os.rm(tgz_path)

                conan_cmd = conan_bin
            end
        end

        local ncpu = os.cpuinfo().ncpu or 4
        local jobs_arg = string.format("-c tools.build:jobs=%d", ncpu)

        os.cd(path.join(prj_dir, "scripts", "conan", "slang"))
        try {
            function()
                os.exec("%s create . --build=missing %s", conan_cmd, jobs_arg)
            end,
            catch
            {
                function(e)
                    os.exec(conan_cmd .. " profile detect --force")
                    os.exec("%s create . --build=missing %s", conan_cmd, jobs_arg)
                end
            }
        }

        os.cd(prj_dir)
        os.exec("%s install . --output-folder=%s --build=missing %s", conan_cmd, libs_dir, jobs_arg)

        -- Install libgmp
        os.exec("xmake run -P %s install_libgmp", prj_dir)
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
            "sv_lint",
            "wave_vpi_main",
            "nosim"
        }
        for _, target in ipairs(tools_target) do
            os.exec("xmake build -P %s -y -v %s", prj_dir, target)
        end

        import("lib.detect.find_file")
        if find_file("verdi", { "$(env PATH)" }) then
            local ok = try { function()
                os.exec("xmake build -P %s -y -v wave_vpi_main_fsdb", prj_dir)
                return true
            end }
            if not ok then
                cprint(
                    "${yellow}[WARN] skip wave_vpi_main_fsdb build: verdi was found but FSDB dependencies are not usable${clear}")
            end
        end
    end)
end)

target("lsp-check-lua", function()
    set_kind("phony")
    set_default(false)
    on_run(function()
        import("lib.detect.find_tool")
        local python = find_tool("python3") or find_tool("python")
        if not python then
            raise("python3 not found in PATH")
        end

        local input = os.getenv("F")
        local check_path = path.join(prj_dir, "src", "lua")
        if input and input ~= "" then
            check_path = path.absolute(input, prj_dir)
        end
        if not os.isfile(check_path) and not os.isdir(check_path) then
            raise("lsp-check-lua path not found: " .. check_path)
        end
        if os.isfile(check_path) and path.extension(check_path) ~= ".lua" then
            raise("lsp-check-lua file must be .lua: " .. check_path)
        end

        local check_script = path.join(prj_dir, "scripts", "emmylua_ls_check.py")
        if not os.isfile(check_script) then
            raise("lsp-check-lua script not found: " .. check_script)
        end
        print("[lsp-check-lua] Checking: " .. check_path)
        os.execv(python.program, {
            check_script,
            check_path,
            "--root",
            prj_dir
        })
    end)
end)

target("format-lua", function()
    set_kind("phony")
    set_default(false)
    on_run(function()
        import("lib.detect.find_tool")
        local python = find_tool("python3") or find_tool("python")
        if not python then
            raise("python3 not found in PATH")
        end

        local format_script = path.join(prj_dir, "scripts", "emmylua_format.py")
        if not os.isfile(format_script) then
            raise("format-lua script not found: " .. format_script)
        end

        local function is_generated_lua(file)
            local filename = path.filename(file)
            return filename:startswith("ChdlAccess")
                or filename:startswith("LuaEdgeStepScheduler")
                or filename:startswith("LuaStepScheduler")
                or filename:startswith("LuaNormalScheduler")
        end

        local input = os.getenv("F")
        local format_paths = {}
        if input and input ~= "" then
            table.insert(format_paths, path.absolute(input, prj_dir))
        else
            table.join2(format_paths, os.files(path.join(prj_dir, "*.lua")))
            local candidates = {}
            table.join2(candidates, os.files(path.join(prj_dir, "tests", "**", "*.lua")))
            table.join2(candidates, os.files(path.join(prj_dir, "scripts", "xmake", "**", "*.lua")))
            table.join2(candidates, os.files(path.join(prj_dir, "src", "lua", "verilua", "**", "*.lua")))
            for _, file in ipairs(candidates) do
                if not is_generated_lua(file) then
                    table.insert(format_paths, file)
                end
            end
        end

        for _, format_path in ipairs(format_paths) do
            if not os.isfile(format_path) and not os.isdir(format_path) then
                raise("format-lua path not found: " .. format_path)
            end
            if os.isfile(format_path) and path.extension(format_path) ~= ".lua" then
                raise("format-lua file must be .lua: " .. format_path)
            end
        end

        local args = { format_script }
        for _, format_path in ipairs(format_paths) do
            table.insert(args, format_path)
        end
        os.execv(python.program, args)
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
        os.exec("xmake run -P %s format-lua", prj_dir)
        os.exec("xmake run -P %s format-cpp", prj_dir)
        os.exec("cargo fmt")
    end)
end)

target("setup_verilua", function()
    set_kind("phony")
    on_run(function()
        local shell_rc = path.join(os.getenv("HOME"), "." .. os.shell() .. "rc")
        if os.islink(shell_rc) then
            shell_rc = path.absolute(os.readlink(shell_rc), path.directory(shell_rc))
        end
        local activate = "source '" .. path.join(prj_dir, "verilua.sh"):gsub("'", "'\\''") .. "'"
        local lines = {}
        local in_block = false
        if os.isfile(shell_rc) then
            for line in io.lines(shell_rc) do
                if line:find("# >>> verilua setup >>>", 1, true) then
                    in_block = true
                elseif line:find("# <<< verilua setup <<<", 1, true) then
                    in_block = false
                elseif not in_block then
                    table.insert(lines, line)
                end
            end
            if in_block then
                raise("setup_verilua: unterminated verilua setup block in " .. shell_rc)
            end
            while #lines > 0 and lines[#lines] == "" do
                table.remove(lines)
            end
        end
        if #lines > 0 then
            table.insert(lines, "")
        end
        table.insert(lines, "# >>> verilua setup >>>")
        table.insert(lines, activate)
        table.insert(lines, "# <<< verilua setup <<<")
        local content = table.concat(lines, "\n") .. "\n"
        local tmp = shell_rc .. ".tmp"
        io.writefile(tmp, content)
        if os.filesize(tmp) ~= #content then
            os.rm(tmp)
            raise("setup_verilua: incomplete write to " .. tmp)
        end
        os.mv(tmp, shell_rc)
        cprint("[setup_verilua] wrote ${green}%s${reset}", activate)
        cprint("[setup_verilua] this shell: ${green}%s${reset}", activate)

        os.exec("xmake run -P %s -y -v build_libverilua", prj_dir)
        os.exec("xmake build -P %s -y -v libsignal_db_gen", prj_dir)
        os.exec("xmake build -P %s -y -v libsv_lint", prj_dir)
        os.exec("xmake build -P %s -y -v turso_ffi", prj_dir)
        os.exec("xmake run -P %s -y -v build_all_tools", prj_dir)

        import("lib.detect.find_file")
        if find_file("iverilog", { "$(env PATH)" }) then
            os.exec("xmake build -P %s -y -v iverilog_vpi_module", prj_dir)
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
        cprint("${💥} ${yellow}[1/6]${reset} Update git submodules...")
        os.exec("xmake run -P %s update_submodules", prj_dir)

        cprint("${💥} ${yellow}[2/6]${reset} Install other libs...")
        os.exec("xmake run -P %s install_other_libs", prj_dir)

        cprint("${💥} ${yellow}[3/6]${reset} Install LuaJIT-2.1...")
        os.exec("xmake run -P %s install_luajit", prj_dir)

        cprint("${💥} ${yellow}[4/6]${reset} Install lua modules...")
        os.exec("xmake run -P %s install_lua_modules", prj_dir)

        cprint("${💥} ${yellow}[5/6]${reset} Install tinycc...")
        os.exec("xmake run -P %s install_tinycc", prj_dir)

        cprint("${💥} ${yellow}[6/6]${reset} Setup verilua home on ${green}%s${reset}...", os.shell())
        os.exec("xmake run -P %s setup_verilua", prj_dir)
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
        -- if find_file("xrun", { "$(env PATH)" }) then
        --     table.insert(simulators, "xcelium")
        -- end
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
            "fork_basics",
            "combinational_logic",
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
                            ctx.run(dir, "xmake build -v -P .", { SIM = "verilator", VL_XMK_USE_INERTIAL_PUT = "1" })
                            ctx.run(dir, "xmake run -v -P .", { SIM = "verilator", VL_XMK_USE_INERTIAL_PUT = "1" })
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
            "test-issue11",
            "test-basic-signal",
            "test-scheduler",
            "test-comb",
            "test-comb-await-rw",
            "test-await-rw-corner",
            "test-rw-flush",
            "test-rw-reflush-panic",
            "test-readonly-write-error",
            "test-comb-1",
            "test-bitvec-signal",
            "test-no-internal-clock",
            "test-handles",
            "test-force-release-coalesce",
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
            "test-dpi-exporter-chdl",
            "test-dummy-vpi",
            "test-cov-exporter",
            "test-cov-exporter-dynamic",
            "test-signal-db",
            -- slang_common unit tests
            "test-slang-common",
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
