--------------------------------
-- Setup package path
--------------------------------
package.path = package.path .. ";" .. os.getenv("VERILUA_HOME") .. "/src/lua/verilua/?.lua"

local srcs = require("LuaSrcs")
for i, src in pairs(srcs) do package.path = package.path .. ";" .. src end


--------------------------------
-- Configuration load
--------------------------------
require("LuaSimConfig")
local VERILUA_CFG, VERILUA_CFG_PATH = LuaSimConfig.get_cfg()
local cfg = require(VERILUA_CFG)


--------------------------------
-- Required package
--------------------------------
require("LuaScheduler")
require("LuaDut")
require("LuaBundle")
require("LuaUtils")


--------------------------------
-- Initialization
--------------------------------
verilua_colorful("Hello from lua")

-- Basic initialization
local dut = create_proxy(cfg.top)
local start_time = os.clock()
math.randomseed(cfg.seed)


--------------------------------
-- Print with cycles info (this will increase simulation time)
--------------------------------
local old_print = print
local print = function(...)
    old_print("[LuaMain] ", ...)
end


--------------------------------
-- Main body
--------------------------------

local function lua_main()
    await_posedge(dut.reset)
    await_posedge(dut.clock)

    local cycles = 0
    local clock_hdl = vpi.handle_by_name(dut.clock("name"))
    local loop = function()
        print("from main task cycles:" .. cycles)



        if cycles % 1000 == 0 and cycles ~= 0 then
            print(cycles, "Running...", os.clock())
            io.flush()
        end

        -- await_posedge(dut.clock)
        await_posedge_hdl(clock_hdl) -- higher performance
        cycles = cycles + 1
    end

    if cfg.enable_shutdown then
        for i = 0, cfg.shutdown_cycles do loop() end
    else
        while true do loop() end
    end

    print("Finish")
    vpi.simulator_control(SimCtrl.FINISH)
end


local function create_lua_main_step()
    local cycles = 0
    print("hello from create lua main step")
    return function()
        print("from lua main step", cycles)


        
        if cycles % 1000 == 0 and cycles ~= 0 then
            print(cycles, "Running...", os.clock())
            io.flush()
        end

        cycles = cycles + 1
        return cycles
    end
end

local lua_main_step_impl = create_lua_main_step()

function lua_main_step()
    lua_main_step_impl()
end


--------------------------------
-- Initialize scheduler task table
--------------------------------
scheduler:create_task_table({
    {"main", lua_main, {}}
})


--------------------------------
-- Simulation event: will be called once a callback is valid.
--------------------------------
function sim_event(id)
    scheduler:schedule_tasks(id)
end


--------------------------------
-- Lua side initialize
--------------------------------
function verilua_init()
    print("----------[Lua] Verilua Init!----------")
    print((ANSI_COLOR_MAGENTA .. "configuration file is %s/%s.lua" .. ANSI_COLOR_RESET):format(VERILUA_CFG_PATH, VERILUA_CFG))


    print("----------[Lua] Verilua Init finish!----------")

    if not cfg.single_step_mode then
        scheduler:schedule_all_tasks()
    end
end


--------------------------------
-- Simulation finish callback
--------------------------------
function finish_callback()
    end_time = os.clock()
    old_print(ANSI_COLOR_MAGENTA)
    print("----------[Lua] Simulation finish!----------")
    print("----------[Lua] Time elapsed: " .. (end_time - start_time).. " seconds" .. "----------")
    old_print(ANSI_COLOR_RESET)
end

