--- Pack a module tree into a sealed `.vlbc` and load it with `require`.
---
--- ```
---   axi/agent.lua  --require-->  axi/inner.lua  --require-->  axi/util.lua
---         |                           |                           |
---         +------------- bundle_to_bc (one LuaJIT chunk) ---------+
---                                 |
---                                 |  AES-256-GCM
---                                 v
---                         dist/axi/agent.vlbc     (one file)
---                                 |
---                    require("axi.agent")  [loader]
---                                 |
---                                 v
---                    package.preload[axi.agent]
---                    package.preload[axi.inner]
---                    package.preload[axi.util]
---                                 |
---                                 v
---                    same as require("axi.agent") on the original tree
--- ```
---
--- Only literal `require("x")` / `require 'x'` are followed.
--- `verilua.*` / `pl.*` / stdlib / cpath `.so` stay out (DEFAULT_SKIP).
---
--- ```lua
--- local BundleToVlbc = require "verilua.utils.BundleToVlbc"
--- BundleToVlbc.bundle_to_vlbc("axi.agent", { out = "dist/axi/agent.vlbc" })
--- -- init.lua already called install_loader():
--- local agent = require("axi.agent")
--- ```
---
--- Must run inside Verilua. Seal/unseal use the compile-time
--- `VL_BUNDLE_KEY_HEX` (64 hex = raw AES-256 key; anything else = SHA-256).
--- `.lua` still wins over `.vlbc`. Loader logs via `verilua_warning`.
--- Runtime errors keep lineinfo: `vlbc://axi.agent:42`.

local ffi = require "ffi"
local io = require "io"
local SymbolHelper = require "verilua.utils.SymbolHelper"

local assert = assert
local error = error
local tonumber = tonumber
local type = type

--- Names / roots that stay on the customer machine.
--- `json` / `socket` / `lfs` / `lester` are not listed: a VIP may own those names.
--- Native `.so` is skipped via package.cpath even if missing here.
local DEFAULT_SKIP = {
    -- Lua 5.1 / LuaJIT stdlib (also covers string.buffer, table.new, jit.*)
    bit = true,
    ffi = true,
    jit = true,
    debug = true,
    io = true,
    os = true,
    string = true,
    table = true,
    math = true,
    package = true,
    coroutine = true,
    bit32 = true,
    -- Shipped with Verilua; customer already has them
    inspect = true, -- src/lua/thirdparty_lib/inspect.lua
    verilua = true, -- the framework itself
    pl = true,      -- Penlight (pl.class, pl.path, ...)
}

---@param name string
---@param skip table<string, boolean>
---@return boolean
local function should_skip(name, skip)
    if skip[name] then
        return true
    end
    return skip[name:match("^([^%.]+)")] == true
end

---@param src string
---@return string
local function strip_comments(src)
    src = src:gsub("%-%-%[%[.-%]%]", "")
    src = src:gsub("%-%-[^\n]*", "")
    return src
end

---@param src string
---@return string[]
local function scan_requires(src)
    local names = {}
    local seen = {}
    for name in strip_comments(src):gmatch([[require%s*%(?%s*["']([%w_%.%-]+)["']%s*%)?]]) do
        if not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end
    return names
end

---@class verilua.utils.BundleToVlbc.Opts
---@field skip? table<string, boolean> Extra module names or roots to leave unbundled
---@field path? string Where to find `.lua` sources at pack time (default: `package.path`). Not stored in the `.vlbc`.
---@field out? string Output path (default: `<module/path>.vlbc`)

--- Bundle `entry` and its literal `require()` deps into one loadable LuaJIT bytecode.
---@nodiscard
---@param entry string Module name, e.g. `"axi.agent"`
---@param opts? verilua.utils.BundleToVlbc.Opts
---@return string
local function bundle_to_bc(entry, opts)
    opts = opts or {}
    assert(type(entry) == "string" and entry ~= "", "[bundle_to_vlbc] `entry` must be a non-empty module name")

    local skip = {}
    for k, v in pairs(DEFAULT_SKIP) do
        skip[k] = v
    end
    if opts.skip then
        assert(type(opts.skip) == "table", "[bundle_to_vlbc] `opts.skip` must be a table")
        for k, v in pairs(opts.skip) do
            skip[k] = v
        end
    end

    local search_path = opts.path or package.path
    assert(type(search_path) == "string", "[bundle_to_vlbc] `opts.path` must be a string")

    ---@type table<string, string>
    local srcs = {}
    ---@type table<string, boolean>
    local visiting = {}

    ---@param name string
    local function collect(name)
        if srcs[name] or should_skip(name, skip) or visiting[name] then
            return
        end

        local file, err = package.searchpath(name, search_path)
        if not file then
            local cfile = package.searchpath(name, package.cpath)
            if cfile then
                return
            end
            error(("[bundle_to_vlbc] cannot find %s: %s"):format(name, err))
        end
        if not file:find("%.lua$") then
            return
        end

        local f = assert(io.open(file, "rb"))
        local src = f:read("*a")
        f:close()
        if not src then
            error(("[bundle_to_vlbc] failed to read %s"):format(file))
        end

        visiting[name] = true
        local deps = scan_requires(src)
        for i = 1, #deps do
            collect(deps[i])
        end
        visiting[name] = nil
        srcs[name] = src
    end

    collect(entry)
    if not srcs[entry] then
        error(("[bundle_to_vlbc] entry produced no source: %s"):format(entry))
    end

    local parts = { "local preload = package.preload\nlocal load = load\n" }
    for name, src in pairs(srcs) do
        local chunk, load_err = load(src, "@vlbc://" .. name)
        if not chunk then
            error(("[bundle_to_vlbc] failed to compile %s: %s"):format(name, load_err))
        end
        -- Keep lineinfo so traceback can name the original line.
        local bc = string.dump(chunk, false)
        parts[#parts + 1] = ("preload[%q] = function(...) return assert(load(%q, %q))(...) end\n"):format(
            name,
            bc,
            "@vlbc://" .. name
        )
    end
    parts[#parts + 1] = ("return require(%q)\n"):format(entry)

    local wrapper, wrap_err = load(table.concat(parts), "@vlbc://" .. entry)
    if not wrapper then
        error(("[bundle_to_vlbc] failed to compile bundle wrapper: %s"):format(wrap_err))
    end
    return string.dump(wrapper, true)
end

local SEAL_DECL =
"int vl_bundle_seal(const unsigned char *input, size_t input_len, unsigned char *output, size_t output_cap, size_t *output_len);"
local UNSEAL_DECL =
"int vl_bundle_unseal(const unsigned char *input, size_t input_len, unsigned char *output, size_t output_cap, size_t *output_len);"

local function bind(decl)
    local ok, fn = pcall(function()
        return SymbolHelper.try_ffi_cast(decl)
    end)
    if not ok then
        error(
            "[bundle_to_vlbc] "
            .. decl:match("vl_bundle_%w+")
            .. " unavailable; run inside Verilua with libverilua loaded: "
            .. tostring(fn)
        )
    end
    return fn
end

local function call_crypt(fn, name, blob, extra_cap)
    local cap = #blob + (extra_cap or 64)
    local out = ffi.new("unsigned char[?]", cap)
    local n = ffi.new("size_t[1]")
    local rc = fn(blob, #blob, out, cap, n)
    if rc == -3 then
        cap = assert(tonumber(n[0]))
        out = ffi.new("unsigned char[?]", cap)
        rc = fn(blob, #blob, out, cap, n)
    end
    if rc ~= 0 then
        local why = ({
            [-1] = "no compile-time key (set VL_BUNDLE_KEY_HEX when building libverilua)",
            [-2] = "invalid arguments",
            [-3] = "output buffer too small",
            [-4] = "not a compatible VLBC (bad magic or format version)",
            [-5] = "key mismatch or corrupted blob (this libverilua was built with a different VL_BUNDLE_KEY_HEX)",
        })[rc] or ("failed: " .. tostring(rc))
        error("[" .. name .. "] " .. why)
    end
    return ffi.string(out, tonumber(n[0]))
end

--- Seal a plaintext bytecode blob.
---@param plain string
---@return string
local function seal_bytes(plain)
    assert(type(plain) == "string", "[bundle_to_vlbc] seal_bytes: expected string")
    return call_crypt(bind(SEAL_DECL), "vl_bundle_seal", plain, 64)
end

--- Unseal a VLBC blob.
---@param blob string
---@return string
local function unseal_bytes(blob)
    assert(type(blob) == "string", "[bundle_to_vlbc] unseal_bytes: expected string")
    return call_crypt(bind(UNSEAL_DECL), "vl_bundle_unseal", blob, 0)
end

local function default_out(entry)
    return (entry:gsub("%.", "/")) .. ".vlbc"
end

local function write_file(path, data)
    local dir = path:match("^(.*)/[^/]+$")
    if dir and dir ~= "" then
        assert(os.execute("mkdir -p '" .. dir:gsub("'", "'\"'\"'") .. "'"))
    end
    local f = assert(io.open(path, "wb"), "[bundle_to_vlbc] cannot write " .. path)
    f:write(data)
    f:close()
end

--- Bundle `entry` and write a sealed `.vlbc` file.
---@param entry string
---@param opts? verilua.utils.BundleToVlbc.Opts
---@return string out_path
local function bundle_to_vlbc(entry, opts)
    opts = opts or {}
    local bc = bundle_to_bc(entry, opts)
    local sealed = seal_bytes(bc)
    local out = opts.out or default_out(entry)
    write_file(out, sealed)
    return out
end

local loader_installed = false

--- Install `package.loaders` entry that loads `.vlbc` after `.lua`.
local function install_loader()
    if loader_installed then
        return
    end
    loader_installed = true

    ---@param modname string
    local function vlbc_loader(modname)
        local search = package.path:gsub("%.lua", ".vlbc")
        local file = package.searchpath(modname, search)
        if not file then
            return nil
        end
        local f = io.open(file, "rb")
        if not f then
            return nil
        end
        local blob = f:read("*a")
        f:close()
        if not blob or blob:sub(1, 4) ~= "VLBC" then
            error("[vlbc_loader] not a VLBC file: " .. file)
        end
        verilua_warning("VLBC  require(" .. modname .. ") <= " .. file)
        local ok, plain = pcall(unseal_bytes, blob)
        if not ok then
            error("[vlbc_loader] " .. file .. ": " .. tostring(plain))
        end
        return function()
            return assert(load(plain, "@vlbc://" .. modname))()
        end
    end

    table.insert(package.loaders, 3, vlbc_loader)
end

---@class verilua.utils.BundleToVlbc
---@field bundle_to_bc fun(entry: string, opts?: verilua.utils.BundleToVlbc.Opts): string
---@field bundle_to_vlbc fun(entry: string, opts?: verilua.utils.BundleToVlbc.Opts): string
---@field install_loader fun()
---@field seal_bytes fun(plain: string): string
---@field unseal_bytes fun(blob: string): string
return {
    bundle_to_bc = bundle_to_bc,
    bundle_to_vlbc = bundle_to_vlbc,
    install_loader = install_loader,
    seal_bytes = seal_bytes,
    unseal_bytes = unseal_bytes,
}
