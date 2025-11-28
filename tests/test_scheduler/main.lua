--==============================================================================
-- Utility function for robust task removal synchronization
-- This handles simulator-specific timing differences in task cleanup
local function wait_for_task_removal(task_id, max_nsim)
    max_nsim = max_nsim or 3
    local wait_count = 0
    while scheduler:check_task_exists(task_id) and wait_count < max_nsim do
        await_nsim()
        wait_count = wait_count + 1
    end
    return wait_count
end

--==============================================================================
-- All tests must be in one fork because Verilua entry point is fork
fork {
    function()
        print("=== Verilua Scheduler Test Started ===")

        -- Get signal handles for testing
        local clock = dut.clock:chdl()
        local reset = dut.reset:chdl()
        local enable = dut.enable:chdl()
        local data_in = dut.data_in:chdl()
        local data_out = dut.data_out:chdl()
        local counter = dut.counter:chdl()
        local valid = dut.valid:chdl()

        --==============================================================================
        -- 1. Basic Task Management Test
        --==============================================================================

        print("\n--- 1. Basic Task Management Test ---")

        -- Test fork creating multiple tasks
        local task1_executed = false
        local task2_executed = false
        local task3_executed = false

        fork {
            function()
                task1_executed = true
            end,

            task_with_name = function()
                task2_executed = true
            end,

            function()
                task3_executed = true
            end
        }

        -- Verify task execution
        clock:posedge() -- Give tasks time to execute
        assert(task1_executed, "Task 1 should be executed")
        assert(task2_executed, "Task 2 should be executed")
        assert(task3_executed, "Task 3 should be executed")
        print("✓ Basic task management test passed")

        --==============================================================================
        -- 2. Timing Control Test
        --==============================================================================

        print("\n--- 2. Timing Control Test ---")

        -- Test posedge
        local posedge_count = 0

        fork {
            function()
                clock:posedge(3, function(count)
                    posedge_count = posedge_count + 1
                end)
            end
        }

        -- Run enough time for timing test to complete
        clock:posedge(5)

        assert(posedge_count == 3, "Should have 3 posedge callbacks")
        print("✓ Timing control test passed")

        --==============================================================================
        -- 3. Task Synchronization Test
        --==============================================================================

        print("\n--- 3. Task Synchronization Test ---")

        local sync_event = ("test_sync_event"):ehdl()
        local task_wait_count = 0
        local task_send_count = 0

        fork {
            event_waiter_1 = function()
                sync_event:wait()
                task_wait_count = task_wait_count + 1
            end,

            event_sender = function()
                clock:posedge(3)
                sync_event:send()
                task_send_count = task_send_count + 1
            end
        }

        clock:posedge(10)
        assert(task_wait_count == 1, "Should have 1 task awakened")
        assert(task_send_count == 1, "Should have 1 task send event")
        print("✓ Task synchronization test passed")

        -- Test 3.1: Multiple tasks waiting for same event
        local multi_sync_event = ("multi_sync_event"):ehdl()
        local waiter1_count = 0
        local waiter2_count = 0
        local waiter3_count = 0
        local sender_count = 0

        fork {
            waiter1 = function()
                multi_sync_event:wait()
                waiter1_count = waiter1_count + 1
            end,

            waiter2 = function()
                multi_sync_event:wait()
                waiter2_count = waiter2_count + 1
            end,

            waiter3 = function()
                multi_sync_event:wait()
                waiter3_count = waiter3_count + 1
            end,

            event_sender = function()
                clock:posedge(2)
                multi_sync_event:send()
                sender_count = sender_count + 1
            end
        }

        clock:posedge(10)
        assert(waiter1_count == 1, "Waiter1 should be awakened")
        assert(waiter2_count == 1, "Waiter2 should be awakened")
        assert(waiter3_count == 1, "Waiter3 should be awakened")
        assert(sender_count == 1, "Sender should send event")
        print("✓ Multiple tasks waiting for same event test passed")

        -- Test 3.2: Event sent from outside fork
        local external_sync_event = ("external_sync_event"):ehdl()
        local external_waiter1_count = 0
        local external_waiter2_count = 0

        fork {
            external_waiter1 = function()
                external_sync_event:wait()
                external_waiter1_count = external_waiter1_count + 1
            end,

            external_waiter2 = function()
                external_sync_event:wait()
                external_waiter2_count = external_waiter2_count + 1
            end
        }

        -- Send event from outside fork
        clock:posedge(2)
        external_sync_event:send()

        clock:posedge(10)
        assert(external_waiter1_count == 1, "External waiter1 should be awakened")
        assert(external_waiter2_count == 1, "External waiter2 should be awakened")
        print("✓ Event sent from outside fork test passed")

        --==============================================================================
        -- 4. jfork and join Test
        --==============================================================================

        print("\n--- 4. jfork and join Test ---")

        -- Test 4.1: Single jfork task
        local jfork_test_value = 0
        local jfork_ehdl = jfork {
            function()
                clock:posedge(3)
                jfork_test_value = 42
            end
        }

        join(jfork_ehdl)
        assert(jfork_test_value == 42, "jfork task should complete")
        print("✓ Single jfork task test passed")

        -- Test 4.2: Two jfork tasks with join
        local task1_result = 0
        local task2_result = 0

        local jfork_ehdl1 = jfork {
            function()
                clock:posedge(2)
                task1_result = 1
            end
        }

        local jfork_ehdl2 = jfork {
            function()
                clock:posedge(100)
                task2_result = 2
            end
        }

        -- Join both tasks to ensure completion
        join({ jfork_ehdl1, jfork_ehdl2 })

        assert(task1_result == 1, "Task1 should have value 1")
        assert(task2_result == 2, "Task2 should have value 2")
        print("✓ Two jfork tasks with join test passed")

        print("✓ All jfork and join tests passed")

        --==============================================================================
        -- 5. Remove task test (using jfork returned task_id)
        --==============================================================================

        print("\n--- 5. Remove task test ---")

        local scheduler = require "LuaScheduler"

        -- Test 1: Remove a continuously running task
        local task1_counter = 0
        local task1_ehdl, task1_id = jfork {
            function()
                while true do
                    clock:posedge()
                    task1_counter = task1_counter + 1
                end
            end
        }

        clock:posedge(5)
        local counter_before_removal = task1_counter
        scheduler:remove_task(task1_id)
        clock:posedge(5)
        local counter_after_removal = task1_counter

        assert(not scheduler:check_task_exists(task1_id), "Task should be removed")
        assert(counter_before_removal == counter_after_removal, "Removed task should not execute")

        -- Test 2: Remove a task using await_nsim/await_rd/await_rw
        local task2_counter = 0
        local task2_ehdl, task2_id = jfork {
            function()
                while true do
                    await_nsim()
                    task2_counter = task2_counter + 1
                    await_rw()
                end
            end
        }

        clock:posedge(3)
        local counter2_before_removal = task2_counter
        scheduler:remove_task(task2_id)
        clock:posedge(3)
        local counter2_after_removal = task2_counter

        assert(not scheduler:check_task_exists(task2_id), "Task2 should be removed")
        assert(counter2_before_removal == counter2_after_removal, "Removed task2 should not execute")

        -- Test 3: Remove a completed task
        local task3_finished = false
        local task3_ehdl, task3_id = jfork {
            function()
                clock:posedge()
                task3_finished = true
            end
        }

        clock:posedge(2)
        assert(task3_finished, "Task3 should be completed")

        if scheduler:check_task_exists(task3_id) then
            scheduler:remove_task(task3_id)
            assert(not scheduler:check_task_exists(task3_id), "Task3 should be removed")
        end


        -- Test 4: Remove task immediately after creation (edge case)
        local _, task4_id = jfork {
            function()
                while true do
                    await_nsim()
                end
            end
        }

        scheduler:remove_task(task4_id)
        local nsim_waited = wait_for_task_removal(task4_id)
        assert(not scheduler:check_task_exists(task4_id), "Task4 should be removed after " .. nsim_waited .. " nsim")
        print("Task4 removal took " .. nsim_waited .. " nsim")
        if cfg.simulator == "iverilog" then
            assert(nsim_waited == 2)
        else
            assert(nsim_waited == 1)
        end

        -- Test 5: Remove task immediately after creation
        local _, task5_id = jfork {
            function()
                while true do
                    clock:posedge()
                end
            end
        }

        scheduler:remove_task(task5_id)
        clock:posedge()
        assert(not scheduler:check_task_exists(task5_id), "Task5 should be removed")

        print("✓ Remove task test passed (using jfork returned task_id)")

        --==============================================================================
        -- 6. Comprehensive Test - Complex Scenario
        --==============================================================================

        print("\n--- 6. Comprehensive Test - Complex Scenario ---")

        reset:set(1)
        clock:posedge()
        reset:set(0)
        clock:posedge()

        enable:set(1)

        local complex_test_results = {
            counter_values = {},
            data_transfers = 0
        }

        fork {
            counter_monitor = function()
                for i = 1, 10 do
                    clock:posedge()
                    table.insert(complex_test_results.counter_values, counter:get())
                end
            end,

            data_transfer = function()
                for i = 1, 5 do
                    clock:posedge()
                    data_in:set(i * 10)
                    clock:posedge()
                    if valid:get() == 1 then
                        data_out:get()
                        complex_test_results.data_transfers = complex_test_results.data_transfers + 1
                    end
                end
            end
        }

        clock:posedge(20)
        assert(#complex_test_results.counter_values == 10, "Should record 10 counter values")
        assert(complex_test_results.data_transfers > 0, "Should have data transfers")
        print("✓ Comprehensive test passed")

        --==============================================================================
        -- 7. wakeup_task Test
        --==============================================================================

        print("\n--- 7. wakeup_task Test ---")

        -- Test 1: Create task, let it finish, then wakeup
        local finish_counter = 0
        local finish_task_id = scheduler:append_task(nil, "finish_task", function()
            finish_counter = finish_counter + 1
        end, true)

        assert(finish_counter == 1, "Task should run and finish")
        scheduler:wakeup_task(finish_task_id)
        assert(finish_counter == 2, "Task should run again after wakeup")

        -- Test 2: jfork task wakeup after completion
        local jfork_wakeup_counter = 0
        local jfork_wakeup_ehdl, jfork_wakeup_task_id = jfork {
            jfork_wakeup_task = function()
                jfork_wakeup_counter = jfork_wakeup_counter + 1
                clock:posedge(2)
            end
        }

        join(jfork_wakeup_ehdl)
        local counter_after_first_run = jfork_wakeup_counter
        assert(counter_after_first_run == 1, "jfork task should run once")

        clock:posedge(3)
        scheduler:wakeup_task(jfork_wakeup_task_id)
        clock:posedge(5)
        local counter_after_wakeup = jfork_wakeup_counter
        assert(counter_after_wakeup == 2, "jfork task should run again after wakeup")
        print("✓ jfork task wakeup test passed")

        -- Test 3: Error - wakeup running task
        local running_wakeup_ehdl, running_wakeup_task_id = jfork {
            running_wakeup_task = function()
                for i = 1, 10 do
                    clock:posedge()
                end
            end
        }

        clock:posedge(3)
        local success_running, error_msg_running = pcall(function()
            scheduler:wakeup_task(running_wakeup_task_id)
        end)
        assert(not success_running, "Should fail when waking up running task")
        assert(string.find(error_msg_running, "Task already running"), "Should mention task already running")

        join(running_wakeup_ehdl)
        print("✓ Running task wakeup error test passed")

        -- Test 4: Error - wakeup unregistered task
        local success, error_msg = pcall(function()
            scheduler:wakeup_task(99999)
        end)
        assert(not success, "Should fail when waking up unregistered task")
        assert(string.find(error_msg, "Task not registered"), "Should mention task not registered")
        print("✓ Unregistered task error test passed")

        print("✓ wakeup_task test passed")

        --==============================================================================
        -- 8. try_wakeup_task Test
        --==============================================================================

        print("\n--- 8. try_wakeup_task Test ---")

        -- Test 1: Safe wake up jfork task after completion
        local jfork_try_counter = 0
        local jfork_try_ehdl, jfork_try_task_id = jfork {
            jfork_try_task = function()
                jfork_try_counter = jfork_try_counter + 1
                clock:posedge(2)
            end
        }

        join(jfork_try_ehdl)
        local counter_after_first_try = jfork_try_counter
        assert(counter_after_first_try == 1, "jfork task should run once")

        clock:posedge(3)
        scheduler:try_wakeup_task(jfork_try_task_id)
        clock:posedge(5)
        local counter_after_try_wakeup = jfork_try_counter
        assert(counter_after_try_wakeup == 2, "jfork task should run again after try_wakeup")
        print("✓ jfork task try_wakeup test passed")

        -- Test 2: Safe wake up append_task after completion
        local try_counter = 0
        local try_task_id = scheduler:append_task(nil, "try_task", function()
            try_counter = try_counter + 1
        end, true)

        clock:posedge(5)
        assert(try_counter == 1, "Task should run and finish")

        clock:posedge(3)
        scheduler:try_wakeup_task(try_task_id)
        clock:posedge(5)
        assert(try_counter == 2, "Task should run again after try_wakeup")
        print("✓ Finished task try_wakeup test passed")

        -- Test 3: Safe behavior on running task
        local running_counter = 0
        local running_task_id = scheduler:append_task(nil, "running_task", function()
            for i = 1, 6 do
                running_counter = running_counter + 1
                clock:posedge()
            end
        end, true)

        clock:posedge(2)
        local counter_before_try = running_counter
        scheduler:try_wakeup_task(running_task_id)
        clock:posedge(8)
        local counter_after_complete = running_counter
        assert(counter_after_complete == 6, "Task should complete normally without interference")
        print("✓ Safe behavior on running task test passed")

        -- Test 4: Error - try_wakeup unregistered task
        local success2, error_msg2 = pcall(function()
            scheduler:try_wakeup_task(88888)
        end)
        assert(not success2, "Should fail when try_wakeup unregistered task")
        assert(string.find(error_msg2, "Task not registered"), "Should mention task not registered")
        print("✓ Unregistered task try_wakeup error test passed")

        print("✓ try_wakeup_task test passed")

        --==============================================================================
        -- Test Complete
        --==============================================================================

        print("\n=== All Verilua Scheduler Tests Passed ===")

        -- Finish simulation
        sim.finish()
    end
}
