---@diagnostic disable: undefined-global, undefined-field

local prj_dir = os.projectdir()
local shared_dir = path.join(prj_dir, "shared")

target("turso_ffi", function()
    set_kind("phony")
    set_default(false)
    on_build(function()
        os.cd(path.join(prj_dir, "src", "turso_ffi"))
        os.exec("cargo build --release -p turso_ffi")
    end)

    after_build(function()
        os.cp(path.join(prj_dir, "target", "release", "libturso_ffi.so"), shared_dir)
    end)
end)
