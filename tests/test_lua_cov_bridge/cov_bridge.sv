// Coverage bridge injected into the generated tb_top (see xmake.lua). Lua passes a
// bin tag to verilua_cov_sample(), which samples the covergroup below, and reads
// cov_hit_count to confirm the samples arrived.
//
// Covergroups are compiled out when SIM_VERILATOR is defined, because that
// simulator does not support them; the DPI exports stay on every simulator.
int cov_hit_count = 0;

`ifndef SIM_VERILATOR
covergroup cg_lua_cov_bridge with function sample(int unsigned cov_id);
    cp_tag: coverpoint cov_id {
        bins count_zero   = {0};
        bins count_small  = {[1:63]};
        bins count_medium = {[64:127]};
        bins count_large  = {[128:255]};
    }
endgroup

cg_lua_cov_bridge cg_lua_cov_bridge_inst = new();
`endif // SIM_VERILATOR

export "DPI-C" function verilua_cov_sample;
function void verilua_cov_sample(int unsigned cov_id);
`ifndef SIM_VERILATOR
    cg_lua_cov_bridge_inst.sample(cov_id);
`endif
    cov_hit_count++;
endfunction

export "DPI-C" function verilua_cov_hit_count;
function int verilua_cov_hit_count();
    return cov_hit_count;
endfunction
