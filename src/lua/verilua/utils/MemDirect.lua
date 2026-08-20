---@diagnostic disable: unnecessary-assert, unresolved-require

local ffi = require "ffi"

local cfg = _G.cfg
local f = string.format

-- Everything lives in the standalone `libmem_direct.so` built by
-- mem_direct_gen: the entry table and the self-locating base pointer
-- (resolved through Verilator's public scope registry at runtime).
ffi.cdef [[
    int mem_direct_prepare(void *base_ptr);
    int mem_direct_count();
    const char *mem_direct_entry_name(int i);
    uint64_t mem_direct_entry_offset(int i);
    uint32_t mem_direct_entry_mem_bytes(int i);
    uint32_t mem_direct_entry_rtl_width(int i);
    uint64_t mem_direct_entry_array_size(int i);
    uint64_t mem_direct_base();
]]

---@class (exact) verilua.utils.MemDirect.entry
---@field name string
---@field offset integer
---@field mem_bytes integer
---@field rtl_width integer
---@field array_size integer

---@class (exact) verilua.utils.MemDirect
---@field private initialized boolean
---@field base ffi.cdata* Design-state base pointer after init (rootp)
---@field private map table<string, verilua.utils.MemDirect.entry>
---@field init fun(self: verilua.utils.MemDirect): verilua.utils.MemDirect
---@field try_init fun(self: verilua.utils.MemDirect): boolean
---@field lookup fun(self: verilua.utils.MemDirect, hierpath: string): verilua.utils.MemDirect.entry?
---@field ptr fun(self: verilua.utils.MemDirect, hierpath: string, index?: integer): ffi.cdata*|nil
---@field GetSignalNames fun(self: verilua.utils.MemDirect, pattern?: string): string[]
local MemDirect = {
    initialized = false,
    ---@diagnostic disable-next-line: assign-type-mismatch
    base = nil,
    map = {},
}

function MemDirect:init()
    if self.initialized then
        return self
    end

    assert(
        cfg.simulator == "verilator",
        "[MemDirect] only supported under Verilator (cfg.simulator="
        .. tostring(cfg.simulator)
        .. ")"
    )

    local so_path = os.getenv("VL_MEM_DIRECT_SO")
    assert(
        so_path and so_path ~= "",
        "[MemDirect] VL_MEM_DIRECT_SO is not set; build with verilua.verilator_mem_direct=1 "
        .. "(xmake sets it automatically) or export it to the path of libmem_direct.so"
    )
    local fp = io.open(so_path, "r")
    assert(fp, f("[MemDirect] VL_MEM_DIRECT_SO points to a missing file: %s", so_path))
    ---@cast fp -nil
    fp:close()

    -- Loud failure on a broken/incompatible library is intended.
    local lib = ffi.load(so_path)

    ---@diagnostic disable: need-check-nil, call-non-callable
    -- Self-locating base: the .so walks Verilator's public scope registry
    -- (resolved against the simulator binary at dlopen).
    local base_u64 = lib.mem_direct_base()
    assert(
        base_u64 ~= 0,
        "[MemDirect] mem_direct_base() returned 0; the model is not constructed yet "
        .. "or no DPI/VPI scope is registered (at least one public/DPI signal is required)"
    )

    local n = lib.mem_direct_prepare(ffi.cast("void *", base_u64))
    assert(n and n > 0, "[MemDirect] mem_direct_prepare failed")

    self.base = ffi.cast("uint8_t *", base_u64)
    self.map = {}
    local count = lib.mem_direct_count()
    for i = 0, count - 1 do
        local name = ffi.string(lib.mem_direct_entry_name(i))
        ---@type verilua.utils.MemDirect.entry
        local entry = {
            name = name,
            offset = tonumber(lib.mem_direct_entry_offset(i)) --[[@as integer]],
            mem_bytes = tonumber(lib.mem_direct_entry_mem_bytes(i)) --[[@as integer]],
            rtl_width = tonumber(lib.mem_direct_entry_rtl_width(i)) --[[@as integer]],
            array_size = tonumber(lib.mem_direct_entry_array_size(i)) --[[@as integer]],
        }
        self.map[name] = entry
    end
    ---@diagnostic enable: need-check-nil, call-non-callable

    self.initialized = true
    cfg.enable_mem_direct = true
    return self
end

function MemDirect:try_init()
    if self.initialized then
        return true
    end
    if cfg.simulator ~= "verilator" then
        return false
    end
    local so_path = os.getenv("VL_MEM_DIRECT_SO")
    if not so_path or so_path == "" then
        return false
    end
    -- Env var set means the feature is requested; any failure past this
    -- point (missing file, stale .so, missing main-side symbols) is loud.
    self:init()
    return true
end

function MemDirect:lookup(hierpath)
    assert(self.initialized, "[MemDirect] not initialized")
    local entry = self.map[hierpath]
    if entry == nil and hierpath:sub(1, 4) == "TOP." then
        -- Verilator VPI exposes the design under an extra "TOP." root scope
        -- (e.g. cfg.top = "TOP.tb_top"); header-derived names have no such prefix.
        entry = self.map[hierpath:sub(5)]
    end
    return entry
end

function MemDirect:ptr(hierpath, index)
    local entry = self:lookup(hierpath)
    if not entry then
        return nil
    end
    local off = entry.offset
    if index then
        assert(entry.array_size > 0, f("[MemDirect] %s is not an array", hierpath))
        assert(index >= 0 and index < entry.array_size, f("[MemDirect] index %d out of range for %s", index, hierpath))
        off = off + index * entry.mem_bytes
    end
    return ffi.cast("uint8_t *", self.base + off)
end

function MemDirect:GetSignalNames(pattern)
    assert(self.initialized, "[MemDirect] not initialized")
    local ret = {}
    for name, _ in pairs(self.map) do
        if not pattern or name:find(pattern, 1, true) then
            ret[#ret + 1] = name
        end
    end
    table.sort(ret)
    return ret
end

return MemDirect
