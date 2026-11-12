---@diagnostic disable: undefined-global, undefined-field

local project_dir = os.scriptdir()
local root_dir = path.join(project_dir, "..", "..")
local luasim_bin = path.join(root_dir, "tools", "luasim")
local results_root = path.join(project_dir, "build", "validation")
local artifact_dir = path.join(results_root, "results")
local case_timeout = 15
local build_timeout = 300

--- Wrap a value in single quotes for safe shell interpolation.
local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", [['"'"']]) .. "'"
end

local scripts = {
    main = "main.lua",
    ready_valid = "ready_valid.lua",
}

--- Patterns are lowercase Lua patterns matched against the case diagnostics that
--- remain after its CASE_READY/FINAL/PASS lines are removed.
local negative_cases = {
    duplicate_path = { "already", "duplicate", "repeated" },
    missing_signal = { "not found", "unknown signal", "missing", "does not exist", "cannot find" },
    width_zero = { "width", "positive" },
    width_negative = { "width", "positive" },
    width_fraction = { "width", "integer" },
    unknown_x = { "x/z", "x or z", "unknown", "two.state", "2.state" },
    unknown_z = { "x/z", "x or z", "unknown", "two.state", "2.state" },
    declare_initial = { "declar", "initial", "started", "registration", "frozen" },
    declare_task = { "declar", "task", "started", "registration", "frozen" },
    force = { "unsupported.*force", "not support.*force", "unavailable.*force", "force.*unsupported",
        "force.*not support", "force.*unavailable" },
    release = { "unsupported.*release", "not support.*release", "unavailable.*release", "release.*unsupported",
        "release.*not support", "release.*unavailable" },
    freeze = { "unsupported.*freeze" },
    freeze_imm = { "unsupported.*freeze" },
    array = { "array", "index" },
    readonly_set = { "readonly", "read only", "read.only", "read.phase" },
    readonly_immediate = { "readonly", "read only", "read.only", "read.phase" },
    readonly_hex = { "readonly", "read only", "read.only", "read.phase" },
    readonly_rw = { "readonly", "read only", "read.only", "read.phase" },
    readonly_delta = { "readonly", "read only", "read.only", "read.phase" },
    negative_time = { "time", "delay", "non.negative" },
    fractional_step = { "integer", "step", "time" },
    max_time = { "max_time", "time.*limit", "limit.*time" },
    max_delta = { "max_delta", "delta.*limit", "limit.*delta" },
    default_delta_limit = { "max_delta", "delta.*limit", "limit.*delta" },
    module_error = { "injected module failure" },
    initial_error = { "injected initial failure" },
    task_error = { "injected task failure" },
    invalid_delta_false = { "max_delta_cycles.*safe integer" },
    invalid_max_time_false = { "max_time.*safe integer" },
    invalid_max_time_zero = { "max_time.*safe integer" },
}

local startup_failures = {
    invalid_precision_fraction = { "time_precision.*integer" },
    unsupported_step_mode = { "scheduler mode", "mode" },
}

local configs = {
    invalid_precision_fraction = "return { time_precision = -9.5 }\n",
    unsupported_step_mode = 'return { mode = "step" }\n',
    config = 'return { top = "custom_tb", time_precision = -9 }\n',
}

local positive_cases = {
    "main", "ready_valid", "config", "initial_declaration",
    "native_clock", "any_change", "randomize",
    "collect_signals_rejected", "auto_bundle_rejected",
    "no_default_time_limit", "readonly_future", "finish_twice", "wave",
    "finish_top", "finish_initial", "wave_before_tasks", "native_backend", "callback_reuse_stress",
    "declaration_validation", "inflight_cancel", "next_time_before_timer", "batch_task_reuse",
    "try_restart_completed", "append_completed", "ull_limits",
    "queue_empty_edge", "queue_empty_nsim",
}

---@class LuasimSuite
---@field run_all_cases fun(): integer
---@field run_project_target fun(target_name: string, marker: string, envs: table<string,string>, out_dir: string): string[]
---@field check_transactions fun(output: string, out_dir: string): string[]
---@field report_target fun(failures: string[], label: string)

-- xmake exposes the complete os/io API only inside a target script, so the runner
-- takes those tables from on_run instead of reading the globals at file scope.
---@param sandbox { os: table, io: table }
---@return LuasimSuite
local function build_suite(sandbox)
    local xmake_os, xmake_io = sandbox.os, sandbox.io

    local function case_names()
        local names = {}
        for _, name in ipairs(positive_cases) do
            table.insert(names, name)
        end
        for _, name in ipairs(table.orderkeys(negative_cases)) do
            table.insert(names, name)
        end
        for _, name in ipairs(table.orderkeys(startup_failures)) do
            table.insert(names, name)
        end
        return names
    end

    ---@param lowercase_text string
    ---@param patterns string[]
    ---@return boolean
    local function matches_any(lowercase_text, patterns)
        for _, pattern in ipairs(patterns) do
            if lowercase_text:find(pattern) then
                return true
            end
        end
        return false
    end

    ---@param text string
    ---@param expected string
    ---@return boolean
    local function has_line(text, expected)
        for line in (text .. "\n"):gmatch("([^\n]*)\n") do
            if line == expected then
                return true
            end
        end
        return false
    end

    ---@param text string
    ---@return string[]
    local function final_lines(text)
        local lines = {}
        for line in (text .. "\n"):gmatch("([^\n]*)\n") do
            if line:find("^FINAL ") then
                table.insert(lines, line)
            end
        end
        return lines
    end

    --- Run one command under a bounded timeout and capture its combined output.
    ---@param command string Shell command, already quoted
    ---@param envs table<string,string> Environment assignments
    ---@param work_dir string Directory to run in, so relative artifacts land there
    ---@param log_path string File receiving combined stdout and stderr
    ---@param timeout_seconds integer
    ---@return { returncode: number, output: string, log: string }
    local function run_process(command, envs, work_dir, log_path, timeout_seconds)
        local assignments = {}
        for key, value in pairs(envs) do
            table.insert(assignments, key .. "=" .. shell_quote(value))
        end
        table.sort(assignments)

        -- The trailing printf keeps the exit status in the saved log, so a failing
        -- case leaves a readable artifact instead of an xmake error.
        local script = string.format(
            "cd %s && { env -u SIM -u VL_CFG_FILE -u VL_LUA_SCRIPT -u VL_DUT_TOP -u VL_TEST_LUASIM_CASE %s " ..
            "timeout %d %s; printf '__VL_EXIT__%%d\\n' $?; } > %s 2>&1",
            shell_quote(work_dir), table.concat(assignments, " "), timeout_seconds, command, shell_quote(log_path))
        xmake_os.execv(xmake_os.shell(), { "-c", script })

        local output = xmake_io.readfile(log_path) or ""
        local returncode = tonumber(output:match("__VL_EXIT__(%d+)%s*$")) or -1
        output = output:gsub("__VL_EXIT__%d+%s*$", "")
        return { returncode = returncode, output = output, log = log_path }
    end

    --- Check the case contract: ready marker, one final callback, pass marker, or for
    --- the negative cases a nonzero exit plus the expected diagnostic.
    ---@param result { returncode: number, output: string, log: string }
    ---@param marker string
    ---@return string[]
    local function validate(result, marker)
        local failures = {}
        local output = result.output
        if result.returncode == 124 or result.returncode == 137 then
            table.insert(failures, "subprocess exceeded its bounded timeout")
            return failures
        end

        if startup_failures[marker] then
            if result.returncode == 0 then
                table.insert(failures, "invalid startup configuration exited successfully")
            end
            if output:find("CASE_READY ", 1, true) then
                table.insert(failures, "user script ran after invalid startup configuration")
            end
            if not matches_any(output:lower(), startup_failures[marker]) then
                table.insert(failures, "missing startup configuration diagnostic")
            end
            return failures
        end

        local expected_diagnostics = negative_cases[marker]
        if expected_diagnostics == nil then
            if result.returncode ~= 0 then
                table.insert(failures, "positive case did not complete successfully")
            end
            if not has_line(output, "CASE_READY " .. marker) then
                table.insert(failures, "test body never reached its ready marker")
            end
            local finals = final_lines(output)
            if #finals ~= 1 or finals[1] ~= "FINAL " .. marker .. " 1" then
                table.insert(failures, "expected one final callback, got " .. table.concat(finals, ","))
            end
            if not has_line(output, "PASS " .. marker) then
                table.insert(failures, "positive case did not print its pass marker")
            end
            return failures
        end

        if result.returncode == 0 then
            table.insert(failures, "negative case exited successfully")
        end
        local diagnostics = {}
        for line in (output .. "\n"):gmatch("([^\n]*)\n") do
            if not (line:find("^CASE_READY ") or line:find("^FINAL ") or line:find("^PASS ")) then
                table.insert(diagnostics, line)
            end
        end
        if not matches_any(table.concat(diagnostics, "\n"):lower(), expected_diagnostics) then
            table.insert(failures, "missing explicit diagnostic matching: " .. table.concat(expected_diagnostics, " | "))
        end
        if output:find("NEGATIVE_CASE_RETURNED", 1, true) or has_line(output, "PASS " .. marker) then
            table.insert(failures, "unsupported operation returned without raising")
        end
        return failures
    end

    ---@param bits string
    ---@return string
    local function strip_leading_zeros(bits)
        return (bits:gsub("^0+", ""))
    end

    --- Expand a hexadecimal literal into a binary bit string.
    ---@param hex string
    ---@return string
    local function hex_to_bits(hex)
        local nibbles = {
            ["0"] = "0000",
            ["1"] = "0001",
            ["2"] = "0010",
            ["3"] = "0011",
            ["4"] = "0100",
            ["5"] = "0101",
            ["6"] = "0110",
            ["7"] = "0111",
            ["8"] = "1000",
            ["9"] = "1001",
            a = "1010",
            b = "1011",
            c = "1100",
            d = "1101",
            e = "1110",
            f = "1111",
        }
        local parts = {}
        for character in hex:gmatch("%x") do
            table.insert(parts, nibbles[character:lower()])
        end
        return strip_leading_zeros(table.concat(parts))
    end

    --- Verify the dump keeps both 129-bit values and emits ordered 5/10 steps.
    ---@param vcd_path string
    ---@return string[]
    local function check_wave(vcd_path)
        if not xmake_os.isfile(vcd_path) then
            return { "wave.vcd was not created" }
        end
        local content = xmake_io.readfile(vcd_path) or ""
        local failures = {}
        local wide_codes = {}
        local wide_set = {}
        for width, code, name in content:gmatch("%$var%s+%S+%s+(%d+)%s+(%S+)%s+(%S+)") do
            if width == "129" and name == "wide" then
                table.insert(wide_codes, code)
                wide_set[code] = true
            end
        end
        if not content:find("$enddefinitions", 1, true) or #wide_codes == 0 then
            table.insert(failures, "VCD lacks definitions or the 129-bit signal")
        end

        local timestamps = {}
        for value in content:gmatch("\n#(%d+)") do
            table.insert(timestamps, tonumber(value))
        end
        local ordered = true
        for index = 2, #timestamps do
            if timestamps[index] < timestamps[index - 1] then
                ordered = false
            end
        end
        local has_five, has_ten = false, false
        for _, value in ipairs(timestamps) do
            if value == 5 then
                has_five = true
            elseif value == 10 then
                has_ten = true
            end
        end
        if not ordered or not (has_five and has_ten) then
            table.insert(failures, "VCD timestamps do not contain ordered steps 5 and 10")
        end

        local seen = {}
        for bits, code in content:gmatch("\n[bB]([01]+)%s+(%S+)") do
            if wide_set[code] then
                seen[strip_leading_zeros(bits)] = true
            end
        end
        local expected = {
            hex_to_bits("10123456789abcdeffedcba9876543210"),
            hex_to_bits("100000000000000000000000000000001"),
        }
        for _, value in ipairs(expected) do
            if not seen[value] then
                table.insert(failures, "VCD did not preserve both 129-bit values")
                break
            end
        end
        return failures
    end

    --- Verify the early dump declares every identifier whose value it writes.
    ---@param vcd_path string
    ---@return string[]
    local function check_early_wave(vcd_path)
        if not xmake_os.isfile(vcd_path) then
            return { "early waveform was not created" }
        end
        local content = xmake_io.readfile(vcd_path) or ""
        local failures = {}
        local codes = {}
        local late = {}
        for width, code, name in content:gmatch("%$var%s+%S+%s+(%d+)%s+(%S+)%s+(%S+)") do
            codes[code] = true
            if width == "1" and name == "late" then
                table.insert(late, code)
            end
        end
        if #late ~= 1 or not content:find("1" .. late[1] .. "\n", 1, true) then
            table.insert(failures, "declared signal or initial-callback value missing from VCD")
        end
        for line in (content .. "\n"):gmatch("([^\n]*)\n") do
            local code
            if line:sub(1, 1) == "b" then
                code = line:match("%s(%S+)$")
            elseif line:sub(1, 1):match("[01xz]") then
                code = line:sub(2)
            end
            if code and not codes[code] then
                table.insert(failures, "VCD uses an undeclared signal identifier: " .. code)
            end
        end
        return failures
    end

    ---@return string
    local function expected_transactions()
        return xmake_io.readfile(path.join(project_dir, "expected-transactions.txt")) or ""
    end

    --- Compare the TXN lines with the committed fixture and keep them as an artifact.
    ---@param output string
    ---@param out_dir string
    ---@return string[]
    local function check_transactions(output, out_dir)
        local lines = {}
        for line in (output .. "\n"):gmatch("([^\n]*)\n") do
            if line:find("^TXN ") then
                table.insert(lines, line)
            end
        end
        local actual = #lines > 0 and (table.concat(lines, "\n") .. "\n") or ""
        xmake_io.writefile(path.join(out_dir, "transactions.log"), actual)
        if actual ~= expected_transactions() then
            return { "transaction log differs from the fixed fixture" }
        end
        return {}
    end

    ---@param failures string[]
    ---@param label string
    local function report_target(failures, label)
        for _, failure in ipairs(failures) do
            print("CHECK: " .. failure)
        end
        if #failures ~= 0 then
            raise(label .. " failed")
        end
        print("PASS " .. label)
    end

    ---@return integer failed_count
    local function run_all_cases()
        xmake_os.mkdir(artifact_dir)
        local names = case_names()
        local failed = {}
        for _, name in ipairs(names) do
            local case_dir = path.join(artifact_dir, name)
            xmake_os.mkdir(case_dir)

            local envs = { VL_TEST_LUASIM_CASE = name }
            if configs[name] then
                local config_path = path.join(case_dir, "cfg.lua")
                xmake_io.writefile(config_path, configs[name])
                envs.VL_CFG_FILE = config_path
            end

            local script = scripts[name] or "cases.lua"
            local command = shell_quote(luasim_bin) .. " " .. shell_quote(path.join(project_dir, script))
            local result = run_process(command, envs, case_dir, path.join(case_dir, "stdout.log"), case_timeout)
            local failures = validate(result, name)
            if #failures == 0 and name == "ready_valid" then
                failures = check_transactions(result.output, case_dir)
            elseif #failures == 0 and name == "wave" then
                failures = check_wave(path.join(case_dir, "wave.vcd"))
            elseif #failures == 0 and name == "wave_before_tasks" then
                failures = check_early_wave(path.join(case_dir, "wave.vcd"))
            end

            if #failures == 0 then
                print("PASS " .. name)
            else
                table.insert(failed, name)
                print(string.format("FAIL %s: %s", name, table.concat(failures, "; ")))
                print("     log: " .. result.log)
            end
        end

        local summary = string.format("%d/%d passed; %d failed", #names - #failed, #names, #failed)
        xmake_io.writefile(path.join(results_root, "results.log"), summary .. "\n")
        print(summary)
        return #failed
    end

    --- Build a verilua target and run the runner script the rule generated for it.
    --- Build and run one project target, then apply the shared case contract.
    ---@param target_name string
    ---@param marker string
    ---@param envs table<string,string>
    ---@param out_dir string
    ---@return string[]
    local function run_project_target(target_name, marker, envs, out_dir)
        xmake_os.mkdir(out_dir)
        local build = run_process(
            string.format("xmake build -P %s %s", shell_quote(project_dir), target_name),
            envs, project_dir, path.join(out_dir, "build.log"), build_timeout)
        if build.returncode ~= 0 then
            return { "target build failed, see " .. build.log }
        end
        local result = run_process(
            string.format("xmake run -P %s %s", shell_quote(project_dir), target_name),
            envs, project_dir, path.join(out_dir, "stdout.log"), case_timeout)
        return validate(result, marker)
    end

    return {
        run_all_cases = run_all_cases,
        run_project_target = run_project_target,
        check_transactions = check_transactions,
        report_target = report_target,
    }
end

target("test", function()
    set_kind("phony")
    on_run(function()
        local suite = build_suite({ os = os, io = io })
        if suite.run_all_cases() ~= 0 then
            raise("luasim cases failed; artifacts in " .. artifact_dir)
        end
    end)
end)

-- Same ready/valid component hosted by the simulator selected through SIM.
target("test_rtl", function()
    set_kind("phony")
    set_default(false)
    on_run(function()
        local sim = os.getenv("SIM") or "verilator"
        if sim == "luasim" then
            raise("test_rtl needs a real simulator; unset SIM or pick iverilog/vcs/verilator/xcelium")
        end

        local suite = build_suite({ os = os, io = io })
        local out_dir = path.join(results_root, "rtl-compare-" .. sim)
        local failures = suite.run_project_target("rtl_compare", "ready_valid", { SIM = sim }, out_dir)
        if #failures == 0 then
            failures = suite.check_transactions(io.readfile(path.join(out_dir, "stdout.log")) or "", out_dir)
        end
        suite.report_target(failures, "rtl_compare " .. sim)
    end)
end)

-- Hosts the same ready_valid.lua component in a real simulator picked by SIM,
-- matching how the other integration tests select their backend.
target("rtl_compare", function()
    set_default(false)
    add_rules("verilua")

    on_config(function(target)
        local sim = os.getenv("SIM") or "verilator"
        -- SIM=luasim selects the Lua backend, which does not host this target.
        if sim == "luasim" then
            return
        elseif sim == "iverilog" then
            target:set("toolchains", "@iverilog")
        elseif sim == "vcs" then
            target:set("toolchains", "@vcs")
        elseif sim == "xcelium" then
            target:set("toolchains", "@xcelium")
        elseif sim == "verilator" then
            target:set("toolchains", "@verilator")
        else
            raise("unknown simulator: %s", sim)
        end
    end)

    add_files("top.sv")
    set_values("verilua.top", "top")
    set_values("verilua.lua_main", "ready_valid.lua")
    set_values("verilua.no_internal_clock", "1")
end)
