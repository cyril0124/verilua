--- You can use `fork` to create multiple tasks.
--- Each task is a function with no arguments.
fork {
    function()
        print("hello from first `fork`")

        --- Create a `CallableHDL`(chdl) using `ProxyTableHandle`
        local clock = dut.clock:chdl()
        --- `CallableHDL` has a `__type` field to indicate its type
        assert(clock.__type == "CallableHDL")

        --- Create a `CallableHDL` using string literal
        --- `clock` and `clock_1` are the same
        --- The top-level of the verilua testbench is `tb_top` by default, where `clock` is the internal signal of the `tb_top` not our DUT
        local clock_1 = ("tb_top.clock"):chdl()

        --- `reset` is also the internal signal of `tb_top`
        local reset = dut.reset:chdl()

        --- Set the value of the `reset` signal using `set` method
        reset:set(1)
        --- Waitting for the `posedge` event of the `clock` signal
        --- `clock` signal is managed by the `tb_top` so you dont have to generate `clock` pulses by yourself
        clock:posedge()
        reset:set(0)
        clock:posedge()

        --- The first argument of `posedge` is the number of events to wait
        clock:posedge(10)

        --- The second argument of `posedge` is a callback, which will be called when the event happens
        clock:posedge(5, function(count)
            --- Expect to call this callback 5 times
            print("repeat posedge clock 5 times, now is " .. count)
        end)

        --- Also support `negedge`
        clock:negedge()

        --- `cfg` is a pretty useful global variable, which saves some configuration information
        assert(cfg.simulator == "verilator" or cfg.simulator == "vcs" or cfg.simulator == "iverilog")
        assert(cfg.top == "tb_top")
        print("Current project directory: ", cfg.prj_dir)

        --- `cfg` also merged the configuration from the configuration settings in `xmake.lua`: `set_values("cfg.user_cfg", "./cfg.lua")`
        assert(cfg.var1 == 1)
        assert(cfg.var2 == "hello")

        --- `cfg:get_or_else` can be used to get the value of the configuration, if the configuration is not found, it will return the default value
        assert(cfg:get_or_else("var1", 4) == 1)
        assert(cfg:get_or_else("var3", "default") == "default")

        --- `cycles` is also the internal signal of `tb_top` which is a 64-bit signal containing the number of clock cycles in posedge.
        --- The value of the `cycles` signal will never be reset even if the `reset` signal is set.
        local cycles = dut.cycles:get()
        print("current cycle:", cycles)

        --- Dump the wave file
        -- sim.dump_wave()

        --- Dump the wave file with a custom file name
        -- sim.dump_wave("wave.vcd")

        --- To create a `CallaleHDL` pointing to a internal signal, you must at the `u_<dut_name>` level since the `u_<dut_name>` is auto instantiated by  `testbench_gen`.
        local internal_reg = dut.u_top.internal_reg:chdl()

        --- Dump the current value of the `CallableHDL` object, the displayed value is in hex string format
        internal_reg:dump() --- prints "[tb_top.u_top.internal_reg] => 0x11" in the console

        --- `dump` also supports `ProxyTableHandle`
        dut.u_top.internal_reg:dump()

        --- Dump the current value of the `CallableHDL` object, the returned value is a string
        --- `print(internal_reg:dump_str())` is equivalent to `internal_reg:dump()`
        local str = internal_reg:dump_str()

        --- `dump_str` also supports `ProxyTableHandle`
        local str1 = dut.u_top.internal_reg:dump_str()

        --- Read signal value from `CallableHDL` using `get` method
        local internal_reg_v = internal_reg:get()
        --- The return value of `get` method for a signal with width less than 32 is a lua number
        assert(type(internal_reg_v) == "number")

        --- Read signal value from `CallableHDL` using `get_hex_str` method
        local internal_reg_v_hex_str = internal_reg:get_hex_str()
        --- The return value of `get_hex_str` method for any signal(width of the signal don't matter) is a hex string, e.g. "123", "deadbeef"
        assert(type(internal_reg_v_hex_str) == "string")

        --- `get_bin_str` and `get_dec_str` are also supported which return a binary string and a decimal string separately
        local str2 = internal_reg:get_bin_str()
        local str3 = internal_reg:get_dec_str()

        --- Cache the `ProxyTableHandle` object for later use
        local u_top = dut.u_top
        --- `u_top.internal_reg:chdl()` is equivalent to `dut.u_top.internal_reg:chdl()`
        --- This is pretty useful when you have a deep hierarchy of signal needed to be accessed using `dut`

        --- <chdl>:get() and <chdl>:set() has different behavior in different signal width
        --- 1. width <= 32
        do
            local reg32 = u_top.reg32:chdl()
            --- The return value of `get` method for a signal with width less than or equal to 32 is a lua number
            local reg32_v = reg32:get()
            assert(type(reg32_v) == "number")
            assert(reg32_v == 32)

            --- `get_hex_str` workds on any signal width
            assert(reg32:get_hex_str() == "00000020")

            --- `<chdl>:expect(<lua number value>/<uint64_t>)` can be used to check the value of the signal,
            --- if the value is not equal to the expected value, an error will be thrown
            reg32:expect(32)

            --- `<chdl>:is(<lua number value>/<uint64_t>)` will return a boolean value indicating whether
            --- the value of the signal is equal to the expected value
            assert(reg32:is(32))

            --- `set` method accepts a lua number when the width of the signal is less than or equal to 32
            --- Notice: Typically you should not `set` a internal signal, `set` should be used on the top level IO signals.
            reg32:set(123)
        end
        --- 2. width > 32 and width <= 64
        do
            local reg64 = u_top.reg64:chdl()
            --- The return value of `get` method for a signal with width greater than 32 and less than or equal to 64 is a `uint64_t`
            --- which is a `cdata` object in lua
            local reg64_v = reg64:get()
            assert(type(reg64_v) == "cdata")
            assert(reg64_v == 0xFFFFFFFFFFFFFFFFULL)

            --- `get_hex_str` workds on any signal width
            assert(reg64:get_hex_str() == "ffffffffffffffff")

            --- `get64` method always returns a `uint64_t`
            local reg64_v2 = reg64:get64()
            assert(type(reg64_v2) == "cdata")
            assert(reg64_v2 == 0xFFFFFFFFFFFFFFFFULL)
            assert(reg64_v2 == reg64_v)
            assert(ffi.istype(ffi.new("uint64_t"), reg64_v2))

            reg64:expect(0xFFFFFFFFFFFFFFFFULL)
            assert(reg64:is(0xFFFFFFFFFFFFFFFFULL))

            --- `get` method now accepts a `force_multi_beat` argument which return a `MultiBeatData` ffi object
            --- A breif description of the `MultiBeatData` object:
            ---     - `MultiBeatData` is a `uint32_t[]` ffi object in lua
            ---     - `MultiBeatData`[0] is the beat number of the signal, each beat represents 32 bits of signal value
            ---         e.g. For signal with width 64, `MultiBeatData`[0] is 2, for signal with width 128, `MultiBeatData`[0] is 4, etc.
            ---     - In Lua, table index starts from 1, so `MultiBeatData`[1] is the first beat of the signal value,
            ---         and `MultiBeatData`[2] is the second beat of the signal value, etc.
            ---     - So you can always consider ``MultiBeatData`` as lua table of signal value, each element of the table is a 32bit lua number
            local reg64_v_tbl = reg64:get(true)
            assert(type(reg64_v_tbl) == "cdata")
            --- 0xFFFFFFFFFFFFFFFFULL can be represented in `MultiBeatData` => { 2, 0xFFFFFFFF, 0xFFFFFFFF } with index starts from 0
            assert(reg64_v_tbl[0] == 2)
            assert(reg64_v_tbl[1] == 0xFFFFFFFF)
            assert(reg64_v_tbl[2] == 0xFFFFFFFF)
            assert(ffi.istype(ffi.new("uint32_t[?]", 3) --[[@as ffi.ct*]], reg64_v_tbl))

            --- `set` method needs a lua table where each element is a 32bit lua number
            --- Because the width of the signal is 64, so we need 2 elements in the table
            reg64:set({ 1, 2 }) -- <LSB .. MSB>
            --- Value will be updated after the next simulation cycle
            clock:posedge()
            reg64_v = reg64:get()
            assert(reg64_v == 0x0000000200000001ULL)

            --- `set` has another overload which accepts a lua number/uint64_t and a `force_single_beat` argument
            reg64:set(1234, true)
            clock:posedge()
            reg64:expect(1234)

            reg64:set(0xFFFF0000FFFF0000ULL, true)
            clock:posedge()
            reg64:expect(0xFFFF0000FFFF0000ULL)
        end
        --- 3. width > 64
        do
            local reg128 = u_top.reg128:chdl()

            --- The return value of `get` method for a signal with width greater than 64 is a `MultiBeatData` ffi object
            local reg128_v = reg128:get()
            assert(type(reg128_v) == "cdata")
            assert(reg128_v[0] == 4)
            assert(reg128_v[1] == 128)
            assert(reg128_v[2] == 0)
            assert(reg128_v[3] == 0)

            --- `get64` method always returns a `uint64_t`
            local reg128_v2 = reg128:get64()
            assert(reg128_v2 == 0x0000000000000080ULL)
            assert(reg128_v2 == 128ULL)
            assert(reg128_v2 == 128)

            --- Like `reg64`, `set` method accepts a lua table where each element is a 32bit lua number
            reg128:set({ 1, 2, 3, 4 })
            clock:posedge()
            reg128_v = reg128:get()
            assert(reg128_v[0] == 4)
            assert(reg128_v[1] == 1)
            assert(reg128_v[2] == 2)
            assert(reg128_v[3] == 3)
            assert(reg128_v[4] == 4)

            --- `set` with `force_single_beat` argument accepts a lua number/uint64_t, where the uncovered bits will be set to 0
            reg128:set(0xFFFF0000FFFF0000ULL, true)
            clock:posedge()
            reg128_v = reg128:get()
            assert(reg128_v[0] == 4)
            assert(reg128_v[1] == 0xFFFF0000)
            assert(reg128_v[2] == 0xFFFF0000)
            assert(reg128_v[3] == 0x0000)
            assert(reg128_v[4] == 0x0000)

            --- `get_hex_str` workds on any signal width
            assert(reg128:get_hex_str() == "0000000000000000ffff0000ffff0000")
        end

        --- There are few ways to get bitfield from a signal value
        --- 1. using methods in `LuaUtils`
        do
            local utils = require "LuaUtils"
            local v = tonumber(0b00001010) --[[@as integer]]
            assert(utils.bitfield32(1, 1, v) == 1)
            assert(utils.bitfield32(1, 3, v) == 5)

            local v2 = 0xFFFFFFFF00000000ULL
            assert(utils.bitfield64(32, 63, v2) == 0xFFFFFFFFULL)
        end
        --- 2. using `BitVec`
        do
            local BitVec = require "BitVec"
            local v = 0xFF01
            local bv = BitVec(v, 16)
            assert(bv:get_bitfield(0, 0) == 1)
            assert(bv:get_bitfield(8, 15) == 0xff)

            local reg128 = dut.u_top.reg128:chdl()
            reg128:set(0x123, true)
            clock:posedge()

            --- `<chdl>:get_bitvec()` will return a `BitVec` object
            local bv128 = reg128:get_bitvec()
            assert(bv128:get_bitfield(0, 3) == 3)
            assert(reg128:get_bitvec():get_bitfield(0, 3) == 3)
        end

        --- If you dont care about the performance, a auto-type-based value assignment is also supported
        do
            --- `<chdl>.value` is a special field for auto-type-based value assignment
            --- Any value can be assigned to `<chdl>.value` and the value will be assigned to the signal correctly without concerning the signal width
            --- This approach is very handy when you dont care about the performance
            local reg128 = dut.u_top.reg128:chdl()
            reg128.value = 1
            clock:posedge()
            reg128:expect_hex_str("1")

            reg128.value = "0x123"
            clock:posedge()
            reg128:expect_hex_str("123")

            reg128.value = 0xFFFFFFFFFFFFFFFFULL
            clock:posedge()
            reg128:expect_hex_str("ffffffffffffffff")

            reg128.value = { 0x12345, 0, 0, 0 }
            clock:posedge()
            reg128:expect_hex_str("12345")
        end

        --- Also there has a auto-type-based comparison support
        do
            local reg128 = dut.u_top.reg128:chdl()
            reg128.value = 0x12345
            clock:posedge()
            --- A global function `v` is provided for auto-type-based value assignment
            assert(reg128 == v(0x12345))
            assert(reg128 ~= v(0x12346))
            assert(reg128 == v(0x12345ULL))
            assert(reg128 == v({ 0x12345, 0, 0, 0 }))
            assert(reg128 ~= v({ 0x12346, 0, 0, 0 }))
            assert(reg128 == v("0x12345"))
            assert(reg128 ~= v("0x12346"))
        end

        local u_sub = dut.u_top.u_sub

        --- `<ProxyTableHandle>:tostring()` will return the full path(hierarchical path) of the signal
        assert(u_sub:tostring() == "tb_top.u_top.u_sub")
        assert(dut:tostring() == "tb_top")
        --- Also support `tostring`
        assert(tostring(u_sub) == "tb_top.u_top.u_sub")
        assert(tostring(dut) == "tb_top")

        --- Create a bundle of signals by using `Bundle`(bdl) data structure
        --- `bdl` will contains the following signals:
        ---   - tb_top.u_top.u_sub.some_prefix_valid
        ---   - tb_top.u_top.u_sub.some_prefix_ready
        ---   - tb_top.u_top.u_sub.some_prefix_bits_data_0
        ---   - tb_top.u_top.u_sub.some_prefix_bits_data_1
        ---   - tb_top.u_top.u_sub.some_prefix_bits_data_2
        --- The signal matching rule is:
        --- 1. is_decoupled = true
        ---     <hier>.<prefix>_bits_<signal_name>
        --- 2. is_decoupled = false
        ---     <hier>.<prefix>_<signal_name>
        local bdl = ([[
            | valid
            | ready
            | data_0
            | data_1
            | data_2
        ]]):bdl {
            hier = u_sub:tostring(),
            prefix = "some_prefix_",
            is_decoupled = true, -- default is true, which means the bundle is decoupled(valid/ready handshake), a `valid` signal is required
        }
        assert(bdl.__type == "Bundle")
        assert(bdl.valid.__type == "CallableHDL")
        assert(bdl.bits.data_0.__type == "CallableHDL")
        assert(bdl.bits.data_1.__type == "CallableHDL")
        assert(bdl.bits.data_2.__type == "CallableHDL")

        local bdl_decl_str = [[
            | valid
            | ready
            | bits_data_0
            | bits_data_1
            | bits_data_2
        ]]
        local bdl2 = bdl_decl_str:bdl {
            hier = u_sub:tostring(),
            prefix = "some_prefix_",
            is_decoupled = false,
        }
        assert(bdl2.__type == "Bundle")
        assert(bdl2.valid.__type == "CallableHDL")
        assert(bdl2.bits_data_0.__type == "CallableHDL")
        assert(bdl2.bits_data_1.__type == "CallableHDL")
        assert(bdl2.bits_data_2.__type == "CallableHDL")

        --- Create an `AliasBundle`(abdl)
        --- Signals in the declaration string follow by `=>` are alias names
        local abdl = ([[
            | valid => vld
            | ready
            | bits_data_0 => d0
            | bits_data_1 => d1
            | bits_data_2
        ]]):abdl {
            hier = u_sub:tostring(),
            prefix = "some_prefix_"
        }
        assert(abdl.__type == "AliasBundle")
        assert(abdl.vld.__type == "CallableHDL")
        assert(abdl.ready.__type == "CallableHDL")
        assert(abdl.d0.__type == "CallableHDL")
        assert(abdl.d1.__type == "CallableHDL")
        assert(abdl.bits_data_2.__type == "CallableHDL")

        --- `<ProxyTableHandle>:with_prefix(<prefix_name>)` allows you to create a new `ProxyTableHandle` object with a prefix string
        --- The prefix string will be appended to the hierarchical path of the signal
        local u_sub_with_prefix = dut.u_top.u_sub:with_prefix("some_prefix_")
        assert(u_sub_with_prefix.valid:tostring() == "tb_top.u_top.u_sub.some_prefix_valid")
        assert(u_sub_with_prefix.ready:tostring() == "tb_top.u_top.u_sub.some_prefix_ready")
        assert(u_sub_with_prefix.bits_data_0:tostring() == "tb_top.u_top.u_sub.some_prefix_bits_data_0")
        assert(u_sub_with_prefix.bits_data_1:tostring() == "tb_top.u_top.u_sub.some_prefix_bits_data_1")
        assert(u_sub_with_prefix.bits_data_2:tostring() == "tb_top.u_top.u_sub.some_prefix_bits_data_2")

        --- If you don't want to specify the signal string, you can use `<ProxyTableHandle>:auto_bundle(...)` to create a bundle of signals
        --- which matches the provided rules
        local auto_bdl = u_sub:auto_bundle {
            prefix = "some_prefix_"
        }
        assert(auto_bdl.__type == "Bundle")
        assert(auto_bdl.valid.__type == "CallableHDL")
        assert(auto_bdl.ready.__type == "CallableHDL")
        assert(auto_bdl.bits_data_0.__type == "CallableHDL")
        assert(auto_bdl.bits_data_1.__type == "CallableHDL")
        assert(auto_bdl.bits_data_2.__type == "CallableHDL")

        local auto_bdl2 = u_sub:auto_bundle {
            startswith = "some_prefix",
        }

        assert(auto_bdl2.some_prefix_valid.__type == "CallableHDL")
        assert(auto_bdl2.some_prefix_ready.__type == "CallableHDL")
        assert(auto_bdl2.some_prefix_bits_data_0.__type == "CallableHDL")
        assert(auto_bdl2.some_prefix_bits_data_1.__type == "CallableHDL")
        assert(auto_bdl2.some_prefix_bits_data_2.__type == "CallableHDL")

        --- Combine with other rules
        local auto_bdl2 = u_sub:auto_bundle {
            startswith = "some_prefix",
            wildmatch = "*_data_*"
        }
        assert(auto_bdl2.some_prefix_valid == nil)
        assert(auto_bdl2.some_prefix_bits_data_0.__type == "CallableHDL")
        assert(auto_bdl2.some_prefix_bits_data_1.__type == "CallableHDL")
        assert(auto_bdl2.some_prefix_bits_data_2.__type == "CallableHDL")

        --- Sometimes you may want to detect if a specific signal exists, you can use the `vpiml` module
        local vpiml = require "vpiml"
        --- `vpiml_handle_by_name_safe` will return -1 if the signal doesn't exist
        local ret = vpiml.vpiml_handle_by_name_safe(dut.u_top.some_non_existent_signal:tostring())
        assert(ret == -1)
        ret = vpiml.vpiml_handle_by_name("tb_top.u_top.u_sub.some_prefix_valid")
        assert(ret ~= -1)

        --- You can use the following methods to iterate some regular signals because `ProxyHandleTable` is also a lua table
        for i = 0, 2 do
            local chdl = dut.u_top.u_sub["some_prefix_bits_data_" .. i]:chdl()
            assert(chdl.__type == "CallableHDL")
        end

        local a = 123

        --- `fork` can be used anywhere
        fork {
            function()
                print("hello from inner `fork`")
                clock:posedge()
                a = a + 1
            end
        }

        --- A `fork` created task is running in the background
        assert(a == 123)

        clock:posedge()
        assert(a == 124)

        --- To wait for a spcific task to finish, you can use `jfork` combined with `join`
        local e = jfork {
            --- Notice: `jfork` only accept a single function as its argument
            function()
                clock:posedge()
                a = a + 1
            end
        }
        join(e)
        assert(a == 125)

        --- `join` can wait for multiple tasks to finish
        local e1 = jfork {
            function()
                clock:posedge()
                a = a + 1
            end
        }
        local e2 = jfork {
            function()
                clock:posedge(20)
                a = a + 1
            end
        }
        join({ e1, e2 })
        assert(a == 127)

        --- A running task can be removed even if it is not finished
        --- To do so, you need to get the task id from `jfork` and pass it to `scheduler:remove_task(<task_id>)` when you want to remove it
        local e3, task_id = jfork { --- The second return value is the task id
            function()
                clock:posedge(100, function(c)
                    a = a + 1
                end)
            end
        }
        clock:posedge(10)
        scheduler:remove_task(task_id)
        assert(a == 138)
        clock:posedge(10)
        assert(a == 138) --- `a` is not changed since the task is removed

        --- Finish the simulation, you must call this function manually otherwise the simulation will be stuck and never finish
        sim.finish()
    end,

    --- You can also create tasks with name.
    task_with_name = function()
        --- Task will be removed from scheduler if it runs to the end.
    end,

    --- Other tasks...
}

--- `fork` can be used for multiple times.
fork {
    function()
        print("hello from another `fork`")
    end
}


--- You can use `initial` to create tasks which will be executed at the start of simulation.
initial {
    function()
        print("hello from initial task")
    end,

    --- `initial` can include multiple tasks.
    function()
        local a = 1
        print(a + 1)
    end
}

--- `initial` can be used for multiple times.
initial {
    function()
        print("hello from another initial task")
    end
}

--- You can use `final` to create tasks which will be executed at the end of simulation.
--- `final` can be used for multiple times and can include multiple tasks in one `final` block just like `initial`.
final {
    function()
        print("hello from final task")
    end
}
