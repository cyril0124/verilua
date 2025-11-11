---@class (exact) verilua.utils.PerfCounter.state
---@field calls integer
---@field total number

---@class (exact) verilua.utils.PerfCounter
---@field private perf_map table<string, verilua.utils.PerfCounter.state>
---@field wrap_func fun(self: verilua.utils.PerfCounter, name: string, func: function): function
---@field print_perf fun(self: verilua.utils.PerfCounter, name: string?)
local PerfCounter = {
    perf_map = {},
}

function PerfCounter:wrap_func(name, func)
    assert(self.perf_map[name] == nil, "PerfCounter:wrap_func: name already exists")
    self.perf_map[name] = { calls = 0, total = 0.0 }

    local state = self.perf_map[name]

    local wrapped_func = function(...)
        local s = os.clock()
        -- Support at most 4 return values
        local r0, r1, r2, r3 = func(...)
        local e = os.clock()
        state.calls = state.calls + 1
        state.total = state.total + (e - s)
        return r0, r1, r2, r3
    end
    return wrapped_func
end

function PerfCounter:print_perf(name)
    -- Branch 1: Print a detailed report for a single function.
    if name then
        local stats = self.perf_map[name]
        if not stats or stats.calls == 0 then
            assert(false, string.format("Performance counter for '%s' not found or was never called.", name))
        end
        local avg_time_ms = (stats.total / stats.calls) * 1000
        print(string.format("---- Performance Report for: %s ----", name))
        print(string.format("  Total Time : %.4f s", stats.total))
        print(string.format("  Calls      : %d", stats.calls))
        print(string.format("  Avg Time   : %.4f ms/call", avg_time_ms))
        print("------------------------------------------")
        return
    end

    -- Branch 2: Print a summary table for all functions.

    -- Step 1: Prepare the data for printing.
    local entries = {}
    local grand_total_time = 0.0
    for n, stats in pairs(self.perf_map) do
        if stats.calls > 0 then
            table.insert(entries, { name = n, stats = stats })
            grand_total_time = grand_total_time + stats.total
        end
    end

    if #entries == 0 then
        print("No performance data recorded.")
        return
    end

    -- Sort entries by total time (descending) to show the most expensive calls first.
    table.sort(entries, function(a, b)
        return a.stats.total > b.stats.total
    end)

    -- Step 2: Calculate dynamic column widths for a clean table layout.
    local col_widths = { name = 8, total = 14, calls = 14, avg = 10, percent = 8 }
    for _, entry in ipairs(entries) do
        if #entry.name > col_widths.name then
            col_widths.name = #entry.name
        end
    end

    -- Step 3: Define helpers for table rendering.

    -- Helper function to draw horizontal lines (e.g., ┌───┬───┐).
    local function draw_line(l, m, r, c)
        c = c or "─"
        local parts = {
            l, c:rep(col_widths.name + 2), m,
            c:rep(col_widths.total + 2), m,
            c:rep(col_widths.calls + 2), m,
            c:rep(col_widths.avg + 2), m,
            c:rep(col_widths.percent + 2), r
        }
        print(table.concat(parts))
    end

    -- Pre-build the format strings for the header and data rows.
    local header_format = string.format(
        "│ %%-%ds │ %%%ds │ %%%ds │ %%%ds │ %%%ds │",
        col_widths.name, col_widths.total, col_widths.calls, col_widths.avg, col_widths.percent
    )

    -- Correctly construct the row format string using table.concat to avoid errors.
    -- This creates a valid format string like: "│ %-20s │ %14.4f │ %8d │ %15.4f │ %8s │"
    local row_format = table.concat({
        "│ %-", col_widths.name, "s │ %", col_widths.total, ".4f │ %", col_widths.calls,
        "d │ %", col_widths.avg, ".4f │ %", col_widths.percent, "s │"
    })

    -- Step 4: Print the final table.
    draw_line("┌", "┬", "┐")
    print(string.format(header_format, "Function", "Total Time (s)", "Calls", "Avg Time (ms)", "Percent"))
    draw_line("├", "┼", "┤")

    for _, entry in ipairs(entries) do
        local stats = entry.stats
        local avg_time_ms = (stats.total / stats.calls) * 1000

        local percentage_str = "0.00%"
        if grand_total_time > 1e-9 then -- Avoid division by zero
            percentage_str = string.format("%.2f%%", (stats.total / grand_total_time) * 100)
        end

        print(string.format(row_format, entry.name, stats.total, stats.calls, avg_time_ms, percentage_str))
    end

    draw_line("└", "┴", "┘")
end

return PerfCounter
