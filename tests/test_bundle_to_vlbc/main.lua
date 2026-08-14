local path = require "pl.path"
local file = require "pl.file"
local dir = require "pl.dir"
local BundleToVlbc = require "verilua.utils.BundleToVlbc"

local root = path.join(os.getenv("VL_BUILD_DIR") or ".", "vlbc_mods")
dir.makepath(root)
file.write(path.join(root, "vip_mod.lua"), [[
return { tag = "from-lua" }
]])

fork {
    function()
        local opts = { path = path.join(root, "?.lua") }
        local ok, err_or_out = pcall(function()
            return BundleToVlbc.bundle_to_vlbc("vip_mod", {
                path = opts.path,
                out = path.join(root, "vip_mod.vlbc"),
            })
        end)

        if not ok then
            local msg = tostring(err_or_out)
            assert(
                msg:find("VL_BUNDLE_KEY_HEX", 1, true)
                or msg:find("no compile-time key", 1, true)
                or msg:find("vl_bundle_seal", 1, true),
                "unexpected pack error: " .. msg
            )
            print("[test_bundle_to_vlbc] seal unavailable (no key / no symbol) — asserted")
            sim.finish()
            return
        end

        file.delete(path.join(root, "vip_mod.lua"))
        package.loaded["vip_mod"] = nil
        package.path = path.join(root, "?.lua") .. ";" .. path.join(root, "?.vlbc") .. ";" .. package.path
        local m = require("vip_mod")
        assert(m.tag == "from-lua", "vlbc require mismatch")
        print("[test_bundle_to_vlbc] require(vip_mod) from .vlbc ok")

        local vlbc_path = path.join(root, "vip_mod.vlbc")
        local blob = assert(file.read(vlbc_path))
        local flip = blob:byte(#blob)
        blob = blob:sub(1, -2) .. string.char(bit.bxor(flip, 0xFF))
        assert(file.write(vlbc_path, blob))
        package.loaded["vip_mod"] = nil
        local bad_ok, bad_err = pcall(require, "vip_mod")
        assert(not bad_ok, "corrupted vlbc should fail")
        bad_err = tostring(bad_err)
        assert(
            bad_err:find("key mismatch", 1, true) or bad_err:find("VL_BUNDLE_KEY_HEX", 1, true),
            "expected key-mismatch message, got: " .. bad_err
        )
        print("[test_bundle_to_vlbc] corrupted vlbc reports key mismatch")
        sim.finish()
    end,
}
