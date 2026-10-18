-- Exercises every canonical CHDL write API against each beat class the access
-- layer generates separate code for (Single / Double / Multi), on both plain
-- signals and array element views.
--
-- `get_hex_str()` is the common readback: it is zero padded to the signal
-- width, so a single expectation helper works for 8, 64 and 128 bit signals.

local clock = dut.clock:chdl()
local resolve_x_env = os.getenv("VL_RESOLVE_X_AS_ZERO")
local resolve_x_as_zero = resolve_x_env == nil or resolve_x_env == "1" or resolve_x_env == "true"
local resolve_string_x = cfg.simulator == "iverilog" and resolve_x_as_zero

local function test_section(name)
    print(string.format("[TEST] %s", name))
end

--- Zero padded hex expectation for a signal of `width` bits.
local function padded(width, s)
    return string.rep("0", math.floor(width / 4) - #s) .. s
end

local function checker(sig, width, label)
    return function(want, api)
        local got = sig:get_hex_str()
        assert(got == padded(width, want),
            string.format("%s: %s wrote %s, expected %s", label, api, got, padded(width, want)))
    end
end

--- Every scalar write API, run against one handle (plain signal or `arr[i]`).
local function check_scalar(sig, width, label)
    assert(sig:get_width() == width, label .. ": unexpected width " .. sig:get_width())
    local is = checker(sig, width, label)

    -- Plain writes: the deferred form lands on the next edge, `_imm` right away
    sig:set_imm(0x0)
    is("0", "set_imm")
    sig:set(0x5a)
    clock:posedge()
    is("5a", "set")

    sig:set_imm_unchecked(0x11)
    is("11", "set_imm_unchecked")
    sig:set_unchecked(0x22)
    clock:posedge()
    is("22", "set_unchecked")

    -- Property writes are the same operation spelled as an assignment
    sig.value_imm = 0x33
    is("33", ".value_imm")
    sig.value = 0x44
    clock:posedge()
    is("44", ".value")

    -- Bit fields: the untouched bits must survive
    sig:set_imm(0x0)
    sig:set_bits_imm(0, 3, 0xa)
    is("a", "set_bits_imm")
    sig:set_bits(4, 7, 0x5)
    clock:posedge()
    is("5a", "set_bits")

    -- Hex string bit fields reach past the 64 bit limit of set_bits
    local full = string.rep("5a", math.floor(width / 8))
    sig:set_imm(0x0)
    sig:set_bits_imm_hex_str(0, width - 1, full)
    is(full, "set_bits_imm_hex_str")
    sig:set_imm(0x0)
    sig:set_bits_hex_str(0, width - 1, full)
    clock:posedge()
    is(full, "set_bits_hex_str")

    -- String writes, one pair per radix
    sig:set_imm_hex_str("5a")
    is("5a", "set_imm_hex_str")
    sig:set_hex_str("a5")
    clock:posedge()
    is("a5", "set_hex_str")

    sig:set_imm_bin_str("1011")
    is("b", "set_imm_bin_str")
    sig:set_bin_str("1100")
    clock:posedge()
    is("c", "set_bin_str")

    -- Icarus resolves lowercase x in string reads only while the switch is on.
    local x_visible = cfg.simulator ~= "verilator" and not resolve_string_x

    -- x alternating with f on the hex side and with 1 on the bit side, so x
    -- covers high and low positions and the readback also proves the order
    local byte_count = math.floor(width / 8)
    local hex_in = string.rep("fx", byte_count)
    local hex_want = string.rep(x_visible and "fx" or "f0", byte_count)
    local bin_in = string.rep("1x1x1x1x", byte_count)
    local bin_want = string.rep(x_visible and "1x1x1x1x" or "10101010", byte_count)
    -- Mixed nibbles remain X on 4-state simulators, even when Icarus resolves lowercase x.
    local bin_as_hex_want = string.rep(cfg.simulator == "verilator" and "a" or "x", math.floor(width / 4))

    local function assert_x(got, want, api)
        got = got:lower()
        assert(got == want, string.format("%s: %s wrote %s, expected %s", label, api, got, want))
    end

    sig:set_imm_hex_str(hex_in)
    assert_x(sig:get_hex_str(), hex_want, "set_imm_hex_str")
    sig:set_imm(0x0)
    sig:set_hex_str(hex_in)
    clock:posedge()
    assert_x(sig:get_hex_str(), hex_want, "set_hex_str")

    sig:set_imm_bin_str(bin_in)
    assert_x(sig:get_bin_str(), bin_want, "set_imm_bin_str")
    assert_x(sig:get_hex_str(), bin_as_hex_want, "set_imm_bin_str then get_hex_str")
    sig:set_imm(0x0)
    sig:set_bin_str(bin_in)
    clock:posedge()
    assert_x(sig:get_bin_str(), bin_want, "set_bin_str")

    if cfg.simulator == "iverilog" then
        ---@param got string
        ---@param want string
        ---@param api string
        local function assert_raw(got, want, api)
            assert(got == want, string.format("%s: %s read %s, expected %s", label, api, got, want))
        end

        local hex_digit_count = math.floor(width / 4)
        local bit_pair_count = math.floor(width / 2)

        -- Mixed known/unknown digits use uppercase X, which is not replaced.
        assert_raw(sig:get_hex_str(), string.rep("X", hex_digit_count), "mixed-x hex")
        assert_raw(sig:get_dec_str(), "X", "mixed-x decimal")

        sig:set_imm_bin_str(string.rep("x", width))
        local resolved_x = resolve_x_as_zero and "0" or "x"
        assert_raw(sig:get_bin_str(), string.rep(resolved_x, width), "all-x binary")
        assert_raw(sig:get_hex_str(), string.rep(resolved_x, hex_digit_count), "all-x hex")
        assert_raw(sig:get_dec_str(), resolved_x, "all-x decimal")
        assert_raw(sig:get_str(BinStr), string.rep(resolved_x, width), "all-x get_str binary")
        assert_raw(sig:get_str(HexStr), string.rep(resolved_x, hex_digit_count), "all-x get_str hex")
        assert_raw(sig:get_str(DecStr), resolved_x, "all-x get_str decimal")
        assert_raw(sig:get_str(OctStr), string.rep(resolved_x, math.ceil(width / 3)), "all-x octal")
        assert(sig:is_hex_str("00") == resolve_x_as_zero, label .. ": all-x zero comparison ignores the switch")

        -- Neither lowercase z nor mixed-digit uppercase Z is resolved.
        sig:set_imm_bin_str(string.rep("z", width))
        assert_raw(sig:get_bin_str(), string.rep("z", width), "all-z binary")
        assert_raw(sig:get_hex_str(), string.rep("z", hex_digit_count), "all-z hex")
        assert_raw(sig:get_dec_str(), "z", "all-z decimal")
        assert_raw(sig:get_str(OctStr), string.rep("z", math.ceil(width / 3)), "all-z octal")

        sig:set_imm_bin_str(string.rep("1z", bit_pair_count))
        assert_raw(sig:get_bin_str(), string.rep("1z", bit_pair_count), "mixed-z binary")
        assert_raw(sig:get_hex_str(), string.rep("Z", hex_digit_count), "mixed-z hex")
        assert_raw(sig:get_dec_str(), "Z", "mixed-z decimal")
    end

    -- Verilator's VPI accepts vpiDecStrVal only for variables up to 64 bits
    -- (verilated_vpi.cpp lists VLVT_UINT8/16/32/64 but not VLVT_WDATA), so a
    -- decimal string write to a wider signal is dropped. Other simulators take it.
    local decimal_ok = not (cfg.simulator == "verilator" and width > 64)
    if decimal_ok then
        sig:set_imm_dec_str("90")
        is("5a", "set_imm_dec_str")
        sig:set_dec_str("91")
        clock:posedge()
        is("5b", "set_dec_str")
    else
        print(string.format(
            "[test_chdl_write_api] skip decimal writes on %s: Verilator has no vpiDecStrVal for > 64 bit",
            label))
    end

    -- set_str picks the radix from the prefix, decimal when there is none
    sig:set_imm_str("0x5a")
    is("5a", "set_imm_str")
    sig:set_imm_str("0b1011")
    is("b", "set_imm_str (0b)")
    if decimal_ok then
        -- No prefix means decimal, so this shares the vpiDecStrVal limit above
        sig:set_imm_str("90")
        is("5a", "set_imm_str (dec)")
    end
    sig:set_str("0xa5")
    clock:posedge()
    is("a5", "set_str")

    -- Randomized writes must stay inside the signal width and actually vary
    local seen, distinct = {}, 0
    for _ = 1, 32 do
        sig:randomize_imm()
        local got = sig:get_hex_str()
        assert(#got == width / 4,
            string.format("%s: randomize_imm produced %s, wider than %d bits", label, got, width))
        if not seen[got] then
            seen[got] = true
            distinct = distinct + 1
        end
    end
    assert(distinct >= 2, label .. ": randomize_imm returned a constant over 32 draws")

    sig:randomize()
    clock:posedge()
    assert(#sig:get_hex_str() == width / 4, label .. ": randomize produced an out-of-width value")

    -- A cached write is dropped when the value matches the previous cached
    -- write, so a plain write made in between stays visible
    sig:reset_set_cached()
    sig:set_imm_cached(0x5a)
    is("5a", "set_imm_cached")
    sig:set_imm(0x11)
    sig:set_imm_cached(0x5a)
    is("11", "set_imm_cached (unchanged value must be skipped)")
    sig:reset_set_cached()
    sig:set_imm_cached(0x5a)
    is("5a", "set_imm_cached (after reset_set_cached)")

    sig:reset_set_cached()
    sig:set_cached(0xa5)
    clock:posedge()
    is("a5", "set_cached")
end

--- force / release / freeze, run against one forceable handle.
local function check_force(sig, width, label)
    local is = checker(sig, width, label)

    sig:set_imm(0x0)
    sig:force(0x11)
    clock:posedge()
    is("11", "force")

    -- A forced signal ignores plain writes until it is released
    sig:set_imm(0x22)
    clock:posedge()
    is("11", "force holds against set_imm")

    sig:release()
    clock:posedge()
    sig:set_imm(0x33)
    is("33", "release")

    sig:force_imm(0x44)
    is("44", "force_imm")
    sig:release_imm()
    clock:posedge()
    sig:set_imm(0x55)
    is("55", "release_imm")

    -- freeze pins whatever the signal currently holds
    sig:freeze()
    clock:posedge()
    is("55", "freeze")
    sig:release()
    clock:posedge()
    sig:set_imm(0x66)
    is("66", "release after freeze")

    sig:freeze_imm()
    clock:posedge()
    is("66", "freeze_imm")
    sig:release_imm()
    clock:posedge()
    sig:set_imm(0x77)
    is("77", "release_imm after freeze_imm")

    -- Hex strings reach past the 64 bit limit of force(), which takes a number
    local wide = string.rep("d", math.floor(width / 4))
    sig:force_hex_str(wide)
    clock:posedge()
    is(wide, "force_hex_str")
    sig:release()
    clock:posedge()

    local wide_imm = string.rep("6", math.floor(width / 4))
    sig:force_imm_hex_str(wide_imm)
    is(wide_imm, "force_imm_hex_str")
    sig:release_imm()
    clock:posedge()
end

--- Array-only write APIs, plus the full scalar suite on element views.
local function check_array(path, width, size)
    local arr = (path):chdl()
    assert(arr.is_array, path .. ": expected an array handle")
    assert(arr.array_size == size, path .. ": unexpected array_size " .. tostring(arr.array_size))

    local function elem_is(idx, want, api)
        local got = arr[idx]:get_hex_str()
        assert(got == padded(width, want),
            string.format("%s[%d]: %s wrote %s, expected %s", path, idx, api, got, padded(width, want)))
    end

    -- The same index must hand back the same handle
    assert(arr[0] == arr[0], path .. ": arr[i] must return a cached handle")

    -- Index assignment is a write form of its own (CallableHDL.__newindex)
    arr[0] = 0x77
    clock:posedge()
    elem_is(0, "77", "arr[i] = v")

    -- Whole-array writes take one value per element
    local values, zeros = {}, {}
    for i = 1, size do
        values[i] = i * 0x10 + i
        zeros[i] = 0
    end
    local function all_are(api)
        for i = 1, size do
            elem_is(i - 1, string.format("%x", values[i]), api)
        end
    end

    arr:set_all_imm(values)
    all_are("set_all_imm")

    arr:set_all_imm_unchecked(zeros)
    arr:set_all(values)
    clock:posedge()
    all_are("set_all")

    arr:set_all_imm(zeros)
    arr:set_all_imm_unchecked(values)
    all_are("set_all_imm_unchecked")

    arr:set_all_imm(zeros)
    arr:set_all_unchecked(values)
    clock:posedge()
    all_are("set_all_unchecked")

    -- An element view is a full CallableHDL, so the whole scalar suite applies.
    -- Run it on the first and last element to cover both ends of the index range.
    check_scalar(arr[0], width, path .. "[0]")
    check_scalar(arr[size - 1], width, string.format("%s[%d]", path, size - 1))
end

fork {
    function()
        clock:posedge(5)

        test_section("scalar writes - Single (8 bit)")
        check_scalar(("tb_top.u_top.single_8"):chdl(), 8, "single_8")

        test_section("scalar writes - Single (32 bit)")
        check_scalar(("tb_top.u_top.single_32"):chdl(), 32, "single_32")

        test_section("scalar writes - Double (64 bit)")
        check_scalar(("tb_top.u_top.double_64"):chdl(), 64, "double_64")

        test_section("scalar writes - Multi (128 bit)")
        check_scalar(("tb_top.u_top.multi_128"):chdl(), 128, "multi_128")

        test_section("array writes - Single (8 bit)")
        check_array("tb_top.u_top.arr_single", 8, 4)

        test_section("array writes - Double (64 bit)")
        check_array("tb_top.u_top.arr_double", 64, 4)

        test_section("array writes - Multi (128 bit)")
        check_array("tb_top.u_top.arr_multi", 128, 2)

        -- A 4-state simulator reads an x bit as 0 under the VL_RESOLVE_X_AS_ZERO
        -- default, and as the raw aval bit (1) when that switch is off; either way
        -- the other bits keep their value, at every width.
        if cfg.simulator ~= "verilator" then
            test_section("x-state numeric reads")

            -- x in the low beat: the high beat keeps its bits
            local double_64 = ("tb_top.u_top.double_64"):chdl()
            double_64:set_imm_hex_str("0000000f0000000x")
            assert(double_64:get() == (resolve_x_as_zero and 0xf00000000 or 0xf0000000f),
                string.format("double_64: x in the low beat read %s", tostring(double_64:get())))

            -- x in the high beat: the low beat keeps its bits
            double_64:set_imm_hex_str("0000000x0000000f")
            assert(double_64:get() == (resolve_x_as_zero and 0xf or 0xf0000000f),
                string.format("double_64: x in the high beat read %s", tostring(double_64:get())))

            local multi_128 = ("tb_top.u_top.multi_128"):chdl()
            multi_128:set_imm_hex_str(string.rep("f", 31) .. "x")
            local beats = multi_128:get()
            assert(beats[1] == (resolve_x_as_zero and 0xfffffff0 or 0xffffffff),
                string.format("multi_128: the beat holding x read %s", tostring(beats[1])))
            assert(beats[4] == 0xffffffff, "multi_128: beats without x must keep their value")
        end

        local force_ok = true
        if cfg.simulator == "verilator" then
            local p = io.popen("verilator --version 2>/dev/null")
            if p then
                local out = p:read("*a") or ""
                p:close()
                local major, minor = out:match("Verilator%s+(%d+)%.(%d+)")
                major, minor = tonumber(major), tonumber(minor)
                force_ok = major ~= nil and (major > 5 or (major == 5 and minor >= 50))
            else
                force_ok = false
            end
        end

        if force_ok then
            test_section("force / release / freeze - scalars")
            check_force(("tb_top.u_top.force_single"):chdl(), 8, "force_single")
            check_force(("tb_top.u_top.force_double"):chdl(), 64, "force_double")
            check_force(("tb_top.u_top.force_multi"):chdl(), 128, "force_multi")

            -- iverilog drops the put flags for a memory word: __vpiArray::put_word_value
            -- ignores its `flags` argument and always does a plain write, so force and
            -- freeze on an array element behave like set there.
            if cfg.simulator == "iverilog" then
                print("[test_chdl_write_api] skip force/release/freeze on array elements: " ..
                    "iverilog ignores vpiForceFlag for memory words")
            else
                test_section("force / release / freeze - array elements")
                check_force(("tb_top.u_top.force_arr_single"):chdl()[1], 8, "force_arr_single[1]")
                check_force(("tb_top.u_top.force_arr_double"):chdl()[1], 64, "force_arr_double[1]")
                check_force(("tb_top.u_top.force_arr_multi"):chdl()[1], 128, "force_arr_multi[1]")
            end
        else
            print("[test_chdl_write_api] skip force/release/freeze: Verilator < 5.050 (no forceable)")
        end

        print("[TEST] All CHDL write API tests passed successfully!")
        sim.finish()
    end,
}
