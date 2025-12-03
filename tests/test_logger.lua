--- Test for Logger module
--- Run with: luajit tests/test_logger.lua

local Logger = require "verilua.utils.Logger"

print("=" .. string.rep("=", 60))
print("Testing Logger Module (High-Performance Version)")
print("=" .. string.rep("=", 60))

-- Test 1: Create a logger
local log = Logger.new("TestModule")
assert(log ~= nil, "Failed to create logger")
print("✓ Test 1: Logger creation passed")

-- Test 2: Verify compile-time optimization
-- Check that log functions are generated at creation time
assert(type(log.debug) == "function", "debug should be a function")
assert(type(log.info) == "function", "info should be a function")
assert(type(log.warning) == "function", "warning should be a function")
assert(type(log.error) == "function", "error should be a function")
print("✓ Test 2: Compile-time function generation passed")

-- Test 3: Basic logging
log:info("This is an info message")
log:success("This is a success message")
log:warning("This is a warning message")
log:debug("This is a debug message")
print("✓ Test 3: Basic logging passed")

-- Test 4: Header
log:header("Test Header", 50)
print("✓ Test 4: Header passed")

-- Test 5: Section
log:section_start("Test Section", 50)
log:section_line("Line 1", 50)
log:section_line("Line 2 with more content", 50)
log:section_end(50)
print("✓ Test 5: Section passed")

-- Test 6: Progress bar
local bar = log:progress_bar(0.75, 20)
print("Progress bar (75%): " .. bar)
bar = log:progress_bar(0.25, 20)
print("Progress bar (25%): " .. bar)
bar = log:progress_bar(1.0, 20)
print("Progress bar (100%): " .. bar)
print("✓ Test 6: Progress bar passed")

-- Test 7: Table
log:table(
    { "Name", "Value", "Status" },
    {
        { "Item1", "100", "OK" },
        { "Item2", "200", "FAIL" },
        { "Item3", "300", "WARN" },
    }
)
print("✓ Test 7: Table passed")

-- Test 8: Key-value pairs
log:kv("Key1", "Value1")
log:kv("LongerKey", 12345)
log:kv("ShortKey", true, 20)
print("✓ Test 8: Key-value pairs passed")

-- Test 9: Banner
log:banner()
print("✓ Test 9: Banner passed")

-- Test 10: Simulation summary
log:sim_summary(1.2345)
print("✓ Test 10: Simulation summary passed")

-- Test 11: Line
log:line(40, nil, false)
log:line(40, nil, true)
print("✓ Test 11: Line passed")

-- Test 12: Static colorize function
local colored = Logger.colorize("Red text", Logger.COLORS.RED)
print("Colored text: " .. colored)
print("✓ Test 12: Static colorize passed")

-- Test 13: Configuration accessors
print("CFG.USE_COLORS:", Logger.CFG.USE_COLORS)
print("CFG.USE_ICONS:", Logger.CFG.USE_ICONS)
print("CFG.USE_UNICODE:", Logger.CFG.USE_UNICODE)
print("CFG.MIN_LEVEL:", Logger.CFG.MIN_LEVEL)
print("✓ Test 13: Configuration accessors passed")

-- Test 14: Default logger
local default = Logger.default
assert(default ~= nil, "Default logger should exist")
default:info("Message from default logger")
print("✓ Test 14: Default logger passed")

-- Test 15: No colors mode (per-instance override)
local no_color_log = Logger.new("NoColor", { use_colors = false })
no_color_log:info("This should not have colors")
print("✓ Test 15: No colors mode passed")

print("")
print("=" .. string.rep("=", 60))
print("All Logger tests passed!")
print("=" .. string.rep("=", 60))
