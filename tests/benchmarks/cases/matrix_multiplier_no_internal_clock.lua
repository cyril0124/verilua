if os.getenv("JIT_V") == "off" then
    jit.off()
end

local f = string.format
local random = math.random

local function matrix_mul_lua(A, B, M, N, K)
    local C = {}
    for i = 1, M do
        for j = 1, K do
            C[(i - 1) * K + j] = 0
            for k = 1, N do
                C[(i - 1) * K + j] = C[(i - 1) * K + j] + A[(i - 1) * N + k] * B[(k - 1) * K + j]
            end
        end
    end
    return C
end

local clock = dut.clk_i:chdl()
local a_i = dut.a_i:chdl()
local b_i = dut.b_i:chdl()
local c_o = dut.c_o:chdl()
local valid_i = dut.valid_i:chdl()
local valid_o = dut.valid_o:chdl()

fork {
    function()
        while true do
            clock:set(0)
            await_time(2)
            clock:set(1)
            await_time(2)
        end
    end,
    function()
        -- sim.dump_wave()

        math.randomseed(123456789)

        dut.reset_i = 1
        clock:posedge(10)
        dut.reset_i = 0

        local cycles = 0
        for _ = 0, 3000 do
            clock:negedge()

            for i = 0, 60 - 1 do
                a_i:at(i):set(random(1, 100))
            end

            for i = 0, 24 - 1 do
                b_i:at(i):set(random(1, 100))
            end

            valid_i:set(1)

            clock:negedge()

            valid_i:set(0)

            if cycles % 100 == 0 then
                printf("Running... %d/3000\n", cycles)
            end

            cycles = cycles + 1
        end

        print("finish simulation!")
        sim.finish()
    end,

    function()
        local M, N, K = 10, 6, 4

        while true do
            if valid_o:is(1) then
                local ret_a = a_i:get_index_all() -- 10 * 6 = 60
                local ret_b = b_i:get_index_all() -- 6 * 4 = 24

                local C = matrix_mul_lua(ret_a, ret_b, M, N, K)

                local ret_c = c_o:get_index_all()

                for i = 1, 40 do
                    if C[i] ~= ret_c[i][1] then
                        assert(false, f("expected: %d   got: %d", C[i], ret_c[i][1]))
                    end
                end
            end
            clock:posedge()
        end
    end
}
