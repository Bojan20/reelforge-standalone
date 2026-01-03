//! ReelForge Tauri Application
//!
//! Bridges React frontend with Rust audio engine.

mod audio;
mod commands;
mod state;

use state::AppState;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_log::Builder::default().level(log::LevelFilter::Info).build())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .manage(AppState::new())
        .invoke_handler(tauri::generate_handler![
            // Audio engine commands
            commands::init_audio_engine,
            commands::start_audio,
            commands::stop_audio,
            commands::get_audio_status,
            // Mixer commands
            commands::set_channel_volume,
            commands::set_channel_pan,
            commands::set_channel_mute,
            commands::set_channel_solo,
            commands::set_master_volume,
            commands::set_master_limiter,
            // Metering
            commands::get_meters,
            // Transport
            commands::play,
            commands::stop,
            commands::set_position,
            commands::get_position,
        ])
        .setup(|app| {
            log::info!("ReelForge starting...");

            // Start meter update thread
            let handle = app.handle().clone();
            std::thread::spawn(move || {
                audio::meter_broadcast_loop(handle);
            });

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
