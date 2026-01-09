---@diagnostic disable: undefined-global, undefined-field, unnecessary-assert, unnecessary-if

local f = string.format
local default_timescale = "1ns/1ps"
local verilua_home = os.getenv("VERILUA_HOME") or ""
local verilua_tools_home = path.join(verilua_home, "tools")
local verilua_libs_home = path.join(verilua_home, "shared")
local luajitpro_home = path.join(verilua_home, "luajit-pro", "luajit2.1")

---@alias SimulatorType "iverilog" | "verilator" | "vcs" | "xcelium" | "wave_vpi" | "nosim"

---@alias InstrumentationType "cov_exporter"

---@class CovExporterConfig: {module: string, disable_signal?: string, clock?: string, recursive?: boolean}

---@class (exact) InstrumentationConfig
---@field type InstrumentationType
---@field config CovExporterConfig TODO: Other config
---@field extra_args string[] Extra arguments for the instrumentation tool

local function get_simulator_type(target)
    if target:toolchain("verilator") then
        return "verilator"
    elseif target:toolchain("iverilog") then
        return "iverilog"
    elseif target:toolchain("vcs") then
        return "vcs"
    elseif target:toolchain("xcelium") then
        return "xcelium"
    elseif target:toolchain("wave_vpi") then
        return "wave_vpi"
    elseif target:toolchain("nosim") then
        return "nosim"
    else
        return nil
    end
end

local function get_build_dir(target, sim)
    local cfg_build_dir = target:values("cfg.build_dir")
    local cfg_build_dir_name = target:values("cfg.build_dir_name")
    local cfg_build_dir_path = target:values("cfg.build_dir_path")
    local top = target:values("cfg.top") or target:name()
    local build_dir_name = cfg_build_dir_name or top --[[@as string]]
    local build_dir_path = cfg_build_dir_path or path.join("build", sim) --[[@as string]]
    local build_dir = cfg_build_dir or path.absolute(path.join(build_dir_path, build_dir_name)) --[[@as string]]
    return build_dir, build_dir_name, build_dir_path
end

local function before_build_or_run(target)
    --- Check if any of the valid toolchains is set. If not, raise an error.
    --- You should set the toolchain using add_toolchains(<...>).
    --- e.g. (in your xmake.lua)
    --- ```lua
    ---     add_toolchains("@verilator")
    ---     -- or
    ---     add_toolchains("@iverilog")
    ---     -- or
    ---     add_toolchains("@vcs")
    ---     -- or
    ---     add_toolchains("@xcelium")
    ---     -- or
    ---     add_toolchains("@wave_vpi")
    ---     -- or
    ---     add_toolchains("@nosim")
    --- ```
    local sim = get_simulator_type(target)
    assert(sim, [[
        [before_build_or_run] Unknown toolchain!
            Please use one of the following toolchains:
                - add_toolchains("@verilator")
                - add_toolchains("@iverilog")
                - add_toolchains("@vcs")
                - add_toolchains("@xcelium")
                - add_toolchains("@wave_vpi") => For waveform simulation only
                - add_toolchains("@nosim") => For no simulation
    ]])

    -- Used in `on_build` or `on_run` phase
    target:add("sim", sim)
    cprint("${✅} [verilua-xmake] [%s] simulator/toolchain is ${green underline}%s${reset}", target:name(), sim)

    -- Used in `on_build` and `on_run` phases
    local tb_top = target:values("cfg.tb_top") or "tb_top"
    target:add("tb_top", tb_top)

    --- Check top module
    --- e.g. (in your xmake.lua)
    --- ```lua
    ---     set_values("cfg.top", "TestModule")
    --- ```
    local top = assert(
        target:values("cfg.top"),
        [[
                [before_build_or_run] Unknown top module name!
                    You should set 'top' by `set_values("cfg.top", "<your_top_module_name>")`
            ]]
    )
    target:add("top", top) -- Used in `on_build` phase
    cprint("${✅} [verilua-xmake] [%s] top module is ${green underline}%s${reset}", target:name(), top)

    -- Check if VERILUA_HOME is set.
    assert(verilua_home ~= "", "[before_build_or_run] [%s] please set VERILUA_HOME", target:name())

    --- Check verilua version using semantic versioning
    --- e.g.
    --- ```lua
    ---     set_values("cfg.version_required", "1.0.0")
    ---     set_values("cfg.version_required", "> 1.0.0")
    ---     set_values("cfg.version_required", ">= 1.0.0")
    ---     set_values("cfg.version_required", "< 1.0.0")
    ---     set_values("cfg.version_required", "<= 1.0.0")
    ---     set_values("cfg.version_required", "1.0.x")
    --- ```
    local version_required = target:values("cfg.version_required")
    if version_required then
        import("core.base.semver")
        local curr_version = io.readfile(path.join(verilua_home, "VERSION")):trim()
        assert(
            semver.satisfies(curr_version, version_required),
            "[before_build_or_run] [%s] verilua version is satisfied, expected: %s, current version: %s",
            target:name(),
            version_required,
            curr_version
        )
    end

    --- Check build directory
    --- There are two ways to specify the build directory
    --- 1. Set `cfg.build_dir` in xmake config
    ---    e.g. (in your xmake.lua)
    ---    ```lua
    ---        set_values("cfg.build_dir", "/path/to/your/build")
    ---    ```
    --- 2. Set `cfg.build_dir_path` and/or `cfg.build_dir_name` in xmake config
    ---    e.g. (in your xmake.lua)
    ---    ```lua
    ---        set_values("cfg.build_dir_path", "/path/to/your/build")
    ---        set_values("cfg.build_dir_name", "my_build")
    ---    ```
    local build_dir = get_build_dir(target, sim)
    local sim_build_dir = path.join(build_dir, "sim_build") --[[@as string]]
    local cfg_build_dir = target:values("cfg.build_dir")
    local cfg_build_dir_name = target:values("cfg.build_dir_name")
    local cfg_build_dir_path = target:values("cfg.build_dir_path")
    if cfg_build_dir ~= nil then
        assert(
            cfg_build_dir_name == nil,
            "[before_build_or_run] [%s] please set `cfg.build_dir_name` to nil when `cfg.build_dir` is set",
            target:name()
        )
        assert(
            cfg_build_dir_path == nil,
            "[before_build_or_run] [%s] please set `cfg.build_dir_path` to nil when `cfg.build_dir` is set",
            target:name()
        )
    end
    target:add("build_dir", build_dir)         -- Used in `on_build` and `on_run` phases
    target:add("sim_build_dir", sim_build_dir) -- Used in `on_build` and `on_run` phases
    cprint("${✅} [verilua-xmake] [%s] build directory is ${green underline}%s${reset}", target:name(), build_dir)

    -- Generate build directory if not exists
    if not os.isfile(sim_build_dir) then
        os.mkdir(sim_build_dir)
    end

    -- Extract dependencies  from sourcefiles
    local deps_vec = {}
    local deps_path_map = {}
    local sourcefiles = target:sourcefiles()
    for _, sourcefile in ipairs(sourcefiles) do
        local ext = path.extension(sourcefile)
        if ext == ".lua" or ext == ".luau" or ext == ".tl" then
            local dir = path.directory(path.absolute(sourcefile))
            if not deps_path_map[dir] then
                deps_path_map[dir] = true
                deps_vec[#deps_vec + 1] = path.join(dir, "?.lua")
            end
        end
    end

    --- Setup lua_main script which is the entry point of the simulation, can be seen as the main function in C language.
    --- You can set it by environment variable or xmake config
    ---
    --- e.g. (set by enviroment variable `LUA_SCRIPT`)
    --- ```shell
    --- export LUA_SCRIPT=/path/to/your/main.lua
    --- ```
    --- e.g. (set by xmake config)
    --- ```lua
    ---     set_values("cfg.lua_main", "/path/to/your/main.lua")
    --- ```
    local env_lua_main = os.getenv("LUA_SCRIPT")
    local cfg_lua_main = target:values("cfg.lua_main")
    local lua_main = env_lua_main
    if lua_main == nil then
        assert(
            cfg_lua_main,
            "[before_build_or_run] You should set \'cfg.lua_main\' by set_values(\"lua_main\", \"<your_lua_main_script>\")"
        )
        lua_main = path.absolute(cfg_lua_main)
    end
    cprint("${✅} [verilua-xmake] [%s] lua main is ${green underline}%s${reset}", target:name(), lua_main)
    -- Save lua_main directory into deps_str
    deps_vec[#deps_vec + 1] = path.join(path.directory(lua_main), "?.lua")

    --- Verilua allows user to add their own configuration file(written in lua) which will be loaded before the main script.
    --- e.g.
    --- ```lua
    ---     set_values("cfg.user_cfg", "/path/to/your/cfg.lua")
    --- ```
    --- The user configuration file is a lua script and also require to return a table.
    --- e.g. (cfg.lua)
    --- ```lua
    --- local cfg = {}
    --- cfg.some_option = 1
    --- cfg.anything = "string"
    --- return cfg
    --- ```
    --- Notice:
    --          Not all verilua modules are supported in the user configuration file since verilua load user configuration file
    ---         in a pretty early stage and some modules may not be available yet. Currently, only `LuaUtils` is supported.
    --- e.g. (cfg.lua)
    --- ```lua
    --- local utils = require "LuaUtils"
    --- local cfg = {}
    --- cfg.some_option = utils.get_env_or_else("SOME_OPTION", "boolean", false)
    --- -- Your code ...
    --- return cfg
    --- ```
    ---
    --- Notice: `cfg.other_cfg` is deprecated, please use `cfg.user_cfg` instead.
    local user_cfg = target:values("cfg.user_cfg") or target:values("cfg.other_cfg")
    local user_cfg_path = "nil"
    if user_cfg == nil or user_cfg == "" then
        user_cfg = "nil"
    else
        local _user_cfg = user_cfg
        user_cfg = path.basename(user_cfg)
        user_cfg_path = path.absolute(path.directory(_user_cfg))
        cprint("${✅} [verilua-xmake] [%s] user_cfg is ${green underline}%s${reset}", target:name(), user_cfg)
    end

    -- Generate verilua_cfg.lua which is used for loading some common settings used by verilua.
    -- This file can be merged with user configuration file(cfg.user_cfg).
    local verilua_cfg_file = path.absolute(path.join(target:get("build_dir"), "verilua_cfg.lua"))
    local cfg_file_str = f([[
-------------------------------------------
--- Auto generated by verilua, do not edit
-------------------------------------------
local cfg = {}

cfg.top = "%s"
cfg.prj_dir = "%s"
cfg.simulator = "%s"
cfg.script = "%s"
cfg.deps = {"%s"}

local user_cfg = "%s"
local user_cfg_path = "%s"

-- Mix with other config
if user_cfg ~= "nil" then
    _G.package.path = _G.package.path .. ";" .. user_cfg_path .. "/?.lua"
    local _cfg = require(user_cfg)
    assert(type(_cfg) == "table", "cfg is not a table! => type(cfg): " .. type(_cfg) .. " cfg: " .. tostring(_cfg) .. " cfg_path: " .. tostring(user_cfg_path) .. " cfg_name: " .. tostring(user_cfg))

    local sim_cfg = require "LuaSimConfig"
    sim_cfg.merge_config_1(cfg, _cfg, "[xmake.lua -> verilua_cfg.lua]")
end

return cfg
]], tb_top, os.projectdir(), sim, lua_main, path.joinenv(deps_vec, ";"), user_cfg, user_cfg_path)
    if os.isfile(verilua_cfg_file) and io.readfile(verilua_cfg_file) == cfg_file_str then
        cprint("${✅} [verilua-xmake] [%s] ${green underline}verilua_cfg.lua${reset} is up-to-date", target:name())
    else
        local lock = io.openlock(path.join(build_dir, "verilua_cfg.lua.lock")) -- To prevent concurrent writes
        lock:lock()
        io.writefile(verilua_cfg_file, cfg_file_str)
        lock:unlock()
        lock:close()
    end
    target:add("verilua_cfg_file", verilua_cfg_file) -- Used in `on_build` and `on_run` phases

    -- Extra info provided by instrumentation
    local _instrumentation = target:values("instrumentation")
    if _instrumentation then
        local t = type(_instrumentation)
        assert(
            t == "function",
            "[before_build_or_run] `instrumentation` should be a `function` with a return value of `InstrumentationConfig[]`, but got `%s`",
            t
        )

        ---@type InstrumentationConfig[]
        local instrumentation = _instrumentation()
        assert(
            type(instrumentation) == "table",
            "[before_build_or_run] return value of `instrumentation` function should be a `table` of `InstrumentationConfig[]`, but got `%s`",
            type(instrumentation)
        )

        for _, inst in ipairs(instrumentation) do
            if inst.type == "cov_exporter" then
                -- Used by `CoverageGetter.lua`
                target:add(
                    "runenvs",
                    "VL_COV_EXPORTER_META_FILE",
                    path.join(build_dir, ".cov_exporter", "cov_exporter.meta.json")
                )
            end
        end
    end

    if sim == "wave_vpi" then
        local get_waveform = false
        local waveform_file = ""
        for _, sourcefile in ipairs(sourcefiles) do
            local ext = path.extension(sourcefile)
            if ext == ".vcd" or ext == ".fst" or ext == ".fsdb" then
                assert(
                    not get_waveform,
                    "[before_build_or_run] Multiple waveform files are not supported, previous wavefile file: " ..
                    waveform_file
                )
                get_waveform = true
                waveform_file = path.absolute(sourcefile)
            end
        end
        if waveform_file ~= "" then
            target:add("waveform_file", waveform_file) -- Used in `on_build` and `on_run` phases
        end
    end

    target:set("kind", "binary")
end

rule("verilua", function()
    set_extensions(".v", ".sv", ".svh", ".lua", ".luau", ".tl", ".d.tl", ".vlt", ".vcd", ".fst", ".fsdb")

    before_build(before_build_or_run)

    before_run(before_build_or_run)

    on_build(function(target)
        import("lib.detect.find_file")
        assert(verilua_home ~= "", "[on_build] [%s] please set VERILUA_HOME", target:name())

        local top = target:get("top")
        local build_dir = target:get("build_dir")
        local sim_build_dir = path.join(build_dir, "sim_build")
        local sim = target:get("sim") --[[@as SimulatorType]]
        local tb_top = target:get("tb_top")
        local sourcefiles = target:sourcefiles()
        local argv = {}
        local toolchain = ""
        local buildcmd = ""

        --- Check if user has set `cfg.no_internal_clock`
        --- Verilua will generate a clock signal internally if `cfg.no_internal_clock` is not set.
        --- If `cfg.no_internal_clock` is set, Verilua will not generate a clock signal internally.
        --- The user should generate a clock signal to push forward the simulation.
        --- e.g.(in your xmake.lua)
        --- ```lua
        ---     set_values("cfg.no_internal_clock", "1")
        --- ```
        --- Also you need to generate a clock signal in your main.lua:
        --- ```lua
        ---     fork {
        ---         function()
        ---             local clock = dut.clock:chdl()
        ---             while true do
        ---                 clock:set(1)
        ---                 await_time(2)
        ---                 clock:set(0)
        ---                 await_time(2)
        ---             end
        ---         end
        ---     }
        --- ```
        local no_internal_clock = target:values("cfg.no_internal_clock") --[[@as string]]
        if no_internal_clock == "1" then
            cprint("${✅} [verilua-xmake] [%s] ${yellow underline}cfg.no_internal_clock${reset} is enabled!",
                target:name())
        end

        --- Check if user has set `cfg.use_inertial_put`
        --- See https://github.com/cocotb/cocotb/pull/3861 for more details
        --- e.g.(in your xmake.lua)
        --- ```lua
        ---     set_values("cfg.use_inertial_put", "1")
        --- ```
        local use_inertial_put = target:values("cfg.use_inertial_put") --[[@as string]]
        if not use_inertial_put then
            -- By default, `use_inertial_put` is disabled for `verilator` simulator
            if sim == "verilator" then
                use_inertial_put = "0"
            end

            local env_use_inertial_put = os.getenv("CFG_USE_INERTIAL_PUT")
            if env_use_inertial_put then
                assert(
                    env_use_inertial_put == "0" or env_use_inertial_put == "1",
                    "[on_build] environment variable CFG_USE_INERTIAL_PUT should be 0 or 1"
                )
                use_inertial_put = env_use_inertial_put
                cprint(
                    "${✅} [verilua-xmake] [%s] environment variable ${yellow underline}CFG_USE_INERTIAL_PUT = %s${reset}",
                    target:name(),
                    env_use_inertial_put
                )
            end
        end
        if use_inertial_put == "1" then
            cprint("${✅} [verilua-xmake] [%s] ${yellow underline}cfg.use_inertial_put${reset} is enabled!", target:name())
            assert(sim == "verilator", "[on_build] cfg.use_inertial_put is only supported for `verilator` simulator")
        end

        --- Collect include directories from simulator flags for Verilog source files, used by testbench_gen
        local v_include_dirs = {}

        --- For most of the simulators, we have `<sim>.flags` for user to specify extra command line flags.
        --- e.g.(in your xmake.lua)
        --- ```lua
        ---     set_values("verilator.flags", "--trace", "--no-trace-top")
        ---     set_values("vcs.flags", "-timescale=1ps/1ps")
        ---     set_values("iverilog.flags", "-y /some/path")
        --- ```
        if sim == "verilator" then
            local extra_verilator_flags = {
                "--vpi",
                "--cc",
                "--exe",
                "--MMD",
                [[--no-timing -CFLAGS "-DNORMAL_MODE"]],
                "-Mdir", sim_build_dir,
                "-j 0", -- Verilate using use as many CPU threads as the machine has.
                "--Wno-PINMISSING",
                "--Wno-MODDUP",
                "--Wno-WIDTHEXPAND",
                "--Wno-WIDTHTRUNC",
                "--Wno-UNOPTTHREADS",
                "--Wno-IMPORTSTAR",
                "+define+SIM_VERILATOR",
                "--timescale-override " .. default_timescale,
                "--top", tb_top,
                [[-CFLAGS "-std=c++20"]],
                [[-LDFLAGS "-flto"]],
                [[-LDFLAGS "-u coverageCtrl -u getCoverageCount -u getCoverage -u getCondCoverage"]], -- Reserve symbols for coverage(cov_exporter)
            }

            --- Check if there is a verilator config file(*.vlt), if so, disable public flat read/write.
            --- A verilator config file contains the infomation about which signals can be accessed.
            --- Using verilator configuration file instead of plain `--public-flat-rw` can improve simulation performance.
            --- e.g. (config.vlt)
            --- ```plaintext
            --- `verilator_config
            --- public_flat_rw -module "tb_top" -var "*"
            --- public_flat_rd -module "Top" -var "*"
            --- public_flat_rd -module "Sub" -var "io_in_*"
            --- ```
            local public_flat_rw = true
            for _, sourcefile in ipairs(sourcefiles) do
                if sourcefile:endswith(".vlt") then
                    public_flat_rw = false
                end
            end
            if public_flat_rw then
                extra_verilator_flags[#extra_verilator_flags + 1] = "--public-flat-rw"
            end

            -- Enables slow optimizations for the code Verilator itself generates. -O3 may improve simulation performance at the cost of compile time.
            local verilator_opt = "-O3"
            local verilator_x_assign = "--x-assign unique"
            for _, flag in ipairs(target:values("verilator.flags")) do
                flag = flag:trim() -- Remove the left and right whitespace characters of the string
                local maybe_flags = flag:split(" ", { plain = true })
                for i, _flag in ipairs(maybe_flags) do
                    if _flag == "-O0" then
                        verilator_opt = "-O0"
                    elseif _flag:startswith("--x-assign") then
                        local next_flag = maybe_flags[i + 1]
                        assert(
                            next_flag,
                            "Invalid `--x-assign` option for verilator.flags, `--x-assign` should be followed by a value(e.g. --x-assign 0/1/fast/unique)"
                        )
                        verilator_x_assign = "--x-assign " .. next_flag
                    end
                end
            end
            extra_verilator_flags[#extra_verilator_flags + 1] = verilator_opt
            extra_verilator_flags[#extra_verilator_flags + 1] = verilator_x_assign

            if no_internal_clock == "1" then
                extra_verilator_flags[#extra_verilator_flags + 1] = [[-CFLAGS "-DNO_INTERNAL_CLOCK"]]
            end

            -- Some flags can be overridden by user defined flags
            local _verilator_flags = target:values("verilator.flags") or {}
            if type(_verilator_flags) ~= "table" then
                _verilator_flags = { _verilator_flags }
            end
            local verilator_uflags = table.concat(_verilator_flags, " ")
            verilator_uflags = verilator_uflags:split(" ", { plain = true })
            for i, uflag in ipairs(verilator_uflags) do
                if uflag:startswith("--timescale-override") then
                    -- Override the timescale flag
                    for j, eflag in ipairs(extra_verilator_flags) do
                        if eflag:startswith("--timescale-override") then
                            local timescale_value = verilator_uflags[i + 1]
                            assert(
                                timescale_value,
                                "Invalid `--timescale-override` option for verilator.flags, `--timescale-override` should be followed by a value(e.g. --timescale-override 1ns/1ns)"
                            )
                            extra_verilator_flags[j] = uflag .. " " .. timescale_value
                        end
                    end
                elseif uflag:startswith("--timing") then -- TODO: minimum verilator version?
                    for j, eflag in ipairs(extra_verilator_flags) do
                        if eflag:startswith("--no-timing") then
                            -- TODO: test verilator timing mode
                            extra_verilator_flags[j] = [[--timing -CFLAGS "-DTIMING_MODE"]]
                        end
                    end
                elseif uflag:startswith("--trace") then
                    extra_verilator_flags[#extra_verilator_flags + 1] = "--no-trace-top"
                elseif uflag == "-I" then
                    local includedir = verilator_uflags[i + 1]
                    assert(
                        includedir,
                        "Invalid `-I` option for verilator.flags, `-I` should be followed by a value(e.g. -I /some/path)"
                    )
                    table.insert(v_include_dirs, includedir)
                elseif uflag:startswith("+incdir+") then
                    local includedir = uflag:sub(9)
                    table.insert(v_include_dirs, includedir)
                end
            end

            for _, eflag in ipairs(extra_verilator_flags) do
                target:add("values", "verilator.flags", eflag)
            end
        elseif sim == "iverilog" then
            local extra_iverilog_flags = {
                "-g2012",
                "-DSIM_IVERILOG",
                "-s", tb_top,
                "-o", path.join(sim_build_dir, "simv.vvp"),
            }

            -- Some iverilog flags need to be added to the command file
            local extra_iverilog_cmds = {
                "+timescale+" .. default_timescale,
            }

            if no_internal_clock == "1" then
                extra_iverilog_cmds[#extra_iverilog_cmds + 1] = "+define+NO_INTERNAL_CLOCK"
            end

            -- Some flags can be overridden by user defined flags
            local _iverilog_flags = target:values("iverilog.flags") or {}
            if type(_iverilog_flags) ~= "table" then
                _iverilog_flags = { _iverilog_flags }
            end
            local iverilog_uflags = table.concat(_iverilog_flags, " ")
            iverilog_uflags = iverilog_uflags:split(" ", { plain = true })
            for i, uflag in ipairs(iverilog_uflags) do
                if uflag:startswith("+timescale+") then
                    -- Override the timescale flag
                    for j, eflag in ipairs(extra_iverilog_cmds) do
                        if eflag:startswith("+timescale+") then
                            extra_iverilog_cmds[j] = uflag
                        end
                    end
                elseif uflag == "-I" then
                    local includedir = iverilog_uflags[i + 1]
                    assert(
                        includedir,
                        "Invalid `-I` option for iverilog.flags, `-I` should be followed by a value(e.g. -I /some/path)"
                    )
                    table.insert(v_include_dirs, includedir)
                end
            end

            local iverilog_cmd_file = path.join(sim_build_dir, "cmds.f")
            io.writefile(iverilog_cmd_file, table.concat(extra_iverilog_cmds, "\n") .. "\n")
            extra_iverilog_flags[#extra_iverilog_flags + 1] = "-f " .. iverilog_cmd_file

            for _, eflag in ipairs(extra_iverilog_flags) do
                target:add("values", "iverilog.flags", eflag)
            end
        elseif sim == "vcs" then
            local libluajit51_lib = path.join(luajitpro_home, "lib")
            local libverilua_vcs_so = path.join(verilua_libs_home, "libverilua_vcs.so")
            local extra_vcs_flags = {
                "-sverilog",
                "-full64",
                "-debug_access+all",
                "-top", tb_top,
                "-Mdir=" .. sim_build_dir,
                "+v2k",
                "-lca",
                "-kdb",
                "-j" .. tostring((os.cpuinfo().ncpu or 128)),
                "-timescale=" .. default_timescale,
                "+define+SIM_VCS",
                "+define+VCS",
                "-q",
                [[-CFLAGS "-Ofast -march=native -loop-unroll"]],
                [[-LDFLAGS "-flto -Wl,--no-as-needed"]],
                f([[-LDFLAGS "-Wl,-rpath,%s"]], verilua_libs_home),                     -- for libverilua_vcs.so
                f([[-LDFLAGS "-Wl,-rpath,%s"]], libluajit51_lib),                       -- for libluajit-5.1.so
                f([[-LDFLAGS "-L%s -lluajit-5.1 -lverilua_vcs -lz"]], libluajit51_lib), -- libz is used by VERDI
                "-load " .. libverilua_vcs_so,
                "-o", path.join(sim_build_dir, "simv")
            }

            local vcs_cc = find_file("gcc", { "$(env PATH)" })
            local vcs_cpp = find_file("g++", { "$(env PATH)" })
            local vcs_ld = find_file("g++", { "$(env PATH)" })
            if vcs_cc ~= nil then
                extra_vcs_flags[#extra_vcs_flags + 1] = "-cc " .. vcs_cc
            end
            if vcs_cpp ~= nil then
                extra_vcs_flags[#extra_vcs_flags + 1] = "-cpp " .. vcs_cpp
            end
            if vcs_ld ~= nil then
                extra_vcs_flags[#extra_vcs_flags + 1] = "-ld " .. vcs_ld
            end

            --- Disable vcs reg initialization, verilua use `+vcs+initreg+0` by default.
            --- e.g. (in your xmake.lua)
            --- ```lua
            ---     set_values("cfg.vcs_no_initreg", "1")
            --- ```
            if target:values("cfg.vcs_no_initreg") ~= "1" then
                extra_vcs_flags[#extra_vcs_flags + 1] = "+vcs+initreg+random"
            end

            if no_internal_clock == "1" then
                extra_vcs_flags[#extra_vcs_flags + 1] = "+define+NO_INTERNAL_CLOCK"
            end

            -- TODO: pass include flags to `testbench_gen`(VCS/Verilator/Icarus/Xcelium)

            -- Some flags can be overridden by user defined flags
            local _vcs_flags = target:values("vcs.flags") or {}
            if type(_vcs_flags) ~= "table" then
                _vcs_flags = { _vcs_flags }
            end
            local vcs_uflags = table.concat(_vcs_flags, " ")
            vcs_uflags = vcs_uflags:split(" ", { plain = true })
            for i, uflag in ipairs(vcs_uflags) do
                if uflag:startswith("-timescale=") then
                    -- Override the timescale flag
                    for j, eflag in ipairs(extra_vcs_flags) do
                        if eflag:startswith("-timescale=") then
                            extra_vcs_flags[j] = uflag
                        end
                    end
                elseif uflag:startswith("+incdir+") then
                    local includedir = uflag:sub(9)
                    table.insert(v_include_dirs, includedir)
                elseif uflag == "-cc" then
                    for j, eflag in ipairs(extra_vcs_flags) do
                        if eflag:startswith("-cc ") then
                            local cc_value = vcs_uflags[i + 1]
                            assert(
                                cc_value,
                                "Invalid `-cc` option for vcs.flags, `-cc` should be followed by a value(e.g. -cc gcc)"
                            )
                            extra_vcs_flags[j] = uflag .. " " .. cc_value
                        end
                    end
                elseif uflag == "-cpp" then
                    for j, eflag in ipairs(extra_vcs_flags) do
                        if eflag:startswith("-cpp ") then
                            local cpp_value = vcs_uflags[i + 1]
                            assert(
                                cpp_value,
                                "Invalid `-cpp` option for vcs.flags, `-cpp` should be followed by a value(e.g. -cpp g++)"
                            )
                            extra_vcs_flags[j] = uflag .. " " .. cpp_value
                        end
                    end
                elseif uflag == "-ld" then
                    for j, eflag in ipairs(extra_vcs_flags) do
                        if eflag:startswith("-ld ") then
                            local ld_value = vcs_uflags[i + 1]
                            assert(
                                ld_value,
                                "Invalid `-ld` option for vcs.flags, `-ld` should be followed by a value(e.g. -ld g++)"
                            )
                            extra_vcs_flags[j] = uflag .. " " .. ld_value
                        end
                    end
                end
            end

            for _, eflag in ipairs(extra_vcs_flags) do
                target:add("values", "vcs.flags", eflag)
            end
        elseif sim == "xcelium" then
            local extra_xcelium_flags = {
                "-64bit",
                "-licqueue",
                "-elaborate",
                "-name " .. tb_top .. "_snapshot",
                "-xmlibdirpath " .. build_dir,
                "-xmlibdirname " .. path.basename(sim_build_dir),
                "-sv",
                "-timescale " .. default_timescale,
                "-l " .. path.join(build_dir, "xrun_comp.log"),
                "-access +rw",
                "-loadvpi " ..
                path.join(verilua_libs_home, "libverilua_xcelium.so") .. ":vlog_startup_routines_bootstrap",
                "-top " .. tb_top,
                "-nospecify", -- Suppress timing information from specify blocks
                "-define SIM_XCELIUM",
                "-define XCELIUM",
            }

            --- Disable xcelium reg initialization, verilua use `-xminitialize 0` by default.
            --- e.g. (in your xmake.lua)
            --- ```lua
            ---     set_values("cfg.xcelium_no_initreg", "1")
            --- ```
            if target:values("cfg.xcelium_no_initreg") ~= "1" then
                extra_xcelium_flags[#extra_xcelium_flags + 1] = "-xminitialize 0"
            end

            if no_internal_clock == "1" then
                extra_xcelium_flags[#extra_xcelium_flags + 1] = "-define NO_INTERNAL_CLOCK"
            end

            local xcelium_dump_fsdb = false
            local _xcelium_flags = target:values("xcelium.flags") or {}
            if type(_xcelium_flags) ~= "table" then
                _xcelium_flags = { _xcelium_flags }
            end
            local xcelium_uflags = table.concat(_xcelium_flags, " ")
            xcelium_uflags = xcelium_uflags:split(" ", { plain = true })
            for i, uflag in ipairs(xcelium_uflags) do
                if uflag == "-timescale" then
                    -- Override the timescale flag
                    for j, eflag in ipairs(extra_xcelium_flags) do
                        if eflag:startswith("-timescale") then
                            local _timescale = xcelium_uflags[i + 1]
                            assert(
                                _timescale:find("/"),
                                "[on_build] timescale value for `-timescale` option may not be a valid timescale value(e.g. 1ns/1ns)"
                            )
                            extra_xcelium_flags[j] = _timescale
                        end
                    end
                elseif uflag:startswith("+define+XCELIUM_DUMP_FSDB") then
                    xcelium_dump_fsdb = true
                elseif uflag == "-define" then
                    assert(xcelium_uflags[i + 1], "`-define` should be followed by a value")
                    local macro = xcelium_uflags[i + 1]
                    if macro == "XCELIUM_DUMP_FSDB" then
                        xcelium_dump_fsdb = true
                    end
                elseif uflag == "-incdir" then
                    local incudedir = xcelium_uflags[i + 1]
                    assert(incudedir, "`-incdir` should be followed by a value")
                    table.insert(v_include_dirs, incudedir)
                end
            end

            --- By default, xcelium dump SHM waveform, fsdb waveform is only enabled when
            --- user explicitly define `XCELIUM_DUMP_FSDB` macro through `xcelium.flags`.
            --- e.g. (in your xmake.lua)
            --- ```lua
            ---     add_values("xcelium.flags", "-define XCELIUM_DUMP_FSDB")
            ---     -- or
            ---     add_values("xcelium.flags", "+define+XCELIUM_DUMP_FSDB")
            --- ```
            ---
            --- Also, use `XCELIUM_DUMP_VCD` macro to dump vcd waveform.
            --- e.g. (in your xmake.lua)
            --- ```lua
            ---     add_values("xcelium.flags", "-define XCELIUM_DUMP_VCD")
            ---     -- or
            ---     add_values("xcelium.flags", "+define+XCELIUM_DUMP_VCD")
            --- ```
            if xcelium_dump_fsdb then
                local verdi_home = os.getenv("VERDI_HOME")
                local verdi_pli_dir = path.join(verdi_home, "share", "PLI", "IUS", "LINUX64")
                local ld_library_path = os.getenv("LD_LIBRARY_PATH") or ""

                assert(verdi_home, "[on_build] VERDI_HOME is not set when using XCELIUM_DUMP_FSDB")
                os.setenv("LD_LIBRARY_PATH", verdi_pli_dir .. ":" .. ld_library_path)

                extra_xcelium_flags[#extra_xcelium_flags + 1] =
                    "-loadpli1 " ..
                    path.join(verdi_pli_dir, "boot", "debpli.so") .. ":novas_pli_boot"
            end

            for _, eflag in ipairs(extra_xcelium_flags) do
                target:add("values", "xcelium.flags", eflag)
            end
        elseif sim == "wave_vpi" then
            -- Do nothing
        elseif sim == "nosim" then
            local signal_db_file = path.join(build_dir, "signal_db.ldb")
            local extra_nosim_flags = {
                "--build",
                "--quiet",
                "--ignore-underscore-signals",
                "--ignore-chisel-trivial-signals",
                "-o " .. signal_db_file,
                "--top", tb_top,
            }

            local _nosim_flags = target:values("nosim.flags") or {}
            if type(_nosim_flags) ~= "table" then
                _nosim_flags = { _nosim_flags }
            end
            local nosim_uflags = table.concat(_nosim_flags, " ")
            nosim_uflags = nosim_uflags:split(" ", { plain = true })
            for i, uflag in ipairs(nosim_uflags) do
                if uflag == "-I" then
                    local includedir = nosim_uflags[i + 1]
                    assert(
                        includedir,
                        "Invalid `-I` option for nosim.flags, `-I` should be followed by a value(e.g. -I /some/path)"
                    )
                    table.insert(v_include_dirs, includedir)
                end
            end

            for _, eflag in ipairs(extra_nosim_flags) do
                target:add("values", "nosim.flags", eflag)
            end
        end

        local sim_flags = target:values(sim .. ".flags") or {}
        local sim_flags_str = table.concat(sim_flags, " ")
        if sim_flags_str == "" then
            sim_flags_str = "<No flags>"
        end
        cprint(
            "${✅} [verilua-xmake] [%s] `%s.flags` is ${green underline}%s${reset}",
            target:name(),
            sim,
            sim_flags_str
        )
        table.join2(argv, sim_flags)

        -- Add extra includedirs and link flags
        target:add("includedirs",
            path.join(luajitpro_home, "include"),
            path.join(luajitpro_home, "include", "luajit-2.1"),
            path.join(verilua_home, "src", "include")
        )
        -- target:add("links", "luajit-5.1") -- This is move into `apply_build_flags`
        target:add("linkdirs", path.join(luajitpro_home, "lib"), verilua_libs_home)
        target:add("linkdirs", path.join(verilua_home, "conan_installed", "lib"))
        target:add("rpathdirs", path.join(luajitpro_home, "lib"), verilua_libs_home)
        target:add("rpathdirs", path.join(verilua_home, "conan_installed", "lib"))
        target:add("includedirs", path.join(verilua_home, "conan_installed", "include"))

        if sim == "verilator" then
            if use_inertial_put == "1" then
                target:add("links", "verilua_verilator_i")
            else
                target:add("links", "verilua_verilator")
            end
            target:add("files", path.join(verilua_home, "src", "verilator", "*.cpp"))
        elseif sim == "vcs" then
            -- If you are entering a C++ file or an object file compiled from a C++ file on
            -- the vcs command line, you must tell VCS to use the standard C++ library for
            -- linking. To do this, enter the -lstdc++ linker flag with the -LDFLAGS elaboration
            -- option.
            target:add("links", "verilua_vcs", "stdc++")
        end

        --- Generate `<tb_top>.sv` + `others.sv` using `testbench_gen`.
        --- <tb_top>.sv is the testbench top module which instantiates the DUT(top module)  and provides some
        --- internal testbench interfaces used by verilua.
        --- `others.sv` can be used by the user to add some extra testbench logic. This file wont updated by
        --- `testbench_gen` if it already exists.
        ---
        --- You got the `cfg.not_gen_tb` option to disable the automatic generation of testbench top module.
        --- Once you disable it, `<tb_top>.sv` wont be updated or generated even if rtl files changed.
        --- e.g. (in your xmake.lua)
        --- ```lua
        ---     set_values("cfg.not_gen_tb", "1")
        --- ```
        local _not_gen_tb = target:values("cfg.not_gen_tb")
        local not_gen_tb = false
        local _not_gen_tb_t = type(_not_gen_tb)
        if _not_gen_tb_t == "string" and _not_gen_tb == "1" then
            not_gen_tb = true
        elseif _not_gen_tb_t == "table" and _not_gen_tb[1] == "1" then
            not_gen_tb = true
        end
        if sim ~= "wave_vpi" and not not_gen_tb then
            local vfiles = {}
            local file_str = ""
            for _, sourcefile in ipairs(target:sourcefiles()) do
                local ext = path.extension(sourcefile)
                if ext == ".v" or ext == ".sv" or ext == ".svh" then
                    if sourcefile:endswith(tb_top .. ".sv") then
                        raise("<%s.sv> is already exist! %s", tb_top, path.absolute(sourcefile))
                    end
                    table.insert(vfiles, sourcefile)
                    file_str = file_str .. " " .. path.absolute(sourcefile)
                end
            end

            assert(file_str ~= "", "[on_build] Cannot find any .v/.sv files!")

            --- Since <tb_top>.sv and others.sv are generated by `testbench_gen` command, you can
            --- specify the `cfg.tb_gen_flags` to pass some additional flags to `testbench_gen`
            --- e.g. (in your xmake.lua)
            --- ```lua
            ---    set_values("cfg.tb_gen_flags", { "--some_flag", "--another_flag" })
            --- ```
            --- For more information about `testbench_gen`, please refer to `testbench_gen --help`
            local u_tb_gen_flags = target:values("cfg.tb_gen_flags")
            local tb_gen_flags = {
                "--top", top,
                "--tbtop", tb_top,
                "--nodpi",
                "--verbose",
                "--out-dir", build_dir,
                "--lua-meta-file", path.join("build", "meta.lua")
            }
            local include_flag_str = ""
            for _, includedir in ipairs(v_include_dirs) do
                include_flag_str = include_flag_str .. "-I " .. includedir .. " "
            end
            if u_tb_gen_flags then
                tb_gen_flags = table.join2(tb_gen_flags, u_tb_gen_flags)
            end
            local gen_cmd = path.join(verilua_tools_home, "testbench_gen") ..
                " " .. table.concat(tb_gen_flags, " ") .. " " .. file_str .. " " .. include_flag_str

            --- You can also specify your own testbench top module file using `cfg.tb_top_file`.
            --- e.g. (in your xmake.lua)
            --- ```lua
            ---     set_values("cfg.tb_top_file", "/path/to/your/my_tb_top.sv")
            --- ```
            --- In the above example, `my_tb_top.sv` will be used as testbench top module.
            --- Notice: Once you specify your own testbench top module, you are not allowed to
            --- use some of the verilua features which depend on the generated testbench top module, e.g. `sim.dump_wave()`.
            local should_regenerate = true
            local input_tb_top_file = target:values("cfg.tb_top_file")
            if input_tb_top_file ~= nil then
                if os.isfile(input_tb_top_file) then
                    should_regenerate = false
                    input_tb_top_file = path.absolute(input_tb_top_file)
                else
                    raise("cfg.tb_top_file = " .. input_tb_top_file .. " is not a valid file!")
                end
            end

            if should_regenerate then
                local has_testbench_gen = find_file("testbench_gen", { "$(env PATH)" })
                if not has_testbench_gen then
                    raise(
                        "[on_build] Cannot find `testbench_gen`! You should build `testbench_gen` in `verilua` root directory via `xmake build testbench_gen`")
                end

                os.exec(gen_cmd)
                target:add("files", path.join(build_dir, tb_top .. ".sv"), path.join(build_dir, "others.sv"))
            else
                target:add("files", input_tb_top_file)
            end
        end

        --- User defined `before_build`, the reason for this is that we want the generated files(tb_top.sv, others.sv) to be added to the target files
        --- so that we could use them in `before_build` for further processing and at this time we own the complete rtl files.
        --- e.g.(in your xmake.lua)
        --- ```lua
        ---     set_values("before_build", function(target)
        ---         -- Do something
        ---     end)
        --- ```
        local user_before_build = target:values("before_build")
        if user_before_build then
            local t = type(user_before_build)
            assert(t == "function", f("[on_build] before_build should be a `function`, but got `%s`", t))
            if _ENV then
                debug.setupvalue(user_before_build, 1, _ENV)
            end
            user_before_build(target)
        end

        --- Instrumentation feature introduced in verilua for runtime coverage collection and other future features.
        --- Notice: For now, only `cov_exporter` is supported.
        --- e.g. (in your xmake.lua)
        --- ```lua
        ---     set_values("instrumentation", function()
        ---         return {
        ---             {
        ---                 type = "cov_exporter",
        ---                 config = {
        ---                     { module = "LLC", recursive = true }
        ---                 },
        ---                 extra_args = [[
        ---                     +define+SYNTHESIS
        ---                     --alt-clock "tb_top.clock"
        ---                     --dm ".*ram.*"
        ---                 ]]
        ---             },
        ---             -- Other instrumentation configurations...
        ---         }
        ---     end)
        --- ```
        local _instrumentation = target:values("instrumentation")
        if _instrumentation then
            local t = type(_instrumentation)
            assert(
                t == "function",
                "[on_build] `instrumentation` should be a `function` with a return value of `InstrumentationConfig[]`, but got `%s`",
                t
            )

            local instrumentation = _instrumentation()
            assert(
                type(instrumentation) == "table",
                "[on_build] return value of `instrumentation` function should be a `table` of `InstrumentationConfig[]`, but got `%s`",
                type(instrumentation)
            )
            ---@cast instrumentation InstrumentationConfig[]

            local gen_filelist = function()
                local vfiles = {}
                local _sourcefiles = target:sourcefiles()
                for _, sourcefile in ipairs(_sourcefiles) do
                    local ext = path.extension(sourcefile)
                    if ext == ".v" or ext == ".sv" or ext == ".svh" then
                        table.insert(vfiles, path.absolute(sourcefile))
                    end
                end

                local filelist = path.join(build_dir, "instrumentation.f")
                io.writefile(filelist, table.concat(vfiles, "\n"))
                return filelist
            end

            local replace_sourcefiles = function(newpath)
                local _sourcefiles = target:sourcefiles()
                for i, sourcefile in ipairs(_sourcefiles) do
                    local ext = path.extension(sourcefile)
                    if ext == ".v" or ext == ".sv" or ext == ".svh" then
                        local filename = path.filename(sourcefile)
                        local newfile = path.join(newpath, filename)
                        _sourcefiles[i] = newfile
                    end
                end
            end

            for _, inst in ipairs(instrumentation) do
                if inst.type == "cov_exporter" then
                    local cov_exporter_outdir = path.join(build_dir, ".cov_exporter")
                    local cmd = "cov_exporter -q -f " .. gen_filelist() .. " --top " .. tb_top .. " +define+SYNTHESIS "
                    local etype = type(inst.extra_args)
                    if etype == "table" then
                        cmd = cmd .. table.concat(inst.extra_args, " ")
                    elseif etype == "string" then
                        -- Replace '\n' with ' '
                        cmd = cmd .. inst.extra_args:gsub("\n", " ")
                    end
                    cmd = cmd .. " --outdir " .. cov_exporter_outdir .. " --workdir " .. cov_exporter_outdir

                    local config = inst.config
                    for _, module_cfg in ipairs(config) do
                        assert(
                            type(module_cfg.module) == "string",
                            "[on_build] `module` should be a `string`, but got `%s`",
                            type(module_cfg.module)
                        )
                        cmd = cmd .. " --module " .. module_cfg.module
                        if module_cfg.disable_signal then
                            cmd = cmd ..
                                " --disable-signal-pattern \"" ..
                                module_cfg.module .. ":" .. module_cfg.disable_signal .. "\""
                        end
                        if module_cfg.clock then
                            cmd = cmd .. " --clock-signal \"" .. module_cfg.module .. ":" .. module_cfg.clock .. "\""
                        end
                        if module_cfg.recursive then
                            cmd = cmd .. " --recursive-module " .. module_cfg.module
                        end
                    end

                    os.vrun(cmd)
                    replace_sourcefiles(cov_exporter_outdir)
                else
                    raise("[on_build] Unknown instrumentation type: %s", inst.type)
                end
            end
        end

        --- Here we manage to apply some build flags according to target settings.
        --- e.g. cflags, ldflags, defines, includedirs, linkdirs, etc.
        --- These flags are commonly used in C/C++ projects, but they are also useful in verilua project.
        --- e.g. you may want to add some `-D` defines to your verilog source files or add some
        --- include directories for verilator to find some C/C++ header files.
        --- e.g. (in your xmake.lua)
        --- ```lua
        ---     add_defines("SIM_VERILATOR", "HELLO=1")
        ---     add_includedirs("/path/to/inc1", "/path/to/inc2")
        ---     add_cflags("-Wall", "-Wextra")
        ---     add_ldflags("-lfmt", "-lmimalloc")
        ---     add_linkdirs("/path/to/lib1", "/path/to/lib2")
        ---     add_links("fmt", "mimalloc")
        --- ```
        ---@param _argv table?
        ---@return string CFLAGS string
        ---@return string LDFLAGS string
        local function apply_build_flags(_argv)
            _argv = _argv or {}
            local all_cflags_str = ""
            local all_ldflags_str = ""
            -- TODO: Support `add_linkgroups()`

            --- e.g. (in your xmake.lua)
            --- ```lua
            ---     add_cflags("-Wall", "-Wextra")
            --- ```
            local cflags = target:get("cflags")
            local cflags_t = type(cflags)
            if cflags_t == "table" then
                local s = table.concat(cflags, " ")
                all_cflags_str = all_cflags_str .. " " .. s
                table.insert(_argv, f([[-CFLAGS "%s"]], s))
            elseif cflags_t == "string" then
                all_cflags_str = all_cflags_str .. " " .. cflags
                table.insert(_argv, f([[-CFLAGS "%s"]], cflags))
            end

            --- e.g. (in your xmake.lua)
            --- ```lua
            ---     add_ldflags("-lfmt")
            --- ```
            local ldflags = target:get("ldflags")
            local ldflags_t = type(ldflags)
            if ldflags_t == "table" then
                local s = table.concat(ldflags, " ")
                all_ldflags_str = all_ldflags_str .. " " .. s
                table.insert(_argv, f([[-LDFLAGS "%s"]], s))
            elseif ldflags_t == "string" then
                all_ldflags_str = all_ldflags_str .. " " .. ldflags
                table.insert(_argv, f([[-LDFLAGS "%s"]], ldflags))
            end

            --- e.g. (in your xmake.lua)
            --- ```lua
            ---     add_defines("HELLO", "WORLD=1")
            --- ```
            local defines = target:get("defines")
            local defines_t = type(defines)
            if defines_t == "table" then
                for _, define in ipairs(defines) do
                    all_cflags_str = all_cflags_str .. " -D" .. define
                    table.insert(_argv, f([[-CFLAGS "-D%s"]], define))
                end
            elseif defines_t == "string" then
                all_cflags_str = all_cflags_str .. " -D" .. defines
                table.insert(_argv, f([[-CFLAGS "-D%s"]], defines))
            end

            --- e.g. (in your xmake.lua)
            --- ```lua
            ---     add_includedirs("/path/to/inc1", "/path/to/inc2")
            --- ```
            local includedirs = target:get("includedirs")
            local includedirs_t = type(includedirs)
            if includedirs_t == "table" then
                for _, dir in ipairs(includedirs) do
                    all_cflags_str = all_cflags_str .. " -I" .. path.absolute(dir)
                    table.insert(_argv, "-CFLAGS")
                    table.insert(_argv, "-I" .. path.absolute(dir))
                end
            elseif includedirs_t == "string" then
                all_cflags_str = all_cflags_str .. " -I" .. path.absolute(includedirs)
                table.insert(_argv, "-CFLAGS")
                table.insert(_argv, "-I" .. path.absolute(includedirs))
            end

            --- e.g. (in your xmake.lua)
            --- ```lua
            ---     add_linkdirs("/path/to/link1", "/path/to/link2")
            ---     add_rpathdirs("/path/to/link1", "/path/to/link2")
            --- ```
            local linkdirs, rpathdirs = target:get("linkdirs"), target:get("rpathdirs")
            local linkdirs_t, rpathdirs_t = type(linkdirs), type(rpathdirs)
            if linkdirs_t == "table" then
                for _, dir in ipairs(linkdirs) do
                    all_ldflags_str = all_ldflags_str .. " -L" .. path.absolute(dir)
                    table.insert(_argv, "-LDFLAGS \"-L" .. path.absolute(dir) .. "\"")
                end
            elseif linkdirs_t == "string" then
                all_ldflags_str = all_ldflags_str .. " -L" .. path.absolute(linkdirs)
                table.insert(_argv, "-LDFLAGS \"-L" .. path.absolute(linkdirs) .. "\"")
            end
            if rpathdirs_t == "table" then
                for _, dir in ipairs(rpathdirs) do
                    all_ldflags_str = all_ldflags_str .. " -Wl,-rpath," .. path.absolute(dir)
                    table.insert(_argv, "-LDFLAGS \"-Wl,-rpath," .. path.absolute(dir) .. "\"")
                end
            elseif rpathdirs_t == "string" then
                all_ldflags_str = all_ldflags_str .. " -Wl,-rpath," .. path.absolute(rpathdirs)
                table.insert(_argv, "-LDFLAGS \"-Wl,-rpath," .. path.absolute(rpathdirs) .. "\"")
            end

            --- e.g. (in your xmake.lua)
            --- ```lua
            ---     add_links("fmt", "mimalloc")
            --- ```
            local links = target:get("links")
            local links_t = type(links)
            if links_t == "table" then
                for _, link in ipairs(links) do
                    all_ldflags_str = all_ldflags_str .. " -l" .. link
                    table.insert(_argv, "-LDFLAGS")
                    table.insert(_argv, "-l" .. link)
                end
            elseif links_t == "string" then
                all_ldflags_str = all_ldflags_str .. " -l" .. links
                table.insert(_argv, "-LDFLAGS")
                table.insert(_argv, "-l" .. links)
            end

            -- Apply luajit build flags
            local luajit_ldflags =
                "-Wl,--no-as-needed -Wl,--whole-archive " ..
                "-lluajit-5.1 " ..
                "-Wl,--no-whole-archive -Wl,--as-needed"
            if sim == "vcs" then
                -- Otherwise there will be linking errors in specific vcs version.
                -- e.g.: "<lib>: undefined reference to <xxx>", etc.
                luajit_ldflags = "-lluajit-5.1"
            end
            all_ldflags_str = all_ldflags_str .. " " .. luajit_ldflags
            table.insert(_argv,
                "-LDFLAGS " ..
                f([["%s"]], luajit_ldflags)
            )

            return all_cflags_str, all_ldflags_str
        end

        if sim == "verilator" then
            toolchain = assert(
                target:toolchain("verilator"),
                '[on_build] we need to set_toolchains("@verilator") in target("%s")',
                target:name()
            )
            buildcmd = find_file("verilator", { "$(env PATH)" }) or
                assert(toolchain:config("verilator"), "[on_build] verilator not found!")

            apply_build_flags(argv)
        elseif sim == "iverilog" then
            toolchain = assert(
                target:toolchain("iverilog"),
                '[on_build] we need to set_toolchains("@iverilog") in target("%s")',
                target:name()
            )
            buildcmd = find_file("iverilog", { "$(env PATH)" }) or
                assert(toolchain:config("iverilog"), "[on_build] iverilog not found!")
        elseif sim == "vcs" then
            toolchain = assert(
                target:toolchain("vcs"),
                '[on_build] we need to set_toolchains("@vcs") in target("%s")',
                target:name()
            )
            buildcmd = find_file("vcs", { "$(env PATH)" }) or
                assert(toolchain:config("vcs"), "[on_build] vcs not found!")

            apply_build_flags(argv)
        elseif sim == "xcelium" then
            toolchain = assert(
                target:toolchain("xcelium"),
                '[on_build] we need to set_toolchains("@xcelium") in target("%s")',
                target:name()
            )
            buildcmd = find_file("xrun", { "$(env PATH)" }) or
                assert(toolchain:config("xcelium"), "[on_build] vcs not found!")
        elseif sim == "wave_vpi" then
            -- Do nothing
        elseif sim == "nosim" then
            toolchain = assert(
                target:toolchain("nosim"),
                '[on_build] we need to set_toolchains("@nosim") in target("%s")',
                target:name()
            )
            buildcmd = find_file("nosim", { "$(env PATH)" }) or
                assert(toolchain:config("nosim"), "[on_build] nosim not found!")
        else
            raise("Unknown simulator! => " .. tostring(sim))
        end

        sourcefiles = target:sourcefiles()
        local filelist_dut = {} -- only v/sv files
        local filelist_sim = {} -- including c/c++ files
        local full_buildcmd = ""
        if sim == "wave_vpi" then
            local waveform_file = assert(
                target:get("waveform_file"),
                "[on_build] waveform_file not found! Please use add_files to add waveform files (.vcd, .fst, .fsdb)"
            )

            local wave_vpi_main
            do
                if waveform_file:endswith(".fsdb") then
                    wave_vpi_main = find_file("wave_vpi_main_fsdb", { "$(env PATH)" })
                    assert(wave_vpi_main, "[on_build] wave_vpi_main_fsdb is not defined!")
                else
                    wave_vpi_main = find_file("wave_vpi_main", { "$(env PATH)" })
                    if not wave_vpi_main then
                        local toolchain = assert(
                            target:toolchain("wave_vpi"),
                            '[on_build] we need to set_toolchains("@wave_vpi") in target("%s")',
                            target:name()
                        )
                        wave_vpi_main = assert(toolchain:config("wave_vpi"), "[on_build] wave_vpi_main not found!")
                    end
                end
            end

            cprint(
                "${✅} [verilua-xmake] [%s] wave_vpi_main is ${green underline}%s${reset}",
                target:name(),
                wave_vpi_main
            )
            cprint(
                "${✅} [verilua-xmake] [%s] waveform_file is ${green underline}%s${reset}",
                target:name(),
                waveform_file
            )
        else
            -- Used when sim == "xcelium" to build C/C++ files
            local cfiles = {}

            for _, sourcefile in ipairs(sourcefiles) do
                local ext = path.extension(sourcefile) --[[@as string]]
                local abs_sourcefile = path.absolute(sourcefile)
                cprint("${📄} read file ${green dim}%s${reset}", abs_sourcefile)
                if ext ~= ".lua" and ext ~= ".luau" and ext ~= ".tl" then
                    if ext == ".vlt" then
                        if sim == "verilator" then
                            -- Ignore "*.vlt" file if current simulator is not verilator
                            table.insert(filelist_sim, abs_sourcefile)
                            table.insert(argv, abs_sourcefile)
                        end
                    elseif ext == ".v" or ext == ".sv" or ext == ".svh" then
                        table.insert(filelist_dut, abs_sourcefile)
                        table.insert(filelist_sim, abs_sourcefile)
                    elseif ext == ".c" or ext == ".cpp" then
                        table.insert(filelist_sim, abs_sourcefile)
                        if sim == "xcelium" then
                            table.insert(cfiles, abs_sourcefile)
                        else
                            table.insert(argv, abs_sourcefile)
                        end
                    else
                        table.insert(filelist_sim, abs_sourcefile)
                        table.insert(argv, abs_sourcefile)
                    end
                end
            end

            local dut_file_f = path.join(build_dir, "dut_file.f")
            local sim_file_f = path.join(build_dir, "sim_file.f")
            if #filelist_dut >= 200 then
                -- filelist_dut is too long, pass a filelist to simulator
                table.insert(argv, "-f " .. dut_file_f)
            else
                table.join2(argv, filelist_dut)
            end

            -- Write filelist of this build
            io.writefile(dut_file_f, table.concat(filelist_dut, '\n'))
            io.writefile(sim_file_f, table.concat(filelist_sim, '\n'))

            -- Run the build command to generate target binary
            full_buildcmd = buildcmd .. " " .. table.concat(argv, " ")
            cprint(
                "${✅} [verilua-xmake] [%s] full buildcmd is ${green underline}%s${reset}",
                target:name(),
                full_buildcmd
            )
            os.vrun(full_buildcmd)
            if sim == "verilator" then
                --- e.g.
                --- ```lua
                ---     set_values("verilator.opt_slow", "-O3")
                ---     set_values("verilator.opt_fast", "-O0")
                --- ```
                local user_opt_slow = target:values("verilator.opt_slow")
                local user_opt_fast = target:values("verilator.opt_fast")
                assert(
                    type(user_opt_slow) == "nil" or type(user_opt_slow) == "string",
                    "[on_build] `verilator.opt_slow`` must be a string"
                )
                assert(
                    type(user_opt_fast) == "nil" or type(user_opt_fast) == "string",
                    "[on_build] `verilator.opt_fast` must be a string"
                )

                local nproc = os.cpuinfo().ncpu or 128
                local tb_top_mk = path.join(sim_build_dir, "V" .. tb_top .. ".mk")

                -- OPT_SLOW applies to slow-path code, which rarely executes, often only once at the beginning or end of the simulation.
                local opt_slow = user_opt_slow or "-O0"

                -- OPT_FAST specifies optimization options for those parts of the model on the fast path.
                -- This is mostly code that is executed every cycle.
                local opt_fast = user_opt_fast or "-O3 -march=native"

                -- TODO: consider PGO optimization
                os.cd(sim_build_dir)
                os.vrun(
                    [[make -j%d VM_PARALLEL_BUILDS=1 OPT_SLOW="%s" OPT_FAST="%s" -C %s -f %s]],
                    nproc,
                    opt_slow,
                    opt_fast,
                    sim_build_dir,
                    tb_top_mk
                )
                os.cd(os.curdir())
            elseif sim == "xcelium" and #cfiles > 0 then
                import("lib.detect.find_file")

                -- Build libdpi.so
                local cc = os.getenv("CC") or "gcc"
                local cxx = os.getenv("CXX") or "g++"

                local obj_files = {}
                local all_cflags_str, all_ldflags_str = apply_build_flags()
                local total_cfiles = #cfiles
                local obj_dir = path.join(build_dir, "libdpi_objs")

                if not os.isdir(obj_dir) then
                    os.mkdir(obj_dir)
                end

                local cds_root = assert(
                    find_file("cds_root", { "$(env PATH)" }),
                    "[on_build] Current simulator is `xcelium`, but `cds_root` not found!"
                )
                local xrun_home = os.iorun(cds_root .. " xrun"):trim():gsub("\n", "")
                local xrun_include = path.join(xrun_home, "tools", "include")
                assert(
                    os.exists(path.join(xrun_include, "svdpi.h")),
                    "[xcelium.lua] [xrun_comp] error: svdpi.h is not found in %s",
                    xrun_include
                )
                all_cflags_str = all_cflags_str .. " -I" .. xrun_include

                for i, cfile in ipairs(cfiles) do
                    local ext = path.extension(cfile)
                    local basename = path.basename(cfile)
                    local obj_file = path.join(obj_dir, basename) .. ".o"
                    local compiler = cxx
                    if ext == ".c" then
                        compiler = cc
                    end

                    local cmd = f("%s -c -fPIC %s %s -o %s", compiler, all_cflags_str, cfile, obj_file)
                    print(f("[%d/%d]", i, total_cfiles), cmd)
                    os.exec(cmd)

                    obj_files[#obj_files + 1] = obj_file
                end

                -- `libdpi.so` can be automatically recognized by xcelium as a default DPI library without extra flags(i.e. -sv_lib)
                local so_file = path.join(build_dir, "libdpi.so")
                local cmd = f("%s -shared -Wl,-soname,libdpi.so %s -o %s %s", cxx, all_ldflags_str, so_file,
                    table.concat(obj_files, " "))
                print(cmd)
                os.exec(cmd)
            end
        end

        --
        -- Create a clean.sh + build.sh + run.sh that can be used by user to manually build/run/clean the simulation.
        --
        -- Save the current environment variables
        local _runenvs = target:get("runenvs")
        local extra_runenvs = ""
        if _runenvs ~= nil then
            for key, value in pairs(_runenvs) do
                if key == "LD_LIBRARY_PATH" or key == "PATH" then
                    extra_runenvs = extra_runenvs .. "export " .. key .. "=" .. value .. ":$" .. key .. "\n"
                else
                    extra_runenvs = extra_runenvs .. "export " .. key .. "=" .. value .. "\n"
                end
            end
        end

        io.printf(
            path.join(build_dir, "setvars.sh"),
            [[#!/usr/bin/env bash
export VERILUA_CFG=%s
export SIM=%s
%s]],
            target:get("verilua_cfg_file"),
            sim,
            extra_runenvs
        )

        io.printf(
            path.join(build_dir, "clean.sh"),
            [[#!/usr/bin/env bash
source setvars.sh
rm -rf %s]],
            sim_build_dir
        )

        local buildcmd_str = ""
        if sim == "wave_vpi" then
            buildcmd_str = "# wave_vpi did not support build.sh \n#"
        else
            buildcmd_str = buildcmd .. " " .. table.concat(argv, " ")
            -- TODO: extra build cmd for verilator(i.e. cd <sim_build_dir> && make ...)
        end
        io.printf(
            path.join(build_dir, "build.sh"),
            [[#!/usr/bin/env bash
source setvars.sh
%s 2>&1 | tee build.log]],
            buildcmd_str
        )

        local run_sh = ""
        if sim == "verilator" then
            run_sh = f("%s/V%s 2>&1 | tee run.log", sim_build_dir, tb_top)
        elseif sim == "vcs" then
            run_sh = f(
                "%s/simv %s +notimingcheck 2>&1 | tee run.log",
                sim_build_dir,
                (target:values("cfg.vcs_no_initreg") == "1") and "" or "+vcs+initreg+0"
            )
        elseif sim == "xcelium" then
            run_sh = f(
                "xrun -r %s_snapshot -xmlibdirpath %s -xmlibdirname %s -l %s %s -loadvpi %s:vlog_startup_routines_bootstrap",
                tb_top,
                build_dir,
                path.basename(sim_build_dir),
                path.join(build_dir, "xrun_run.log"),
                (target:values("cfg.xcelium_no_initreg") == "1") and "" or "-xminitialize 0",
                path.join(verilua_libs_home, "libverilua_xcelium.so")
            )
        elseif sim == "iverilog" then
            run_sh = f("vvp -M %s -m libverilua_iverilog %s/simv.vvp | tee run.log", verilua_libs_home, sim_build_dir)
        elseif sim == "wave_vpi" then
            local waveform_file = assert(
                target:get("waveform_file"),
                "[on_build] waveform_file not found! Please use add_files to add waveform files (.vcd, .fst, .fsdb)"
            )
            run_sh = f("wave_vpi_main --wave-file %s 2>&1 | tee run.log", waveform_file)
        elseif sim == "nosim" then
            -- TODO:
        end

        io.writefile(
            path.join(build_dir, "run.sh"),
            "#!/usr/bin/env bash\nsource setvars.sh\n" .. run_sh
        )
        io.writefile(
            path.join(build_dir, "debug_run.sh"),
            "#!/usr/bin/env bash\nsource setvars.sh\n" .. "gdb --args " .. run_sh
        )

        io.writefile(
            path.join(build_dir, "verdi.sh"),
            [[#!/usr/bin/env bash
verdi -f filelist.f -sv -nologo $@]]
        )

        -- Copy the generated binary to targetdir
        os.mkdir(target:targetdir())
        if sim == "verilator" then
            local target_file = path.join(sim_build_dir, "V" .. tb_top)
            os.cp(target_file, target:targetdir())
            os.cp(target_file, path.join(target:targetdir(), target:name())) -- make xmake happy, otherwise it would fail to find the binary
        elseif sim == "iverilog" then
            local target_file = path.join(sim_build_dir, "simv.vvp")
            os.cp(target_file, target:targetdir())
            os.cp(target_file, path.join(target:targetdir(), target:name())) -- make xmake happy, otherwise it would fail to find the binary
        elseif sim == "vcs" then
            local target_file = path.join(sim_build_dir, "simv")
            os.cp(target_file, target:targetdir())
            os.cp(target_file, path.join(target:targetdir(), target:name())) -- make xmake happy, otherwise it would fail to find the binary
        elseif sim == "wave_vpi" or sim == "xcelium" then
            os.touch(path.join(target:targetdir(), target:name()))           -- make xmake happy, otherwise it would fail to find the binary
        elseif sim == "nosim" then
            -- Save cmdline into a seperate file which can be used in `SignalDB.lua`
            local lines = {
                "-- Generated by verilua-xmake, do not edit this file manually!",
                "-- This file expected to be read by `SignalDB.lua` to get the cmdline args of nosim.",
                format("return \"%s\"", table.concat(argv, " ")),
            }
            io.writefile(path.join(build_dir, "nosim_cmdline_args.lua"), table.concat(lines, "\n"))

            os.touch(path.join(target:targetdir(), target:name())) -- make xmake happy, otherwise it would fail to find the binary
        end
    end)

    on_clean(function(target)
        local sim = get_simulator_type(target)
        assert(sim, "[on_clean] [%s] simulator type not found!", target:name())

        local build_dir = get_build_dir(target, sim)
        if build_dir ~= "" and os.isdir(build_dir) then
            os.rmdir(build_dir)
        end
        print("[verilua-xmake] [%s] clean build dir: %s", target:name(), build_dir)

        try {
            function()
                local tdir = target:targetdir()
                if tdir and tdir ~= "" and os.isdir(tdir) then
                    os.rmdir(tdir)
                end
            end
        }
    end)

    on_run(function(target)
        assert(verilua_home ~= "", "[on_run] [%s] please set VERILUA_HOME", target:name())

        local sim = target:get("sim")
        local tb_top = target:get("tb_top")
        local build_dir = target:get("build_dir")
        local sim_build_dir = target:get("sim_build_dir")

        -- Set runtime envs
        local runenvs = target:get("runenvs")
        for k, env in pairs(runenvs) do
            local _env = {}
            if k == "LD_LIBRARY_PATH" or k == "PATH" then
                _env[k] = path.absolute(env)
            else
                _env[k] = env
            end
            os.addenvs(_env)
        end

        --- Set VERILUA_CFG for verilua
        --- VERILUA_CFG will be used when verilua call `init.lua` to load user configuration file
        os.setenv("VERILUA_CFG", target:get("verilua_cfg_file"))

        -- Move into build directory to execute our simulation
        os.cd(build_dir)

        --- `<sim>.run_flags` and `<sim>.run_prefix` is provided for the user to controlling the simulation runtime behavior.
        --- e.g. (in your xmake.lua)
        --- ```lua
        ---     add_values("verilator.run_flags", "--flag")
        ---     add_values("verilator.run_prefix", "gdb --args")
        --- ```
        local full_runcmd = ""
        if sim == "verilator" then
            local run_flags = { "" }
            local _run_flags = target:values("verilator.run_flags")
            if _run_flags then
                table.join2(run_flags, _run_flags)
            end

            local run_prefix = { "" }
            local _run_prefix = target:values("verilator.run_prefix")
            if _run_prefix then
                table.join2(run_prefix, _run_prefix)
            end

            local vtb_top = path.join(sim_build_dir, "V" .. tb_top)
            full_runcmd =
                table.concat(run_prefix, " ") ..
                " " .. vtb_top .. " " .. table.concat(run_flags, " ")
        elseif sim == "iverilog" then
            import("lib.detect.find_file")

            local run_flags = { "-M", verilua_libs_home, "-m", "libverilua_iverilog" }
            local _run_flags = target:values("iverilog.run_flags")
            if _run_flags then
                local _run_flags_str
                if type(_run_flags) == "string" then
                    _run_flags_str = _run_flags:trim()
                else
                    _run_flags_str = table.concat(_run_flags, " "):trim()
                end
                local user_run_flags = _run_flags_str:split(" ", { plain = true })

                -- To allow user to override the default `-M` and `-m` flags
                for i, flag in ipairs(user_run_flags) do
                    if flag == "-M" then
                        local M_flag_value = user_run_flags[i + 1]
                        assert(M_flag_value, "[on_run] '-M' flag must be followed by a value")
                        run_flags[2] = M_flag_value
                    elseif flag == "-m" then
                        local m_flag_value = user_run_flags[i + 1]
                        assert(m_flag_value, "[on_run] '-m' flag must be followed by a value")
                        run_flags[4] = m_flag_value
                    end
                end

                table.join2(run_flags, _run_flags)
            end

            local run_prefix = { "" }
            local _run_prefix = target:values("iverilog.run_prefix")
            if _run_prefix then
                table.join2(run_prefix, _run_prefix)
            end

            local vvp = assert(find_file("vvp", { "$(env PATH)" }), "[on_run] vvp not found!")
            local simv_vvp = path.join(sim_build_dir, "simv.vvp")
            full_runcmd =
                table.concat(run_prefix, " ") ..
                " " .. vvp .. " " .. table.concat(run_flags, " ") .. " " .. simv_vvp
        elseif sim == "vcs" then
            local run_flags = {
                "+notimingcheck"
            }
            local _run_flags = target:values("vcs.run_flags")
            if _run_flags then
                table.join2(run_flags, _run_flags)
            end

            if target:values("cfg.vcs_no_initreg") ~= "1" then
                run_flags[#run_flags + 1] = "+vcs+initreg+0"
            end

            local run_prefix = { "" }
            local _run_prefix = target:values("vcs.run_prefix")
            if _run_prefix then
                table.join2(run_prefix, _run_prefix)
            end

            local simv = path.join(sim_build_dir, "simv")
            full_runcmd =
                table.concat(run_prefix, " ") ..
                " " .. simv .. " " .. table.concat(run_flags, " ")
        elseif sim == "xcelium" then
            import("lib.detect.find_file")

            local run_flags = {
                "-64bit",
                "-r " .. tb_top .. "_snapshot",
                "-xmlibdirpath " .. build_dir,
                "-xmlibdirname " .. path.basename(sim_build_dir),
                "-l " .. path.join(build_dir, "xrun_run.log"),
                "-loadvpi " ..
                path.join(verilua_libs_home, "libverilua_xcelium.so") .. ":vlog_startup_routines_bootstrap",
            }

            do
                local xcelium_dump_fsdb = false
                local xcelium_flags = target:values("xcelium.flags") or {}
                if type(xcelium_flags) ~= "table" then
                    xcelium_flags = { xcelium_flags }
                end
                local xcelium_flags_str = table.concat(xcelium_flags, " ")
                local xcelium_uflags = xcelium_flags_str:split(" ", { plain = true })
                for i, uflag in ipairs(xcelium_uflags) do
                    if uflag:startswith("+define+XCELIUM_DUMP_FSDB") then
                        xcelium_dump_fsdb = true
                    elseif uflag == "-define" then
                        local macro = xcelium_uflags[i + 1]
                        if macro == "XCELIUM_DUMP_FSDB" then
                            xcelium_dump_fsdb = true
                        end
                    end
                end

                -- By default, xcelium dump SHM waveform, fsdb waveform is only enabled when user explicitly define `XCELIUM_DUMP_FSDB` macro
                if xcelium_dump_fsdb then
                    local verdi_home = os.getenv("VERDI_HOME")
                    local verdi_pli_dir = path.join(verdi_home, "share", "PLI", "IUS", "LINUX64")
                    local ld_library_path = os.getenv("LD_LIBRARY_PATH") or ""

                    assert(verdi_home, "[on_run] VERDI_HOME is not set when using XCELIUM_DUMP_FSDB")
                    os.setenv("LD_LIBRARY_PATH", verdi_pli_dir .. ":" .. ld_library_path)

                    run_flags[#run_flags + 1] =
                        "-loadpli1 " ..
                        path.join(verdi_pli_dir, "boot", "debpli.so") .. ":novas_pli_boot"
                end
            end

            local _run_flags = target:values("xcelium.run_flags")
            if _run_flags then
                table.join2(run_flags, _run_flags)
            end

            if target:values("cfg.xcelium_no_initreg") ~= "1" then
                run_flags[#run_flags + 1] = "-xminitialize 0"
            end

            local run_prefix = { "" }
            local _run_prefix = target:values("xcelium.run_prefix")
            if _run_prefix then
                table.join2(run_prefix, _run_prefix)
            end

            local xrun = find_file("xrun", { "$(env PATH)" })
            if not xrun then
                local toolchain = assert(
                    target:toolchain("xcelium"),
                    '[on_run] we need to set_toolchains("@xcelium") in target("%s")',
                    target:name()
                )
                xrun = assert(toolchain:config("xrun"), "[on_run] xrun not found!")
            end

            full_runcmd =
                table.concat(run_prefix, " ") ..
                " " .. xrun .. " " .. table.concat(run_flags, " ")
        elseif sim == "wave_vpi" then
            import("lib.detect.find_file")

            local waveform_file = assert(target:get("waveform_file"),
                "[on_run] waveform_file not found! Please use add_files to add waveform files (.vcd, .fst)")

            local wave_vpi_main
            do
                if waveform_file:endswith(".fsdb") then
                    wave_vpi_main = find_file("wave_vpi_main_fsdb", { "$(env PATH)" })
                    assert(wave_vpi_main, "[on_run] wave_vpi_main_fsdb is not defined!")
                else
                    wave_vpi_main = find_file("wave_vpi_main", { "$(env PATH)" })
                    if not wave_vpi_main then
                        local toolchain = assert(
                            target:toolchain("wave_vpi"),
                            '[on_run] we need to set_toolchains("@wave_vpi") in target("%s")',
                            target:name()
                        )
                        wave_vpi_main = assert(toolchain:config("wave_vpi"), "[on_run] wave_vpi_main not found!")
                    end
                end
            end

            cprint("${✅} [verilua-xmake] [%s] wave_vpi_main is ${green underline}%s${reset}", target:name(),
                wave_vpi_main)

            local run_flags = { "--wave-file", waveform_file }
            local _run_flags = target:values("wave_vpi.run_flags")
            if _run_flags then
                table.join2(run_flags, _run_flags)
            end

            local run_prefix = { "" }
            local _run_prefix = target:values("wave_vpi.run_prefix")
            if _run_prefix then
                table.join2(run_prefix, _run_prefix)
            end

            full_runcmd =
                table.concat(run_prefix, " ") ..
                " " .. wave_vpi_main .. " " .. table.concat(run_flags, " ")
        elseif sim == "nosim" then
            import("lib.detect.find_file")

            local nosim = find_file("nosim", { "$(env PATH)" })
            assert(nosim, "[on_run] nosim not found!")

            local run_flags = {}
            local _run_flags = target:values("nosim.run_flags")
            if _run_flags then
                table.join2(run_flags, _run_flags)
            end

            local run_prefix = { "" }
            local _run_prefix = target:values("nosim.run_prefix")
            if _run_prefix then
                table.join2(run_prefix, _run_prefix)
            end

            full_runcmd =
                table.concat(run_prefix, " ") ..
                " " .. nosim .. " " .. table.concat(run_flags, " ")
        else
            raise("TODO: [on_run] unknown simulator => " .. sim)
        end

        cprint(
            "${✅} [verilua-xmake] [%s] full runcmd is ${green underline}%s${reset}",
            target:name(),
            full_runcmd
        )
        os.exec(full_runcmd)
    end)
end)
