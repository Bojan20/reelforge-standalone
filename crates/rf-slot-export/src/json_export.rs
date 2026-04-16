//! Generic JSON Exporter — T3.5
//!
//! Exports the complete FluxForge audio event map as a structured JSON
//! document for use with custom engines, HTML5 games, or any platform
//! not covered by Howler/Wwise/FMOD exporters.
//!
//! ## Output Format
//!
//! Produces two files:
//! - `{id}_audio_manifest.json` — Full event map with all metadata
//! - `{id}_audio_manifest_minimal.json` — Minimal format (name + duration + loop)
//!
//! The full manifest is self-documenting and includes:
//! - All event parameters
//! - Win tier mapping
//! - Voice budget constraints
//! - Integration notes

use serde_json::{json, Value};
use crate::types::{
    AudioEventCategory, ExportBundle, ExportError, ExportFile, ExportTarget,
    FluxForgeExportProject,
};

/// Generic JSON exporter
pub struct GenericJsonExporter;

impl ExportTarget for GenericJsonExporter {
    fn format_name(&self) -> &'static str { "Generic JSON" }
    fn format_version(&self) -> &'static str { "1.0" }
    fn primary_extension(&self) -> &'static str { "json" }

    fn export(&self, project: &FluxForgeExportProject) -> Result<ExportBundle, ExportError> {
        if project.audio_events.is_empty() {
            return Err(ExportError::EmptyProject);
        }

        let game_id = sanitize_id(&project.game_id);

        // ── Full manifest ─────────────────────────────────────────────────────
        let full = build_full_manifest(project);
        let full_str = serde_json::to_string_pretty(&full)
            .map_err(|e| ExportError::Serialization(e.to_string()))?;

        // ── Minimal manifest ──────────────────────────────────────────────────
        let minimal = build_minimal_manifest(project);
        let minimal_str = serde_json::to_string_pretty(&minimal)
            .map_err(|e| ExportError::Serialization(e.to_string()))?;

        // ── Category index ────────────────────────────────────────────────────
        let index = build_category_index(project);
        let index_str = serde_json::to_string_pretty(&index)
            .map_err(|e| ExportError::Serialization(e.to_string()))?;

        let bundle = ExportBundle::new(self.format_name(), self.format_version())
            .with_event_count(project.audio_events.len())
            .add_file(
                ExportFile::json(
                    format!("{game_id}_audio_manifest.json"),
                    full_str,
                ).with_path("audio/")
            )
            .add_file(
                ExportFile::json(
                    format!("{game_id}_audio_manifest_minimal.json"),
                    minimal_str,
                ).with_path("audio/")
            )
            .add_file(
                ExportFile::json(
                    format!("{game_id}_audio_event_index.json"),
                    index_str,
                ).with_path("audio/")
            );

        Ok(bundle)
    }
}

fn sanitize_id(id: &str) -> String {
    id.chars()
        .map(|c| if c.is_alphanumeric() || c == '_' || c == '-' { c } else { '_' })
        .collect()
}

fn build_full_manifest(project: &FluxForgeExportProject) -> Value {
    let events: Vec<Value> = project.audio_events.iter().map(|ev| {
        json!({
            "name": ev.name,
            "description": ev.description,
            "category": format!("{:?}", ev.category).to_lowercase(),
            "tier": format!("{:?}", ev.tier).to_lowercase(),
            "durationMs": ev.duration_ms,
            "voiceCount": ev.voice_count,
            "priority": ev.priority,
            "triggerProbability": ev.trigger_probability,
            "canOverlap": ev.can_overlap,
            "loop": ev.should_loop(),
            "audioWeight": ev.audio_weight,
            "rtpContribution": ev.rtp_contribution,
            "isRequired": ev.is_required,
            "suggestedBus": ev.category.bus_path(),
        })
    }).collect();

    let win_tiers: Vec<Value> = project.win_tiers.iter().map(|t| {
        json!({
            "tierId": t.tier_id,
            "stageName": t.stage_name,
            "fromMultiplier": t.from_multiplier,
            "toMultiplier": t.to_multiplier,
            "rollupDurationMs": t.rollup_duration_ms,
            "particleBurstCount": t.particle_burst_count,
        })
    }).collect();

    json!({
        "schema": "fluxforge-audio-manifest",
        "version": "1.0",
        "game": {
            "name": project.game_name,
            "id": project.game_id,
            "rtpTarget": project.rtp_target,
            "volatility": project.volatility,
            "voiceBudget": project.voice_budget,
            "reels": project.reels,
            "rows": project.rows,
            "winMechanism": project.win_mechanism,
        },
        "summary": {
            "totalEvents": project.audio_events.len(),
            "requiredEvents": project.audio_events.iter().filter(|e| e.is_required).count(),
            "byCategory": build_category_counts(project),
            "byTier": build_tier_counts(project),
        },
        "events": events,
        "winTiers": win_tiers,
        "exportedAt": project.exported_at,
        "generatedBy": project.tool_version,
    })
}

fn build_minimal_manifest(project: &FluxForgeExportProject) -> Value {
    let events: Vec<Value> = project.audio_events.iter().map(|ev| {
        json!({
            "name": ev.name,
            "durationMs": ev.duration_ms,
            "loop": ev.should_loop(),
            "voiceCount": ev.voice_count,
        })
    }).collect();

    json!({
        "game": project.game_id,
        "events": events,
    })
}

fn build_category_index(project: &FluxForgeExportProject) -> Value {
    let categories = [
        ("base_game", AudioEventCategory::BaseGame),
        ("win", AudioEventCategory::Win),
        ("near_miss", AudioEventCategory::NearMiss),
        ("feature", AudioEventCategory::Feature),
        ("jackpot", AudioEventCategory::Jackpot),
        ("special", AudioEventCategory::Special),
        ("ambient", AudioEventCategory::Ambient),
    ];

    let mut by_category = serde_json::Map::new();
    for (key, cat) in &categories {
        let names: Vec<&str> = project.audio_events.iter()
            .filter(|e| &e.category == cat)
            .map(|e| e.name.as_str())
            .collect();
        if !names.is_empty() {
            by_category.insert(key.to_string(), json!(names));
        }
    }

    json!({
        "game": project.game_id,
        "byCategory": Value::Object(by_category),
        "required": project.audio_events.iter()
            .filter(|e| e.is_required)
            .map(|e| e.name.as_str())
            .collect::<Vec<_>>(),
    })
}

fn build_category_counts(project: &FluxForgeExportProject) -> Value {
    let cats = [
        ("base_game", AudioEventCategory::BaseGame),
        ("win", AudioEventCategory::Win),
        ("near_miss", AudioEventCategory::NearMiss),
        ("feature", AudioEventCategory::Feature),
        ("jackpot", AudioEventCategory::Jackpot),
        ("special", AudioEventCategory::Special),
        ("ambient", AudioEventCategory::Ambient),
    ];

    let mut map = serde_json::Map::new();
    for (key, cat) in &cats {
        let count = project.audio_events.iter().filter(|e| &e.category == cat).count();
        if count > 0 {
            map.insert(key.to_string(), json!(count));
        }
    }
    Value::Object(map)
}

fn build_tier_counts(project: &FluxForgeExportProject) -> Value {
    use crate::types::AudioTierExport;
    let tiers = [
        ("subtle", AudioTierExport::Subtle),
        ("standard", AudioTierExport::Standard),
        ("prominent", AudioTierExport::Prominent),
        ("flagship", AudioTierExport::Flagship),
    ];

    let mut map = serde_json::Map::new();
    for (key, tier) in &tiers {
        let count = project.audio_events.iter().filter(|e| &e.tier == tier).count();
        map.insert(key.to_string(), json!(count));
    }
    Value::Object(map)
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::{AudioEventCategory, AudioEventExport, AudioTierExport};

    fn sample_project() -> FluxForgeExportProject {
        let mut p = FluxForgeExportProject::new("Crystal Cascade", "crystal_cascade");
        p.rtp_target = 97.0;
        p.voice_budget = 48;
        p.exported_at = "2026-04-16".to_string();

        for (name, cat, tier) in [
            ("SPIN_START", AudioEventCategory::BaseGame, AudioTierExport::Subtle),
            ("REEL_SPIN", AudioEventCategory::BaseGame, AudioTierExport::Subtle),
            ("WIN_1", AudioEventCategory::Win, AudioTierExport::Standard),
            ("WIN_3", AudioEventCategory::Win, AudioTierExport::Prominent),
            ("WIN_5", AudioEventCategory::Win, AudioTierExport::Flagship),
            ("FREE_SPIN_TRIGGER", AudioEventCategory::Feature, AudioTierExport::Flagship),
            ("NEAR_MISS", AudioEventCategory::NearMiss, AudioTierExport::Standard),
        ] {
            let mut ev = AudioEventExport::new(name);
            ev.category = cat;
            ev.tier = tier;
            ev.duration_ms = 1000;
            p.audio_events.push(ev);
        }
        p
    }

    #[test]
    fn test_generic_produces_three_files() {
        let bundle = GenericJsonExporter.export(&sample_project()).unwrap();
        assert_eq!(bundle.files.len(), 3);
    }

    #[test]
    fn test_full_manifest_valid_json() {
        let bundle = GenericJsonExporter.export(&sample_project()).unwrap();
        let f = bundle.files.iter().find(|f| f.filename.ends_with("_audio_manifest.json")).unwrap();
        let json: Value = serde_json::from_str(&f.content).unwrap();
        assert_eq!(json["schema"], "fluxforge-audio-manifest");
        assert_eq!(json["version"], "1.0");
        assert!(json["events"].as_array().unwrap().len() > 0);
    }

    #[test]
    fn test_minimal_manifest_minimal() {
        let bundle = GenericJsonExporter.export(&sample_project()).unwrap();
        let f = bundle.files.iter().find(|f| f.filename.contains("minimal")).unwrap();
        let json: Value = serde_json::from_str(&f.content).unwrap();
        let events = json["events"].as_array().unwrap();
        // Only name, durationMs, loop, voiceCount
        let first = &events[0];
        assert!(first["name"].is_string());
        assert!(first["durationMs"].is_u64());
        assert!(first.get("description").is_none()); // not in minimal
    }

    #[test]
    fn test_category_index_groups_correctly() {
        let bundle = GenericJsonExporter.export(&sample_project()).unwrap();
        let f = bundle.files.iter().find(|f| f.filename.contains("event_index")).unwrap();
        let json: Value = serde_json::from_str(&f.content).unwrap();
        let win_events = json["byCategory"]["win"].as_array().unwrap();
        assert!(win_events.iter().any(|e| e == "WIN_1"));
        assert!(win_events.iter().any(|e| e == "WIN_5"));
    }

    #[test]
    fn test_summary_counts_correct() {
        let bundle = GenericJsonExporter.export(&sample_project()).unwrap();
        let f = bundle.files.iter().find(|f| f.filename.ends_with("_audio_manifest.json")).unwrap();
        let json: Value = serde_json::from_str(&f.content).unwrap();
        let total = json["summary"]["totalEvents"].as_u64().unwrap();
        assert_eq!(total, 7); // 7 events in sample
    }
}
