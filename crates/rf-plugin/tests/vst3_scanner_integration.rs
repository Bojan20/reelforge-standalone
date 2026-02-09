//! Integration test for VST3 scanner
//!
//! Tests actual VST3 plugin discovery on the system

use rf_plugin::{PluginInstance, PluginScanner, PluginType};

#[test]
fn test_scan_vst3_directory() {
    let mut scanner = PluginScanner::new();

    // Scan actual VST3 directory
    let vst3_path = std::path::PathBuf::from("/Library/Audio/Plug-Ins/VST3");

    if !vst3_path.exists() {
        println!("VST3 directory not found, skipping test");
        return;
    }

    // Add path and scan
    scanner.add_path(PluginType::Vst3, vst3_path);
    let result = scanner.scan_all();

    assert!(result.is_ok(), "Scan failed: {:?}", result.err());

    let plugins = result.unwrap();
    println!("Found {} plugins", plugins.len());

    // Print first 10 plugins for debugging
    for (i, plugin) in plugins.iter().take(10).enumerate() {
        println!(
            "{}. {} by {} ({:?})",
            i + 1,
            plugin.name,
            plugin.vendor,
            plugin.plugin_type
        );
    }

    // Should find at least some plugins
    assert!(!plugins.is_empty(), "No plugins found");

    // Look for FabFilter Pro-Q 4 specifically
    let pro_q = plugins
        .iter()
        .find(|p| p.name.contains("Pro-Q") || p.name.contains("FabFilter"));

    if let Some(plugin) = pro_q {
        println!("\nFound FabFilter plugin:");
        println!("  Name: {}", plugin.name);
        println!("  Vendor: {}", plugin.vendor);
        println!("  Path: {:?}", plugin.path);
        println!("  ID: {}", plugin.id);
    }
}

#[test]
fn test_load_vst3_plugin() {
    // Try to load FabFilter Pro-Q 4
    let plugin_path =
        std::path::PathBuf::from("/Library/Audio/Plug-Ins/VST3/FabFilter Pro-Q 4.vst3");

    if !plugin_path.exists() {
        println!("FabFilter Pro-Q 4 not found, skipping test");
        return;
    }

    let result = rf_plugin::vst3::Vst3Host::load(&plugin_path);

    assert!(result.is_ok(), "Failed to load plugin: {:?}", result.err());

    let host = result.unwrap();
    println!("Loaded plugin: {}", host.info().name);
    println!("Parameters: {}", host.parameter_count());

    // Should have some parameters
    assert!(host.parameter_count() > 0);
}
