---@diagnostic disable

local curr_dir = os.scriptdir()
local rtl_dir = path.join(os.scriptdir(), "..", "rtl")

local function target_common()
    add_rules("verilua")

    on_config(function(target)
        local sim = os.getenv("SIM") or "verilator"
        if sim == "iverilog" then
            target:set("toolchains", "@iverilog")
        elseif sim == "vcs" then
            target:set("toolchains", "@vcs")
        elseif sim == "verilator" then
            target:set("toolchains", "@verilator")
        else
            raise("unknown simulator: %s", sim)
        end
    end)
end

target("signal_operation", function()
    target_common()
    set_default(false)
    add_files(path.join(rtl_dir, "top.sv"))
    set_values("cfg.top", "top")
    set_values("cfg.lua_main", path.join(curr_dir, "cases", "signal_operation.lua"))
end)

target("multitasking", function()
    target_common()
    set_default(false)
    add_files(path.join(rtl_dir, "top.sv"))
    set_values("cfg.top", "top")
    set_values("cfg.lua_main", path.join(curr_dir, "cases", "multitasking.lua"))
end)

target("matrix_multiplier", function()
    target_common()
    set_default(false)
    add_files(path.join(rtl_dir, "matrix_multiplier.sv"))
    set_values("cfg.top", "matrix_multiplier")
    set_values("cfg.lua_main", path.join(curr_dir, "cases", "matrix_multiplier.lua"))
end)

target("benchmarks", function()
    set_kind("phony")
    set_default(true)
    on_run(function(target)
        import("core.base.json")
        import("lib.detect.find_file")
        if not find_file("hyperfine", { "$(env PATH)" }) then
            raise("[benchmarks] hyperfine not found!")
        end

        local warmup = 10
        local runs = 10
        local simulators = {
            "iverilog",
            "verilator",
        }
        local simulator_versions = {}
        local cases = {
            "signal_operation",
            "multitasking",
            "matrix_multiplier"
        }
        local results = {}
        local merged_resutls = {}

        for _, simulator in ipairs(simulators) do
            if not find_file(simulator, { "$(env PATH)" }) then
                raise("[benchmarks] simulator: `%s` not found!", simulator)
            end
        end

        if find_file("vcs", { "$(env PATH)" }) then
            table.insert(simulators, "vcs")
        end

        for _, sim in ipairs(simulators) do
            if sim == "iverilog" then
                simulator_versions[sim] = os.iorun("iverilog -V"):split('\n', { plain = true })[1]
            elseif sim == "verilator" then
                simulator_versions[sim] = os.iorun("verilator --version"):split('\n', { plain = true })[1]
            elseif sim == "vcs" then
                local got_vcs_version = false
                for _, line in ipairs(os.iorun("vcs -help"):split('\n', { plain = true })) do
                    if line:startswith("vcs script version") then
                        simulator_versions[sim] = line
                        got_vcs_version = true
                    end
                end
                assert(got_vcs_version, "[benchmarks] failed to get vcs version")
            else
                raise("[benchmarks] simulator: `%s` not supported!", sim)
            end
        end

        for _, sim in ipairs(simulators) do
            for _, jit_v in ipairs({ "on", "off" }) do
                local sum_value = 0
                local extra_info = format("sim version: %s", simulator_versions[sim])
                for _, case in ipairs(cases) do
                    local command_name = case .. "__sim_" .. sim .. "__jit_" .. jit_v

                    os.tryrm(path.join(curr_dir, "build"))
                    os.execv("xmake", {
                        "build",
                        "-P", curr_dir,
                        case
                    }, {
                        envs = {
                            SIM = sim,
                        }
                    })

                    os.execv("hyperfine", {
                        "-w", warmup,
                        "-r", runs,
                        "--command-name", command_name,
                        "--export-json", command_name .. ".json",
                        format("xmake run -P %s %s", curr_dir, case)
                    }, {
                        envs = {
                            JIT_V = jit_v,
                            SIM = sim,
                        }
                    })

                    local v = json.loadfile(path.join(curr_dir, command_name .. ".json")).results[1].mean * 1000
                    results[#results + 1] = {
                        name = format("[benchmarks] %s - sim `%s` - jit `%s`", case, sim, jit_v),
                        unit = "ms",
                        value = v,
                        extra = extra_info,
                    }
                    sum_value = sum_value + v
                end

                merged_resutls[#merged_resutls + 1] = {
                    name = format("[benchmarks] merged resutls - sim `%s` - jit `%s`", sim, jit_v),
                    unit = "ms",
                    value = sum_value,
                    extra = extra_info,
                }
            end
        end

        print("results:", results)
        print("merged_resutls:", merged_resutls)

        local final_results = {}
        table.join2(final_results, merged_resutls)
        table.join2(final_results, results)
        json.savefile(path.join(curr_dir, "output.json"), final_results)
    end)
end)
