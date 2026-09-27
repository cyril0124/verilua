---@diagnostic disable: undefined-global, undefined-field

local scriptdir = os.scriptdir()

--- Absolute include directory reachable only through one source simulator's flags.
---@param name string
---@return string
local function incdir(name)
    return path.join(scriptdir, "include", name)
end

--- Build a nosim target whose RTL only elaborates when the other simulators' flags were
--- translated into `nosim.flags`.
---@param name string xmake target name
---@param build_dir_name string distinct build directory name under `build/nosim`
---@param infer boolean whether `verilua.infer_nosim_flags` is enabled
local function add_nosim_target(name, build_dir_name, infer)
    target(name, function()
        add_rules("verilua")
        set_default(false)
        add_toolchains("@nosim")

        add_files("./top.sv")
        set_values("verilua.top", "top")
        set_values("verilua.lua_main", "./main.lua")
        set_values("verilua.build_dir_name", build_dir_name)

        if infer then
            set_values("verilua.infer_nosim_flags", "1")
        end

        -- A user-written nosim flag must survive next to the inferred ones.
        set_values("nosim.flags", "--std 1800-2017")

        -- Each source simulator contributes one spelling per whitelisted option kind. The trailing
        -- `-full64` / `-lca` / `--trace` have no nosim equivalent and must be reported as dropped.
        add_values("vcs.flags",
            "+incdir+" .. incdir("vcs_a") .. "+" .. incdir("vcs_b"),
            "+define+INFER_FROM_VCS_LEVEL=1",
            "-timescale=1ps/1ps",
            "-y",
            incdir("vcs_a"),
            "+libext+.v+.sv",
            "-full64",
            "-lca")
        add_values("verilator.flags", "-I" .. incdir("verilator"), "-DINFER_FROM_VERILATOR_LEVEL=1",
            "--timescale 1ns/1ns", "--trace")
        add_values("iverilog.flags", "-I", incdir("iverilog"), "-D", "INFER_FROM_IVERILOG_LEVEL=1")
        add_values("xcelium.flags", "-incdir", incdir("xcelium"), "-define", "INFER_FROM_XCELIUM_LEVEL=1")

        -- testbench_gen only receives the inferred include dirs, so its parse needs the probe macros
        -- passed explicitly (`-DNAME=1` joined form: repeated `-D` values are deduplicated by
        -- `add_values`). nosim must still get them from the inferred flags.
        add_values("verilua.tb_gen_flags",
            "-DINFER_FROM_VCS_LEVEL=1",
            "-DINFER_FROM_VERILATOR_LEVEL=1",
            "-DINFER_FROM_IVERILOG_LEVEL=1",
            "-DINFER_FROM_XCELIUM_LEVEL=1")
    end)
end

add_nosim_target("nosim_infer_on", "infer_on", true)
add_nosim_target("nosim_infer_off", "infer_off", false)

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

        --- Build a target and capture its output.
        ---@param name string
        ---@return boolean ok
        ---@return string output Build output, or the build error when the build failed
        local function build(name)
            local output = ""
            local ok = try {
                function()
                    output = os.iorunv("xmake", { "build", "-P", scriptdir, name })
                    return true
                end,
                catch {
                    function(errors)
                        output = tostring(errors)
                    end
                }
            }
            return ok == true, output
        end

        -- Without the switch the nosim build must fail: the includes are only reachable through the
        -- other simulators' flags. Nothing may be reported as dropped either.
        os.tryrm(build_root)
        local off_ok, off_output = build("nosim_infer_off")
        check(off_ok == false,
            "nosim_infer_off must fail to build while verilua.infer_nosim_flags is unset")
        check(off_output:find("no nosim equivalent", 1, true) == nil,
            "no drop report may be printed while verilua.infer_nosim_flags is unset")

        -- With the switch on, slang resolves the includes and the probe headers' macro references
        -- stay silent, which only holds if both the `-I` and the `-D` arrived.
        local on_ok, on_output = build("nosim_infer_on")
        check(on_ok == true, "nosim_infer_on must build with verilua.infer_nosim_flags enabled")

        local cmdline_file = path.join(build_root, "infer_on", "nosim_cmdline_args.lua")
        check(os.isfile(cmdline_file), "nosim_infer_on must write nosim_cmdline_args.lua")
        local cmdline = os.isfile(cmdline_file) and io.readfile(cmdline_file) or ""

        for _, dir in ipairs({
            incdir("vcs_a"), incdir("vcs_b"), incdir("verilator"), incdir("iverilog"), incdir("xcelium")
        }) do
            check(cmdline:find("-I " .. dir, 1, true) ~= nil, "nosim command line must contain -I " .. dir)
        end
        for _, macro in ipairs({
            "INFER_FROM_VCS_LEVEL=1", "INFER_FROM_VERILATOR_LEVEL=1", "INFER_FROM_IVERILOG_LEVEL=1",
            "INFER_FROM_XCELIUM_LEVEL=1"
        }) do
            check(cmdline:find("-D " .. macro, 1, true) ~= nil, "nosim command line must contain -D " .. macro)
        end
        check(cmdline:find("--timescale 1ps/1ps", 1, true) ~= nil,
            "nosim command line must contain --timescale 1ps/1ps")

        -- `-y` / `+libext+` are translated, and a `+`-separated libext list is expanded.
        check(cmdline:find("-y " .. incdir("vcs_a"), 1, true) ~= nil,
            "nosim command line must contain -y " .. incdir("vcs_a"))
        for _, ext in ipairs({ ".v", ".sv" }) do
            check(cmdline:find("+libext+" .. ext, 1, true) ~= nil,
                "nosim command line must contain +libext+" .. ext)
        end

        -- The vcs timescale is scanned after the verilator one, so it must win.
        check(cmdline:find("1ns/1ns", 1, true) == nil,
            "nosim command line must not keep the overridden verilator timescale")

        -- A user-written nosim flag is kept next to the inferred ones.
        check(cmdline:find("--std 1800-2017", 1, true) ~= nil,
            "nosim command line must keep the user's own nosim.flags entry")

        -- Flags with no nosim equivalent are reported per source and must not reach the command line.
        for _, expected in ipairs({
            "flags in vcs.flags have no nosim equivalent and were dropped: -full64 -lca",
            "flags in verilator.flags have no nosim equivalent and were dropped: --trace"
        }) do
            check(on_output:find(expected, 1, true) ~= nil, "build output must contain: " .. expected)
        end
        for _, dropped_flag in ipairs({ "-full64", "-lca", "--trace" }) do
            check(cmdline:find(dropped_flag, 1, true) == nil,
                "dropped flag must not reach the nosim command line: " .. dropped_flag)
        end

        print(string.format("[infer_nosim_flags] %d/%d checks passed", checks - #failures, checks))
        if #failures > 0 then
            raise("infer_nosim_flags: %d check(s) failed", #failures)
        end
    end)
end)
