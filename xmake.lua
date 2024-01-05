
local lib_name   = "lua_vpi"
local prj_dir    = os.getenv("PWD")
local src_dir    = prj_dir .. "/src"
local build_dir  = prj_dir .. "/build"
local lua_dir    = prj_dir .. "/luajit2.1"
local extern_dir = prj_dir .. "/extern"
local shared_dir = prj_dir .. "/shared"


target(lib_name)
    before_build(function (target)
        print("--------------------- [Before Build] ---------------------- ")

        
        print("---------------------------------------------------------- ")
    end)

    set_kind("shared")

    set_toolchains("clang")
    set_languages("c99", "c++17")
    
    set_targetdir(build_dir .. "/bin")
    set_objectdir(build_dir .. "/obj")

    add_defines(
        "ACCUMULATE_LUA_TIME"
    )

    add_cxflags(
        "-Ofast -funroll-loops -march=native -fomit-frame-pointer",
        {force = true}
    )

    -- shared lib link flags (! instead of add_ldflags)
    add_shflags(
        "-L".. lua_dir .. "/lib" .. " -lluajit-5.1",
        "-L".. extern_dir .. "/fmt/build" .. " -lfmt",
        "-Wl,--no-as-needed", 
        {force = true}
    )


    add_files(
        src_dir .. "/verilua/*.cpp"
    )

    add_includedirs(
        src_dir .. "/include",
        lua_dir .. "/include",
        extern_dir .. "/fmt/include",
        extern_dir .. "/LuaBridge/Source",
        extern_dir .. "/LuaBridge/Source/LuaBridge"
    )

    -- on install
    add_headerfiles(
        src_dir .. "/include/lua_vpi.h"
    )

    after_build(function (target)
        print("--------------------- [After Build] ---------------------- ")

        print("* copy " .. target:targetfile() .. " into " .. shared_dir)
            os.run("cp " .. target:targetfile() .. " " .. shared_dir)
        
        print("---------------------------------------------------------- ")
    end)

--
-- If you want to known more usage about xmake, please see https://xmake.io
--
-- ## FAQ
--
-- You can enter the project directory firstly before building project.
--
--   $ cd projectdir
--
-- 1. How to build project?
--
--   $ xmake
--
-- 2. How to configure project?
--
--   $ xmake f -p [macosx|linux|iphoneos ..] -a [x86_64|i386|arm64 ..] -m [debug|release]
--
-- 3. Where is the build output directory?
--
--   The default output directory is `./build` and you can configure the output directory.
--
--   $ xmake f -o outputdir
--   $ xmake
--
-- 4. How to run and debug target after building project?
--
--   $ xmake run [targetname]
--   $ xmake run -d [targetname]
--
-- 5. How to install target to the system directory or other output directory?
--
--   $ xmake install
--   $ xmake install -o installdir
--
-- 6. Add some frequently-used compilation flags in xmake.lua
--
-- @code
--    -- add debug and release modes
--    add_rules("mode.debug", "mode.release")
--
--    -- add macro definition
--    add_defines("NDEBUG", "_GNU_SOURCE=1")
--
--    -- set warning all as error
--    set_warnings("all", "error")
--
--    -- set language: c99, c++11
--    set_languages("c99", "c++11")
--
--    -- set optimization: none, faster, fastest, smallest
--    set_optimize("fastest")
--
--    -- add include search directories
--    add_includedirs("/usr/include", "/usr/local/include")
--
--    -- add link libraries and search directories
--    add_links("tbox")
--    add_linkdirs("/usr/local/lib", "/usr/lib")
--
--    -- add system link libraries
--    add_syslinks("z", "pthread")
--
--    -- add compilation and link flags
--    add_cxflags("-stdnolib", "-fno-strict-aliasing")
--    add_ldflags("-L/usr/local/lib", "-lpthread", {force = true})
--
-- @endcode
--

