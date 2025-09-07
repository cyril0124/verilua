local inspect = require "inspect"

local expect_eq_table = function(t1, t2)
    local left = inspect(t1)
    local right = inspect(t2)
    assert(inspect(t1) == inspect(t2), "\n" .. left .. "\n!=\n" .. right)
end

fork {
    function()
        local sd = require("SignalDB"):init()

        local expect_db_data = {
            tb_top = {
                -- SignalName, Width, VpiType
                { "clock",  1,  "vpiReg" },
                { "reset",  1,  "vpiReg" },
                { "cycles", 64, "vpiReg" },
                u_others = {
                    { "clock", 1, "vpiNet" },
                    { "reset", 1, "vpiNet" }
                },
                u_top = {
                    { "r1",    1,   "vpiReg" },
                    { "r8",    8,   "vpiReg" },
                    { "r128",  128, "vpiReg" },
                    { "l1",    1,   "vpiNet" },
                    { "l8",    8,   "vpiNet" },
                    { "l128",  128, "vpiNet" },
                    { "b1",    1,   "vpiNet" },
                    { "b8",    8,   "vpiNet" },
                    { "b128",  128, "vpiNet" },
                    { "clock", 1,   "vpiNet" },
                    { "reset", 1,   "vpiNet" },
                    { "w1",    1,   "vpiNet" },
                    { "w8",    8,   "vpiNet" },
                    { "w128",  128, "vpiNet" },
                    u_sub = {
                        { "r1",    1,   "vpiReg" },
                        { "r8",    8,   "vpiReg" },
                        { "r128",  128, "vpiReg" },
                        { "clock", 1,   "vpiNet" },
                        { "reset", 1,   "vpiNet" },
                        { "w1",    1,   "vpiNet" },
                        { "w8",    8,   "vpiNet" },
                        { "w128",  128, "vpiNet" }
                    },
                    u_sub2 = {
                        { "r1",    1,   "vpiReg" },
                        { "r8",    8,   "vpiReg" },
                        { "r128",  128, "vpiReg" },
                        { "clock", 1,   "vpiNet" },
                        { "reset", 1,   "vpiNet" },
                        { "w1",    1,   "vpiNet" },
                        { "w8",    8,   "vpiNet" },
                        { "w128",  128, "vpiNet" }
                    }
                }
            }
        }

        expect_eq_table(sd:get_db_data(), expect_db_data)

        assert(sd:get_top_module() == "tb_top")

        expect_eq_table(sd:get_signal_info("tb_top.u_top.l128"), { "l128", 128, "vpiNet" })

        local ret = sd:find_hier("*sub*")
        assert(#ret == 2)
        assert(table.contains(ret, "tb_top.u_top.u_sub"))
        assert(table.contains(ret, "tb_top.u_top.u_sub2"))

        local ret2 = sd:find_signal("clock", "*sub*") --[[@as table<integer, string>]]
        assert(#ret2 == 2)
        assert(table.contains(ret2, "tb_top.u_top.u_sub.clock"))
        assert(table.contains(ret2, "tb_top.u_top.u_sub2.clock"))

        local ret3 = sd:find_all("*sub*")
        assert(#ret3 == 2)
        assert(table.contains(ret3, "tb_top.u_top.u_sub"))
        assert(table.contains(ret3, "tb_top.u_top.u_sub2"))

        local ret4 = sd:find_all("*r1*")
        assert(#ret4 == 6)
        assert(table.contains(ret4, "tb_top.u_top.r1"))
        assert(table.contains(ret4, "tb_top.u_top.r128"))
        assert(table.contains(ret4, "tb_top.u_top.u_sub.r1"))
        assert(table.contains(ret4, "tb_top.u_top.u_sub2.r1"))
        assert(table.contains(ret4, "tb_top.u_top.u_sub.r128"))
        assert(table.contains(ret4, "tb_top.u_top.u_sub2.r128"))

        sim.finish()
    end
}
