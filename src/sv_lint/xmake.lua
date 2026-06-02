---@diagnostic disable

local prj_dir = os.projectdir()
local curr_dir = os.scriptdir()
local build_dir = path.join(prj_dir, "build")
local libs_dir = path.join(prj_dir, "conan_installed")
local boost_unordered_dir = path.join(prj_dir, "extern", "boost_unordered")

target("sv_lint", function()
    set_kind("binary")
    add_ldflags("-static")

    set_languages("c99", "c++20")
    set_targetdir(path.join(build_dir, "bin"))
    set_objectdir(path.join(build_dir, "obj"))

    if is_mode("debug") then
        set_symbols("debug")
        set_optimize("none")
    end

    add_files(path.join(curr_dir, "main.cpp"))

    add_defines("SLANG_BOOST_SINGLE_HEADER")

    add_includedirs(
        curr_dir,
        boost_unordered_dir,
        path.join(libs_dir, "include")
    )

    add_links("svlang", "fmt", "mimalloc")
    add_linkdirs(path.join(libs_dir, "lib"))
    add_rpathdirs(path.join(libs_dir, "lib"))

    before_build(function(target)
        local version = io.readfile(path.join(prj_dir, "VERSION")):trim()
        target:add("defines", format([[VERILUA_VERSION="%s"]], version))
    end)
end)

target("libsv_lint", function()
    set_kind("shared")
    set_basename("sv_lint")

    set_languages("c99", "c++20")
    set_targetdir(path.join(build_dir, "shared"))
    set_objectdir(path.join(build_dir, "obj"))

    if is_mode("debug") then
        set_symbols("debug")
        set_optimize("none")
    end

    add_files(path.join(curr_dir, "sv_lint_lib.cpp"))

    add_defines("SLANG_BOOST_SINGLE_HEADER")

    add_includedirs(
        curr_dir,
        boost_unordered_dir,
        path.join(libs_dir, "include")
    )

    add_links("svlang", "fmt", "mimalloc")
    add_linkdirs(path.join(libs_dir, "lib"))
    add_rpathdirs(path.join(libs_dir, "lib"))
end)
