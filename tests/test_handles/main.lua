---@diagnostic disable: unnecessary-assert, unnecessary-if

local clock = dut.clock:chdl()
local is_verilator = cfg.simulator == "verilator"

local function test_section(name)
    print(string.format("[TEST] %s", name))
end

fork {
    function()
        -- Wait for initialization to settle
        clock:posedge(5)

        -- ========================================================================
        -- Test: LuaCallableHDL - Basic operations
        -- ========================================================================
        test_section("CallableHDL - Basic operations")

        local data_0 = ("tb_top.u_top.data_0"):chdl()
        assert(data_0.__type == "CallableHDL")
        assert(data_0:get_width() == 8)

        local data_2 = ("tb_top.u_top.data_2"):chdl()

        -- get/set operations (use set_imm for immediate effect)
        data_0:set_imm(0x55)
        assert(data_0:get() == 0x55)

        -- get64 for 64-bit signal
        local wide_64 = ("tb_top.u_top.wide_signal_64"):chdl()
        local val64 = wide_64:get64()
        assert(type(val64) == "cdata" or type(val64) == "number")

        -- get_bitvec
        local bv = data_0:get_bitvec()
        assert(bv.__type == "BitVec")

        -- Test :hdl() method
        local data_1_hdl = ("tb_top.u_top.data_1"):hdl()
        assert(data_1_hdl ~= -1)
        local data_1 = ("tb_top.u_top.data_1"):chdl(data_1_hdl)
        assert(data_1.__type == "CallableHDL")

        -- ========================================================================
        -- Test: CallableHDL - String operations
        -- ========================================================================
        test_section("CallableHDL - String operations")

        -- get_hex_str, get_bin_str, get_dec_str (use set_imm for immediate effect)
        data_2:set_imm(0xAB)
        local hex_str = data_2:get_hex_str()
        assert(hex_str == "ab")
        local bin_str = data_2:get_bin_str()
        assert(#bin_str == 8)
        local dec_str = data_2:get_dec_str()
        assert(dec_str == "171")

        -- set_hex_str, set_bin_str, set_dec_str
        data_2:set_hex_str("42")
        clock:posedge() -- Wait for set to take effect
        assert(data_2:get() == 0x42)
        data_2:set_bin_str("00001111")
        clock:posedge()
        assert(data_2:get() == 0x0F)
        data_2:set_dec_str("100")
        clock:posedge()
        assert(data_2:get() == 100)

        -- ========================================================================
        -- Test: CallableHDL - Array operations
        -- ========================================================================
        test_section("CallableHDL - Array operations")

        local arr = ("tb_top.u_top.array_signal"):chdl()
        assert(arr.is_array == true)
        assert(arr.array_size == 4)

        -- Test at() method for accessing array elements
        local elem0 = arr:at(0)
        assert(elem0.__type == "CallableHDL")
        -- Initial value from RTL
        assert(elem0:get() == 0x10)

        local elem1 = arr:at(1)
        assert(elem1.__type == "CallableHDL")
        assert(elem1:get() == 0x20)

        -- Test index-based operations (use regular set to demonstrate non-imm usage)
        arr:set_index(0, 0x55)
        clock:posedge() -- Wait for set to take effect
        assert(arr:get_index(0) == 0x55)
        -- Note: elem0 is a separate CallableHDL, re-fetch to verify
        local elem0_updated = arr:at(0)
        assert(elem0_updated:get() == 0x55)

        -- Test set_index_all
        arr:set_index_all({ 0xAA, 0xBB, 0xCC, 0xDD })
        clock:posedge() -- Wait for set to take effect
        assert(arr:get_index(0) == 0xAA)
        assert(arr:get_index(1) == 0xBB)
        assert(arr:get_index(2) == 0xCC)
        assert(arr:get_index(3) == 0xDD)

        -- Verify at() method reflects the updated values
        assert(arr:at(0):get() == 0xAA)
        assert(arr:at(1):get() == 0xBB)
        assert(arr:at(3):get() == 0xDD)

        local all_vals = arr:get_index_all()
        assert(#all_vals == 4)
        assert(all_vals[1] == 0xAA)
        assert(all_vals[2] == 0xBB)
        assert(all_vals[3] == 0xCC)
        assert(all_vals[4] == 0xDD)

        -- ========================================================================
        -- Test: CallableHDL - Edge waiting operations
        -- ========================================================================
        test_section("CallableHDL - Edge waiting operations")

        clock:posedge()
        clock:posedge(3)
        clock:negedge()
        clock:negedge(2)

        -- posedge_until
        local counter = 0
        local result = clock:posedge_until(10, function(c)
            counter = counter + 1
            return counter >= 3
        end)
        assert(result == true)
        assert(counter == 3)

        -- negedge_until
        counter = 0
        result = clock:negedge_until(10, function(c)
            counter = counter + 1
            return counter >= 2
        end)
        assert(result == true)
        assert(counter == 2)

        -- ========================================================================
        -- Test: CallableHDL - Expect operations
        -- ========================================================================
        test_section("CallableHDL - Expect operations")

        -- Use a non-auto-incrementing signal for testing (use set_imm for immediate effect)
        local data_2 = ("tb_top.u_top.data_2"):chdl()
        data_2:set_imm(0x42)
        data_2:expect(0x42)
        data_2:expect_not(0x43)
        data_2:expect_hex_str("42")
        data_2:expect_not_hex_str("43")
        data_2:expect_dec_str("66")
        data_2:expect_not_dec_str("67")

        -- is/is_not operations
        assert(data_2:is(0x42) == true)
        assert(data_2:is_not(0x43) == true)
        assert(data_2:is_hex_str("42") == true)
        assert(data_2:is_dec_str("66") == true)

        -- ========================================================================
        -- Test: CallableHDL - Dump operations
        -- ========================================================================
        test_section("CallableHDL - Dump operations")

        data_0:set_imm(0xAB)
        local dump_str = data_0:dump_str()
        assert(type(dump_str) == "string")
        -- Check exact golden string format: "[tb_top.u_top.data_0] => 0xab"
        assert(dump_str == "[tb_top.u_top.data_0] => 0xab", "Got: " .. dump_str)

        -- ========================================================================
        -- Test: CallableHDL - Shuffled range operations
        -- ========================================================================
        test_section("CallableHDL - Shuffled range operations")

        data_0:shuffled_range_u32({ 10, 20, 30 })
        -- Verify all values in the shuffled range are encountered
        local seen_values = {}
        for i = 1, 100 do
            data_0:set_imm_shuffled()
            local val = data_0:get()
            assert(val == 10 or val == 20 or val == 30, "Invalid shuffled value: " .. val)
            seen_values[val] = true
        end
        -- Ensure all three values were seen at least once
        assert(seen_values[10] and seen_values[20] and seen_values[30], "Not all shuffled values were encountered")
        data_0:reset_shuffled_range()

        -- ========================================================================
        -- Test: fake_chdl
        -- ========================================================================
        test_section("fake_chdl")

        local fake_counter = 0
        local fake_signal = ("tb_top.u_top.fake_signal"):fake_chdl {
            get = function(self)
                return fake_counter
            end,
            set = function(self, value)
                fake_counter = value
            end,
            get_width = function(self)
                return 8
            end
        }

        assert(fake_signal.__type == "CallableHDL")
        assert(fake_signal:get() == 0)
        fake_signal:set(100)
        assert(fake_signal:get() == 100)
        assert(fake_signal:get_width() == 8)

        -- ========================================================================
        -- Test: LuaBundle - Decoupled bundle
        -- ========================================================================
        test_section("Bundle - Decoupled")

        local bdl1 = ("valid | ready | field1 | field2 | field3"):bdl {
            hier = "tb_top.u_top",
            is_decoupled = true
        }
        assert(bdl1.__type == "Bundle")
        assert(bdl1.valid.__type == "CallableHDL")
        assert(bdl1.ready.__type == "CallableHDL")
        assert(bdl1.bits.field1.__type == "CallableHDL")
        assert(bdl1.bits.field2.__type == "CallableHDL")
        assert(bdl1.bits.field3.__type == "CallableHDL")

        -- Test fire() method (use regular set to demonstrate non-imm usage)
        bdl1.valid:set(0)
        bdl1.ready:set(0)
        clock:posedge()
        assert(bdl1:fire() == false)
        bdl1.valid:set(1)
        clock:posedge()
        assert(bdl1:fire() == false)
        bdl1.ready:set(1)
        clock:posedge()
        assert(bdl1:fire() == true)
        bdl1.valid:set(0)
        bdl1.ready:set(0)
        clock:posedge()

        -- Bundle with prefix
        local bdl2 = ("valid | ready | data | addr"):bdl {
            hier = "tb_top.u_top",
            prefix = "prefix_",
            is_decoupled = true
        }
        assert(bdl2.__type == "Bundle")
        assert(type(bdl2.bits.data:get()) == "number")

        -- ========================================================================
        -- Test: Bundle - Non-decoupled bundle
        -- ========================================================================
        test_section("Bundle - Non-decoupled")

        local bdl3 = ("data_0 | data_1 | data_2"):bdl {
            hier = "tb_top.u_top",
            prefix = "",
            is_decoupled = false
        }
        assert(bdl3.__type == "Bundle")
        assert(bdl3.data_0.__type == "CallableHDL")
        assert(bdl3.data_1.__type == "CallableHDL")
        assert(bdl3.data_2.__type == "CallableHDL")

        -- Test get_all
        local all_values = bdl3:get_all()
        assert(#all_values == 3)

        -- Test set_all
        bdl3:set_all({ 0x11, 0x22, 0x33 })
        clock:posedge()

        -- ========================================================================
        -- Test: Bundle - Optional signals (old and new syntax)
        -- ========================================================================
        test_section("Bundle - Optional signals")

        -- Old syntax: using optional_signals parameter
        local opt_bdl = ("valid | data | nonexistent"):bdl {
            hier = "tb_top.u_top",
            prefix = "opt_",
            is_decoupled = false,
            optional_signals = { "nonexistent" }
        }
        assert(opt_bdl.__type == "Bundle")
        assert(opt_bdl.valid.__type == "CallableHDL")
        assert(opt_bdl.data.__type == "CallableHDL")
        assert(opt_bdl.nonexistent == nil)

        -- New syntax: using bracket syntax [signal_name]
        local opt_bdl2 = ("valid | data | [nonexistent]"):bdl {
            hier = "tb_top.u_top",
            prefix = "opt_",
            is_decoupled = false,
        }
        assert(opt_bdl2.__type == "Bundle")
        assert(opt_bdl2.valid.__type == "CallableHDL")
        assert(opt_bdl2.data.__type == "CallableHDL")
        assert(opt_bdl2.nonexistent == nil)

        -- Multiple optional signals with bracket syntax
        local opt_bdl3 = ("[missing1] | valid | [missing2] | data"):bdl {
            hier = "tb_top.u_top",
            prefix = "opt_",
            is_decoupled = false,
        }
        assert(opt_bdl3.__type == "Bundle")
        assert(opt_bdl3.valid.__type == "CallableHDL")
        assert(opt_bdl3.data.__type == "CallableHDL")
        assert(opt_bdl3.missing1 == nil)
        assert(opt_bdl3.missing2 == nil)

        -- ========================================================================
        -- Test: Bundle - Dump methods
        -- ========================================================================
        test_section("Bundle - Dump methods")

        bdl3.data_0:set_imm(0x11)
        bdl3.data_1:set_imm(0x22)
        bdl3.data_2:set_imm(0x33)
        local dump_str = bdl3:dump_str()
        assert(dump_str == "data_0: 0x11 | data_1: 0x22 | data_2: 0x33", "Got: " .. dump_str)

        -- ========================================================================
        -- Test: AliasBundle - Basic operations
        -- ========================================================================
        test_section("AliasBundle - Basic operations")

        local abdl1 = ([[
            | orig_signal_0 => alias_0
            | orig_signal_1 => alias_1
            | orig_signal_2
        ]]):abdl {
            hier = "tb_top.u_top",
            prefix = ""
        }
        assert(abdl1.__type == "AliasBundle")
        assert(abdl1.alias_0.__type == "CallableHDL")
        assert(abdl1.alias_1.__type == "CallableHDL")
        assert(abdl1.orig_signal_2.__type == "CallableHDL")

        -- Verify alias bundle works
        local a0 = abdl1.alias_0:get()
        local a1 = abdl1.alias_1:get()
        assert(type(a0) == "number")
        assert(type(a1) == "number")

        -- ========================================================================
        -- Test: AliasBundle - Multiple aliases (pointing to same signal)
        -- ========================================================================
        test_section("AliasBundle - Multiple aliases")

        local abdl2 = ([[
            | orig_signal_0 => primary/secondary/tertiary
        ]]):abdl {
            hier = "tb_top.u_top",
            prefix = ""
        }

        -- Verify all aliases point to the same underlying signal via hdl comparison
        ---@diagnostic disable: access-invisible
        local primary_hdl = abdl2.primary.hdl
        local secondary_hdl = abdl2.secondary.hdl
        local tertiary_hdl = abdl2.tertiary.hdl
        ---@diagnostic enable: access-invisible
        assert(primary_hdl == secondary_hdl, "primary and secondary should have same hdl")
        assert(primary_hdl == tertiary_hdl, "primary and tertiary should have same hdl")

        -- Verify modifying via one alias affects all
        abdl2.primary:set_imm(0xAA)
        assert(abdl2.secondary:get() == 0xAA)
        assert(abdl2.tertiary:get() == 0xAA)

        -- ========================================================================
        -- Test: AliasBundle - String interpolation
        -- ========================================================================
        test_section("AliasBundle - String interpolation")

        local p_val = "prefix"
        local abdl3 = ([[
            | {p}_bits_data => data_val
            | {p}_bits_addr => addr_val
        ]]):abdl {
            hier = "tb_top.u_top",
            prefix = "",
            p = p_val,
        }
        assert(type(abdl3.data_val:get()) == "number")
        assert(type(abdl3.addr_val:get()) == "number")

        -- ========================================================================
        -- Test: AliasBundle - Optional signals (old and new syntax)
        -- ========================================================================
        test_section("AliasBundle - Optional signals")

        -- Old syntax: using optional_signals parameter
        local opt_abdl = ([[
            | orig_signal_0 => alias_0
            | nonexistent => alias_ne
        ]]):abdl {
            hier = "tb_top.u_top",
            prefix = "",
            optional_signals = { "alias_ne" }
        }
        assert(opt_abdl.__type == "AliasBundle")
        assert(opt_abdl.alias_0.__type == "CallableHDL")
        assert(opt_abdl.alias_ne == nil)

        -- New syntax: using bracket syntax [origin => alias]
        local opt_abdl2 = ([[
            | orig_signal_0 => alias_0
            | [nonexistent => alias_ne]
        ]]):abdl {
            hier = "tb_top.u_top",
            prefix = "",
        }
        assert(opt_abdl2.__type == "AliasBundle")
        assert(opt_abdl2.alias_0.__type == "CallableHDL")
        assert(opt_abdl2.alias_ne == nil)

        -- Multiple optional signals with bracket syntax
        local opt_abdl3 = ([[
            | [missing1 => miss1]
            | orig_signal_0 => alias_0
            | [missing2 => miss2/miss2_alt]
            | orig_signal_1 => alias_1
        ]]):abdl {
            hier = "tb_top.u_top",
            prefix = "",
        }
        assert(opt_abdl3.__type == "AliasBundle")
        assert(opt_abdl3.alias_0.__type == "CallableHDL")
        assert(opt_abdl3.alias_1.__type == "CallableHDL")
        assert(opt_abdl3.miss1 == nil)
        assert(opt_abdl3.miss2 == nil)
        assert(opt_abdl3.miss2_alt == nil)

        -- Optional signal without alias in abdl
        local opt_abdl4 = ([[
            | orig_signal_0 => alias_0
            | [nonexistent_signal]
        ]]):abdl {
            hier = "tb_top.u_top",
            prefix = "",
        }
        assert(opt_abdl4.__type == "AliasBundle")
        assert(opt_abdl4.alias_0.__type == "CallableHDL")
        assert(opt_abdl4.nonexistent_signal == nil)

        -- ========================================================================
        -- Test: AliasBundle - Dump methods
        -- ========================================================================
        test_section("AliasBundle - Dump methods")

        abdl1.alias_0:set(0xA0)
        abdl1.alias_1:set(0xA1)
        abdl1.orig_signal_2:set(0xA2)
        clock:posedge() -- Wait for set to take effect
        local abdl_dump = abdl1:dump_str()
        assert(
            abdl_dump ==
            "orig_signal_0 -> alias_0: 0xa0 | orig_signal_1 -> alias_1: 0xa1 | orig_signal_2 -> orig_signal_2: 0xa2",
            "Got: " .. abdl_dump)

        -- ========================================================================
        -- Test: ProxyTableHandle - Basic operations
        -- ========================================================================
        test_section("ProxyTableHandle - Basic operations")

        assert(dut.__type == "ProxyTableHandle")
        assert(dut.u_top.__type == "ProxyTableHandle")
        assert(dut.u_top.u_sub.__type == "ProxyTableHandle")

        local sub_path = dut.u_top.u_sub:tostring()
        assert(sub_path == "tb_top.u_top.u_sub")

        -- ========================================================================
        -- Test: ProxyTableHandle - Get/Set operations
        -- ========================================================================
        test_section("ProxyTableHandle - Get/Set operations")

        -- Use set_imm for immediate effect on auto-incrementing signal
        dut.u_top.data_0:set_imm(0xCC)
        assert(dut.u_top.data_0:get() == 0xCC)

        local hex_str = dut.u_top.data_wide:get_hex_str()
        assert(type(hex_str) == "string")

        -- ========================================================================
        -- Test: ProxyTableHandle - hdl() method
        -- ========================================================================
        test_section("ProxyTableHandle - hdl() method")

        local data_2_hdl = dut.u_top.data_2:hdl()
        assert(data_2_hdl ~= -1)

        -- Verify we can create chdl from the same path
        local data_2_chdl_direct = dut.u_top.data_2:chdl()
        assert(data_2_chdl_direct.__type == "CallableHDL")

        -- ========================================================================
        -- Test: ProxyTableHandle - Edge operations
        -- ========================================================================
        test_section("ProxyTableHandle - Edge operations")

        dut.clock:posedge()
        dut.clock:posedge(2)
        dut.clock:negedge()
        dut.clock:negedge(2)

        local counter = 0
        local res = dut.clock:posedge_until(10, function(c)
            counter = counter + 1
            return counter >= 2
        end)
        assert(res == true)

        -- ========================================================================
        -- Test: ProxyTableHandle - Expect operations
        -- ========================================================================
        test_section("ProxyTableHandle - Expect operations")

        -- Use a signal that doesn't auto-increment (use set_imm for immediate effect)
        dut.u_top.data_2:set_imm(0x50)
        dut.u_top.data_2:expect(0x50)
        dut.u_top.data_2:expect_not(0x51)
        dut.u_top.data_2:expect_hex_str("50")
        dut.u_top.data_2:expect_not_hex_str("51")

        assert(dut.u_top.data_2:is(0x50) == true)
        assert(dut.u_top.data_2:is_not(0x51) == true)
        assert(dut.u_top.data_2:is_hex_str("50") == true)

        -- ========================================================================
        -- Test: ProxyTableHandle - Dump operations
        -- ========================================================================
        test_section("ProxyTableHandle - Dump operations")

        -- Use regular set to demonstrate non-imm usage
        dut.u_top.data_2:set(0x50)
        clock:posedge() -- Wait for set to take effect
        local proxy_dump = dut.u_top.data_2:dump_str()
        assert(proxy_dump == "[tb_top.u_top.data_2] => 0x50", "Got: " .. proxy_dump)

        -- ========================================================================
        -- Test: ProxyTableHandle - with_prefix
        -- ========================================================================
        test_section("ProxyTableHandle - with_prefix")

        local io_in_proxy = dut.u_top:with_prefix("io_in_")
        assert(io_in_proxy.__type == "ProxyTableHandle")
        local v0 = io_in_proxy.value_0:get()
        local v1 = io_in_proxy.value_1:get()
        assert(type(v0) == "number")
        assert(type(v1) == "number")

        -- ========================================================================
        -- Test: ProxyTableHandle - chdl() conversion
        -- ========================================================================
        test_section("ProxyTableHandle - chdl() conversion")

        local internal_reg = dut.u_top.u_sub.internal_reg:chdl()
        assert(internal_reg.__type == "CallableHDL")
        local ireg_val = internal_reg:get()
        assert(type(ireg_val) == "number" or type(ireg_val) == "cdata")

        -- ========================================================================
        -- Test: ProxyTableHandle - name() and get_width()
        -- ========================================================================
        test_section("ProxyTableHandle - name() and get_width()")

        local path_name = dut.u_top.data_2:name()
        assert(path_name == "tb_top.u_top.data_2")

        local width = dut.u_top.data_2:get_width()
        assert(width == 8)

        -- ========================================================================
        -- Test: string.auto_bundle - startswith
        -- ========================================================================
        test_section("string.auto_bundle - startswith")

        local auto_bdl1 = ("tb_top.u_top"):auto_bundle {
            startswith = "axi_"
        }
        assert(auto_bdl1.__type == "Bundle")
        assert(auto_bdl1.axi_aw_valid.__type == "CallableHDL")
        assert(auto_bdl1.axi_ar_valid.__type == "CallableHDL")

        -- ========================================================================
        -- Test: string.auto_bundle - endswith
        -- ========================================================================
        test_section("string.auto_bundle - endswith")

        local auto_bdl2 = ("tb_top.u_top"):auto_bundle {
            endswith = "_suffix"
        }
        assert(auto_bdl2.__type == "Bundle")
        assert(auto_bdl2.signal_ending_suffix.__type == "CallableHDL")

        -- ========================================================================
        -- Test: string.auto_bundle - prefix
        -- ========================================================================
        test_section("string.auto_bundle - prefix")

        local auto_bdl3 = ("tb_top.u_top"):auto_bundle {
            prefix = "io_in_"
        }
        assert(auto_bdl3.__type == "Bundle")
        assert(auto_bdl3.value_0.__type == "CallableHDL")

        -- ========================================================================
        -- Test: string.auto_bundle - startswith + endswith
        -- ========================================================================
        test_section("string.auto_bundle - startswith + endswith")

        local auto_bdl4 = ("tb_top.u_top"):auto_bundle {
            startswith = "io_in_",
            endswith = "_0"
        }
        assert(auto_bdl4.__type == "Bundle")
        assert(auto_bdl4.io_in_value_0.__type == "CallableHDL")

        -- ========================================================================
        -- Test: string.auto_bundle - filter function
        -- ========================================================================
        test_section("string.auto_bundle - filter")

        local auto_bdl5 = ("tb_top.u_top"):auto_bundle {
            filter = function(name, width)
                return width == 32 and name:find("wide")
            end
        }
        assert(auto_bdl5.__type == "Bundle")
        assert(auto_bdl5.wide_signal_32.__type == "CallableHDL")
        assert(auto_bdl5.wide_signal_32:get_width() == 32)

        -- ========================================================================
        -- Test: string.auto_bundle - matches (Lua pattern)
        -- ========================================================================
        test_section("string.auto_bundle - matches")

        local auto_bdl6 = ("tb_top.u_top"):auto_bundle {
            matches = "^axi_.*_valid$"
        }
        assert(auto_bdl6.__type == "Bundle")
        assert(auto_bdl6.axi_aw_valid.__type == "CallableHDL")

        -- ========================================================================
        -- Test: string.auto_bundle - wildmatch
        -- ========================================================================
        test_section("string.auto_bundle - wildmatch")

        local auto_bdl7 = ("tb_top.u_top"):auto_bundle {
            wildmatch = "*_value_*"
        }
        assert(auto_bdl7.__type == "Bundle")
        assert(auto_bdl7.io_in_value_0.__type == "CallableHDL")

        -- ========================================================================
        -- Test: string.auto_bundle - matches + filter
        -- ========================================================================
        test_section("string.auto_bundle - matches + filter")

        local auto_bdl8 = ("tb_top.u_top"):auto_bundle {
            matches = "^wide_",
            filter = function(name, width)
                return width == 64
            end
        }
        assert(auto_bdl8.__type == "Bundle")
        assert(auto_bdl8.wide_signal_64.__type == "CallableHDL")

        -- ========================================================================
        -- Test: string.auto_bundle - wildmatch + filter + prefix
        -- ========================================================================
        test_section("string.auto_bundle - wildmatch + filter + prefix")

        local auto_bdl9 = ("tb_top.u_top"):auto_bundle {
            wildmatch = "*_value_*",
            prefix = "io_in_",
            filter = function(name, width)
                return width == 8
            end
        }
        assert(auto_bdl9.__type == "Bundle")
        assert(auto_bdl9.value_0.__type == "CallableHDL")

        -- ========================================================================
        -- Test: ProxyTableHandle:auto_bundle
        -- ========================================================================
        test_section("ProxyTableHandle:auto_bundle")

        local proxy_auto_bdl = dut.u_top:auto_bundle {
            startswith = "data_"
        }
        assert(proxy_auto_bdl.__type == "Bundle")
        assert(proxy_auto_bdl.data_0.__type == "CallableHDL")

        -- ========================================================================
        -- Test: ProxyTableHandle - Freeze and release
        -- ========================================================================
        if not is_verilator then
            test_section("ProxyTableHandle - Freeze operations")

            local freeze_sig = dut.u_top.opt_data:chdl()
            freeze_sig:set_imm(0x88)
            freeze_sig:set_freeze()
            clock:posedge()
            assert(freeze_sig:get() == 0x88)
            freeze_sig:set_release()
            clock:posedge() -- Wait a cycle for release to take effect
            freeze_sig:set_imm(0x99)
            assert(freeze_sig:get() == 0x99)
        end



        -- ========================================================================
        -- Test: CallableHDL - Force and release (skip for Verilator)
        -- ========================================================================
        if not is_verilator then
            test_section("CallableHDL - Force and release")

            local force_sig = ("tb_top.u_top.opt_valid"):chdl()
            force_sig:set_force(0x1)
            clock:posedge()
            assert(force_sig:get() == 0x1)

            force_sig:set_release()
            clock:posedge() -- Wait a cycle for release to take effect
            force_sig:set_imm(0x0)
            assert(force_sig:get() == 0x0)
        end

        -- ========================================================================
        -- Test: ProxyTableHandle - Force and release (skip for Verilator)
        -- ========================================================================
        if not is_verilator then
            test_section("ProxyTableHandle - Force and release")

            dut.u_top.opt_valid:set_force(0x1)
            clock:posedge()
            assert(dut.u_top.opt_valid:get() == 0x1)

            dut.u_top.opt_valid:set_release()
            clock:posedge() -- Wait a cycle for release to take effect
            dut.u_top.opt_valid:set_imm(0x0)
            assert(dut.u_top.opt_valid:get() == 0x0)
        end

        -- ========================================================================
        -- Test: CallableHDL - get_bitvec
        -- ========================================================================
        test_section("CallableHDL - get_bitvec")

        local bv_signal = ("tb_top.u_top.data_0"):chdl()
        bv_signal:set_imm(0xA5)
        local bv = bv_signal:get_bitvec()
        assert(bv.__type == "BitVec")
        -- BitVec value can be checked via tostring
        local bv_str = tostring(bv)
        assert(bv_str == "a5" or bv_str == "000000a5", "BitVec string: " .. bv_str)

        -- ========================================================================
        -- Test: Bundle - set_all and format_dump_str
        -- ========================================================================
        test_section("Bundle - set_all and format_dump_str")

        -- Use non-incrementing signals
        local set_bdl = ("opt_data | opt_valid | data_2"):bdl {
            hier = "tb_top.u_top",
            prefix = "",
            is_decoupled = false
        }

        set_bdl:set_all({ 0xAA, 0xBB, 0xCC })
        clock:posedge() -- Wait for set to take effect

        -- Verify values after set_all
        assert(set_bdl.opt_data:get() == 0xAA)
        assert(set_bdl.opt_valid:get() == 0xBB)
        assert(set_bdl.data_2:get() == 0xCC)

        local formatted = set_bdl:format_dump_str(function(chdl, name)
            return string.format("%s=0x%s", name, chdl:get_hex_str())
        end)
        assert(formatted == "opt_data=0xaa | opt_valid=0xbb | data_2=0xcc", "Got: " .. formatted)

        -- ========================================================================
        -- Test: AliasBundle - format_dump_str
        -- ========================================================================
        test_section("AliasBundle - format_dump_str")

        local fmt_abdl = ([[
            | orig_signal_0 => alias_a
            | orig_signal_1 => alias_b
        ]]):abdl {
            hier = "tb_top.u_top",
            prefix = ""
        }

        fmt_abdl.alias_a:set(0x11)
        fmt_abdl.alias_b:set(0x22)
        clock:posedge() -- Wait for set to take effect

        local abdl_formatted = fmt_abdl:format_dump_str(function(chdl, name, alias_name)
            return string.format("%s(%s)=0x%s", alias_name, name, chdl:get_hex_str())
        end)
        assert(abdl_formatted == "alias_a(orig_signal_0)=0x11 | alias_b(orig_signal_1)=0x22", "Got: " .. abdl_formatted)

        -- ========================================================================
        -- All tests passed
        -- ========================================================================
        print("[TEST] All handle tests passed successfully!")

        sim.finish()
    end
}
