initial {
    function()
        print("[initial] fork_basics example is starting")
    end
}

final {
    function()
        print("[final] fork_basics example finished successfully")
    end
}

fork {
    main_task = function()
        local clock = dut.clock:chdl()
        local reset = dut.reset:chdl()
        local enable = dut.enable:chdl()
        local counter = dut.counter:chdl()

        local function reset_dut()
            reset:set(1)
            enable:set(0)
            clock:posedge(2)
            reset:set(0)
            clock:posedge()
            counter:expect(0)
        end

        print("[main] section 1: fork + EventHandle")
        reset_dut()

        local reached_target = ("reached_target"):ehdl()
        local waiter_resumed = false

        fork {
            driver_task = function()
                print("[driver_task] driving enable for 4 cycles")
                enable:set(1)
                clock:posedge(4)
                enable:set(0)
            end,

            monitor_task = function()
                while counter:get() < 4 do
                    clock:posedge()
                end

                print("[monitor_task] counter reached 4, sending event")
                reached_target:send()
            end,

            waiter_task = function()
                reached_target:wait()
                waiter_resumed = true
                print("[waiter_task] resumed after event")
                counter:expect(4)
            end
        }

        clock:posedge(6)
        assert(waiter_resumed, "waiter task should be resumed by the event")

        print("[main] section 2: single jfork + join")
        local joined_once = false
        local single_ehdl = jfork {
            delayed_task = function()
                clock:posedge(2)
                joined_once = true
                print("[delayed_task] single joinable task finished")
            end
        }
        join(single_ehdl)
        assert(joined_once, "single joinable task should finish before join returns")

        print("[main] section 3: multiple jfork + join")
        local fast_done = false
        local slow_done = false

        local fast_ehdl = jfork {
            fast_task = function()
                clock:posedge()
                fast_done = true
                print("[fast_task] finished")
            end
        }

        local slow_ehdl = jfork {
            slow_task = function()
                clock:posedge(3)
                slow_done = true
                print("[slow_task] finished")
            end
        }

        join { fast_ehdl, slow_ehdl }
        assert(fast_done and slow_done, "all joinable tasks should finish before join returns")

        print("[main] all fork basics checks passed")
        sim.finish()
    end
}
