fork {
    function()
        local test = function(q)
            dut.clock:posedge(10)

            local initial_t = sim.get_sim_time()
            local t = sim.get_sim_time()

            local finish_1 = false
            fork {
                function()
                    local v1 = q:pop_waitable()
                    local _t = sim.get_sim_time()
                    assert(initial_t ~= _t)
                    assert(t == _t)
                    assert(v1 == 10)
                    print("finish 1")
                    finish_1 = true
                end
            }

            dut.clock:posedge(10)

            local finish_2 = false
            fork {
                function()
                    local v1 = q:pop_waitable()
                    local _t = sim.get_sim_time()
                    assert(initial_t ~= _t)
                    assert(t == _t)
                    assert(v1 == 20)
                    print("finish 2")
                    finish_2 = true
                end
            }

            local finish_3 = false
            fork {
                function()
                    q:wait_not_empty()
                    local _t = sim.get_sim_time()
                    assert(initial_t ~= _t)
                    assert(t == _t)
                    assert(q:pop() == 30)
                    print("finish 3")
                    finish_3 = true
                end
            }

            t = sim.get_sim_time()
            q:push_waitable(10)

            dut.clock:posedge(10)

            t = sim.get_sim_time()
            q:push_waitable(20)

            dut.clock:posedge(10)

            t = sim.get_sim_time()
            q:push_waitable(30)

            await_time(0)
            assert(finish_1 and finish_2 and finish_3)

            t = sim.get_sim_time()
            q:push_waitable(40)
            q:push_waitable(50)

            assert(q:wait_not_empty())
            assert(q:pop_waitable() == 40)
            assert(q:pop_waitable() == 50)
            assert(t == sim.get_sim_time())
            assert(q:is_empty())

            q:push_waitable(60)
            assert(q:pop_waitable() == 60)

            q:push_waitable(70)
            dut.clock:posedge()
            assert(q:wait_not_empty())
            assert(q:pop_waitable() == 70)
        end

        local Queue = require("verilua.utils.Queue")
        local q = Queue() --[[@as verilua.utils.Queue<integer>]]

        test(q)

        local StaticQueue = require("verilua.utils.StaticQueue")
        local sq = StaticQueue(10) --[[@as verilua.utils.StaticQueue<integer>]]

        test(sq)

        sim.finish()
    end,
}
