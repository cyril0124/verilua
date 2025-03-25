local env = require "env"

local test_value_incr = env.register_test_case "test value incr" {
    function ()
        env.dut_reset()

        env.posedge()
            dut.incr:set(1)

        env.posedge()
            dut.value:expect(0)

        env.posedge()
            dut.value:expect(1)
            dut.incr:set(0)

        env.posedge()
            dut.value:expect(2)

        env.posedge()
            dut.value:expect(2)
    end
}

local test_value_no_incr = env.register_test_case "test value no incr" {
    function ()
        env.dut_reset()

        env.posedge()
            dut.incr:set(0)

        env.expect_not_happen_until(1000, function ()
            return dut.value:is_not(0)
        end)
    end
}

local test_value_overflow = env.register_test_case "test value overflow" {
    function ()
        env.dut_reset()

        env.posedge()
            dut.incr:set(1)

        env.expect_happen_until(300, function()
            return dut.value:get() == 255
        end)
    end
}

fork {
    function ()
        env.dut_reset()

        test_value_incr()
        test_value_no_incr()
        test_value_overflow()

        env.TEST_SUCCESS()
        sim.finish()
    end
}