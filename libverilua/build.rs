fn main() {
    if std::env::var("CARGO_FEATURE_IVERILOG_VPI_MOD").is_ok() {
        println!("cargo:rustc-link-lib=static=vpi");
        println!("cargo:rustc-link-lib=static=veriuser");

        println!("cargo:rustc-link-search=native=/usr/local/lib");
        if let Ok(iverilog_home) = std::env::var("IVERILOG_HOME") {
            println!("cargo:rustc-link-search=native={iverilog_home}/lib");
        }
        if let Ok(paths) = std::env::var("LD_LIBRARY_PATH") {
            for path in paths.split(':') {
                println!("cargo:rustc-link-search=native={path}");
            }
        }
    }

    extern crate cpp_build;
    cpp_build::build("src/utils/mod.rs");
}
