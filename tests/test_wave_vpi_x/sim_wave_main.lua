local clock = dut.clock:chdl()
local data_b = dut.data_b:chdl()
local data_wide = dut.data_wide:chdl()

fork {
    function()
        -- Advance one cycle to be at a known good state
        clock:posedge()

        local hex_b = data_b:get_hex_str()
        local bin_b = data_b:get_bin_str()
        print("[cycle 1] data_b hex_str: " .. hex_b)
        print("[cycle 1] data_b bin_str: " .. bin_b)

        -- data_b should have X values: upper nibble = 0xA (1010), lower nibble = X
        assert(
            string.find(hex_b, "x") ~= nil,
            string.format("Expected X-state in data_b hex_str, got: %s (bin: %s)", hex_b, bin_b)
        )
        assert(
            string.find(bin_b, "x") ~= nil,
            string.format("Expected X-state in data_b bin_str, got: %s", bin_b)
        )

        -- get_dec_str should return "x" when X-state is present
        local dec_b = data_b:get_dec_str()
        print("[cycle 1] data_b dec_str: " .. dec_b)
        assert(
            dec_b == "x",
            string.format("Expected 'x' for data_b dec_str with X-state, got: %s", dec_b)
        )

        -- Advance past reset deassert (reset deasserts around cycle 4 in the gen wave)
        clock:posedge(5)

        hex_b = data_b:get_hex_str()
        print("[after reset deassert] data_b hex_str: " .. hex_b)
        assert(
            hex_b == "ff",
            string.format("Expected data_b hex_str 'ff' after reset deassert, got: %s", hex_b)
        )

        local bin_b2 = data_b:get_bin_str()
        print("[after reset deassert] data_b bin_str: " .. bin_b2)
        assert(
            bin_b2 == "11111111",
            string.format("Expected data_b bin_str '11111111' after reset deassert, got: %s", bin_b2)
        )

        -- data_b = 0xFF = 255 in decimal
        local dec_b2 = data_b:get_dec_str()
        print("[after reset deassert] data_b dec_str: " .. dec_b2)
        assert(
            dec_b2 == "255",
            string.format("Expected data_b dec_str '255' after reset deassert, got: %s", dec_b2)
        )

        -- data_wide should also be non-X after reset
        local hex_wide = data_wide:get_hex_str()
        print("[after reset deassert] data_wide hex_str: " .. hex_wide)
        assert(
            string.find(hex_wide, "x") == nil,
            string.format("Expected no X-state in data_wide hex_str after reset deassert, got: %s", hex_wide)
        )

        local bin_wide = data_wide:get_bin_str()
        print("[after reset deassert] data_wide bin_str: " .. bin_wide)
        assert(
            string.find(bin_wide, "x") == nil,
            string.format("Expected no X-state in data_wide bin_str after reset deassert, got: %s", bin_wide)
        )

        print("All X-state tests passed!")
        sim.finish()
    end
}
