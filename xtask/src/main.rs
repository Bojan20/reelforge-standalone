//! ReelForge Build Tasks
//!
//! Usage:
//!   cargo xtask bundle          - Build VST3/CLAP plugins
//!   cargo xtask test            - Run all tests
//!   cargo xtask bench           - Run benchmarks
//!   cargo xtask docs            - Generate documentation
//!   cargo xtask release         - Full release build

use std::env;
use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{Context, Result, bail};
use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "xtask", about = "ReelForge build tasks")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Build VST3/CLAP plugins
    Bundle {
        /// Build in release mode
        #[arg(short, long)]
        release: bool,
    },
    /// Run all tests
    Test {
        /// Run only DSP tests
        #[arg(long)]
        dsp: bool,
    },
    /// Run benchmarks
    Bench,
    /// Generate documentation
    Docs {
        /// Open in browser
        #[arg(short, long)]
        open: bool,
    },
    /// Full release build
    Release {
        /// Target triple (e.g., x86_64-apple-darwin)
        #[arg(short, long)]
        target: Option<String>,
    },
    /// Check code quality
    Check,
    /// Create installer package (DMG/MSI/AppImage)
    Package {
        /// Build type
        #[arg(short, long, default_value = "release")]
        profile: String,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let project_root = project_root()?;

    match cli.command {
        Commands::Bundle { release } => bundle_plugins(&project_root, release),
        Commands::Test { dsp } => run_tests(&project_root, dsp),
        Commands::Bench => run_benchmarks(&project_root),
        Commands::Docs { open } => generate_docs(&project_root, open),
        Commands::Package { profile } => create_package(&project_root, &profile),
        Commands::Release { target } => build_release(&project_root, target),
        Commands::Check => check_quality(&project_root),
    }
}

fn project_root() -> Result<PathBuf> {
    let manifest_dir = env::var("CARGO_MANIFEST_DIR")
        .context("CARGO_MANIFEST_DIR not set")?;

    Ok(Path::new(&manifest_dir)
        .parent()
        .context("Failed to get parent directory")?
        .to_path_buf())
}

fn bundle_plugins(root: &Path, release: bool) -> Result<()> {
    println!("📦 Building ReelForge plugins...\n");

    let mut args = vec!["build", "-p", "rf-plugin"];
    if release {
        args.push("--release");
    }

    let status = Command::new("cargo")
        .current_dir(root)
        .args(&args)
        .status()
        .context("Failed to run cargo build")?;

    if !status.success() {
        bail!("Plugin build failed");
    }

    // Create plugin bundles
    let profile = if release { "release" } else { "debug" };
    let target_dir = root.join("target").join(profile);

    #[cfg(target_os = "macos")]
    {
        create_macos_bundles(root, &target_dir)?;
    }

    #[cfg(target_os = "windows")]
    {
        create_windows_bundles(root, &target_dir)?;
    }

    #[cfg(target_os = "linux")]
    {
        create_linux_bundles(root, &target_dir)?;
    }

    println!("\n✅ Plugin bundles created successfully!");
    Ok(())
}

#[cfg(target_os = "macos")]
fn create_macos_bundles(root: &Path, target_dir: &Path) -> Result<()> {
    use std::fs;

    let plugins = ["rf_plugin"];
    let bundle_dir = root.join("target").join("bundles");
    fs::create_dir_all(&bundle_dir)?;

    for plugin in plugins {
        let lib_name = format!("lib{}.dylib", plugin);
        let lib_path = target_dir.join(&lib_name);

        if !lib_path.exists() {
            println!("⚠️  {} not found, skipping", lib_name);
            continue;
        }

        // VST3 bundle
        let vst3_bundle = bundle_dir.join(format!("{}.vst3", plugin));
        let vst3_contents = vst3_bundle.join("Contents").join("MacOS");
        fs::create_dir_all(&vst3_contents)?;
        fs::copy(&lib_path, vst3_contents.join(plugin))?;

        // Create Info.plist
        let plist_content = format!(r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>{}</string>
    <key>CFBundleIdentifier</key>
    <string>audio.reelforge.{}</string>
    <key>CFBundleName</key>
    <string>ReelForge</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleVersion</key>
    <string>0.1.0</string>
</dict>
</plist>"#, plugin, plugin);

        fs::write(vst3_bundle.join("Contents").join("Info.plist"), &plist_content)?;

        println!("  📁 Created {}.vst3", plugin);

        // CLAP bundle
        let clap_bundle = bundle_dir.join(format!("{}.clap", plugin));
        let clap_contents = clap_bundle.join("Contents").join("MacOS");
        fs::create_dir_all(&clap_contents)?;
        fs::copy(&lib_path, clap_contents.join(plugin))?;
        fs::write(clap_bundle.join("Contents").join("Info.plist"), &plist_content)?;

        println!("  📁 Created {}.clap", plugin);
    }

    Ok(())
}

#[cfg(target_os = "windows")]
fn create_windows_bundles(root: &Path, target_dir: &Path) -> Result<()> {
    use std::fs;

    let plugins = ["rf_plugin"];
    let bundle_dir = root.join("target").join("bundles");
    fs::create_dir_all(&bundle_dir)?;

    for plugin in plugins {
        let dll_name = format!("{}.dll", plugin);
        let dll_path = target_dir.join(&dll_name);

        if !dll_path.exists() {
            println!("⚠️  {} not found, skipping", dll_name);
            continue;
        }

        // VST3
        let vst3_path = bundle_dir.join(format!("{}.vst3", plugin));
        fs::copy(&dll_path, &vst3_path)?;
        println!("  📁 Created {}.vst3", plugin);

        // CLAP
        let clap_path = bundle_dir.join(format!("{}.clap", plugin));
        fs::copy(&dll_path, &clap_path)?;
        println!("  📁 Created {}.clap", plugin);
    }

    Ok(())
}

#[cfg(target_os = "linux")]
fn create_linux_bundles(root: &Path, target_dir: &Path) -> Result<()> {
    use std::fs;

    let plugins = ["rf_plugin"];
    let bundle_dir = root.join("target").join("bundles");
    fs::create_dir_all(&bundle_dir)?;

    for plugin in plugins {
        let so_name = format!("lib{}.so", plugin);
        let so_path = target_dir.join(&so_name);

        if !so_path.exists() {
            println!("⚠️  {} not found, skipping", so_name);
            continue;
        }

        // VST3
        let vst3_path = bundle_dir.join(format!("{}.vst3", plugin));
        fs::copy(&so_path, &vst3_path)?;
        println!("  📁 Created {}.vst3", plugin);

        // CLAP
        let clap_path = bundle_dir.join(format!("{}.clap", plugin));
        fs::copy(&so_path, &clap_path)?;
        println!("  📁 Created {}.clap", plugin);
    }

    Ok(())
}

fn run_tests(root: &Path, dsp_only: bool) -> Result<()> {
    println!("🧪 Running tests...\n");

    let mut args = vec!["test"];
    if dsp_only {
        args.extend(["--package", "rf-dsp"]);
    } else {
        args.push("--workspace");
    }

    let status = Command::new("cargo")
        .current_dir(root)
        .args(&args)
        .status()
        .context("Failed to run tests")?;

    if !status.success() {
        bail!("Tests failed");
    }

    println!("\n✅ All tests passed!");
    Ok(())
}

fn run_benchmarks(root: &Path) -> Result<()> {
    println!("⏱️  Running benchmarks...\n");

    let status = Command::new("cargo")
        .current_dir(root)
        .args(["bench", "--package", "rf-dsp"])
        .status()
        .context("Failed to run benchmarks")?;

    if !status.success() {
        bail!("Benchmarks failed");
    }

    Ok(())
}

fn generate_docs(root: &Path, open: bool) -> Result<()> {
    println!("📚 Generating documentation...\n");

    let mut args = vec!["doc", "--workspace", "--no-deps"];
    if open {
        args.push("--open");
    }

    let status = Command::new("cargo")
        .current_dir(root)
        .args(&args)
        .status()
        .context("Failed to generate docs")?;

    if !status.success() {
        bail!("Documentation generation failed");
    }

    println!("\n✅ Documentation generated!");
    Ok(())
}

fn build_release(root: &Path, target: Option<String>) -> Result<()> {
    println!("🚀 Building release...\n");

    let mut args = vec!["build", "--release", "--workspace"];

    if let Some(ref t) = target {
        args.extend(["--target", t]);
    }

    let status = Command::new("cargo")
        .current_dir(root)
        .args(&args)
        .status()
        .context("Failed to build release")?;

    if !status.success() {
        bail!("Release build failed");
    }

    // Also build plugins
    bundle_plugins(root, true)?;

    println!("\n✅ Release build complete!");
    Ok(())
}

fn check_quality(root: &Path) -> Result<()> {
    println!("🔍 Checking code quality...\n");

    // Clippy
    println!("Running clippy...");
    let clippy_status = Command::new("cargo")
        .current_dir(root)
        .args(["clippy", "--workspace", "--", "-D", "warnings"])
        .status()
        .context("Failed to run clippy")?;

    if !clippy_status.success() {
        bail!("Clippy found issues");
    }

    // Format check
    println!("\nChecking formatting...");
    let fmt_status = Command::new("cargo")
        .current_dir(root)
        .args(["fmt", "--all", "--check"])
        .status()
        .context("Failed to check formatting")?;

    if !fmt_status.success() {
        println!("⚠️  Formatting issues found. Run 'cargo fmt' to fix.");
    }

    println!("\n✅ Code quality check complete!");
    Ok(())
}

fn create_package(root: &Path, profile: &str) -> Result<()> {
    use std::fs;

    println!("📦 Creating installer package...\n");

    let target_dir = root.join("target").join(profile);
    let package_dir = root.join("target").join("package");
    fs::create_dir_all(&package_dir)?;

    #[cfg(target_os = "macos")]
    {
        create_macos_dmg(root, &target_dir, &package_dir)?;
    }

    #[cfg(target_os = "windows")]
    {
        create_windows_installer(root, &target_dir, &package_dir)?;
    }

    #[cfg(target_os = "linux")]
    {
        create_linux_appimage(root, &target_dir, &package_dir)?;
    }

    println!("\n✅ Package created!");
    Ok(())
}

#[cfg(target_os = "macos")]
fn create_macos_dmg(root: &Path, target_dir: &Path, package_dir: &Path) -> Result<()> {
    use std::fs;

    println!("Creating macOS DMG...");

    let app_name = "ReelForge";
    let version = "0.1.0";

    // Create .app bundle structure
    let app_bundle = package_dir.join(format!("{}.app", app_name));
    let contents = app_bundle.join("Contents");
    let macos = contents.join("MacOS");
    let resources = contents.join("Resources");

    fs::create_dir_all(&macos)?;
    fs::create_dir_all(&resources)?;

    // Copy binary
    let binary_path = target_dir.join("reelforge");
    if binary_path.exists() {
        fs::copy(&binary_path, macos.join("reelforge"))?;
        println!("  ✓ Copied binary");
    } else {
        println!("  ⚠ Binary not found at {:?}", binary_path);
        println!("  Run 'cargo build --release' first");
    }

    // Create Info.plist
    let plist = format!(r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>{}</string>
    <key>CFBundleDisplayName</key>
    <string>{}</string>
    <key>CFBundleIdentifier</key>
    <string>audio.reelforge.app</string>
    <key>CFBundleVersion</key>
    <string>{}</string>
    <key>CFBundleShortVersionString</key>
    <string>{}</string>
    <key>CFBundleExecutable</key>
    <string>reelforge</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>"#, app_name, app_name, version, version);

    fs::write(contents.join("Info.plist"), plist)?;
    println!("  ✓ Created Info.plist");

    // Create DMG using hdiutil
    let dmg_path = package_dir.join(format!("{}-{}-macos.dmg", app_name, version));

    // First create a temporary folder for DMG contents
    let dmg_temp = package_dir.join("dmg_temp");
    fs::create_dir_all(&dmg_temp)?;

    // Copy app bundle to temp
    let dest_app = dmg_temp.join(format!("{}.app", app_name));
    copy_dir_all(&app_bundle, &dest_app)?;

    // Create symlink to Applications
    #[cfg(unix)]
    {
        use std::os::unix::fs::symlink;
        let _ = symlink("/Applications", dmg_temp.join("Applications"));
    }

    // Create DMG
    let status = Command::new("hdiutil")
        .args([
            "create",
            "-volname", app_name,
            "-srcfolder", dmg_temp.to_str().unwrap(),
            "-ov",
            "-format", "UDZO",
            dmg_path.to_str().unwrap(),
        ])
        .status();

    match status {
        Ok(s) if s.success() => {
            println!("  ✓ Created DMG: {:?}", dmg_path);
        }
        _ => {
            println!("  ⚠ Failed to create DMG (hdiutil not available)");
            println!("  App bundle available at: {:?}", app_bundle);
        }
    }

    // Cleanup
    let _ = fs::remove_dir_all(&dmg_temp);

    Ok(())
}

fn copy_dir_all(src: &Path, dst: &Path) -> Result<()> {
    use std::fs;

    fs::create_dir_all(dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let ty = entry.file_type()?;
        let dst_path = dst.join(entry.file_name());

        if ty.is_dir() {
            copy_dir_all(&entry.path(), &dst_path)?;
        } else {
            fs::copy(entry.path(), dst_path)?;
        }
    }
    Ok(())
}

#[cfg(target_os = "windows")]
fn create_windows_installer(_root: &Path, target_dir: &Path, package_dir: &Path) -> Result<()> {
    use std::fs;

    println!("Creating Windows installer...");

    let app_name = "ReelForge";
    let version = "0.1.0";

    // Copy executable
    let exe_path = target_dir.join("reelforge.exe");
    let dest_exe = package_dir.join("reelforge.exe");

    if exe_path.exists() {
        fs::copy(&exe_path, &dest_exe)?;
        println!("  ✓ Copied executable");
    } else {
        println!("  ⚠ Executable not found");
    }

    // Create a simple batch installer script
    let installer_script = format!(r#"@echo off
echo Installing {} v{}...
mkdir "%ProgramFiles%\ReelForge" 2>nul
copy /Y reelforge.exe "%ProgramFiles%\ReelForge\"
echo Installation complete!
pause
"#, app_name, version);

    fs::write(package_dir.join("install.bat"), installer_script)?;
    println!("  ✓ Created install.bat");

    println!("\n  For production, use NSIS or WiX to create proper MSI installer");

    Ok(())
}

#[cfg(target_os = "linux")]
fn create_linux_appimage(_root: &Path, target_dir: &Path, package_dir: &Path) -> Result<()> {
    use std::fs;

    println!("Creating Linux AppImage...");

    let app_name = "ReelForge";
    let version = "0.1.0";

    // Create AppDir structure
    let appdir = package_dir.join(format!("{}.AppDir", app_name));
    let usr_bin = appdir.join("usr").join("bin");
    fs::create_dir_all(&usr_bin)?;

    // Copy executable
    let exe_path = target_dir.join("reelforge");
    if exe_path.exists() {
        fs::copy(&exe_path, usr_bin.join("reelforge"))?;
        println!("  ✓ Copied executable");
    }

    // Create .desktop file
    let desktop = format!(r#"[Desktop Entry]
Name={}
Exec=reelforge
Icon=reelforge
Type=Application
Categories=AudioVideo;Audio;
"#, app_name);

    fs::write(appdir.join(format!("{}.desktop", app_name.to_lowercase())), desktop)?;

    // Create AppRun script
    let apprun = r#"#!/bin/bash
SELF=$(readlink -f "$0")
HERE=${SELF%/*}
export PATH="${HERE}/usr/bin:${PATH}"
exec "${HERE}/usr/bin/reelforge" "$@"
"#;

    let apprun_path = appdir.join("AppRun");
    fs::write(&apprun_path, apprun)?;

    // Make AppRun executable
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = fs::metadata(&apprun_path)?.permissions();
        perms.set_mode(0o755);
        fs::set_permissions(&apprun_path, perms)?;
    }

    println!("  ✓ Created AppDir structure");
    println!("\n  To create AppImage, run:");
    println!("  appimagetool {}.AppDir {}-{}-x86_64.AppImage", app_name, app_name, version);

    Ok(())
}
