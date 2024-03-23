

basic = {
    prj_dir = os.getenv("$PWD"),
    top = "tb_top",
    simulator = "verilator",
    mode = "step",
    script = "LuaMain.lua",
    period = 10,
    unit = "ns",
    seed = 101,
    attach = false,
    enable_shutdown = false,
    srcs = {
        "./src/lua/?.lua",
        "./src/lua/main/?.lua"
    },
}

-- deps = {
--     verilua_huancun = "",
-- }

-- configs = {
--     main    = "./config_1.lua",
--     another = "./config_2.lua"
-- }

