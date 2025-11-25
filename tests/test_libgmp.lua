local g = require "verilua.utils.LibGMP"
local sbu = require "verilua.utils.StrBitsUtils"
string.adjust_hex_bitwidth = sbu.adjust_hex_bitwidth

g:init()

local a = g.types.z()
a:init_set_str("1234567890abcdef112233445566778899", 16)
assert(a:get_str(16) == "1234567890abcdef112233445566778899")

a:init_set_str("abcd", 16)
assert(a:get_hex_str() == "abcd")
a:clear()

local b = g.types.z()
b:init_set_str("1001001001", 2)
assert(b:popcount() == 4)

local c = g.types.z()
c:init_set_str("1", 10)
assert(c:get_hex_str() == "1")
c:add_hex_str("1234"):add_hex_str("1")
assert(c:get_hex_str() == "1236")

local d = g.types.z()
d:init_set_str("1", 10)
d:lshift(3)
assert(d:get_hex_str() == "8")
d:lshift(1)
assert(d:get_hex_str() == "10")

local e = g.types.z()
e:init_set_str("10", 2)
e:rshift(1)
assert(e:get_hex_str() == "1")
e:rshift(1)
assert(e:get_hex_str() == "0")

local f = g.types.z()
f:init_set_str("1011", 2)
f:and_hex_str("6")
assert(f:get_hex_str() == "2")

local a1 = g.types.z()
a1:init_set_str("1011", 2)
a1:or_hex_str("6")
assert(a1:get_hex_str() == "f")

local a2 = g.types.z()
a2:init_set_str("1011", 2)
a2:xor_hex_str("6")
assert(a2:get_hex_str() == "d")

local a3 = g.types.z()
a3:init_set_str("1011", 2)
assert(a3:get_hex_str() == "b")
a3:combit(1)
assert(a3:get_hex_str() == "9")
a3:combit(3)
assert(a3:get_hex_str() == "1")

local a4 = g.types.z()
a4:init_set_str("1011", 2)
assert(a4:get_bitfield(1, 2):get_bin_str() == "1")
assert(a4:get_bitfield(1, 3):get_bin_str() == "101")

local a5 = g.types.z()
a5:init_set_str("1011", 2)
assert(a5:get_bitfield_hex_str(1, 4) == "5")

local a6 = g.types.z()
a6:init_set_str("0", 10)
assert(a6:get_bitfield_hex_str(0, 4) == "0")

local a7 = g.types.z()
a7:init_set_str("1010001", 2)
a7:set_bitfield_hex_str(1, 2, "3")
assert(a7:get_bin_str() == "1010111")

local a8 = g.types.z()
a8:init_set_str("1", 2)
a8:add_hex_str("1")
assert(a8:get_hex_str():adjust_hex_bitwidth(1) == "0")

