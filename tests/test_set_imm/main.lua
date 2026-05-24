local function expect_comb_value(comb_imm, value)
    comb_imm:expect(value + 0x11)
end

local function immediate_response_bfm(clock, reset, req_valid, req_addr, resp_valid, resp_data, resp_seen_comb)
    local expected_addrs = { 0x05, 0x09 }
    local request_count = 0

    while true do
        clock:posedge()
        await_rw()

        if reset:is(1) or req_valid:is(0) then
            resp_valid:set_imm(0)
            resp_data:set_imm(0)
        else
            request_count = request_count + 1
            local addr = req_addr:get()
            local expected_addr = expected_addrs[request_count]
            if expected_addr ~= nil then
                req_addr:expect(expected_addr)
            end

            local response = addr + 0x40
            ---@cast response integer
            resp_valid:set_imm(1)
            resp_data:set_imm(response)
            resp_valid:expect(1)
            resp_data:expect(response)
            await_rd()
            resp_seen_comb:expect(1)
        end
    end
end

fork {
    function()
        local clock = dut.clock:chdl()
        local reset = dut.reset:chdl()
        local queued_in = dut.queued_in:chdl()
        local imm_in = dut.imm_in:chdl()
        local sampled_queued = dut.sampled_queued:chdl()
        local sampled_imm = dut.sampled_imm:chdl()
        local comb_imm = dut.comb_imm:chdl()
        local req_valid = dut.req_valid:chdl()
        local req_addr = dut.req_addr:chdl()
        local resp_valid = dut.resp_valid:chdl()
        local resp_data = dut.resp_data:chdl()
        local resp_seen_comb = dut.resp_seen_comb:chdl()
        local resp_seen_sampled = dut.resp_seen_sampled:chdl()
        local resp_data_sampled = dut.resp_data_sampled:chdl()
        local dut_owned = dut.u_top.dut_owned:chdl()

        fork {
            function()
                immediate_response_bfm(clock, reset, req_valid, req_addr, resp_valid, resp_data, resp_seen_comb)
            end,
        }

        queued_in:set_imm(0)
        imm_in:set_imm(0)
        resp_valid:set_imm(0)
        resp_data:set_imm(0)
        reset:set_imm(1)
        clock:posedge(2)
        clock:negedge()
        reset:set_imm(0)
        clock:posedge()

        await_rd()
        resp_seen_comb:expect(1)

        clock:posedge()
        await_rd()
        resp_seen_sampled:expect(1)
        resp_data_sampled:expect(0x45)
        resp_seen_comb:expect(1)

        clock:posedge()
        await_rw()
        req_valid:expect(0)
        await_rd()
        resp_seen_sampled:expect(1)
        resp_data_sampled:expect(0x49)

        sampled_queued:expect(0)
        sampled_imm:expect(0)

        -- `set` is queued for a later simulation phase and is not visible immediately.
        clock:negedge()
        queued_in:set(0x21)
        queued_in:expect(0)
        sampled_queued:expect(0)
        clock:posedge()
        queued_in:expect(0x21)
        sampled_queued:expect(0)
        clock:posedge()
        sampled_queued:expect(0x21)

        -- `set_imm` is visible right away on the driven signal.
        clock:negedge()
        imm_in:set_imm(0x34)
        imm_in:expect(0x34)
        sampled_imm:expect(0)
        await_rd()
        expect_comb_value(comb_imm, 0x34)
        clock:posedge()
        await_rd()
        sampled_imm:expect(0x34)

        -- Multiple immediate writes in the same timestep keep the last value.
        clock:negedge()
        imm_in:set_imm(0x12)
        imm_in:set_imm(0x56)
        imm_in:expect(0x56)
        await_rd()
        expect_comb_value(comb_imm, 0x56)
        clock:posedge()
        await_rd()
        sampled_imm:expect(0x56)

        -- `set_imm` is not a force: the DUT can overwrite the value later.
        clock:negedge()
        dut_owned:set_imm(0x80)
        dut_owned:expect(0x80)
        clock:posedge()
        await_rd()
        dut_owned:expect(0x91)
        clock:posedge()
        await_rd()
        dut_owned:expect(0xA2)

        sim.finish()
    end,
}
