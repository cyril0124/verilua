---@diagnostic disable: undefined-global, undefined-field

local prj_dir = os.projectdir()
local curr_dir = os.scriptdir()
local build_dir = path.join(prj_dir, "build")
local shared_dir = path.join(prj_dir, "shared")
local libs_dir = path.join(prj_dir, "conan_installed")
local lua_dir = path.join(prj_dir, "luajit-pro", "luajit2.1")

local common_features = "acc_time"
-- local common_features = "debug acc_time"

local verilator_features = "chunk_task verilator_inner_step_callback " .. common_features
local vcs_features = "chunk_task merge_cb " .. common_features
local xcelium_features = vcs_features .. " promote_luajit_global"
local iverilog_features = "chunk_task merge_cb " .. common_features
local wave_vpi_features = "chunk_task " .. common_features
local nosim_features = "chunk_task " .. common_features

local build_iverilog_vpi_module_cmd = format(
    [[cargo build --release --features "iverilog iverilog_vpi_mod %s"]],
    iverilog_features
)

local function setup_cargo_env(os)
    -- Setup environment variables for cargo build
    os.setenv("LUA_LIB", path.join(lua_dir, "lib"))
    os.setenv("LUA_LIB_NAME", "luajit-5.1")
    os.setenv("LUA_LINK", "shared")
end

local function build_lib_common(simulator)
    set_kind("phony")
    on_build(function(target)
        setup_cargo_env(os)

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
        elseif simulator == "verilator_i" then
            os.vrun([[cargo build --release --features "verilator %s"]], verilator_features .. " inertial_put")
        elseif simulator == "verilator_dpi" then
            os.setenv("RUSTFLAGS", "-Clink-arg=-Wl,--wrap=" .. table.concat(vpi_funcs, ",--wrap="))
            os.vrun([[cargo build --release --features "verilator dpi %s"]], verilator_features)
            os.setenv("RUSTFLAGS", "")
        elseif simulator == "vcs" then
            os.vrun([[cargo build --release --features "vcs %s"]], vcs_features)
        elseif simulator == "xcelium" then
            os.vrun([[cargo build --release --features "vcs %s"]], xcelium_features)
        elseif simulator == "vcs_dpi" then
            os.setenv("RUSTFLAGS", "-Clink-arg=-Wl,--wrap=" .. table.concat(vpi_funcs, ",--wrap="))
            os.vrun([[cargo build --release --features "vcs dpi %s"]], vcs_features)
            os.setenv("RUSTFLAGS", "")
        elseif simulator == "xcelium_dpi" then
            os.setenv("RUSTFLAGS", "-Clink-arg=-Wl,--wrap=" .. table.concat(vpi_funcs, ",--wrap="))
            os.vrun([[cargo build --release --features "vcs dpi %s"]], xcelium_features)
            os.setenv("RUSTFLAGS", "")
        elseif simulator == "wave_vpi" then
            os.vrun([[cargo build --release --features "wave_vpi %s"]], wave_vpi_features)
        elseif simulator == "iverilog" then
            os.vrun(build_iverilog_vpi_module_cmd)
        elseif simulator == "nosim" then
            os.vrun([[cargo build --release --features "nosim %s"]], nosim_features)
        else
            raise("Unknown simulator => " .. simulator)
        end

        if not os.isdir(shared_dir) then
            os.mkdir(shared_dir)
        end

        os.cp(
            path.join(prj_dir, "target", "release", "libverilua.so"),
            path.join(shared_dir, "libverilua_" .. simulator .. ".so")
        )
    end)
end

local all_libverilua_targets = {}
for _, simulator in ipairs({
    "verilator",
    "verilator_i", -- `verilator` with `inertial_put` feature
    "verilator_dpi",
    "vcs",
    "vcs_dpi",
    "xcelium",
    "xcelium_dpi",
    "iverilog",
    "wave_vpi",
    "nosim"
}) do
    -- libverilua_verilator
    -- libverilua_verilator_i
    -- libverilua_verilator_dpi
    -- libverilua_vcs
    -- libverilua_vcs_dpi
    -- libverilua_xcelium
    -- libverilua_xcelium_dpi
    -- libverilua_iverilog
    -- libverilua_wave_vpi
    -- libverilua_nosim
    local target_name = "libverilua_" .. simulator
    all_libverilua_targets[#all_libverilua_targets + 1] = target_name
    target(target_name, function()
        build_lib_common(simulator)
    end)
end

-- Build all libverilua libraries
target("build_libverilua", function()
    set_kind("phony")
    on_run(function(target)
        import("lib.detect.find_file")

        print("--------------------- [Build libverilua] ---------------------- ")
        try { function() os.vrun("cargo clean") end }

        for _, target_name in ipairs(all_libverilua_targets) do
            if not target_name:find("iverilog") then
                cprint("* Build ${green}%s${reset}", target_name)
                os.vrun("xmake build " .. target_name)
            end
        end

        if find_file("iverilog", { "$(env PATH)" }) then
            setup_cargo_env(os)

            cprint("* Build ${green}libverilua_iverilog${reset}")
            os.vrun("xmake build libverilua_iverilog")

            cprint("* Build ${green}iverilog_vpi_module${reset}")
            os.vrun("xmake build iverilog_vpi_module")
        end

        print("---------------------------------------------------------- ")
    end)
end)

target("iverilog_vpi_module", function()
    set_kind("phony")
    on_build(function(target)
        setup_cargo_env(os)

        try { function() os.vrun("cargo clean") end }
        os.vrun(build_iverilog_vpi_module_cmd)

        os.cp(path.join(prj_dir, "target", "release", "libverilua.so"), path.join(shared_dir, "libverilua_iverilog.vpi"))
    end)
end)

target("build_libverilua_no_opt", function()
    set_kind("phony")
    on_run(function()
        setup_cargo_env(os)
        try { function() os.vrun("cargo clean") end }

        os.mkdir(path.join(shared_dir, "no_opt"))

        print("[build libverilua_no_opt] build libverilua_verilator.so...")
        os.vrun([[cargo build --release --features "verilator verilator_inner_step_callback %s"]], common_features)
        os.cp(path.join(prj_dir, "target", "release", "libverilua.so"), path.join(shared_dir, "no_opt", "libverilua_verilator.so"))

        print("[build libverilua_no_opt] build libverilua_vcs.so...")
        os.vrun([[cargo build --release --features "vcs %s"]], common_features)
        os.cp(path.join(prj_dir, "target", "release", "libverilua.so"), path.join(shared_dir, "no_opt", "libverilua_vcs.so"))

        local build_iverilog_vpi_module_cmd = format(
            [[cargo build --release --features "iverilog iverilog_vpi_mod %s"]],
           common_features
        )
        print("[build libverilua_no_opt] build libverilua_iverilog.so...")
        os.vrun(build_iverilog_vpi_module_cmd)
        os.cp(path.join(prj_dir, "target", "release", "libverilua.so"), path.join(shared_dir, "no_opt", "libverilua_iverilog.so"))
        os.cp(path.join(prj_dir, "target", "release", "libverilua.so"), path.join(shared_dir, "no_opt", "libverilua_iverilog.vpi"))
    end)
end)
