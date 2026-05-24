---@diagnostic disable

local curr_dir = os.scriptdir()
local prj_dir = path.join(curr_dir, "..", "..")
local libs_dir = path.join(prj_dir, "conan_installed")
local slang_common_dir = path.join(prj_dir, "src", "slang_common")
local boost_unordered_dir = path.join(prj_dir, "extern", "boost_unordered")

target("test_slang_common", function()
    set_kind("binary")
    set_default(false)

    -- Match cov_exporter / dpi_exporter / signal_db_gen / testbench_gen.
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
        path.join(libs_dir, "include")
    )

    add_links("svlang", "fmt", "mimalloc")
    add_links("assert", "cpptrace", "dwarf", "zstd", "z") -- libassert
    add_linkdirs(path.join(libs_dir, "lib"))
    add_rpathdirs(path.join(libs_dir, "lib"))

    -- Static libstdc++ / libmimalloc / libgcc_eh need pthread/dl/rt explicitly.
    add_syslinks("pthread", "dl", "rt")
end)
