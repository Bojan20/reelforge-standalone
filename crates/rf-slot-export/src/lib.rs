//! rf-slot-export — FluxForge UCP Export Engine
//!
//! ## T3.1: ExportTarget trait + shared types
//! ## T3.2: Howler.js AudioSprite exporter (Playa compatible)
//! ## T3.3: Wwise project exporter (XML authoring data)
//! ## T3.4: FMOD Studio project exporter
//! ## T3.5: Generic JSON exporter
//!
//! ## Usage
//!
//! ```rust,ignore
//! use rf_slot_export::{HowlerAudioSpriteExporter, ExportTarget, FluxForgeExportProject};
//!
//! let project = FluxForgeExportProject::new("My Slot", "my_slot");
//! // ... populate events ...
//!
//! let exporter = HowlerAudioSpriteExporter;
//! let bundle = exporter.export(&project)?;
//! for file in &bundle.files {
//!     std::fs::write(&file.filename, &file.content)?;
//! }
//! ```

pub mod types;
pub mod howler;
pub mod wwise;
pub mod fmod;
pub mod json_export;

// ── Public re-exports ─────────────────────────────────────────────────────────
pub use types::{
    ExportTarget, ExportBundle, ExportFile, ExportError,
    FluxForgeExportProject, AudioEventExport, WinTierExport,
    AudioTierExport, AudioEventCategory,
};
pub use howler::HowlerAudioSpriteExporter;
pub use wwise::WwiseBankExporter;
pub use fmod::FModBankExporter;
pub use json_export::GenericJsonExporter;

// ═══════════════════════════════════════════════════════════════════════════════
// CONVENIENCE: Export to all targets at once
// ═══════════════════════════════════════════════════════════════════════════════

/// Export a project to all available formats simultaneously.
///
/// Returns a map from format name → export result.
/// Failed targets are included as Err entries.
pub fn export_all(
    project: &FluxForgeExportProject,
) -> Vec<(String, Result<ExportBundle, ExportError>)> {
    let targets: Vec<Box<dyn ExportTarget>> = vec![
        Box::new(HowlerAudioSpriteExporter),
        Box::new(WwiseBankExporter),
        Box::new(FModBankExporter),
        Box::new(GenericJsonExporter),
    ];

    targets.into_iter()
        .map(|t| {
            let name = t.format_name().to_string();
            let result = t.export(project);
            (name, result)
        })
        .collect()
}

/// List all available export formats
pub fn available_formats() -> Vec<(&'static str, &'static str)> {
    vec![
        (HowlerAudioSpriteExporter.format_name(), HowlerAudioSpriteExporter.format_version()),
        (WwiseBankExporter.format_name(), WwiseBankExporter.format_version()),
        (FModBankExporter.format_name(), FModBankExporter.format_version()),
        (GenericJsonExporter.format_name(), GenericJsonExporter.format_version()),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::{AudioEventCategory, AudioEventExport, AudioTierExport};

    fn test_project() -> FluxForgeExportProject {
        let mut p = FluxForgeExportProject::new("Test Game", "test_game");
        p.rtp_target = 96.0;
        p.voice_budget = 48;
        p.exported_at = "2026-04-16".to_string();

        for name in ["SPIN_START", "REEL_SPIN", "WIN_1", "WIN_3", "WIN_5", "FREE_SPIN_TRIGGER"] {
            let mut ev = AudioEventExport::new(name);
            ev.duration_ms = 1000;
            ev.category = if name.starts_with("WIN") {
                AudioEventCategory::Win
            } else if name.starts_with("FREE") {
                AudioEventCategory::Feature
            } else {
                AudioEventCategory::BaseGame
            };
            ev.tier = AudioTierExport::Standard;
            p.audio_events.push(ev);
        }
        p
    }

    #[test]
    fn test_all_formats_produce_bundles() {
        let project = test_project();
        let results = export_all(&project);
        assert_eq!(results.len(), 4);
        for (format, result) in &results {
            assert!(result.is_ok(), "Export failed for {}: {:?}", format, result.as_ref().err());
        }
    }

    #[test]
    fn test_available_formats_returns_four() {
        let formats = available_formats();
        assert_eq!(formats.len(), 4);
    }

    #[test]
    fn test_export_all_events_consistent_count() {
        let project = test_project();
        let results = export_all(&project);
        for (format, result) in &results {
            let bundle = result.as_ref().unwrap();
            assert_eq!(
                bundle.event_count, project.audio_events.len(),
                "Event count mismatch for {}", format
            );
        }
    }

    #[test]
    fn test_empty_project_all_fail() {
        let empty = FluxForgeExportProject::new("Empty", "empty");
        let results = export_all(&empty);
        for (format, result) in &results {
            assert!(result.is_err(), "Expected error for empty project in {}", format);
        }
    }
}
