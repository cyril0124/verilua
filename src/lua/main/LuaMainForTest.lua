--------------------------------
-- Setup package path
--------------------------------
local VERILUA_HOME = os.getenv("VERILUA_HOME")
package.path = package.path .. ";" .. VERILUA_HOME .. "/src/lua/?.lua"
package.path = package.path .. ";" .. VERILUA_HOME .. "/src/lua/verilua/?.lua"
package.path = package.path .. ";" .. VERILUA_HOME .. "/src/lua/thirdparty_lib/?.lua"
package.path = package.path .. ";" .. VERILUA_HOME .. "/luajit2.1/share/lua/5.1/?.lua"


--------------------------------
-- Required package
--------------------------------
require("LuaScheduler")
require("LuaDut")
require("LuaBundle")
local cfg = require("LuaSimConfig")


--------------------------------
-- Initialization
--------------------------------
print("Hello from lua")

-- Basic configuration
cfg['top'] = "Top"
cfg['seed'] = 0
cfg['enable_shutdown'] = true
cfg['shutdown_cycles'] = 50

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
-- Overide assert
--------------------------------
-- local old_assert = assert
-- local assert = function (cond, str)
--     if not cond then
--         str = str or ""
--         io.write(str)
--         io.flush()
--     end
--     old_assert(cond)
-- end


--------------------------------
-- Main body
--------------------------------
ch_a_bundle = Bundle({"count", "count_1", "cycles"}, "", "Top", "Channel A")
ch_b_bundle = Bundle({"lfsr"}, "", "Top.u_lfsr", "Channel B")
ch_c_bundle = Bundle({"valid", "ready", "rd_data"}, "", "Top", "Channel C", true)

require("TileLinkDB")
local utils = require("LuaUtils")

local tl_db = TileLinkDB("tl_db.db", VERILUA_HOME .. "/db")

local function table_average(t)
    local sum = 0
    local count = 0

    for _ , value in ipairs(t) do
        sum = sum + value
        count = count + 1
    end

    return (sum / count)
end

local function test(times, n)
    local a = {}
    for i = 1, n do
        local begin = os.clock()
        for j = 1, times do
            -- local tab = math.random(100)
            -- utils.to_hex_str_memoize(tab)
            local t = math.random(100)
            local func = t > 50 and function() return 123 end or function() end
            local a = func()
        end
        local endd = os.clock()
        table.insert(a, endd - begin)
    end
    print("a => ", table_average(a))

    local b = {}
    for i = 1, n do
        local begin = os.clock()
        for j = 1, times do
            -- local tab = math.random(100)
            -- utils:to_hex_str(tab)
            local t = math.random(100)
            local func = t > 50 and function() return 123 end or nil
            if func ~= nil then
                local a = func()
            end
        end
        local endd = os.clock()
        table.insert(b, endd - begin)
    end
    print("b => ", table_average(b))
end

require("TLCAgent")
-- tlc_agent = TLCAgent(
--     "tlc_agent", 
--     Bundle({"valid", "ready", "address", "opcode", "param", "data", "source"}, "tlc_", "Top", "tlc_agent bundle a", true),
--     Bundle({"valid", "ready", "address", "param", "data", "source"}, "tlc_chnl_b_", "Top", "tlc_agent bundle b", true),
--     Bundle({"valid", "ready", "address", "opcode", "param", "data", "source"}, "tlc_", "Top", "tlc_agent bundle c", true),
--     Bundle({"valid", "ready", "address", "opcode", "param", "data", "source", "sink"}, "tlc_chnl_d_", "Top", "tlc_agent bundle d", true),
--     Bundle({"valid", "ready", "source", "sink"}, "tlc_", "Top", "tlc_agent bundle e", true),
--     vpi.handle_by_name(dut.clock("name")),
--     true
-- )

local function lua_main()
    await_posedge(dut.reset)
    await_posedge(dut.clock)

    -- test(50000, 10)
    -- assert(false)

    local cycles = 0
    local clock_hdl = vpi.handle_by_name(dut.clock("name"))
    local loop = function()
        -- local large_table = {}
        -- for i = 1, 1000000 do
        --     large_table[i] = "This is a test line."
        -- end

        -- for i = 1, 1000000 do
        --     local line = large_table[i]
        -- end

        print("from main task cycles:" .. cycles)
        -- print(ch_c_bundle.bits.rd_data())
        
        -- local tablex = require("pl.tablex")
        -- local t1 = {1, 2, 3}
        -- local t2 = {1, 2, 3}
        -- print("cmp_1: ", t1 == t2)
        -- print("cmp_2: ", tablex.compare(t1, t2, function(v1, v2) return v1 == v2 end))

        tl_db:save(TileLinkTrans(cycles, 0, 2, "A", 1, 2, {math.random(100), math.random(100)}, 11, 22, {math.random(100), math.random(100), math.random(100)}, nil))

        if cycles % 1000 == 0 and cycles ~= 0 then
            -- scheduler:remove_task(2)
            scheduler:remove_task(3)
            print(cycles, "Running...", os.clock())
            io.flush()
        end
        if cycles == 1234 then
            local func = function(a, b) 
                local finish = false
                while not finish do
                    print("[appended task]", a, b, "running...", dut.cycles())
                    while dut.cycles() <= 1333 do
                        print("[appended task] waitting...", dut.cycles())
                        await_posedge(dut.clock)
                    end
                    finish = true
                end
            end
        end

        if cycles % 100 == 0 and cycles ~= 0 then
            scheduler:list_tasks()
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

require("FakeCache")
local fake_cache = FakeCache("fake cache", 64, 4, 64, 
    Bundle({"valid", "ready", "address", "opcode", "param", "data", "source"}, "tlc_", "Top", "tlc_agent bundle a", true),
    Bundle({"valid", "ready", "address", "param", "data", "source"}, "tlc_chnl_b_", "Top", "tlc_agent bundle b", true),
    Bundle({"valid", "ready", "address", "opcode", "param", "data", "source"}, "tlc_", "Top", "tlc_agent bundle c", true),
    Bundle({"valid", "ready", "address", "opcode", "param", "data", "source", "sink"}, "tlc_chnl_d_", "Top", "tlc_agent bundle d", true),
    Bundle({"valid", "ready", "source", "sink"}, "tlc_", "Top", "tlc_agent bundle e", true),
    vpi.handle_by_name(dut.clock("name")),
    true
)
local function another_task()
    await_posedge(dut.reset)
    await_posedge(dut.clock)
    

    local cycles = 0
    local clock_hdl = vpi.handle_by_name(dut.clock("name"))

    while true do
        print("from another task cycles:" .. cycles)
        cycles = cycles + 1
        if cycles == 1 then
            local err = fake_cache:load(fake_cache:to_address(1, 2))
        end

        -- if cycles % 100 == 0 and cycles ~= 0 then
        --     tlc_agent:acquire_block(0x33, TLParamGrow.NtoT, 123)
        -- end
        -- if cycles % 123 == 0 and cycles ~= 0 then
        --     tlc_agent:release(0x123, TLParamShrink.TtoN, 12)
        -- end
        -- if cycles % 144 == 0 and cycles ~= 0 then
        --     tlc_agent:release_data(0x111, TLParamShrink.TtoN, 122, {0x1234, 0x111}, 2)
        -- end
        -- if cycles % 155 == 0 and cycles ~= 0 then
        --     tlc_agent:grant_ack(12, 22)
        -- end
        -- if cycles % 225 == 0 and cycles ~= 0 then
        --     tlc_agent:probeack(cycles, TLParamShrink.BtoN, 212)
        -- end
        -- if cycles % 325 == 0 and cycles ~= 0 then
        --     tlc_agent:probeack_data(cycles + 1, TLParamShrink.TtoN, 111, {0x444, 0x666}, 2)
        -- end
        -- local cache = FakeCache(32, 4)
        -- local set, tag = cache:parse_address(0x1234)
        -- print(set, tag, "set_bits:", cache.set_bits, "block_bits:", cache.block_bits)
        -- print("bitfield32: ", utils:bitfield32(0, 7, 0x1234))
        -- assert(false)
        -- await_posedge(dut.clock)
        -- fake_cache:cycle_resolve()
        await_posedge_hdl(clock_hdl) -- higher performance
    end
end

local function another_task_1()
    await_posedge(dut.reset)
    await_posedge(dut.clock)
    

    local cycles = 0
    local clock_hdl = vpi.handle_by_name(dut.clock("name"))
    while true do
        print("from another task 1 cycles:" .. cycles)
        cycles = cycles + 1

        -- await_posedge(dut.clock)
        await_posedge_hdl(clock_hdl) -- higher performance
    end
end

local function create_lua_main_step()
    local cycles = 0
    print("hello from create lua main step")
    return function()


        print("from lua main step", cycles)
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
    {"main", lua_main, {}},
    {"another task", another_task, {}},
    {"another task 1", another_task_1, {}}
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

    -- tlc_agent:init_resolve_backend()
    fake_cache:agent_init()

    print("----------[Lua] Verilua Init finish!----------")

    if not cfg.single_step_mode then
        scheduler:schedule_all_tasks()
    end
end


--------------------------------
-- Simulation finish callback
--------------------------------
function finish_callback()
    if tl_db ~= nil then
        tl_db:clean_up()
    end

    end_time = os.clock()
    old_print(ANSI_COLOR_MAGENTA)
    print("----------[Lua] Simulation finish!----------")
    print("----------[Lua] Time elapsed: " .. (end_time - start_time).. " seconds" .. "----------")
    old_print(ANSI_COLOR_RESET)
end

