
require("LuaUtils")

local test_statistic = {}
local exports = {}

local describe = function (name, func)
    print()
    verilua_info(string.format("[%s] >>> start test", name))

    local s = os.clock()
    local success, msg = pcall(func)
    local e = os.clock()
    local elapsed_time = e - s
    if not success then
        print("Error msg: ", msg)
        verilua_warning(string.format("[%s] <<< test FAILED!", name))
        table.insert(test_statistic, {name = name, msg = msg, success = "failed", time = elapsed_time})
    else
        verilua_info(string.format("[%s] <<< test SUCCESS!", name))
        table.insert(test_statistic, {name = name, msg = "nil", success = "success", time = elapsed_time})
    end
    print()
end

local report_statistic = function ()
    local success = 0
    local failed = 0
    local total = #test_statistic
    print("\n----------------------------------- test report statistic -----------------------------------")
    if #test_statistic == 0 then
        print("Nothing...")
        print("----------------------------------------------------------------------------------------------\n")
        return
    end

    for i, v in ipairs(test_statistic) do
        local color = colors.green
        if v.success == "success" then
            success = success + 1
            color = colors.green
        elseif v.success == "failed" then
            failed = failed + 1
            color = colors.red
        else
            assert(false, "Unreconize => "..v.success)
        end
        print(string.format("[%d] name: %s  status: %s  time: %.2fs  msg: %s", i, v.name, color .. v.success .. colors.reset, v.time, v.msg))
    end
    print("----------------------------------------------------------------------------------------------")
    print(string.format("pass rate: %.2f", success*100 / (success + failed) ).."%")
    print(string.format("success: %d\nfailed: %d\ntotal: %d\n", success, failed, total))
end

exports.describe = describe
exports.report_statistic = report_statistic

-- a special syntax sugar to export all functions to the global table (copy from luafun)
-- usage: require("LuaTest")()
setmetatable(exports, {
    __call = function(t, override)
        for k, v in pairs(t) do
            if rawget(_G, k) ~= nil then
                local msg = 'function ' .. k .. ' already exists in global scope.'
                if override then
                    rawset(_G, k, v)
                    print('WARNING: ' .. msg .. ' Overwritten.')
                else
                    print('NOTICE: ' .. msg .. ' Skipped.')
                end
            else
                rawset(_G, k, v)
            end
        end
    end,
})

return exports