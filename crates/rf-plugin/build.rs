fn main() {
    #[cfg(target_os = "macos")]
    {
        // Compile ObjC helper for AU plugin hosting (in-process)
        cc::Build::new()
            .file("src/au_host.m")
            .flag("-fobjc-arc")
            .flag("-fmodules")
            .compile("au_host");

        // Link frameworks needed for AU hosting
        println!("cargo:rustc-link-lib=framework=AppKit");
        println!("cargo:rustc-link-lib=framework=AudioToolbox");
        println!("cargo:rustc-link-lib=framework=CoreAudioKit");
        println!("cargo:rustc-link-lib=framework=AVFoundation");
        println!("cargo:rustc-link-lib=framework=CoreFoundation");
    }
}
