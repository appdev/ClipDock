use std::path::PathBuf;

fn main() {
    let manifest_dir =
        PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR is required"));
    let bridge_source = manifest_dir.join("src/lib.rs");
    let generated_dir = manifest_dir.join("../../target/swift-bridge/generated");

    println!("cargo:rerun-if-changed={}", bridge_source.display());

    swift_bridge_build::parse_bridges([bridge_source])
        .write_all_concatenated(generated_dir, env!("CARGO_PKG_NAME"));
}
