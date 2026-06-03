local ffi = require "ffi"
local stringx = require "pl.stringx"
local template = require "verilua.sv.SVTemplate"

local type = type
local pairs = pairs
local assert = assert
local f = string.format
local tostring = tostring
local setmetatable = setmetatable

--- Handle returned by `add "property"`, used to reference a property via `$(prop:name)`.
---@class verilua.sv.SVBuilder.property
---@field __type "Property" Discriminator tag.
---@field name string The property identifier as declared in SV.

--- Handle returned by `add "sequence"`, used to reference a sequence via `$(seq:name)`.
---@class verilua.sv.SVBuilder.sequence
---@field __type "Sequence" Discriminator tag.
---@field name string The sequence identifier as declared in SV.

--- Parameters accepted by the curried `add(typ)(params)` call.
---@class verilua.sv.SVBuilder.add.params
---@field name string Unique statement name (becomes the SV identifier).
---@field expr string SV expression body; supports `$(var)` template substitution.
---@field cov_type? "sequence" | "property" For `add "cover"` only: wrap as sequence or property (default: "property").
---@field sample_event? string For `add "covergroup"` only: per-covergroup sampling event override (e.g. "posedge alt_clk").
---@field envs? table<string, any> Per-call template variables; merged on top of global_envs.

--- Incremental builder for SystemVerilog SVA assertions and covergroups.
--- Accumulates declarations via `add`, then emits the full SV text via `generate()`.
---@class (exact) verilua.sv.SVBuilder
---@field private default_clocking_expr string Rendered `default clocking @(...); endclocking` statement.
---@field private default_clocking_event string The event expression (e.g. "posedge top.dut.clk") for covergroup reuse.
---@field private unique_stmt_name_map table<string, boolean> Guards uniqueness of all statement names.
---@field private global_envs table<string, any> Global template variables available to all `add` calls.
---@field private seq_envs table<string, verilua.sv.SVBuilder.sequence> Registry of defined sequences (accessed via `$(seq:name)`).
---@field private prop_envs table<string, verilua.sv.SVBuilder.property> Registry of defined properties (accessed via `$(prop:name)`).
---@field private sequence_vec string[] Ordered list of rendered sequence statements.
---@field private property_vec string[] Ordered list of rendered property statements.
---@field private content_vec string[] Ordered list of rendered cover/assert statements.
---@field private covergroup_vec string[] Ordered list of rendered covergroup definitions + instantiations.
---@field private _covergroup_names {name: string, inst_name: string}[] Metadata for final-block coverage report generation.
---@field private coverage_report_enabled boolean Whether the final block coverage report is generated.
---@field private lint_enabled boolean Whether automatic sv_lint checking is active on each `add` call.
---@field with_global_envs fun(self: verilua.sv.SVBuilder, envs: table<string, any>): verilua.sv.SVBuilder Register global template variables for all subsequent `add` calls.
---@field add fun(self: verilua.sv.SVBuilder, typ: "cover" | "assert" | "property" | "sequence" | "covergroup"): fun(params: verilua.sv.SVBuilder.add.params): verilua.sv.SVBuilder.property | verilua.sv.SVBuilder.sequence | nil Curried entry point: select type, then pass params.
---@field default_clocking fun(self: verilua.sv.SVBuilder, signal: verilua.handles.CallableHDL|verilua.handles.ProxyTableHandle, edge_type: "posedge" | "negedge", overwrite: boolean?): verilua.sv.SVBuilder Set the default sampling clock for SVA and covergroups.
---@field clean fun(self: verilua.sv.SVBuilder): verilua.sv.SVBuilder Reset all internal state to empty.
---@field set_lint fun(self: verilua.sv.SVBuilder, enable: boolean): verilua.sv.SVBuilder Enable or disable automatic sv_lint checking on each `add` call.
---@field set_coverage_report fun(self: verilua.sv.SVBuilder, enable: boolean): verilua.sv.SVBuilder Enable or disable the `final` block coverage report for covergroups.
---@field generate fun(self: verilua.sv.SVBuilder): string Return the full generated SV text. Equivalent to `tostring(ctx)`.
local SVBuilder = {
    default_clocking_expr = "",
    default_clocking_event = "",
    unique_stmt_name_map = {},
    global_envs = {},
    seq_envs = {},
    prop_envs = {},
    sequence_vec = {},
    property_vec = {},
    content_vec = {},
    covergroup_vec = {},
    _covergroup_names = {},
    lint_enabled = true,
    coverage_report_enabled = true,
}

setmetatable(SVBuilder, {
    __tostring = function(self)
        local parts = {}

        if self.default_clocking_expr ~= "" then
            parts[#parts + 1] = self.default_clocking_expr
        end

        for _, v in ipairs(self.sequence_vec) do
            parts[#parts + 1] = tostring(v)
        end

        for _, v in ipairs(self.property_vec) do
            parts[#parts + 1] = tostring(v)
        end

        local content_count = #self.content_vec
        for i, v in ipairs(self.content_vec) do
            parts[#parts + 1] = f("// %d/%d\n%s", i, content_count, tostring(v))
        end

        for _, v in ipairs(self.covergroup_vec) do
            parts[#parts + 1] = tostring(v)
        end

        -- Generate final block for coverage report
        if self.coverage_report_enabled and #self._covergroup_names > 0 then
            local final_lines = { "final begin" }
            for _, entry in ipairs(self._covergroup_names) do
                final_lines[#final_lines + 1] = f(
                    '    $display("[COVERAGE] %s: %%.2f%%%%", %s.get_inst_coverage());',
                    entry.name, entry.inst_name
                )
            end
            final_lines[#final_lines + 1] = "end"
            parts[#parts + 1] = table.concat(final_lines, "\n")
        end

        if #parts == 0 then
            return ""
        end
        return table.concat(parts, "\n\n") .. "\n\n"
    end
})

local function process_content(content)
    -- Squash multiple spaces and newlines
    return stringx.replace(content, "\n", ""):gsub("%s+", " ")
end

-- Escape Lua pattern magic characters so a literal string can be matched in gsub.
---@param s string
---@return string
local function pat_escape(s)
    return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

-- Rewrite colon-style namespace references into Lua field access so the template
-- engine can evaluate them as plain expressions:
--   $(seq:handshake)  ->  $(seq.handshake)
--   $(prop:no_ovf)    ->  $(prop.no_ovf)
-- Only refs anchored at `<inline_escape><open_bracket>` are rewritten, so bare
-- `seq:foo` text and unrelated method calls like `$(obj:method())` are left
-- untouched (`obj` is neither `seq` nor `prop`).
---@param expr string
---@param inline_escape string
---@param open_bracket string
---@return string
local function rewrite_ns_refs(expr, inline_escape, open_bracket)
    local anchor = pat_escape(inline_escape) .. pat_escape(open_bracket)
    expr = expr:gsub("(" .. anchor .. "%s*)seq:", "%1seq.")
    expr = expr:gsub("(" .. anchor .. "%s*)prop:", "%1prop.")
    return expr
end

-- sv_lint integration: prefer FFI (.so), fall back to subprocess if the
-- shared library is not available.

pcall(ffi.cdef, [[
    int sv_lint_text(const char* sv_text, char* out_diag, int out_diag_size);
]])

local sv_lint_lib ---@type any?
local sv_lint_lib_loaded = false

-- Try to load the shared library once. Returns the FFI lib or nil.
local function get_sv_lint_lib()
    if sv_lint_lib_loaded then
        return sv_lint_lib
    end
    sv_lint_lib_loaded = true

    -- Try $VERILUA_HOME/shared/libsv_lint.so first, then system LD_LIBRARY_PATH.
    local candidates = {}
    local verilua_home = os.getenv("VERILUA_HOME")
    if verilua_home then
        candidates[#candidates + 1] = verilua_home .. "/shared/libsv_lint.so"
    end
    for _, path in ipairs(candidates) do
        local ok, lib = pcall(ffi.load, path)
        if ok then
            sv_lint_lib = lib
            return lib
        end
    end
    -- Try system path (LD_LIBRARY_PATH)
    local ok, lib = pcall(ffi.load, "sv_lint")
    if ok then
        sv_lint_lib = lib
        return lib
    end
    return nil
end

-- Locate the sv_lint binary (subprocess fallback). Cached after first lookup.
local sv_lint_bin_cache ---@type string?
local sv_lint_bin_searched = false

local function find_sv_lint_bin()
    if sv_lint_bin_searched then
        return sv_lint_bin_cache
    end
    sv_lint_bin_searched = true

    -- Try $VERILUA_HOME/tools/sv_lint first, then PATH.
    local verilua_home = os.getenv("VERILUA_HOME")
    if verilua_home then
        local path = verilua_home .. "/tools/sv_lint"
        local fh = io.open(path, "r")
        if fh then
            fh:close()
            sv_lint_bin_cache = path
            return path
        end
    end
    -- Fall back to PATH
    local handle = io.popen("command -v sv_lint 2>/dev/null")
    if handle then
        local result = handle:read("*l")
        handle:close()
        if result and #result > 0 then
            sv_lint_bin_cache = result
            return result
        end
    end
    return nil
end

local diag_buf = ffi.new("char[4096]")

-- Build a module shell containing all existing context + the new statement,
-- then invoke sv_lint (FFI or subprocess). Returns nil on success, or the
-- first diagnostic string on failure.
local function run_sv_lint(self, new_statement, _stmt_name)
    -- Assemble the full SV text for lint
    local parts = { "module __sva_lint;" }
    if self.default_clocking_expr ~= "" then
        parts[#parts + 1] = self.default_clocking_expr
    end
    for _, v in ipairs(self.sequence_vec) do
        parts[#parts + 1] = tostring(v)
    end
    for _, v in ipairs(self.property_vec) do
        parts[#parts + 1] = tostring(v)
    end
    parts[#parts + 1] = new_statement
    parts[#parts + 1] = "endmodule"
    local sv_text = table.concat(parts, "\n")

    -- Try FFI first
    local lib = get_sv_lint_lib()
    if lib then
        local call_ok, rc = pcall(lib.sv_lint_text, sv_text, diag_buf, 4096)
        if call_ok then
            if rc == 0 then
                return nil
            end
            return ffi.string(diag_buf)
        end
        -- FFI call failed (e.g. lazy-binding glibc mismatch): disable FFI,
        -- fall through to subprocess.
        sv_lint_lib = nil
        sv_lint_lib_loaded = true
    end

    -- Subprocess fallback
    local bin = find_sv_lint_bin()
    if not bin then
        return nil -- sv_lint not available, skip silently
    end

    local escaped = sv_text:gsub("'", "'\\''")
    local cmd = f("%s --text '%s' 2>&1", bin, escaped)
    local handle = io.popen(cmd)
    if not handle then
        return nil
    end
    local output = handle:read("*a")
    local _, _, exit_code = handle:close()

    if exit_code ~= 0 and output and #output > 0 then
        -- Trim trailing whitespace
        return output:gsub("%s+$", "")
    end
    return nil
end

--- Enable or disable automatic sv_lint checking on each add() call.
---@param enable boolean
---@return verilua.sv.SVBuilder
function SVBuilder:set_lint(enable)
    self.lint_enabled = enable
    return self
end

--- Enable or disable the final-block coverage report for covergroups.
---@param enable boolean
---@return verilua.sv.SVBuilder
function SVBuilder:set_coverage_report(enable)
    self.coverage_report_enabled = enable
    return self
end

function SVBuilder:generate()
    return tostring(self)
end

function SVBuilder:add(typ)
    ---@param params verilua.sv.SVBuilder.add.params
    return function(params)
        assert(type(params) == "table", "[SVBuilder] add error: `params` should be a table")
        assert(type(params.name) == "string", "[SVBuilder] add error: `params.name` should be a string")
        assert(type(params.expr) == "string", "[SVBuilder] add error: `params.expr` should be a string")

        -- sample_event is only valid for covergroup
        if params.sample_event ~= nil then
            assert(
                typ == "covergroup",
                "[SVBuilder] add error: `sample_event` is only valid for `covergroup`, not `" .. typ .. "`"
            )
        end

        -- Merge envs: params.envs overrides global_envs
        local final_envs = {}
        for k, v in pairs(self.global_envs) do
            final_envs[k] = v
        end
        if params.envs then
            assert(type(params.envs) == "table", "[SVBuilder] add error: `params.envs` should be a table")
            for k, v in pairs(params.envs) do
                final_envs[k] = v
            end
        end

        -- Check for reserved namespace keys
        assert(
            rawget(final_envs, "seq") == nil,
            "[SVBuilder] add error: `envs` contains reserved key `seq`; this name is used for the sequence namespace"
        )
        assert(
            rawget(final_envs, "prop") == nil,
            "[SVBuilder] add error: `envs` contains reserved key `prop`; this name is used for the property namespace"
        )

        -- Reserve the flat names of registered sequences/properties with a
        -- sentinel value, so a bare `$(name)` fails with a helpful "use the
        -- seq:/prop: prefix" hint instead of a generic nil error. A real env
        -- of the same name still wins (guarded by the rawget check).
        for name in pairs(self.seq_envs) do
            if rawget(final_envs, name) == nil then
                ---@diagnostic disable-next-line: assign-type-mismatch
                final_envs[name] = {
                    __render_error = f(
                        "[SVBuilder] cannot reference sequence `%s` as a flat `$(%s)`; use the `seq:` prefix, e.g. `$(seq:%s)`",
                        name, name, name
                    ),
                }
            end
        end
        for name in pairs(self.prop_envs) do
            if rawget(final_envs, name) == nil then
                ---@diagnostic disable-next-line: assign-type-mismatch
                final_envs[name] = {
                    __render_error = f(
                        "[SVBuilder] cannot reference property `%s` as a flat `$(%s)`; use the `prop:` prefix, e.g. `$(prop:%s)`",
                        name, name, name
                    ),
                }
            end
        end

        -- Inject namespaced views so `$(seq:name)` / `$(prop:name)` resolve.
        -- Injected last so they always shadow same-named plain envs / sentinels.
        final_envs.seq = self.seq_envs
        final_envs.prop = self.prop_envs

        for _, v in pairs(final_envs) do
            if type(v) == "table" and rawget(v, "__type") then
                if rawget(v, "__type") == "Sequence" then
                    ---@cast v verilua.sv.SVBuilder.sequence
                    assert(
                        self.unique_stmt_name_map[v.name],
                        "[SVBuilder] add error: `params.envs` contains a `Sequence` that is not in the current context"
                    )
                elseif rawget(v, "__type") == "Property" then
                    ---@cast v verilua.sv.SVBuilder.property
                    assert(
                        self.unique_stmt_name_map[v.name],
                        "[SVBuilder] add error: `params.envs` contains a `Property` that is not in the current context"
                    )
                end
            end
        end

        assert(
            not self.unique_stmt_name_map[params.name],
            f("[SVBuilder] `params.name`(%s) is not unique", params.name)
        )

        -- Rewrite colon-style namespace refs before handing expr to the engine.
        -- Honor custom escape/bracket passed through envs (default `$` and `()`).
        local inline_escape = rawget(final_envs, "_inline_escape") or "$"
        local brackets = rawget(final_envs, "_brackets") or "()"
        local open_bracket = brackets:sub(1, 1)
        local expr = rewrite_ns_refs(params.expr, inline_escape, open_bracket)

        local ret, err = template.substitute(expr, final_envs)
        if err then
            assert(false, err)
        end

        if typ == "cover" then
            local cov_type = "property"
            if params.cov_type then
                assert(
                    params.cov_type == "sequence" or params.cov_type == "property",
                    "[SVBuilder] cover error: `cov_type` should be `sequence` or `property`"
                )
                cov_type = assert(params.cov_type)
            end

            local pre_content_name = f("_GEN_%s_%s", params.name, cov_type:upper())
            local pre_content_raw = f("%s %s(); %s; end%s", cov_type, pre_content_name, ret, cov_type)

            if self.lint_enabled then
                local lint_err = run_sv_lint(self, pre_content_raw, params.name)
                if lint_err then
                    assert(false, f("[SVBuilder] lint error in '%s': %s", params.name, lint_err))
                end
            end

            local pre_content = process_content(pre_content_raw)
            local content = pre_content .. "\n" .. f("%s: cover %s (%s);", params.name, cov_type, pre_content_name)

            self.content_vec[#self.content_vec + 1] = content
            self.unique_stmt_name_map[params.name] = true
            self.unique_stmt_name_map[pre_content_name] = true
            return
        elseif typ == "assert" then
            local pre_content_name = f("_GEN_%s_PROPERTY", params.name)
            local pre_content_raw = f("property %s(); %s; endproperty", pre_content_name, ret)

            if self.lint_enabled then
                local lint_err = run_sv_lint(self, pre_content_raw, params.name)
                if lint_err then
                    assert(false, f("[SVBuilder] lint error in '%s': %s", params.name, lint_err))
                end
            end

            local pre_content = process_content(pre_content_raw)
            local content = pre_content .. "\n" .. f("%s: assert property (%s);", params.name, pre_content_name)

            self.content_vec[#self.content_vec + 1] = content
            self.unique_stmt_name_map[params.name] = true
            self.unique_stmt_name_map[pre_content_name] = true
            return
        elseif typ == "property" then
            local content_raw = f("property %s(); %s; endproperty", params.name, ret)

            if self.lint_enabled then
                local lint_err = run_sv_lint(self, content_raw, params.name)
                if lint_err then
                    assert(false, f("[SVBuilder] lint error in '%s': %s", params.name, lint_err))
                end
            end

            local processed = process_content(content_raw)
            self.property_vec[#self.property_vec + 1] = processed
            self.unique_stmt_name_map[params.name] = true

            ---@type verilua.sv.SVBuilder.property
            local property = {
                __type = "Property",
                name = params.name,
            }
            -- Properties are reachable only via `$(prop:name)`, never flat.
            self.prop_envs[params.name] = property
            return property
        elseif typ == "sequence" then
            local content_raw = f("sequence %s(); %s; endsequence", params.name, ret)

            if self.lint_enabled then
                local lint_err = run_sv_lint(self, content_raw, params.name)
                if lint_err then
                    assert(false, f("[SVBuilder] lint error in '%s': %s", params.name, lint_err))
                end
            end

            local processed = process_content(content_raw)
            self.sequence_vec[#self.sequence_vec + 1] = processed
            self.unique_stmt_name_map[params.name] = true

            ---@type verilua.sv.SVBuilder.sequence
            local sequence = {
                __type = "Sequence",
                name = params.name,
            }
            -- Sequences are reachable only via `$(seq:name)`, never flat.
            self.seq_envs[params.name] = sequence
            return sequence
        elseif typ == "covergroup" then
            -- Determine sampling event: per-covergroup override or default_clocking
            local sample_event_raw = params.sample_event or self.default_clocking_event
            assert(
                sample_event_raw ~= "",
                "[SVBuilder] covergroup error: no sampling event specified and no default_clocking set"
            )

            -- Template-expand sample_event using the same envs as expr
            local sample_event_expanded, se_err = template.substitute(sample_event_raw, final_envs)
            if se_err then
                assert(false, f("[SVBuilder] covergroup sample_event template error in '%s': %s", params.name, se_err))
            end

            -- Trim whitespace and determine header format
            local sample_event_trimmed = sample_event_expanded:match("^%s*(.-)%s*$")
            local cg_header
            if sample_event_trimmed:match("^with%s") or sample_event_trimmed:match("^with$") then
                -- "with function sample(...)" syntax: no @() wrapping
                cg_header = f("covergroup %s %s;", params.name, sample_event_trimmed)
            else
                -- Event-based: wrap with @()
                cg_header = f("covergroup %s @(%s);", params.name, sample_event_trimmed)
            end

            local inst_name = f("_GEN_%s_inst", params.name)

            -- Build the full covergroup text
            local cg_raw = f("%s\n%s\nendgroup", cg_header, ret)

            if self.lint_enabled then
                local lint_err = run_sv_lint(self, cg_raw .. "\n" .. f("%s %s = new;", params.name, inst_name),
                    params.name)
                if lint_err then
                    assert(false, f("[SVBuilder] lint error in '%s': %s", params.name, lint_err))
                end
            end

            -- Store the covergroup definition + instantiation
            local content = cg_raw .. "\n" .. f("%s %s = new;", params.name, inst_name)
            self.covergroup_vec[#self.covergroup_vec + 1] = content
            self.unique_stmt_name_map[params.name] = true
            self.unique_stmt_name_map[inst_name] = true

            -- Track name/inst for final block generation
            self._covergroup_names[#self._covergroup_names + 1] = {
                name = params.name,
                inst_name = inst_name,
            }
            return
        else
            assert(false, "[SVBuilder] add error: unknown type `" .. typ .. "`")
        end

        assert(false, "Should not reach here")
    end
end

function SVBuilder:default_clocking(signal, edge_type, overwrite)
    local t = type(signal)
    assert(
        t == "table",
        "[SVBuilder] default_clocking error: `signal` should be a ProxyTableHandle or CallableHDL, but got " .. t
    )

    local handle_t = signal.__type
    local is_chdl = handle_t == "CallableHDL"
    local is_dut = handle_t == "ProxyTableHandle"
    assert(
        is_chdl or is_dut,
        "[SVBuilder] default_clocking error: `signal` should be a ProxyTableHandle or CallableHDL, but got " ..
        tostring(handle_t)
    )

    ---@type verilua.handles.CallableHDL
    local chdl
    if is_chdl then
        ---@cast signal verilua.handles.CallableHDL
        chdl = signal
    elseif is_dut then
        ---@cast signal verilua.handles.ProxyTableHandle
        chdl = signal:chdl()
    else
        assert(false, "Should not reach here")
    end

    assert(chdl:get_width() == 1, "[SVBuilder] default_clocking error: `signal` should be a 1-bit signal")

    assert(
        edge_type == "posedge" or edge_type == "negedge",
        "[SVBuilder] default_clocking error: `edge_type` should be `posedge` or `negedge`"
    )

    if not overwrite and self.default_clocking_expr ~= "" then
        assert(
            false,
            "[SVBuilder] default_clocking error: `overwrite` is false, but `self.default_clocking_expr` is not empty"
        )
    end

    self.default_clocking_expr = f("default clocking @(%s %s); endclocking", edge_type, chdl.fullpath)
    self.default_clocking_event = f("%s %s", edge_type, chdl.fullpath)

    return self
end

function SVBuilder:with_global_envs(envs)
    for key, value in pairs(envs) do
        self.global_envs[key] = value
    end
    return self
end

function SVBuilder:clean()
    self.default_clocking_expr = ""
    self.default_clocking_event = ""
    self.unique_stmt_name_map = {}
    self.global_envs = {}
    self.seq_envs = {}
    self.prop_envs = {}
    self.sequence_vec = {}
    self.property_vec = {}
    self.content_vec = {}
    self.covergroup_vec = {}
    self._covergroup_names = {}
    return self
end

return SVBuilder
