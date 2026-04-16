//! Wwise Project Exporter — T3.3
//!
//! Generates Wwise-compatible project structure (XML metadata + event list).
//!
//! ## What This Generates
//!
//! This exporter produces WWISE AUTHORING DATA — not binary .bnk files.
//! Binary .bnk compilation requires the Wwise Authoring Data API (WAAPI)
//! or command-line SoundBankGenerator. FluxForge generates the structured
//! XML that can be IMPORTED into Wwise Authoring.
//!
//! ### Output files:
//! - `{id}_wwise_events.xml` — Event list for import into Wwise project
//! - `{id}_wwise_busses.xml` — Suggested bus hierarchy
//! - `{id}_wwise_states.xml` — Game sync states (WIN_1..WIN_5, FEATURE, etc.)
//! - `{id}_wwise_readme.txt` — Integration guide
//!
//! ## Wwise Integration Notes
//!
//! The XML format follows Wwise 2022.x WPROJ conventions.
//! Each FluxForge event maps to a Wwise Event with:
//! - One Action (Play)
//! - Suggested Sound (placeholder — audio engineer assigns actual .wav)
//! - Bus routing to category-specific aux bus

use serde_json::json;
use crate::types::{
    AudioEventCategory, ExportBundle, ExportError, ExportFile, ExportTarget,
    FluxForgeExportProject,
};

/// Wwise project exporter
pub struct WwiseBankExporter;

impl ExportTarget for WwiseBankExporter {
    fn format_name(&self) -> &'static str { "Wwise Project XML" }
    fn format_version(&self) -> &'static str { "2022.1" }
    fn primary_extension(&self) -> &'static str { "xml" }

    fn export(&self, project: &FluxForgeExportProject) -> Result<ExportBundle, ExportError> {
        if project.audio_events.is_empty() {
            return Err(ExportError::EmptyProject);
        }

        let game_id = sanitize_id(&project.game_id);

        // ── 1. Events XML ──────────────────────────────────────────────────────
        let events_xml = build_events_xml(project);

        // ── 2. Bus hierarchy XML ──────────────────────────────────────────────
        let busses_xml = build_busses_xml(project);

        // ── 3. States XML ─────────────────────────────────────────────────────
        let states_xml = build_states_xml(project);

        // ── 4. Switches XML ──────────────────────────────────────────────────
        let switches_xml = build_switches_xml(project);

        // ── 5. RTPCs JSON (for documentation / Wwise game parameter setup) ───
        let rtpcs_json = build_rtpcs_json(project);
        let rtpcs_str = serde_json::to_string_pretty(&rtpcs_json)
            .map_err(|e| ExportError::Serialization(e.to_string()))?;

        // ── 6. Integration guide ──────────────────────────────────────────────
        let readme = build_readme(project);

        let mut bundle = ExportBundle::new(self.format_name(), self.format_version())
            .with_event_count(project.audio_events.len());

        bundle.files = vec![
            ExportFile::text(
                format!("{game_id}_wwise_events.xml"),
                events_xml,
                "application/xml",
            ).with_path("wwise/"),
            ExportFile::text(
                format!("{game_id}_wwise_busses.xml"),
                busses_xml,
                "application/xml",
            ).with_path("wwise/"),
            ExportFile::text(
                format!("{game_id}_wwise_states.xml"),
                states_xml,
                "application/xml",
            ).with_path("wwise/"),
            ExportFile::text(
                format!("{game_id}_wwise_switches.xml"),
                switches_xml,
                "application/xml",
            ).with_path("wwise/"),
            ExportFile::json(
                format!("{game_id}_wwise_rtpcs.json"),
                rtpcs_str,
            ).with_path("wwise/"),
            ExportFile::text(
                "WWISE_INTEGRATION_GUIDE.txt".to_string(),
                readme,
                "text/plain",
            ).with_path("wwise/"),
        ];

        bundle.warnings.push(
            "This export produces Wwise AUTHORING DATA, not compiled .bnk files. \
             Import the XML files into your Wwise project, then use SoundBankGenerator \
             to compile .bnk for runtime.".to_string()
        );

        Ok(bundle)
    }
}

fn sanitize_id(id: &str) -> String {
    id.chars()
        .map(|c| if c.is_alphanumeric() || c == '_' || c == '-' { c } else { '_' })
        .collect()
}

fn build_events_xml(project: &FluxForgeExportProject) -> String {
    let mut out = String::new();
    out.push_str("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n");
    out.push_str("<!-- FluxForge Studio — Wwise Event List -->\n");
    out.push_str(&format!(
        "<!-- Game: {} | RTP: {:.2}% | Voice Budget: {} -->\n",
        project.game_name, project.rtp_target, project.voice_budget
    ));
    out.push_str("<WwiseProject>\n");
    out.push_str("  <Events>\n");

    for event in &project.audio_events {
        let bus = event.category.bus_path();
        let priority = event.priority;
        out.push_str(&format!(
            "    <Event Name=\"{}\" MaxVoices=\"{}\" Priority=\"{}\">\n",
            event.name, event.voice_count, priority
        ));
        out.push_str(&format!(
            "      <!-- Category: {:?} | Tier: {:?} | Duration: {}ms -->\n",
            event.category, event.tier, event.duration_ms
        ));
        out.push_str(&format!(
            "      <!-- Bus: {} -->\n", bus
        ));
        out.push_str("      <Actions>\n");
        out.push_str(&format!(
            "        <Action Type=\"Play\" Target=\"SFX_{}\"/>\n", event.name
        ));
        out.push_str("      </Actions>\n");
        out.push_str("    </Event>\n");
    }

    out.push_str("  </Events>\n");
    out.push_str("</WwiseProject>\n");
    out
}

fn build_busses_xml(project: &FluxForgeExportProject) -> String {
    let mut out = String::new();
    out.push_str("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n");
    out.push_str("<!-- FluxForge Studio — Wwise Bus Hierarchy -->\n");
    out.push_str("<WwiseProject>\n");
    out.push_str("  <MasterBus Name=\"Master Audio Bus\">\n");
    out.push_str(&format!(
        "    <Bus Name=\"SlotGame\" Volume=\"1.0\" MaxVoices=\"{}\">\n",
        project.voice_budget
    ));

    let categories = [
        ("BaseGame", "Base Game"),
        ("Wins", "Win Celebrations"),
        ("NearMiss", "Near Miss"),
        ("Features", "Feature Events"),
        ("Jackpot", "Jackpot Events"),
        ("Special", "Special Effects"),
        ("Ambient", "Ambient Layers"),
    ];

    for (id, label) in &categories {
        out.push_str(&format!(
            "      <Bus Name=\"{}\" Label=\"{}\" Volume=\"1.0\"/>\n",
            id, label
        ));
    }

    out.push_str("    </Bus>\n");
    out.push_str("  </MasterBus>\n");
    out.push_str("</WwiseProject>\n");
    out
}

fn build_states_xml(project: &FluxForgeExportProject) -> String {
    let mut out = String::new();
    out.push_str("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n");
    out.push_str("<!-- FluxForge Studio — Wwise States (Game Syncs) -->\n");
    out.push_str("<WwiseProject>\n");
    out.push_str("  <StateGroups>\n");

    // Win tier states
    out.push_str("    <StateGroup Name=\"WinTier\">\n");
    out.push_str("      <State Name=\"None\"/>\n");
    out.push_str("      <State Name=\"WIN_LOW\"/>\n");
    for tier in &project.win_tiers {
        out.push_str(&format!("      <State Name=\"{}\"/>\n", tier.stage_name));
    }
    out.push_str("    </StateGroup>\n");

    // Game phase states
    out.push_str("    <StateGroup Name=\"GamePhase\">\n");
    for state in &["BaseGame", "FreeSpins", "Bonus", "BigWin", "Jackpot"] {
        out.push_str(&format!("      <State Name=\"{}\"/>\n", state));
    }
    out.push_str("    </StateGroup>\n");

    // Feature active states (derived from feature events)
    let feature_events: Vec<_> = project.audio_events.iter()
        .filter(|e| e.category == AudioEventCategory::Feature)
        .filter(|e| e.name.ends_with("_TRIGGER"))
        .collect();

    if !feature_events.is_empty() {
        out.push_str("    <StateGroup Name=\"FeatureActive\">\n");
        out.push_str("      <State Name=\"None\"/>\n");
        for ev in feature_events {
            let state_name = ev.name.trim_end_matches("_TRIGGER");
            out.push_str(&format!("      <State Name=\"{}\"/>\n", state_name));
        }
        out.push_str("    </StateGroup>\n");
    }

    out.push_str("  </StateGroups>\n");
    out.push_str("</WwiseProject>\n");
    out
}

fn build_switches_xml(project: &FluxForgeExportProject) -> String {
    let mut out = String::new();
    out.push_str("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n");
    out.push_str("<!-- FluxForge Studio — Wwise Switches -->\n");
    out.push_str("<WwiseProject>\n");
    out.push_str("  <SwitchGroups>\n");
    out.push_str(&format!(
        "    <!-- Game: {} | {} reels × {} rows -->\n",
        project.game_name, project.reels, project.rows
    ));

    // Per-reel stop switch
    out.push_str("    <SwitchGroup Name=\"ReelStop\">\n");
    for reel in 0..project.reels {
        out.push_str(&format!("      <Switch Name=\"REEL_{}\"/>\n", reel));
    }
    out.push_str("    </SwitchGroup>\n");

    // Volatility switch (for adaptive music)
    out.push_str("    <SwitchGroup Name=\"SessionMood\">\n");
    for mood in &["Cold", "Neutral", "Warm", "Hot"] {
        out.push_str(&format!("      <Switch Name=\"{}\"/>\n", mood));
    }
    out.push_str("    </SwitchGroup>\n");

    out.push_str("  </SwitchGroups>\n");
    out.push_str("</WwiseProject>\n");
    out
}

fn build_rtpcs_json(project: &FluxForgeExportProject) -> serde_json::Value {
    json!({
        "game": project.game_name,
        "rtpcs": [
            {
                "name": "RTPCWinRatio",
                "description": "Current win / bet ratio (0.0 = loss, 1.0 = break even, 300.0 = 300x)",
                "minValue": 0.0,
                "maxValue": 300.0,
                "defaultValue": 0.0,
                "updateMode": "realtime"
            },
            {
                "name": "RTPCSessionHeat",
                "description": "Player session heat (0.0 = cold losing session, 1.0 = winning streak)",
                "minValue": 0.0,
                "maxValue": 1.0,
                "defaultValue": 0.5,
                "updateMode": "per_spin"
            },
            {
                "name": "RTPCVoiceLoad",
                "description": "Current voice utilization (0.0–1.0, 1.0 = budget exceeded)",
                "minValue": 0.0,
                "maxValue": 1.0,
                "defaultValue": 0.0,
                "updateMode": "realtime"
            },
            {
                "name": "RTPCReelSpeed",
                "description": "Reel spin speed multiplier (1.0=normal, 2.0=turbo)",
                "minValue": 0.5,
                "maxValue": 3.0,
                "defaultValue": 1.0,
                "updateMode": "per_spin"
            }
        ]
    })
}

fn build_readme(project: &FluxForgeExportProject) -> String {
    format!(
        "# Wwise Integration Guide — {}\n\
         # Generated by FluxForge Studio\n\
         # Game ID: {} | RTP: {:.2}% | Voice Budget: {}\n\
         #\n\
         # ═══════════════════════════════════════════════════════\n\
         # IMPORT INSTRUCTIONS\n\
         # ═══════════════════════════════════════════════════════\n\
         #\n\
         # 1. Open your Wwise project\n\
         # 2. Import Events:\n\
         #    File > Import > XML → select *_wwise_events.xml\n\
         # 3. Import Bus Hierarchy:\n\
         #    File > Import > XML → select *_wwise_busses.xml\n\
         # 4. Import Game Syncs:\n\
         #    File > Import > XML → select *_wwise_states.xml\n\
         #    File > Import > XML → select *_wwise_switches.xml\n\
         # 5. Set up RTPCs from *_wwise_rtpcs.json\n\
         # 6. Assign audio .wav files to each SFX_* Sound object\n\
         # 7. Generate SoundBank for your platform\n\
         #\n\
         # ═══════════════════════════════════════════════════════\n\
         # GAME CODE INTEGRATION\n\
         # ═══════════════════════════════════════════════════════\n\
         #\n\
         # AK::SoundEngine::PostEvent(\"SPIN_START\", gameObjectId);\n\
         # AK::SoundEngine::PostEvent(\"WIN_3\", gameObjectId);\n\
         # AK::SoundEngine::SetState(\"WinTier\", \"WIN_3\");\n\
         # AK::SoundEngine::SetRTPCValue(\"RTPCWinRatio\", 15.0f);\n\
         #\n\
         # Event count: {}\n\
         # Required events: {}\n",
        project.game_name,
        project.game_id,
        project.rtp_target,
        project.voice_budget,
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
        let mut p = FluxForgeExportProject::new("Pharaoh's Vault", "pharaohs_vault");
        p.rtp_target = 96.0;
        p.reels = 5;
        p.rows = 3;
        p.exported_at = "2026-04-16".to_string();

        for (name, cat) in [
            ("SPIN_START", AudioEventCategory::BaseGame),
            ("WIN_1", AudioEventCategory::Win),
            ("WIN_5", AudioEventCategory::Win),
            ("FREE_SPIN_TRIGGER", AudioEventCategory::Feature),
            ("JACKPOT_WON_GRAND", AudioEventCategory::Jackpot),
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
    fn test_wwise_produces_six_files() {
        let project = sample_project();
        let bundle = WwiseBankExporter.export(&project).unwrap();
        assert_eq!(bundle.files.len(), 6);
    }

    #[test]
    fn test_events_xml_is_valid_xml() {
        let project = sample_project();
        let bundle = WwiseBankExporter.export(&project).unwrap();
        let events_file = bundle.files.iter().find(|f| f.filename.ends_with("_wwise_events.xml")).unwrap();
        assert!(events_file.content.contains("<?xml"));
        assert!(events_file.content.contains("<Event Name=\"SPIN_START\""));
        assert!(events_file.content.contains("<Event Name=\"WIN_5\""));
    }

    #[test]
    fn test_busses_xml_contains_all_categories() {
        let project = sample_project();
        let bundle = WwiseBankExporter.export(&project).unwrap();
        let busses = bundle.files.iter().find(|f| f.filename.ends_with("_wwise_busses.xml")).unwrap();
        assert!(busses.content.contains("BaseGame"));
        assert!(busses.content.contains("Wins"));
        assert!(busses.content.contains("Jackpot"));
    }

    #[test]
    fn test_states_xml_has_win_tier_group() {
        let project = sample_project();
        let bundle = WwiseBankExporter.export(&project).unwrap();
        let states = bundle.files.iter().find(|f| f.filename.ends_with("_wwise_states.xml")).unwrap();
        assert!(states.content.contains("WinTier"));
        assert!(states.content.contains("WIN_LOW"));
    }

    #[test]
    fn test_warning_about_no_bnk() {
        let project = sample_project();
        let bundle = WwiseBankExporter.export(&project).unwrap();
        assert!(bundle.warnings.iter().any(|w| w.contains(".bnk")));
    }
}
