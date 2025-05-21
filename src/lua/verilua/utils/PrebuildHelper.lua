
local unnamed_task_count = 0
local prebuild_tasks = {}

---@diagnostic disable-next-line: duplicate-set-field
_G.prebuild = function (task_table)
    assert(type(task_table) == "table")

    for name, func in pairs(task_table) do
        if type(name) == "number" then
            name = ("unnamed_prebuild_task_%d"):format(unnamed_task_count)
            unnamed_task_count = unnamed_task_count + 1   
        end

        if _G.enable_verilua_debug then
            _G.verilua_debug("[prebuild] get task name => ", name)
        end

        prebuild_tasks[name] = func
    end
end

_G.run_prebuild_tasks = function ()
    for name, func in pairs(prebuild_tasks) do
        if _G.enable_verilua_debug then
            _G.verilua_debug("[prebuild] run task => ", name)
        end
        func()
    end
end

