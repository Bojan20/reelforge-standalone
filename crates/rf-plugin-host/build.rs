fn main() {
    // Compile ObjC helper for AUv3 hosting
    cc::Build::new()
        .file("src/au_host.m")
        .flag("-fobjc-arc")
        .flag("-fmodules")
        .compile("au_host");

    // Link frameworks
    println!("cargo:rustc-link-lib=framework=AppKit");
    println!("cargo:rustc-link-lib=framework=AudioToolbox");
    println!("cargo:rustc-link-lib=framework=CoreAudioKit");
    println!("cargo:rustc-link-lib=framework=AVFoundation");
    println!("cargo:rustc-link-lib=framework=CoreFoundation");
}
