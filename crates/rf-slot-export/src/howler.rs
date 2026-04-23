//! Howler.js AudioSprite Exporter — T3.2
//!
//! Generates Howler.js-compatible AudioSprite manifest JSON.
//! Compatible with IGT Playa's audio integration format.
//!
//! ## Output Format
//!
//! The primary output is a sprite manifest JSON that audio engineers
//! use to lay out events in a single concatenated audio file:
//!
//! ```json
//! {
//!   "src": ["golden_pantheon.webm", "golden_pantheon.mp3", "golden_pantheon.ogg"],
//!   "sprite": {
//!     "SPIN_START": [0, 150, false],
//!     "REEL_SPIN":  [500, 1500, true],
//!     "WIN_1":      [2500, 800, false],
//!     ...
//!   }
//! }
//! ```
//!
//! Each sprite entry is `[offset_ms, duration_ms, loop]`.
//!
//! ## Cuesheet
//!
//! Also generates a human-readable cuesheet for DAW arrangement:
//! ```text
//! GAME:      Golden Pantheon
//! EVENT      START_MS   DUR_MS   LOOP   TIER
//! SPIN_START 0          150      false  subtle
//! ...
//! ```

use serde_json::{json, Map, Value};
use crate::types::{ExportBundle, ExportError, ExportFile, ExportTarget, FluxForgeExportProject};

/// Howler.js AudioSprite exporter
pub struct HowlerAudioSpriteExporter;

impl ExportTarget for HowlerAudioSpriteExporter {
    fn format_name(&self) -> &'static str { "Howler.js AudioSprite" }
    fn format_version(&self) -> &'static str { "2.2" }
    fn primary_extension(&self) -> &'static str { "json" }

    fn export(&self, project: &FluxForgeExportProject) -> Result<ExportBundle, ExportError> {
        if project.audio_events.is_empty() {
            return Err(ExportError::EmptyProject);
        }

        let game_id = sanitize_id(&project.game_id);
        let event_count = project.audio_events.len();

        // ── 1. Build sprite map ───────────────────────────────────────────────
        // Layout: events placed sequentially with 200ms silence gap between them
        let mut sprite_map = Map::new();
        let mut cuesheet_rows: Vec<CuesheetRow> = Vec::new();
        let gap_ms: u64 = 200;
        let mut cursor_ms: u64 = 0;

        // Sort events: required first, then by tier (flagship → subtle), then alphabetical
        let mut sorted_events = project.audio_events.clone();
        sorted_events.sort_by(|a, b| {
            b.is_required.cmp(&a.is_required)
                .then(b.tier.priority().cmp(&a.tier.priority()))
                .then(a.name.cmp(&b.name))
        });

        for event in &sorted_events {
            let start = cursor_ms;
            let dur = event.duration_ms as u64;
            let is_loop = event.should_loop();

            // Howler sprite: [offset_ms, duration_ms, loop]
            sprite_map.insert(
                event.name.clone(),
                json!([start, dur, is_loop]),
            );

            cuesheet_rows.push(CuesheetRow {
                name: event.name.clone(),
                start_ms: start,
                duration_ms: dur,
                is_loop,
                tier: format!("{:?}", event.tier).to_lowercase(),
                category: format!("{:?}", event.category).to_lowercase(),
                voice_count: event.voice_count,
                priority: event.priority,
            });

            cursor_ms += dur + gap_ms;
        }

        let total_duration_ms = cursor_ms.saturating_sub(gap_ms);

        // ── 2. Build Howler manifest JSON ─────────────────────────────────────
        let manifest = json!({
            // Source audio files — audio engineer fills in actual filenames
            "src": [
                format!("{game_id}.webm"),
                format!("{game_id}.mp3"),
                format!("{game_id}.ogg"),
            ],
            // Pre-load all events
            "preload": true,
            // HTML5 audio fallback
            "html5": false,
            // Volume (1.0 = 100%)
            "volume": 1.0,
            // Sprite definitions
            "sprite": Value::Object(sprite_map),
            // FluxForge metadata (non-standard, ignored by Howler)
            "_fluxforge": {
                "game_name": &project.game_name,
                "game_id": &project.game_id,
                "rtp_target": project.rtp_target,
                "voice_budget": project.voice_budget,
                "total_duration_ms": total_duration_ms,
                "event_count": event_count,
                "exported_at": &project.exported_at,
                "tool_version": &project.tool_version,
            }
        });

        let manifest_json = serde_json::to_string_pretty(&manifest)
            .map_err(|e| ExportError::Serialization(e.to_string()))?;

        // ── 3. Build cuesheet ─────────────────────────────────────────────────
        let cuesheet = build_cuesheet(project, &cuesheet_rows, total_duration_ms);

        // ── 4. Build Playa-compatible event index ─────────────────────────────
        let playa_index = build_playa_index(project, &cuesheet_rows);
        let playa_json = serde_json::to_string_pretty(&playa_index)
            .map_err(|e| ExportError::Serialization(e.to_string()))?;

        let mut bundle = ExportBundle::new(self.format_name(), self.format_version())
            .with_event_count(event_count);

        bundle.files.push(
            ExportFile::json(
                format!("{game_id}_audiosprite.json"),
                manifest_json,
            ).with_path("audio/sprites/")
        );
        bundle.files.push(
            ExportFile::text(
                format!("{game_id}_cuesheet.txt"),
                cuesheet,
                "text/plain",
            ).with_path("audio/sprites/")
        );
        bundle.files.push(
            ExportFile::json(
                format!("{game_id}_playa_events.json"),
                playa_json,
            ).with_path("audio/")
        );

        bundle.warnings.push(
            "AudioSprite timing is LAYOUT ONLY — actual audio files must be created \
             in your DAW and match the offset/duration values in the sprite manifest.".to_string()
        );
        if total_duration_ms > 600_000 {
            bundle.warnings.push(format!(
                "Total sprite duration {}s exceeds 10 minutes — consider splitting into \
                 multiple sprite files for performance.",
                total_duration_ms / 1000
            ));
        }

        Ok(bundle)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal helpers
// ─────────────────────────────────────────────────────────────────────────────

struct CuesheetRow {
    name: String,
    start_ms: u64,
    duration_ms: u64,
    is_loop: bool,
    tier: String,
    category: String,
    voice_count: u8,
    priority: u8,
}

fn build_cuesheet(
    project: &FluxForgeExportProject,
    rows: &[CuesheetRow],
    total_ms: u64,
) -> String {
    let mut out = String::new();
    out.push_str(&format!(
        "# FluxForge AudioSprite Cuesheet\n\
         # Game:    {}\n\
         # ID:      {}\n\
         # RTP:     {:.2}%\n\
         # Voices:  {}/48\n\
         # Events:  {}\n\
         # Total:   {}ms ({:.1}s)\n\
         # Generated: {}\n\
         #\n\
         # INSTRUCTIONS:\n\
         #   1. Create an audio file named [{}.mp3/.webm/.ogg]\n\
         #   2. Place event sounds at the START_MS offsets below\n\
         #   3. Ensure each sound fits within its DURATION_MS window\n\
         #   4. Leave 200ms silence between events\n\
         #\n",
        project.game_name,
        project.game_id,
        project.rtp_target,
        project.voice_budget,
        rows.len(),
        total_ms,
        total_ms as f64 / 1000.0,
        project.exported_at,
        sanitize_id(&project.game_id),
    ));

    // Header
    out.push_str(&format!(
        "{:<30} {:>10} {:>10} {:>6} {:>10} {:>8} {:>8} {:>4}\n",
        "EVENT", "START_MS", "DUR_MS", "LOOP", "CATEGORY", "TIER", "VOICES", "PRI"
    ));
    out.push_str(&"─".repeat(90));
    out.push('\n');

    for row in rows {
        out.push_str(&format!(
            "{:<30} {:>10} {:>10} {:>6} {:>10} {:>8} {:>8} {:>4}\n",
            row.name,
            row.start_ms,
            row.duration_ms,
            if row.is_loop { "LOOP" } else { "ONE" },
            row.category,
            row.tier,
            row.voice_count,
            row.priority,
        ));
    }

    out
}

/// Generate IGT Playa-compatible event index
fn build_playa_index(project: &FluxForgeExportProject, rows: &[CuesheetRow]) -> Value {
    let events: Vec<Value> = rows.iter().map(|row| {
        json!({
            "id": row.name,
            "spriteKey": row.name,
            "category": row.category,
            "tier": row.tier,
            "durationMs": row.duration_ms,
            "loop": row.is_loop,
            "voiceCount": row.voice_count,
            "priority": row.priority,
            "startMs": row.start_ms,
        })
    }).collect();

    json!({
        "game": {
            "name": project.game_name,
            "id": project.game_id,
            "rtpTarget": project.rtp_target,
            "voiceBudget": project.voice_budget,
        },
        "audioEngine": "howler",
        "spriteFile": format!("{}.mp3", sanitize_id(&project.game_id)),
        "events": events,
        "version": "1.0",
        "_generated": "FluxForge Studio",
    })
}

fn sanitize_id(id: &str) -> String {
    id.chars()
        .map(|c| if c.is_alphanumeric() || c == '_' || c == '-' { c } else { '_' })
        .collect()
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::{AudioEventCategory, AudioEventExport, AudioTierExport};

    fn sample_project() -> FluxForgeExportProject {
        let mut p = FluxForgeExportProject::new("Golden Pantheon", "golden_pantheon_v2");
        p.rtp_target = 96.5;
        p.voice_budget = 48;
        p.exported_at = "2026-04-16T00:00:00Z".to_string();

        let events = [
            ("SPIN_START", AudioEventCategory::BaseGame, AudioTierExport::Subtle, 150u32, 1u8, true),
            ("REEL_SPIN", AudioEventCategory::BaseGame, AudioTierExport::Subtle, 1500, 2, true),
            ("REEL_STOP", AudioEventCategory::BaseGame, AudioTierExport::Subtle, 200, 1, true),
            ("WIN_1", AudioEventCategory::Win, AudioTierExport::Standard, 800, 2, false),
            ("WIN_3", AudioEventCategory::Win, AudioTierExport::Prominent, 2000, 4, false),
            ("WIN_5", AudioEventCategory::Win, AudioTierExport::Flagship, 5000, 6, false),
            ("FREE_SPIN_TRIGGER", AudioEventCategory::Feature, AudioTierExport::Flagship, 4000, 6, false),
            ("JACKPOT_WON_GRAND", AudioEventCategory::Jackpot, AudioTierExport::Flagship, 15000, 8, false),
        ];

        for (name, cat, tier, dur, voices, required) in events {
            let mut ev = AudioEventExport::new(name);
            ev.category = cat;
            ev.tier = tier;
            ev.duration_ms = dur;
            ev.voice_count = voices;
            ev.is_required = required;
            p.audio_events.push(ev);
        }

        p
    }

    #[test]
    fn test_export_produces_three_files() {
        let project = sample_project();
        let exporter = HowlerAudioSpriteExporter;
        let bundle = exporter.export(&project).unwrap();
        assert_eq!(bundle.files.len(), 3);
    }

    #[test]
    fn test_sprite_json_valid() {
        let project = sample_project();
        let exporter = HowlerAudioSpriteExporter;
        let bundle = exporter.export(&project).unwrap();

        let manifest_file = bundle.files.iter().find(|f| f.filename.ends_with("_audiosprite.json")).unwrap();
        let json: Value = serde_json::from_str(&manifest_file.content).unwrap();

        assert!(json["sprite"].is_object());
        assert!(json["sprite"]["SPIN_START"].is_array());
        // [offset, duration, loop]
        let spin_start = &json["sprite"]["SPIN_START"];
        assert_eq!(spin_start[2], false); // not a loop
        assert_eq!(spin_start[1], 150); // duration
    }

    #[test]
    fn test_reel_spin_marked_as_loop() {
        let project = sample_project();
        let bundle = HowlerAudioSpriteExporter.export(&project).unwrap();
        let mf = bundle.files.iter().find(|f| f.filename.ends_with("_audiosprite.json")).unwrap();
        let json: Value = serde_json::from_str(&mf.content).unwrap();
        // REEL_SPIN should be loop=true
        let reel_spin = &json["sprite"]["REEL_SPIN"];
        assert_eq!(reel_spin[2], true, "REEL_SPIN should be loop=true");
    }

    #[test]
    fn test_no_time_overlap_between_events() {
        let project = sample_project();
        let bundle = HowlerAudioSpriteExporter.export(&project).unwrap();
        let mf = bundle.files.iter().find(|f| f.filename.ends_with("_audiosprite.json")).unwrap();
        let json: Value = serde_json::from_str(&mf.content).unwrap();

        // Collect all [start, end) intervals
        let sprite = json["sprite"].as_object().unwrap();
        let mut intervals: Vec<(u64, u64)> = sprite.values()
            .map(|v| (v[0].as_u64().unwrap(), v[0].as_u64().unwrap() + v[1].as_u64().unwrap()))
            .collect();
        intervals.sort_by_key(|i| i.0);

        for window in intervals.windows(2) {
            assert!(window[1].0 >= window[0].1,
                "Overlap: {:?} overlaps {:?}", window[0], window[1]);
        }
    }

    #[test]
    fn test_empty_project_returns_error() {
        let project = FluxForgeExportProject::new("Empty", "empty");
        let result = HowlerAudioSpriteExporter.export(&project);
        assert!(result.is_err());
    }

    #[test]
    fn test_event_count_in_bundle() {
        let project = sample_project();
        let bundle = HowlerAudioSpriteExporter.export(&project).unwrap();
        assert_eq!(bundle.event_count, project.audio_events.len());
    }

    #[test]
    fn test_cuesheet_contains_all_events() {
        let project = sample_project();
        let bundle = HowlerAudioSpriteExporter.export(&project).unwrap();
        let cuesheet = bundle.files.iter().find(|f| f.filename.ends_with("_cuesheet.txt")).unwrap();

        for event in &project.audio_events {
            assert!(
                cuesheet.content.contains(&event.name),
                "Cuesheet missing event: {}", event.name
            );
        }
    }

    #[test]
    fn test_playa_index_structure() {
        let project = sample_project();
        let bundle = HowlerAudioSpriteExporter.export(&project).unwrap();
        let playa = bundle.files.iter().find(|f| f.filename.ends_with("_playa_events.json")).unwrap();
        let json: Value = serde_json::from_str(&playa.content).unwrap();

        assert_eq!(json["audioEngine"], "howler");
        assert!(json["events"].as_array().unwrap().len() > 0);
        assert!(json["events"][0]["id"].is_string());
        assert!(json["events"][0]["durationMs"].is_u64());
    }
}
