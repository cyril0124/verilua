---@diagnostic disable: undefined-global, undefined-field

local prj_dir = os.projectdir()
local shared_dir = path.join(prj_dir, "shared")

target("bigint_ffi", function()
    set_kind("phony")
    set_default(false)
    on_build(function()
        os.cd(path.join(prj_dir, "src", "bigint_ffi"))
        os.exec("cargo build --release -p bigint_ffi")
    end)

    after_build(function()
        -- Ensure the shared dir exists (fresh checkouts/worktrees do not have it)
        os.mkdir(shared_dir)
        os.cp(path.join(prj_dir, "target", "release", "libbigint_ffi.so"), shared_dir)
    end)
end)
