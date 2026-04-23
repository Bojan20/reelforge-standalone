//! FMOD Studio Project Exporter — T3.4
//!
//! Generates FMOD Studio-compatible project metadata.
//!
//! ## What This Generates
//!
//! FMOD Studio .bank files require FMOD Studio desktop application compilation.
//! FluxForge generates the structured JSON that can be used with FMOD Studio's
//! command-line builder or imported via FMOD Studio's project structure.
//!
//! ### Output files:
//! - `{id}_fmod_events.json` — Event definitions for FMOD Studio
//! - `{id}_fmod_buses.json` — Mixer bus routing
//! - `{id}_fmod_parameters.json` — Game parameters (FMOD equivalent of RTPCs)
//! - `FMOD_INTEGRATION_GUIDE.txt` — C++ integration reference

use serde_json::{json, Value};
use crate::types::{
    AudioEventCategory, ExportBundle, ExportError, ExportFile, ExportTarget,
    FluxForgeExportProject,
};

/// FMOD Studio project exporter
pub struct FModBankExporter;

impl ExportTarget for FModBankExporter {
    fn format_name(&self) -> &'static str { "FMOD Studio Project" }
    fn format_version(&self) -> &'static str { "2.02" }
    fn primary_extension(&self) -> &'static str { "json" }

    fn export(&self, project: &FluxForgeExportProject) -> Result<ExportBundle, ExportError> {
        if project.audio_events.is_empty() {
            return Err(ExportError::EmptyProject);
        }

        let game_id = sanitize_id(&project.game_id);

        // ── 1. Event definitions ──────────────────────────────────────────────
        let events_json = build_events_json(project);
        let events_str = serde_json::to_string_pretty(&events_json)
            .map_err(|e| ExportError::Serialization(e.to_string()))?;

        // ── 2. Mixer buses ────────────────────────────────────────────────────
        let buses_json = build_buses_json(project);
        let buses_str = serde_json::to_string_pretty(&buses_json)
            .map_err(|e| ExportError::Serialization(e.to_string()))?;

        // ── 3. Parameters (FMOD Game Parameters) ─────────────────────────────
        let params_json = build_parameters_json(project);
        let params_str = serde_json::to_string_pretty(&params_json)
            .map_err(|e| ExportError::Serialization(e.to_string()))?;

        // ── 4. Snapshot config ────────────────────────────────────────────────
        let snapshots_json = build_snapshots_json(project);
        let snapshots_str = serde_json::to_string_pretty(&snapshots_json)
            .map_err(|e| ExportError::Serialization(e.to_string()))?;

        let readme = build_readme(project);

        let mut bundle = ExportBundle::new(self.format_name(), self.format_version())
            .with_event_count(project.audio_events.len());

        bundle.files = vec![
            ExportFile::json(
                format!("{game_id}_fmod_events.json"),
                events_str,
            ).with_path("fmod/"),
            ExportFile::json(
                format!("{game_id}_fmod_buses.json"),
                buses_str,
            ).with_path("fmod/"),
            ExportFile::json(
                format!("{game_id}_fmod_parameters.json"),
                params_str,
            ).with_path("fmod/"),
            ExportFile::json(
                format!("{game_id}_fmod_snapshots.json"),
                snapshots_str,
            ).with_path("fmod/"),
            ExportFile::text(
                "FMOD_INTEGRATION_GUIDE.txt".to_string(),
                readme,
                "text/plain",
            ).with_path("fmod/"),
        ];

        bundle.warnings.push(
            "This export produces FMOD Studio PROJECT DATA, not compiled .bank files. \
             Import into FMOD Studio and use File > Build to generate .bank files.".to_string()
        );

        Ok(bundle)
    }
}

fn sanitize_id(id: &str) -> String {
    id.chars()
        .map(|c| if c.is_alphanumeric() || c == '_' { c } else { '_' })
        .collect()
}

fn build_events_json(project: &FluxForgeExportProject) -> Value {
    let events: Vec<Value> = project.audio_events.iter().map(|ev| {
        let folder = match ev.category {
            AudioEventCategory::BaseGame => "Base Game",
            AudioEventCategory::Win => "Wins",
            AudioEventCategory::NearMiss => "Near Miss",
            AudioEventCategory::Feature => "Features",
            AudioEventCategory::Jackpot => "Jackpot",
            AudioEventCategory::Special => "Special",
            AudioEventCategory::Ambient => "Ambient",
        };

        json!({
            "name": ev.name,
            "path": format!("event:/SlotGame/{}/{}", folder, ev.name),
            "folder": folder,
            "description": ev.description,
            "category": format!("{:?}", ev.category),
            "tier": format!("{:?}", ev.tier),
            "durationMs": ev.duration_ms,
            "maxInstances": ev.voice_count,
            "cooldownMs": 0,
            "priority": ev.priority,
            "spatializer": false,
            "doppler": false,
            "looping": ev.should_loop(),
            "oneshot": !ev.should_loop(),
            "parameters": build_event_parameters(ev),
            // FMOD Studio automation tracks
            "timeline": {
                "type": "timeline",
                "length": ev.duration_ms,
                "instruments": [
                    {
                        "type": "single_sound",
                        "startMs": 0,
                        "lengthMs": ev.duration_ms,
                        "assetPath": format!("Assets/SFX_{}.wav", ev.name),
                    }
                ]
            }
        })
    }).collect();

    json!({
        "_meta": {
            "game": project.game_name,
            "gameId": project.game_id,
            "rtpTarget": project.rtp_target,
            "exportedAt": project.exported_at,
            "fluxforgeVersion": project.tool_version,
        },
        "bankName": format!("SlotGame_{}", sanitize_id(&project.game_id)),
        "events": events
    })
}

fn build_event_parameters(ev: &crate::types::AudioEventExport) -> Vec<Value> {
    let mut params = Vec::new();

    // Win ratio parameter for WIN_N events
    if ev.name.starts_with("WIN_") || ev.name.starts_with("JACKPOT_") {
        params.push(json!({
            "name": "WinRatio",
            "type": "continuous",
            "min": 0.0,
            "max": 300.0,
            "default": 1.0,
        }));
    }

    // Intensity for base game events
    if ev.category == AudioEventCategory::BaseGame {
        params.push(json!({
            "name": "Intensity",
            "type": "continuous",
            "min": 0.0,
            "max": 1.0,
            "default": 0.5,
        }));
    }

    params
}

fn build_buses_json(project: &FluxForgeExportProject) -> Value {
    json!({
        "masterBus": {
            "name": "Master",
            "volume": 1.0,
            "children": [
                {
                    "name": "SlotGame",
                    "volume": 1.0,
                    "maxVoices": project.voice_budget,
                    "children": [
                        { "name": "BaseGame", "volume": 1.0 },
                        { "name": "Wins", "volume": 1.0 },
                        { "name": "NearMiss", "volume": 1.0 },
                        { "name": "Features", "volume": 1.0 },
                        { "name": "Jackpot", "volume": 1.0 },
                        { "name": "Special", "volume": 1.0 },
                        { "name": "Ambient", "volume": 0.7 }
                    ]
                }
            ]
        }
    })
}

fn build_parameters_json(project: &FluxForgeExportProject) -> Value {
    json!({
        "game": project.game_name,
        "parameters": [
            {
                "name": "WinRatio",
                "type": "game_parameter",
                "min": 0.0,
                "max": 300.0,
                "default": 0.0,
                "description": "Win amount / bet amount (0=loss, 1=even, 300=300x jackpot)"
            },
            {
                "name": "SessionHeat",
                "type": "game_parameter",
                "min": 0.0,
                "max": 1.0,
                "default": 0.5,
                "description": "Player session emotional state (0=cold/losing, 1=hot/winning)"
            },
            {
                "name": "SpinSpeed",
                "type": "game_parameter",
                "min": 0.5,
                "max": 3.0,
                "default": 1.0,
                "description": "Reel spin speed multiplier"
            },
            {
                "name": "VoiceLoad",
                "type": "game_parameter",
                "min": 0.0,
                "max": 1.0,
                "default": 0.0,
                "description": "Normalized voice load (0=empty, 1=budget full)"
            }
        ]
    })
}

fn build_snapshots_json(project: &FluxForgeExportProject) -> Value {
    // FMOD snapshots for different game states (override mixer volumes)
    let jackpot_name = format!("{}_Jackpot", sanitize_id(&project.game_id));
    let feature_name = format!("{}_Feature", sanitize_id(&project.game_id));

    json!({
        "game": project.game_name,
        "snapshots": [
            {
                "name": jackpot_name,
                "description": "Jackpot celebration — boost all buses",
                "busOverrides": [
                    { "bus": "SlotGame/Jackpot", "volume": 1.0 },
                    { "bus": "SlotGame/BaseGame", "volume": 0.0 },
                    { "bus": "SlotGame/Ambient", "volume": 0.0 }
                ]
            },
            {
                "name": feature_name,
                "description": "Feature active — reduce base game audio",
                "busOverrides": [
                    { "bus": "SlotGame/Features", "volume": 1.0 },
                    { "bus": "SlotGame/BaseGame", "volume": 0.3 }
                ]
            }
        ]
    })
}

fn build_readme(project: &FluxForgeExportProject) -> String {
    format!(
        "# FMOD Studio Integration Guide — {}\n\
         # Generated by FluxForge Studio\n\
         # Game ID: {} | RTP: {:.2}%\n\
         #\n\
         # ═══════════════════════════════════════════════════════\n\
         # IMPORT INSTRUCTIONS\n\
         # ═══════════════════════════════════════════════════════\n\
         #\n\
         # 1. Open FMOD Studio 2.02+\n\
         # 2. Create new project for your platform\n\
         # 3. Use the JSON files as reference to:\n\
         #    - Create events matching *_fmod_events.json\n\
         #    - Set up bus routing from *_fmod_buses.json\n\
         #    - Add Game Parameters from *_fmod_parameters.json\n\
         #    - Create Snapshots from *_fmod_snapshots.json\n\
         # 4. Add your audio assets (.wav/.flac) to each event\n\
         # 5. Build: File > Build All → generates Master.bank\n\
         #\n\
         # ═══════════════════════════════════════════════════════\n\
         # C++ INTEGRATION\n\
         # ═══════════════════════════════════════════════════════\n\
         #\n\
         # FMOD_GUID eventGuid;\n\
         # system->lookupID(\"event:/SlotGame/Base Game/SPIN_START\", &eventGuid);\n\
         # FMOD::Studio::EventInstance* instance;\n\
         # system->createInstanceByID(eventGuid, &instance);\n\
         # instance->start();\n\
         # instance->setParameterByName(\"WinRatio\", 15.0f);\n\
         #\n\
         # Events: {} | Required: {}\n",
        project.game_name,
        project.game_id,
        project.rtp_target,
        project.audio_events.len(),
        project.audio_events.iter().filter(|e| e.is_required).count(),
    )
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::{AudioEventCategory, AudioEventExport, AudioTierExport};

    fn sample_project() -> FluxForgeExportProject {
        let mut p = FluxForgeExportProject::new("Dragon's Hoard", "dragons_hoard");
        p.rtp_target = 95.5;
        p.voice_budget = 48;
        p.exported_at = "2026-04-16".to_string();

        for (name, cat) in [
            ("SPIN_START", AudioEventCategory::BaseGame),
            ("WIN_1", AudioEventCategory::Win),
            ("WIN_5", AudioEventCategory::Win),
            ("FREE_SPIN_TRIGGER", AudioEventCategory::Feature),
        ] {
            let mut ev = AudioEventExport::new(name);
            ev.category = cat;
            ev.tier = AudioTierExport::Standard;
            ev.duration_ms = 1000;
            p.audio_events.push(ev);
        }
        p
    }

    #[test]
    fn test_fmod_produces_five_files() {
        let bundle = FModBankExporter.export(&sample_project()).unwrap();
        assert_eq!(bundle.files.len(), 5);
    }

    #[test]
    fn test_events_json_valid() {
        let bundle = FModBankExporter.export(&sample_project()).unwrap();
        let events_file = bundle.files.iter().find(|f| f.filename.ends_with("_fmod_events.json")).unwrap();
        let json: Value = serde_json::from_str(&events_file.content).unwrap();
        let events = json["events"].as_array().unwrap();
        assert!(!events.is_empty());
        assert!(events.iter().any(|e| e["name"] == "SPIN_START"));
    }

    #[test]
    fn test_event_paths_use_fmod_format() {
        let bundle = FModBankExporter.export(&sample_project()).unwrap();
        let f = bundle.files.iter().find(|f| f.filename.ends_with("_fmod_events.json")).unwrap();
        let json: Value = serde_json::from_str(&f.content).unwrap();
        let path = json["events"][0]["path"].as_str().unwrap();
        assert!(path.starts_with("event:/SlotGame/"), "Expected FMOD path format, got: {}", path);
    }

    #[test]
    fn test_parameters_json_has_win_ratio() {
        let bundle = FModBankExporter.export(&sample_project()).unwrap();
        let f = bundle.files.iter().find(|f| f.filename.ends_with("_fmod_parameters.json")).unwrap();
        let json: Value = serde_json::from_str(&f.content).unwrap();
        let params = json["parameters"].as_array().unwrap();
        assert!(params.iter().any(|p| p["name"] == "WinRatio"));
    }

    #[test]
    fn test_warning_about_no_bank() {
        let bundle = FModBankExporter.export(&sample_project()).unwrap();
        assert!(bundle.warnings.iter().any(|w| w.contains(".bank")));
    }
}
