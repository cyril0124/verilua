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

assert(
    scheduler:get_curr_task_id() == scheduler.NULL_TASK_ID,
    "Expected scheduler.curr_task_id to be NULL_TASK_ID when not inside a task"
)

--==============================================================================
-- All tests must be in one fork because Verilua entry point is fork
fork {
    main_task = function()
        assert(
            scheduler:get_curr_task_id() ~= scheduler.NULL_TASK_ID,
            "Expected scheduler.curr_task_id to be non-NULL_TASK_ID at any point inside a task"
        )
        assert(
            scheduler:get_curr_task_name() == "main_task",
            "Expected current task name to be 'main_task'"
        )

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
        -- 1.5. Get Running Tasks Test
        --==============================================================================

        print("\n--- 1.5. Get Running Tasks Test ---")

        -- Create multiple test tasks
        local test_task_1_id = scheduler:append_task(nil, "test_task_1", function()
            -- Task body
        end)

        local test_task_2_id = scheduler:append_task(nil, "test_task_2", function()
            -- Task body
        end)

        local test_task_3_id = scheduler:append_task(nil, "test_task_3", function()
            -- Task body
        end)

        -- Get all running tasks
        local running_tasks = scheduler:get_running_tasks()

        -- Verify return type and content
        assert(type(running_tasks) == "table", "get_running_tasks should return a table")

        -- Count running tasks accurately (using pairs since task IDs may not be consecutive)
        local running_task_count = 0
        ---@diagnostic disable-next-line: access-invisible
        for _ in pairs(scheduler.task_name_map_running) do
            running_task_count = running_task_count + 1
        end

        -- Count returned tasks
        local returned_task_count = 0
        for _ in ipairs(running_tasks) do
            returned_task_count = returned_task_count + 1
        end

        -- Verify task count matches
        assert(returned_task_count == running_task_count,
            string.format("Returned task count (%d) should match running task count (%d)",
                returned_task_count, running_task_count))

        -- Verify we have at least our 3 test tasks
        assert(returned_task_count >= 3,
            string.format("Should have at least 3 running tasks, got %d", returned_task_count))

        -- Verify task structure
        local task_found = {}
        for _, task_info in ipairs(running_tasks) do
            assert(type(task_info) == "table", "Each task should be a table")
            assert(type(task_info.id) == "number", "Task id should be a number")
            assert(type(task_info.name) == "string", "Task name should be a string")

            -- Check if our test tasks are in the list
            if task_info.id == test_task_1_id then
                assert(task_info.name == "test_task_1", "Task 1 name mismatch")
                task_found[1] = true
            elseif task_info.id == test_task_2_id then
                assert(task_info.name == "test_task_2", "Task 2 name mismatch")
                task_found[2] = true
            elseif task_info.id == test_task_3_id then
                assert(task_info.name == "test_task_3", "Task 3 name mismatch")
                task_found[3] = true
            end
        end

        assert(task_found[1], "Task 1 should be in the running tasks list")
        assert(task_found[2], "Task 2 should be in the running tasks list")
        assert(task_found[3], "Task 3 should be in the running tasks list")

        print("✓ Get running tasks test passed")

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

        -- Test 4.3: join_any returns the first completed handle
        local any_task1_done = false
        local any_task2_done = false

        local any_ehdl1 = jfork {
            fast_task = function()
                clock:posedge(2)
                any_task1_done = true
            end
        }

        local any_ehdl2 = jfork {
            slow_task = function()
                clock:posedge(100)
                any_task2_done = true
            end
        }

        local first = join_any(any_ehdl1, any_ehdl2)
        assert(first == any_ehdl1, "join_any should return the faster task's handle")
        assert(any_task1_done == true, "fast task should be done")
        assert(any_task2_done == false, "slow task should NOT be done yet")
        print("✓ join_any returns first completed handle")

        -- Test 4.4: join_any with already-finished handle
        local already_done_ehdl = jfork {
            instant_task = function()
                -- finishes immediately (no posedge wait)
            end
        }
        clock:posedge(1) -- let it run

        local pending_ehdl = jfork {
            pending_task = function()
                clock:posedge(50)
            end
        }

        local first2 = join_any(already_done_ehdl, pending_ehdl)
        assert(first2 == already_done_ehdl, "join_any should return already-finished handle immediately")
        print("✓ join_any with already-finished handle")

        -- Clean up: wait for remaining tasks to avoid dangling
        join(any_ehdl2)
        join(pending_ehdl)

        print("✓ All join_any tests passed")

        --==============================================================================
        -- 4.5. task_group Test
        --==============================================================================

        print("\n--- 4.5. task_group Test ---")

        -- Test 4.5.1: Basic task_group auto-joins all tasks
        local tg_task1_done = false
        local tg_task2_done = false
        local tg_task3_done = false

        task_group(function(tg)
            tg:fork { tg_task1 = function()
                clock:posedge(3)
                tg_task1_done = true
            end }
            tg:fork { tg_task2 = function()
                clock:posedge(5)
                tg_task2_done = true
            end }
            tg:fork { tg_task3 = function()
                clock:posedge(1)
                tg_task3_done = true
            end }
        end)

        -- After task_group returns, ALL tasks must be finished
        assert(tg_task1_done, "task_group: task1 should be done")
        assert(tg_task2_done, "task_group: task2 should be done")
        assert(tg_task3_done, "task_group: task3 should be done")
        print("✓ task_group auto-joins all tasks")

        -- Test 4.5.2: task_group with explicit join_any inside body
        local tg_fast_done = false
        local tg_slow_done = false
        local tg_any_result = nil

        task_group(function(tg)
            local fast_ehdl = tg:fork { tg_fast = function()
                clock:posedge(2)
                tg_fast_done = true
            end }
            tg:fork { tg_slow = function()
                clock:posedge(50)
                tg_slow_done = true
            end }
            tg_any_result = tg:join_any()
            -- After join_any, fast should be done but slow should not
            assert(tg_fast_done, "task_group join_any: fast task should be done")
            assert(not tg_slow_done, "task_group join_any: slow task should NOT be done yet")
            assert(tg_any_result == fast_ehdl, "task_group join_any: should return fast handle")
        end)

        -- After task_group scope exits, even the slow task is joined
        assert(tg_slow_done, "task_group: slow task should be done after scope exit")
        print("✓ task_group with join_any inside body")

        -- Test 4.5.3: task_group with explicit join_all inside body
        local tg_all_a_done = false
        local tg_all_b_done = false

        task_group(function(tg)
            tg:fork { tg_all_a = function()
                clock:posedge(4)
                tg_all_a_done = true
            end }
            tg:fork { tg_all_b = function()
                clock:posedge(6)
                tg_all_b_done = true
            end }
            tg:join_all()
            -- Both should be done after explicit join_all
            assert(tg_all_a_done, "task_group explicit join_all: a should be done")
            assert(tg_all_b_done, "task_group explicit join_all: b should be done")
        end)
        print("✓ task_group with explicit join_all")

        -- Test 4.5.4: empty task_group (no tasks forked)
        local empty_tg_reached_end = false
        task_group(function(tg)
            -- no forks
            empty_tg_reached_end = true
        end)
        assert(empty_tg_reached_end, "empty task_group should complete immediately")
        print("✓ empty task_group completes immediately")

        -- Test 4.5.5: tg:fork with multiple tasks in one call
        local tg_multi_a_done = false
        local tg_multi_b_done = false
        local tg_multi_c_done = false

        task_group(function(tg)
            tg:fork {
                tg_multi_a = function()
                    clock:posedge(2)
                    tg_multi_a_done = true
                end,
                tg_multi_b = function()
                    clock:posedge(4)
                    tg_multi_b_done = true
                end,
                tg_multi_c = function()
                    clock:posedge(6)
                    tg_multi_c_done = true
                end,
            }
        end)

        assert(tg_multi_a_done, "task_group multi-fork: a should be done")
        assert(tg_multi_b_done, "task_group multi-fork: b should be done")
        assert(tg_multi_c_done, "task_group multi-fork: c should be done")
        print("✓ task_group with multiple tasks in one tg:fork call")

        -- Test 4.5.6: nested task_group
        local nested_outer_done = false
        local nested_inner1_done = false
        local nested_inner2_done = false

        task_group(function(outer)
            outer:fork { nested_outer_task = function()
                task_group(function(inner)
                    inner:fork { nested_inner1 = function()
                        clock:posedge(3)
                        nested_inner1_done = true
                    end }
                    inner:fork { nested_inner2 = function()
                        clock:posedge(5)
                        nested_inner2_done = true
                    end }
                end)
                -- inner group is fully joined here
                assert(nested_inner1_done, "nested: inner1 should be done")
                assert(nested_inner2_done, "nested: inner2 should be done")
                nested_outer_done = true
            end }
        end)

        assert(nested_outer_done, "nested: outer task should be done")
        assert(nested_inner1_done, "nested: inner1 should be done after outer")
        assert(nested_inner2_done, "nested: inner2 should be done after outer")
        print("✓ nested task_group")

        -- Test 4.5.7: task that finishes immediately (no yield)
        local tg_instant_done = false
        local tg_instant_with_yield_done = false

        task_group(function(tg)
            tg:fork { tg_instant = function()
                -- No yield at all, finishes immediately
                tg_instant_done = true
            end }
            tg:fork { tg_instant_with_yield = function()
                clock:posedge(3)
                tg_instant_with_yield_done = true
            end }
        end)

        assert(tg_instant_done, "task_group: instant task should be done")
        assert(tg_instant_with_yield_done, "task_group: yielding task should also be done")
        print("✓ task_group with instantly-finishing task")

        -- Test 4.5.8: phased execution (fork after join_all)
        local tg_phase1_done = false
        local tg_phase2_done = false

        task_group(function(tg)
            tg:fork { tg_phase1 = function()
                clock:posedge(3)
                tg_phase1_done = true
            end }

            tg:join_all() -- wait for phase 1
            assert(tg_phase1_done, "phase1 should be done after explicit join_all")

            -- Fork new tasks after join_all
            tg:fork { tg_phase2 = function()
                clock:posedge(5)
                tg_phase2_done = true
            end }
        end)

        assert(tg_phase2_done, "task_group: phase2 should be done after scope exit")
        print("✓ task_group phased execution (fork after join_all)")

        -- Test 4.5.9: join_any returns nil when all tasks already finished
        task_group(function(tg)
            tg:fork { tg_done_early = function()
                -- finishes immediately
            end }
            clock:posedge(1) -- let it complete

            local result = tg:join_any()
            assert(result == nil, "join_any should return nil when all tasks already finished")
        end)
        print("✓ task_group join_any returns nil when all done")

        -- Test 4.5.10: join_any called twice returns different handles
        task_group(function(tg)
            local e1 = tg:fork { tg_seq_a = function()
                clock:posedge(2)
            end }
            local e2 = tg:fork { tg_seq_b = function()
                clock:posedge(5)
            end }

            local first = tg:join_any()
            assert(first == e1, "first join_any should return faster task")

            local second = tg:join_any()
            assert(second == e2, "second join_any should return the remaining task")

            -- Now all done, should return nil
            local third = tg:join_any()
            assert(third == nil, "third join_any should return nil")
        end)
        print("✓ task_group join_any called multiple times")

        -- Test 4.5.11: anonymous tasks (numeric keys)
        local tg_anon1_done = false
        local tg_anon2_done = false

        task_group(function(tg)
            tg:fork {
                function()
                    clock:posedge(2)
                    tg_anon1_done = true
                end,
                function()
                    clock:posedge(4)
                    tg_anon2_done = true
                end,
            }
        end)

        assert(tg_anon1_done, "task_group: anonymous task 1 should be done")
        assert(tg_anon2_done, "task_group: anonymous task 2 should be done")
        print("✓ task_group with anonymous (numeric key) tasks")

        -- Test 4.5.12: task error propagates (not silently swallowed)
        local tg_error_ok = pcall(function()
            task_group(function(tg)
                tg:fork { tg_error_task = function()
                    error("intentional test error")
                end }
            end)
        end)
        assert(not tg_error_ok, "task_group should propagate task errors")
        print("✓ task_group propagates task errors")

        print("✓ All task_group tests passed")

        --==============================================================================
        -- 5. Remove task test (using jfork returned task_id)
        --==============================================================================

        print("\n--- 5. Remove task test ---")

        local scheduler = require "verilua.scheduler.LuaScheduler"

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

        -- Test 6: Remove task multiple times
        do
            local e = (""):ehdl()
            local v = 0
            local func = function()
                e:wait()
                v = v + 1

                while true do
                    e:wait()
                end
            end

            local tid = scheduler.NULL_TASK_ID
            tid = scheduler:append_task(nil, "test", func, true)

            scheduler:remove_task(tid)

            tid = scheduler:append_task(tid, "test", func, true)

            scheduler:remove_task(tid)

            assert(v == 0)
            e:send()
            assert(v == 0)

            await_time(0)

            assert(v == 0)
        end

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
        assert(error_msg_running and string.find(error_msg_running, "Task already running"),
            "Should mention task already running")

        join(running_wakeup_ehdl)
        print("✓ Running task wakeup error test passed")

        -- Test 4: Error - wakeup unregistered task
        local success, error_msg = pcall(function()
            scheduler:wakeup_task(99999)
        end)
        assert(not success, "Should fail when waking up unregistered task")
        assert(error_msg and string.find(error_msg, "Task not registered"), "Should mention task not registered")
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
        assert(error_msg2 and string.find(error_msg2, "Task not registered"),
            "Should mention task not registered")
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
