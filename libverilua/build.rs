fn main() {
    if std::env::var("CARGO_FEATURE_IVERILOG_VPI_MOD").is_ok() {
        if let Ok(iverilog_home) = std::env::var("IVERILOG_HOME") {
            println!("cargo:rustc-link-lib=static=vpi");
            println!("cargo:rustc-link-lib=static=veriuser");
            println!("cargo:rustc-link-search=native={iverilog_home}/lib");
        } else {
            panic!("IVERILOG_HOME is not set");
        }
    }

    extern crate cpp_build;
    cpp_build::build("src/utils/mod.rs");
}
