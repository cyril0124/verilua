---@diagnostic disable: undefined-global, undefined-field

local project_dir = os.projectdir()
local waveform = path.join(project_dir, "build", "replay.fst")
local simulator = os.getenv("SIM") or "verilator"
local random_wave_name = simulator == "vcs" and "random_order.vcd.fsdb" or "random_order.vcd"
local random_waveform = path.join(project_dir, "build", random_wave_name)

target("replay_gen", function()
    set_default(false)
    add_rules("verilua")
    add_toolchains("@verilator")
    add_files("top.sv")
    add_values("verilator.flags", "--trace", "--trace-fst")
    set_values("verilua.top", "top")
    set_values("verilua.lua_main", "replay_tb.lua")
    after_run(function()
        os.cp("replay.fst", waveform)
    end)
end)

target("replay_wave", function()
    set_default(false)
    add_rules("verilua")
    add_toolchains("@wave_vpi")
    add_files(waveform)
    set_values("verilua.top", "tb_top")
    set_values("verilua.lua_main", "replay_tb.lua")
    set_values("wave_vpi.run_flags", "--ignore-writes")
end)

target("replay_readonly", function()
    set_default(false)
    add_rules("verilua")
    add_toolchains("@wave_vpi")
    add_files(waveform)
    set_values("verilua.top", "tb_top")
    set_values("verilua.lua_main", "replay_readonly.lua")
end)

target("random_order_gen", function()
    set_default(false)
    add_rules("verilua")
    add_files("top.sv")
    if simulator == "vcs" then
        add_toolchains("@vcs")
    elseif simulator == "verilator" then
        add_toolchains("@verilator")
        add_values("verilator.flags", "--trace")
    else
        add_toolchains("@iverilog")
    end
    set_values("verilua.top", "top")
    set_values("verilua.lua_main", "random_order_tb.lua")
    after_run(function()
        os.cp(random_wave_name, random_waveform)
    end)
end)

target("random_order_wave", function()
    set_default(false)
    add_rules("verilua")
    add_toolchains("@wave_vpi")
    add_files(random_waveform)
    set_values("verilua.top", "tb_top")
    set_values("verilua.lua_main", "random_order_tb.lua")
    set_values("wave_vpi.run_flags", "--ignore-writes")
end)

target("short_cursor_wave", function()
    set_default(false)
    add_rules("verilua")
    add_toolchains("@wave_vpi")
    add_files("short_cursor.vcd")
    set_values("verilua.top", "tb_top")
    set_values("verilua.lua_main", "short_cursor_tb.lua")
end)

target("same_index_cursor_wave", function()
    set_default(false)
    add_rules("verilua")
    add_toolchains("@wave_vpi")
    add_files("same_index_cursor.vcd")
    set_values("verilua.top", "tb_top")
    set_values("verilua.lua_main", "same_index_cursor_tb.lua")
end)

target("test_random_order", function()
    set_default(false)
    set_kind("phony")
    on_run(function()
        assert(os.getenv("SIM"), "random-order test requires an explicit SIM")
        assert(simulator == "vcs" or simulator == "verilator" or simulator == "iverilog",
            "random-order test supports SIM=vcs, verilator or iverilog")
        local find_file = import("lib.detect.find_file")
        ---@cast find_file fun(name: string, searchdirs: string[]): string?
        ---@param name string
        ---@return integer, string
        local function run(name)
            os.mkdir(path.join(project_dir, "build"))
            os.exec("xmake b -P . " .. name)
            local log_dir = path.join(project_dir, "build")
            local stdout_file = path.join(log_dir, name .. ".log")
            local stderr_file = path.join(log_dir, name .. ".err")
            local code = os.execv("xmake", { "r", "-P", project_dir, name },
                { stdout = stdout_file, stderr = stderr_file, try = true })
            local output = (io.readfile(stdout_file) or "") .. (io.readfile(stderr_file) or "")
            return code, output
        end

        local reader = simulator == "vcs" and "wave_vpi_main_fsdb" or "wave_vpi_main"
        assert(find_file(simulator, { "$(env PATH)" }) and find_file(reader, { "$(env PATH)" }),
            "random-order test requires " .. simulator .. " and " .. reader)
        if simulator == "vcs" then
            assert(find_file("verdi", { "$(env PATH)" }), "random-order test requires Verdi")
        end
        os.tryrm(random_waveform)
        os.tryrm(path.join(project_dir, "build", simulator, "top", random_wave_name))
        local random_gen_code, recorded_random = run("random_order_gen")
        assert(random_gen_code == 0 and recorded_random:find("RANDOM_ORDER_DONE", 1, true)
            and os.isfile(random_waveform), "random-order recording failed: " .. recorded_random)
        local random_code, replayed_random = run("random_order_wave")
        assert(random_code == 0, "random-order replay failed: " .. replayed_random)

        ---@param output string
        ---@return string[]
        local function random_trace(output)
            local lines = {}
            for line in output:gmatch("RANDOM_ORDER [^\r\n]+") do
                lines[#lines + 1] = line
            end
            assert(#lines == 100, "expected 100 random-order samples")
            return lines
        end

        local expected_random = random_trace(recorded_random)
        local actual_random = random_trace(replayed_random)
        for index, expected in ipairs(expected_random) do
            local mismatch = string.format("random stream diverged at event %d: %s=%s replay=%s",
                index, simulator, expected, actual_random[index])
            if index == 21 then
                local first = simulator == "verilator" and "MEM1" or "REQ1"
                assert(expected:find("RANDOM_ORDER " .. first .. " ", 1, true) == 1,
                    "recording did not exercise the shared-edge callback order")
            elseif index == 25 and simulator ~= "verilator" then
                assert(expected:find("RANDOM_ORDER MEM1 ", 1, true) == 1,
                    "recording did not shuffle memory after request QoS")
            elseif index == 29 and simulator == "verilator" then
                assert(expected:find("RANDOM_ORDER REQ1 ", 1, true) == 1,
                    "recording did not run request QoS after memory")
            end
            assert(actual_random[index] == expected, mismatch)
        end
        print("RANDOM_ORDER_PASS samples=100 simulator=" .. simulator)
    end)
end)

target("run_test", function()
    set_default(true)
    set_kind("phony")
    on_run(function()
        ---@param name string
        ---@param selected_simulator? "vcs"|"iverilog"
        ---@return integer, string
        local function run(name, selected_simulator)
            local envs = selected_simulator and { SIM = selected_simulator } or nil
            os.mkdir(path.join(project_dir, "build"))
            os.execv("xmake", { "b", "-P", project_dir, name }, { envs = envs })
            local log_dir = path.join(project_dir, "build")
            local log_name = selected_simulator and (name .. "_" .. selected_simulator) or name
            local stdout_file = path.join(log_dir, log_name .. ".log")
            local stderr_file = path.join(log_dir, log_name .. ".err")
            local code = os.execv("xmake", { "r", "-P", project_dir, name },
                { envs = envs, stdout = stdout_file, stderr = stderr_file, try = true })
            local output = (io.readfile(stdout_file) or "") .. (io.readfile(stderr_file) or "")
            return code, output
        end

        ---@param output string
        ---@return string
        local function samples(output)
            local values = {}
            for line in output:gmatch("REPLAY_SAMPLE [^\r\n]+") do
                values[#values + 1] = line
            end
            return table.concat(values, "\n")
        end

        local _, reference = run("replay_gen")
        assert(reference:find("REPLAY_TB_PASS samples=100", 1, true), "recording run failed: " .. reference)
        local expected = samples(reference)
        assert(#expected > 0, "recording run printed no samples")

        local code, replay = run("replay_wave")
        assert(code == 0, "replay failed: " .. replay)
        assert(samples(replay) == expected, "replay samples differ from the recording")
        assert(not os.isfile(path.join(project_dir, "build", "wave_vpi", "replay.fst")),
            "sim.dump_wave created a waveform during replay")

        local readonly_code, readonly = run("replay_readonly")
        assert(readonly_code ~= 0 and readonly:find("read-only", 1, true),
            "a write without --ignore-writes must be rejected: " .. readonly)

        import("lib.detect.find_file")
        if find_file("vcs", { "$(env PATH)" }) and find_file("verdi", { "$(env PATH)" })
            and find_file("wave_vpi_main_fsdb", { "$(env PATH)" }) then
            local random_code, random_output = run("test_random_order", "vcs")
            assert(random_code == 0 and random_output:find("RANDOM_ORDER_PASS samples=100", 1, true),
                "random-order test failed: " .. random_output)
        end

        if find_file("iverilog", { "$(env PATH)" }) and find_file("vvp", { "$(env PATH)" })
            and find_file("wave_vpi_main", { "$(env PATH)" }) then
            local random_code, random_output = run("test_random_order", "iverilog")
            assert(random_code == 0 and random_output:find("RANDOM_ORDER_PASS samples=100", 1, true),
                "iVerilog VCD random-order test failed: " .. random_output)
        end

        -- TODO: Re-enable Verilator VCD once its event-21 callback-order mismatch is fixed.
        --[[
        if find_file("verilator", { "$(env PATH)" }) and find_file("wave_vpi_main", { "$(env PATH)" }) then
            local random_code, random_output = run("test_random_order", "verilator")
            assert(random_code == 0 and random_output:find("RANDOM_ORDER_PASS samples=100", 1, true),
                "Verilator VCD random-order test failed: " .. random_output)
        end
        ]]

        local short_code, short_output = run("short_cursor_wave")
        assert(short_code == 0 and short_output:find("SHORT_CURSOR_PASS", 1, true),
            "single-timestamp cursor jump failed: " .. short_output)

        local same_index_code, same_index_output = run("same_index_cursor_wave")
        assert(same_index_code == 0 and same_index_output:find("SAME_INDEX_CURSOR_PASS", 1, true),
            "same-index cursor regression failed: " .. same_index_output)

        print("REPLAY_SUITE_PASS")
    end)
end)
