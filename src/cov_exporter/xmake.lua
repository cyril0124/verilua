---@diagnostic disable

local prj_dir = os.projectdir()
local curr_dir = os.scriptdir()
local libs_dir = path.join(prj_dir, "conan_installed")
local slang_common_dir = path.join(prj_dir, "extern", "slang-common")
local boost_unordered_dir = path.join(prj_dir, "extern", "boost_unordered")

target("cov_exporter", function()
    set_kind("binary")
    add_ldflags("-static")

    set_languages("c++20")

    add_files(
        path.join(curr_dir, "*.cpp"),
        path.join(slang_common_dir, "*.cpp")
    )

    add_defines("SLANG_BOOST_SINGLE_HEADER")

    add_includedirs(
        slang_common_dir,
        boost_unordered_dir,
        path.join(libs_dir, "include"),
        path.join(curr_dir, "include")
    )

    add_links("svlang", "fmt", "mimalloc")
    add_links("assert", "cpptrace", "dwarf", "zstd", "z") -- libassert
    add_linkdirs(path.join(libs_dir, "lib"))
    add_rpathdirs(path.join(libs_dir, "lib"))

    before_build(function(target)
        -- Add version info
        local version = io.readfile(path.join(prj_dir, "VERSION")):trim()
        target:add("defines", format([[VERILUA_VERSION="%s"]], version))
    end)

    after_build(function(target)
        os.cp(target:targetfile(), path.join(prj_dir, "tools"))
    end)
end)
