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

cfg['seed'] = 0
cfg['single_step_mode'] = true
cfg['enable_shutdown'] = false
cfg['shutdown_cycles'] = 10000

local RemoteTerm = require("RemoteTerm")
local rt_slice_0 = RemoteTerm(12345)
local rt_slice_1 = RemoteTerm(12346)

local rt_slice_0_a = RemoteTerm(12355)
local rt_slice_1_a = RemoteTerm(12356)

-- local rt_slice_0_c = RemoteTerm(12365)
-- local rt_slice_1_c = RemoteTerm(12366)

rt_slice_0:print("hello from lua main")
rt_slice_1:print("hello from lua main")

rt_slice_0_a:print("hello from lua main")
rt_slice_1_a:print("hello from lua main")

-- rt_slice_0_c:print("hello from lua main")
-- rt_slice_1_c:print("hello from lua main")

local rt_slice = {rt_slice_0, rt_slice_1}
local rt_slice_a = {rt_slice_0_a, rt_slice_1_a}
-- local rt_slice_c = {rt_slice_0_c, rt_slice_1_c}


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



local nr_slice = 2
local hierachy = cfg.top .. "." .. "l_soc.core_with_l2.l2cache"

local CHANNEL_A = 1
local CHANNEL_B = 2
local CHANNEL_C = 4

local mp_task_s3 = {
    Bundle({"valid", "channel", "mshrTask"}, "task_s3_", hierachy..".slices_0.mainPipe", "MainPipe task s3 slice 0", true),
    Bundle({"valid", "channel", "mshrTask"}, "task_s3_", hierachy..".slices_1.mainPipe", "MainPipe task s3 slice 1", true),
}

local mp_miss_s3 = {
    CallableHDL(hierachy..".slices_0.mainPipe.miss_s3", "MainPipe miss s3 slice 0"),
    CallableHDL(hierachy..".slices_1.mainPipe.miss_s3", "MainPipe miss s3 slice 1"),
}

local mp_hit_s3 = {
    CallableHDL(hierachy..".slices_0.mainPipe.hit_s3", "MainPipe hit s3 slice 0"),
    CallableHDL(hierachy..".slices_1.mainPipe.hit_s3", "MainPipe hit s3 slice 1"),
}

local valid_cnt = {0, 0}
local STEP = 100
local sim_info = { 
    {hit = 0, miss = 0, a_hit = 0, a_miss = 0, c_hit = 0, c_miss = 0}, -- slice 0
    {hit = 0, miss = 0, a_hit = 0, a_miss = 0, c_hit = 0, c_miss = 0}  -- slice 1
}


-- For Verilator only
local function create_lua_main_step()
    local cycles = 0
    print("hello from create lua main step")
    return function()
        -- print("from lua main step", cycles)

        for slice = 1, nr_slice do
            if mp_task_s3[slice]:fire() and mp_task_s3[slice].bits.mshrTask() ~= 1 then
                -- Valid request
                local channel = mp_task_s3[slice].bits.channel()

                if mp_hit_s3[slice]() == 1 then
                    sim_info[slice].hit = sim_info[slice].hit + 1

                    if channel == CHANNEL_A then
                        -- verilua_info("recv channel A")
                        sim_info[slice].a_hit = sim_info[slice].a_hit + 1
                    elseif channel == CHANNEL_B then
                        -- verilua_info("recv channel B")
                    elseif channel then
                        -- verilua_info("recv channel C")
                        sim_info[slice].c_hit = sim_info[slice].c_hit + 1
                    else
                        verilua_assert("Invalid channel value: " .. channel)
                    end
                elseif mp_miss_s3[slice]() == 1 then
                    sim_info[slice].miss = sim_info[slice].miss + 1

                    if channel == CHANNEL_A then
                        -- verilua_info("recv channel A")
                        sim_info[slice].a_miss = sim_info[slice].a_miss + 1
                    elseif channel == CHANNEL_B then
                        -- verilua_info("recv channel B")
                    elseif channel then
                        -- verilua_info("recv channel C")
                        sim_info[slice].c_miss = sim_info[slice].c_miss + 1
                    else
                        verilua_assert("Invalid channel value: " .. channel)
                    end
                else
                    verilua_assert("ERROR!")
                end

                valid_cnt[slice] = valid_cnt[slice] + 1
                if valid_cnt[slice] >= STEP then
                    local hit_rate = sim_info[slice].hit / (sim_info[slice].hit + sim_info[slice].miss)
                    old_print(string.format("[%d] Slice_%d hit:%d miss:%d hit_rate:%.2f", cycles, slice - 1, sim_info[slice].hit, sim_info[slice].miss, hit_rate))
                    io.flush()
                    
                    local a_hit_rate = sim_info[slice].a_hit / (sim_info[slice].a_hit + sim_info[slice].a_miss)
                    -- local c_hit_rate = sim_info[slice].c_hit / (sim_info[slice].c_hit + sim_info[slice].c_miss)
                    
                    -- Format: <[your var name]:[your var val]>
                    --         Start with '<', end with '>', var and val are seperated by ':'
                    rt_slice[slice]:print(string.format("[%d] <hit_slice_%d:%.2f>", cycles, slice-1, hit_rate))
                    rt_slice_a[slice]:print(string.format("[%d] <hit_slice_%d_a:%.2f>", cycles, slice-1, a_hit_rate))
                    -- rt_slice_c[slice]:print(string.format("[%d] <hit_slice_%d_c:%.2f>", cycles, slice-1, c_hit_rate))

                    valid_cnt[slice] = 0
                    sim_info[slice].hit = 0
                    sim_info[slice].miss = 0
                    sim_info[slice].a_hit = 0
                    sim_info[slice].a_miss = 0
                    sim_info[slice].c_hit = 0
                    sim_info[slice].c_miss = 0
                end
            end
        end
        
        -- if cycles % 10000 == 0 and cycles ~= 0 then
        --     print(cycles, "Running...", os.clock())
        --     io.flush()
        -- end

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

