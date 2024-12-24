target("test_all")
    set_kind("phony")
    add_files("./test_*.lua")

    on_run(function (target)
        local files = target:sourcefiles()
        for i, file in ipairs(files) do
            print("=== [%d] start test %s ==================================", i, file)
            os.exec("lua %s --stop-on-fail", file)
            print("")
        end
    end)