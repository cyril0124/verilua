---@diagnostic disable: undefined-global, undefined-field

local scriptdir = os.scriptdir()

target("test-all-lua", function()
    set_kind("phony")
    set_default(false)
    add_files(path.join(scriptdir, "test_*.lua"))
    on_run(function(target)
        local function run_lua_test_files(files)
            for index, file in ipairs(files) do
                print(string.format("=== [%d/%d] start test %s ==================================", index, #files, file))
                os.exec("luajit %s --stop-on-fail --no-quiet", file)
                print("")
            end
        end

        run_lua_test_files(target:sourcefiles())
    end)
end)
