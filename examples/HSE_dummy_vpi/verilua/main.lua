fork {
    function()
        local value = dut.uut.u_sub.value:chdl()
        local value2 = dut.uut.u_sub.value2:chdl()
        local value3 = dut.uut.u_sub.value3:chdl()
        local lua_hexStr = ""
        local lua_hexStr2 = ""
        local lua_hexStr3 = ""

        local start_check = false
        local expected_values = { 1, 2, 3, 4, 5, 6, 7, 8 }
        dut.clk:posedge(10, function(i)
            local v = value:get()
            lua_hexStr = value:get_hex_str()
            lua_hexStr2 = value2:get_hex_str()
            lua_hexStr3 = value3:get_hex_str()
            print("[" .. i .. "]", v, lua_hexStr, lua_hexStr2, lua_hexStr3)

            if v == 1 then
                start_check = true
            end

            if start_check then
                assert(v == expected_values[v])
                assert(value2:get() == expected_values[v] * 3)
            end
        end)

        sim.finish()
    end
}
