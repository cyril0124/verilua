fn main() {
    if std::env::var("CARGO_FEATURE_IVERILOG_VPI_MOD").is_ok() {
        // Rebuild when toolchain search paths change; otherwise cargo reuses a
        // stale link line after IVERILOG_HOME / LD_LIBRARY_PATH moves.
        println!("cargo:rerun-if-env-changed=IVERILOG_HOME");
        println!("cargo:rerun-if-env-changed=LD_LIBRARY_PATH");

        println!("cargo:rustc-link-lib=static=vpi");

        println!("cargo:rustc-link-search=native=/usr/local/lib");
        if let Ok(iverilog_home) = std::env::var("IVERILOG_HOME") {
            println!("cargo:rustc-link-search=native={iverilog_home}/lib");
        }
        if let Ok(paths) = std::env::var("LD_LIBRARY_PATH") {
            for path in paths.split(':').filter(|p| !p.is_empty()) {
                println!("cargo:rustc-link-search=native={path}");
            }
        }
    }

    extern crate cpp_build;
    cpp_build::build("src/utils/mod.rs");
}
