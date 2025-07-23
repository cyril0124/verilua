---@diagnostic disable

local prj_dir = os.projectdir()
local curr_dir = os.scriptdir()
local shared_dir = path.join(prj_dir, "shared")
local build_dir = path.join(prj_dir, "build")
local libs_dir = path.join(prj_dir, "conan_installed")
local lua_dir = path.join(prj_dir, "luajit-pro", "luajit2.1")
local wavevpi_dir = path.join(prj_dir, "wave_vpi")
local boost_unordered_dir = path.join(prj_dir, "extern", "boost_unordered")

local function wave_vpi_main_common()
    set_kind("binary")

    add_deps("libverilua_wave_vpi")

    set_languages("c99", "c++20")
    set_targetdir(path.join(build_dir, "bin"))
    set_objectdir(path.join(build_dir, "obj"))

    add_shflags(
        "-static-libstdc++ -static-libgcc",
        "-Wl,--no-as-needed"
    )

    add_defines("VL_DEF_OPT_USE_BOOST_UNORDERED")

    add_files(
        path.join(curr_dir, "*.cpp"),
        path.join(wavevpi_dir, "src", "*.cc")
    )

    add_includedirs(
        boost_unordered_dir,
        path.join(wavevpi_dir, "src"),
        path.join(libs_dir, "include"),
        path.join(lua_dir, "include", "luajit-2.1")
    )

    if is_mode("debug") then
        add_defines("DEBUG")
        set_symbols("debug")
        set_optimize("none")
        -- add_cxflags("-fsanitize=address", "-fno-omit-frame-pointer", "-fno-optimize-sibling-calls")
        -- add_ldflags("-fsanitize=address")
    else
        add_cxflags("-O2 -funroll-loops -march=native -fomit-frame-pointer")
    end

    add_linkgroups("luajit-5.1", {static = true, whole = true})
    add_linkdirs(path.join(lua_dir, "lib"))

    add_links("luajit_pro_helper")
    add_linkdirs(path.join(prj_dir, "luajit-pro", "target", "release"))
    add_rpathdirs(path.join(prj_dir, "luajit-pro", "target", "release"))

    add_links("fmt", "mimalloc")
    add_links("assert", "cpptrace", "dwarf", "zstd", "z") -- libassert
    add_linkdirs(path.join(libs_dir, "lib"))

    add_links("verilua_wave_vpi")
    add_linkdirs(shared_dir)
    add_rpathdirs(shared_dir)

    add_links("wave_vpi_wellen_impl")
    add_linkdirs(path.join(wavevpi_dir, "target", "release"))

    before_build(function (target)
        -- Add version info
        target:add("defines", format([[VERILUA_VERSION="%s"]], io.readfile(path.join(prj_dir, "VERSION"))))
    end)

    after_build(function (target)
        os.cp(target:targetfile(), path.join(prj_dir, "tools"))
    end)
end

target("wave_vpi_main")
    wave_vpi_main_common()

target("wave_vpi_main_fsdb")
    if os.getenv("VERDI_HOME") then
        wave_vpi_main_common()

        local verdi_home = os.getenv("VERDI_HOME")

        add_includedirs(path.join(verdi_home, "share", "FsdbReader"))

        add_links("nffr", "nsys", "z")
        add_linkdirs(path.join(verdi_home, "share", "FsdbReader", "LINUX64"))
        add_rpathdirs(path.join(verdi_home, "share", "FsdbReader", "LINUX64"))

        add_defines("USE_FSDB")

        before_build(function (target)
            assert(os.host() == "linux", "[wave_vpi_main_fsdb] `wave_vpi_main_fsdb` is only supported on linux")
            print("[wave_vpi_main_fsdb] verdi_home: " .. verdi_home)
        end)
    else
        set_kind("phony")
        on_build(function(target)
            raise("[wave_vpi_main_fsdb] VERDI_HOME is not defined!")
        end)
    end

