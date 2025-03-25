local clock = dut.clock:chdl()
local reset = dut.reset:chdl()

local function posedge(...)
    clock:posedge(...)
end

local function negedge(...)
    clock:negedge(...)
end

local function dut_reset(reset_cycles)
    reset:set_imm(1)
    clock:posedge(reset_cycles or 10)
    reset:set_imm(0)
end

local function expect_happen_until(limit_cycles, func)
    assert(type(limit_cycles) == "number")
    assert(type(func) == "function")
    local ok = clock:posedge_until(limit_cycles, func)
    assert(ok)
end

local function expect_not_happen_until(limit_cycles, func)
    assert(type(limit_cycles) == "number")
    assert(type(func) == "function")
    local ok = clock:posedge_until(limit_cycles, func)
    assert(not ok)
end

local test_case_count = 0

local function TEST_SUCCESS()
    print("total_test_cases: <" .. test_case_count .. ">\n")
    print(">>>TEST_SUCCESS!<<<")

    local ANSI_GREEN = "\27[32m"
    local ANSI_RESET = "\27[0m"

    print(ANSI_GREEN .. [[
  _____         _____ _____ 
 |  __ \ /\    / ____/ ____|
 | |__) /  \  | (___| (___  
 |  ___/ /\ \  \___ \\___ \ 
 | |  / ____ \ ____) |___) |
 |_| /_/    \_\_____/_____/ 
]] .. ANSI_RESET)

    io.flush()
    sim.finish()
end

-- 
-- Test case management
-- 
local function register_test_case(case_name)
    assert(type(case_name) == "string")

    return function(func_table)
        assert(type(func_table) == "table")
        assert(#func_table == 1)
        
        assert(type(func_table[1]) == "function")
        local func = func_table[1]

        local new_env = {
            print = function(...) print("|", ...) end,
            printf = function(...) io.write("|\t" .. string.format(...)) end,
        }

        setmetatable(new_env, { __index = _G })
        setfenv(func, new_env)

        return function (...)
            print(string.format([[
-----------------------------------------------------------------
| [%d] start test case ==> %s
-----------------------------------------------------------------]], test_case_count, case_name))

            -- Execute the test case
            func(...)

            print(string.format([[
-----------------------------------------------------------------
| [%d] end test case ==> %s
-----------------------------------------------------------------]], test_case_count, case_name))

            test_case_count = test_case_count + 1
        end
    end
end

return {
    posedge = posedge,
    negedge = negedge,
    dut_reset = dut_reset,
    expect_happen_until = expect_happen_until,
    expect_not_happen_until = expect_not_happen_until,
    register_test_case = register_test_case,
    TEST_SUCCESS = TEST_SUCCESS,
}