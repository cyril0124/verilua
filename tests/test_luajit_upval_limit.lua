local lester = require "lester"
local describe, it, expect = lester.describe, lester.it, lester.expect

lester.parse_args()

local function make_src(n)
    local locals, uses = {}, {}
    for i = 1, n do
        locals[i] = "local u" .. i .. " = " .. i
        uses[i] = "u" .. i
    end
    return table.concat(locals, "\n")
        .. "\nreturn function()\n  return "
        .. table.concat(uses, "+")
        .. "\nend\n"
end

describe("LuaJIT upvalue limit", function()
    it("loads a function that closes over more than 60 upvalues", function()
        local f, err = loadstring(make_src(61))
        expect.equal(err, nil)
        assert(f)
        expect.equal(f()(), 61 * 62 / 2)
    end)
end)

lester.report()
lester.exit()
