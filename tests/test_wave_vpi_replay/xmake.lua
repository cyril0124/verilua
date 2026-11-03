---@diagnostic disable: undefined-global, undefined-field

local project_dir = os.projectdir()
local waveform = path.join(project_dir, "build", "replay.fst")

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

target("short_cursor_wave", function()
    set_default(false)
    add_rules("verilua")
    add_toolchains("@wave_vpi")
    add_files("short_cursor.vcd")
    set_values("verilua.top", "tb_top")
    set_values("verilua.lua_main", "short_cursor_tb.lua")
end)

target("run_test", function()
    set_default(true)
    set_kind("phony")
    on_run(function()
        os.mkdir(path.join(project_dir, "build"))

        ---@param name string
        ---@return integer, string
        local function run(name)
            os.exec("xmake b -P . " .. name)
            local log_dir = path.join(project_dir, "build")
            local stdout_file = path.join(log_dir, name .. ".log")
            local stderr_file = path.join(log_dir, name .. ".err")
            local code = os.execv("xmake", { "r", "-P", project_dir, name },
                { stdout = stdout_file, stderr = stderr_file, try = true })
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

        local short_code, short_output = run("short_cursor_wave")
        assert(short_code == 0 and short_output:find("SHORT_CURSOR_PASS", 1, true),
            "single-timestamp cursor jump failed: " .. short_output)

        print("REPLAY_SUITE_PASS")
    end)
end)
