---@diagnostic disable: undefined-global, undefined-field

local scriptdir = os.scriptdir()

--- Absolute include directory reachable only through one source simulator's flags.
---@param name string
---@return string
local function incdir(name)
    return path.join(scriptdir, "include", name)
end

--- How often the plain substring `needle` occurs in `haystack`.
---@param haystack string
---@param needle string
---@return integer
local function count_occurrences(haystack, needle)
    return #haystack:split(needle, { plain = true, strict = true }) - 1
end

--- The entries of `needles` that occur in `haystack`.
---@param haystack string
---@param needles string[]
---@return string[]
local function found_in(haystack, needles)
    local found = {}
    for _, needle in ipairs(needles) do
        if haystack:find(needle, 1, true) then
            found[#found + 1] = needle
        end
    end
    return found
end

--- Flags every target shares: each source simulator contributes one spelling per whitelisted option
--- kind. The trailing `-full64` / `-lca` / `--trace` have no nosim equivalent and must be reported as
--- dropped. The timescale is not shared, so a target can make the sources agree on it or disagree.
local function add_shared_flags()
    add_values("vcs.flags",
        "+incdir+" .. incdir("vcs_a") .. "+" .. incdir("vcs_b"),
        "+define+INFER_FROM_VCS_LEVEL=1",
        "-y",
        incdir("vcs_a"),
        "+libext+.v+.sv",
        "-full64",
        "-lca")
    add_values("verilator.flags", "-I" .. incdir("verilator"), "-DINFER_FROM_VERILATOR_LEVEL=1", "--trace")
    add_values("iverilog.flags", "-I", incdir("iverilog"), "-D", "INFER_FROM_IVERILOG_LEVEL=1")
    add_values("xcelium.flags", "-incdir", incdir("xcelium"), "-define", "INFER_FROM_XCELIUM_LEVEL=1")

    -- testbench_gen receives only the inferred include dirs, so its parse needs the probe macros
    -- passed explicitly. nosim gets them from the inferred flags.
    add_values("verilua.tb_gen_flags",
        "-DINFER_FROM_VCS_LEVEL=1",
        "-DINFER_FROM_VERILATOR_LEVEL=1",
        "-DINFER_FROM_IVERILOG_LEVEL=1",
        "-DINFER_FROM_XCELIUM_LEVEL=1")
end

---@class NosimTargetOptions
---@field infer? string `verilua.infer_nosim_flags` value; omitted leaves the switch unset
---@field nosim_flags? string[] Entries for `nosim.flags`; defaults to a `--std` plus one include dir
--- that `xcelium.flags` also provides
---@field top_file? string RTL file to elaborate; defaults to `./top.sv`
---@field configure_flags? fun() Extra flags, applied after the shared ones

--- Build a nosim target whose RTL only elaborates when the flags named by `options.infer` reached
--- `nosim.flags`.
---@param name string xmake target name
---@param build_dir_name string distinct build directory name under `build/nosim`
---@param options NosimTargetOptions
local function add_nosim_target(name, build_dir_name, options)
    target(name, function()
        add_rules("verilua")
        set_default(false)
        add_toolchains("@nosim")

        add_files(options.top_file or "./top.sv")
        set_values("verilua.top", "top")
        set_values("verilua.lua_main", "./main.lua")
        set_values("verilua.build_dir_name", build_dir_name)

        if options.infer then
            set_values("verilua.infer_nosim_flags", options.infer)
        end

        -- A user-written nosim flag must survive next to the inferred ones. The xcelium include dir
        -- is spelled with a different but equivalent path on purpose.
        set_values("nosim.flags", options.nosim_flags or { "--std 1800-2017", "-I " .. incdir("xcelium") .. "/./" })

        add_shared_flags()
        if options.configure_flags then
            options.configure_flags()
        end
    end)
end

add_nosim_target("nosim_infer_off", "infer_off", {})

add_nosim_target("nosim_infer_on", "infer_on", {
    infer = "1",
    configure_flags = function()
        -- Both sources agree on the timescale, so the merge keeps a single `--timescale`.
        add_values("verilator.flags", "--timescale 1ns/1ns", "-DSAME_NAME=")
        -- `+define+NAME` and `-DNAME=` are the same definition with an empty value, so the two
        -- spellings must collapse even though the rendered text differs.
        add_values("vcs.flags", "-timescale=1ns/1ns", "+define+SAME_NAME")
    end,
})

-- Two sources defining one macro differently must fail the build.
add_nosim_target("nosim_infer_conflict_define", "conflict_define", {
    infer = "1",
    configure_flags = function()
        add_values("verilator.flags", "-DCONFLICT_LEVEL=2")
        add_values("vcs.flags", "+define+CONFLICT_LEVEL=1")
    end,
})

-- Two sources disagreeing on the single-valued timescale: same rule.
add_nosim_target("nosim_infer_conflict_timescale", "conflict_timescale", {
    infer = "1",
    configure_flags = function()
        add_values("verilator.flags", "--timescale 1ns/1ns")
        add_values("vcs.flags", "-timescale=1ps/1ps")
    end,
})

-- A macro the user already spelled out in `nosim.flags` conflicts with an inferred one too.
add_nosim_target("nosim_infer_conflict_nosim", "conflict_nosim", {
    infer = "1",
    nosim_flags = { "--std 1800-2017", "-DINFER_FROM_VCS_LEVEL=9" },
})

-- An unknown simulator name in the switch value must fail the build.
add_nosim_target("nosim_infer_bad_source", "bad_source", { infer = "verilator,typo" })

-- The switch may name its sources, so a target that supports several simulators can mirror one of
-- them. The RTL only needs what `vcs.flags` provides.
add_nosim_target("nosim_infer_sources", "infer_sources", {
    infer = "vcs",
    nosim_flags = { "--std 1800-2017" },
    top_file = "./top_vcs_only.sv",
})

target("test", function()
    set_kind("phony")
    set_default(true)

    on_run(function()
        local build_root = path.join(scriptdir, "build", "nosim")
        local failures = {}
        local checks = 0

        ---@param condition boolean
        ---@param message string
        local function check(condition, message)
            checks = checks + 1
            if condition then
                print("[infer_nosim_flags] PASSED: " .. message)
            else
                print("[infer_nosim_flags] FAILED: " .. message)
                failures[#failures + 1] = message
            end
        end

        --- Build a target and capture both of its output streams, so an assertion can match either a
        --- build message or an error text. `os.execv` with `try` returns the exit code instead of
        --- raising; stdout and stderr need separate files because writing both to one truncates it.
        ---@param name string
        ---@return boolean ok
        ---@return string output Build output, stdout followed by stderr
        local function build(name)
            local log_dir = path.join(scriptdir, "build")
            if not os.isdir(log_dir) then
                os.mkdir(log_dir)
            end
            local stdout_file = path.join(log_dir, name .. ".log")
            local stderr_file = path.join(log_dir, name .. ".err")
            local exit_code = os.execv("xmake", { "build", "-P", scriptdir, name },
                { stdout = stdout_file, stderr = stderr_file, try = true })
            local output = (io.readfile(stdout_file) or "") .. (io.readfile(stderr_file) or "")
            -- cprint colorizes its output even into a file, so drop the escapes before matching.
            output = output:gsub("\27%[[%d;]*m", "")
            return exit_code == 0, output
        end

        --- Command line the nosim build wrote for `SignalDB`.
        ---@param build_dir_name string
        ---@return string
        local function cmdline_of(build_dir_name)
            local cmdline_file = path.join(build_root, build_dir_name, "nosim_cmdline_args.lua")
            return os.isfile(cmdline_file) and io.readfile(cmdline_file) or ""
        end

        -- Without the switch the nosim build must fail: the includes are only reachable through the
        -- other simulators' flags.
        os.tryrm(build_root)
        local off_ok = build("nosim_infer_off")
        check(off_ok == false,
            "nosim_infer_off must fail to build while verilua.infer_nosim_flags is unset")

        -- With the switch on, slang elaborates `top.sv`, whose probe headers are reachable and whose
        -- macro references resolve only if every translated spelling arrived. The command line checks
        -- below cover what that elaboration cannot show: merging, conflicts and dropped flags.
        local on_ok, on_output = build("nosim_infer_on")
        check(on_ok == true, "nosim_infer_on must build with verilua.infer_nosim_flags enabled")

        local cmdline = cmdline_of("infer_on")

        -- Both sources name the same timescale, so it must reach the command line once.
        check(count_occurrences(cmdline, "--timescale 1ns/1ns") == 1,
            "a timescale agreed on by two sources must reach the command line exactly once")

        -- `-DNAME=` and `+define+NAME` define the same macro with an empty value, so only one of the
        -- two renderings may reach the command line.
        check(count_occurrences(cmdline, "-D SAME_NAME") == 1,
            "two spellings of the same macro must collapse into one definition")

        -- `-y` / `+libext+` translate, and a `+`-separated libext list expands to one option each.
        -- Nothing in the RTL needs either of them, so the elaboration above cannot cover this.
        check(cmdline:find("-y " .. incdir("vcs_a"), 1, true) ~= nil and
            cmdline:find("+libext+.v", 1, true) ~= nil and
            cmdline:find("+libext+.sv", 1, true) ~= nil,
            "`-y` and a `+`-separated `+libext+` list must be translated and expanded")

        -- A user-written nosim flag is kept next to the inferred ones, and the xcelium include dir
        -- they spelled differently is the same directory `xcelium.flags` names, so the merge must
        -- keep the user's spelling and drop the inferred option.
        check(cmdline:find("--std 1800-2017", 1, true) ~= nil,
            "nosim command line must keep the user's own nosim.flags entry")
        check(cmdline:find("-I " .. incdir("xcelium") .. "/./", 1, true) ~= nil and
            count_occurrences(cmdline, "-I " .. incdir("xcelium")) == 1,
            "an include dir already written into nosim.flags must keep its spelling and not be inferred again")

        -- Flags with no nosim equivalent are reported per source and must not reach the command line.
        check(
            on_output:find("flags in vcs.flags have no nosim equivalent and were dropped: -full64 -lca", 1, true) ~= nil and
            on_output:find("flags in verilator.flags have no nosim equivalent and were dropped: --trace", 1, true) ~= nil,
            "every dropped flag must be reported against the `.flags` it came from")
        local leaked = found_in(cmdline, { "-full64", "-lca", "--trace" })
        check(#leaked == 0, "a dropped flag must not reach the nosim command line, found: " .. table.concat(leaked, " "))

        -- Two sources may not define one macro with two different values, and the report has to name
        -- both sides so the conflict can be resolved without reading the rule.
        local define_ok, define_output = build("nosim_infer_conflict_define")
        check(define_ok == false and define_output:find("-D CONFLICT_LEVEL", 1, true) ~= nil and
            define_output:find("two different values", 1, true) ~= nil and
            define_output:find("verilator.flags uses `2`", 1, true) ~= nil and
            define_output:find("vcs.flags uses `1`", 1, true) ~= nil,
            "a macro defined differently by two sources must fail the build and name both sources")

        -- The single-valued timescale conflicts the same way.
        local timescale_ok, timescale_output = build("nosim_infer_conflict_timescale")
        check(timescale_ok == false and timescale_output:find("--timescale", 1, true) ~= nil and
            timescale_output:find("verilator.flags uses `1ns/1ns`", 1, true) ~= nil and
            timescale_output:find("vcs.flags uses `1ps/1ps`", 1, true) ~= nil,
            "two different timescales must fail the build and name both sources")

        -- The user's own `nosim.flags` takes part in the same merge, so a conflicting inferred macro
        -- is reported against it.
        local nosim_ok, nosim_output = build("nosim_infer_conflict_nosim")
        check(nosim_ok == false and nosim_output:find("nosim.flags uses `9`", 1, true) ~= nil and
            nosim_output:find("vcs.flags uses `1`", 1, true) ~= nil,
            "a macro conflicting with nosim.flags must fail the build and name nosim.flags as one side")

        -- An unknown simulator name in the switch must fail the build.
        local bad_source_ok, bad_source_output = build("nosim_infer_bad_source")
        check(bad_source_ok == false and
            bad_source_output:find("Invalid `verilua.infer_nosim_flags` value `verilator,typo`", 1, true) ~= nil,
            "an unknown switch value must fail the build and quote the value back")

        -- Naming the sources keeps the other simulators' flags out of the nosim build. The build
        -- succeeds on the vcs flags alone, which `top_vcs_only.sv` only elaborates with.
        local sources_ok = build("nosim_infer_sources")
        check(sources_ok == true, "a target limited to the vcs flags must build")
        local sources_cmdline = cmdline_of("infer_sources")
        local wrong_dirs = found_in(sources_cmdline,
            { incdir("verilator"), incdir("iverilog"), incdir("xcelium") })
        check(#wrong_dirs == 0,
            "an unrequested source's include dir must stay out of the command line, found: " ..
            table.concat(wrong_dirs, " "))
        local wrong_macros = found_in(sources_cmdline,
            { "-D INFER_FROM_VERILATOR_LEVEL", "-D INFER_FROM_IVERILOG_LEVEL", "-D INFER_FROM_XCELIUM_LEVEL" })
        check(#wrong_macros == 0,
            "an unrequested source's macro must stay out of the command line, found: " ..
            table.concat(wrong_macros, " "))

        print(string.format("[infer_nosim_flags] %d/%d checks passed", checks - #failures, checks))
        if #failures > 0 then
            raise("infer_nosim_flags: %d check(s) failed", #failures)
        end
    end)
end)
