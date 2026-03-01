// ============================================================================
// rf-fluxmacro — ADB Auto-Generator Step
// ============================================================================
// FM-20: Audio Design Brief generator. Maps game mechanics to audio needs,
// generates ADB document (Markdown + JSON) with 10 sections.
// ============================================================================

use std::collections::HashMap;

use crate::context::{LogLevel, MacroContext};
use crate::error::FluxMacroError;
use crate::rules::RuleSet;
use crate::security;
use crate::steps::{MacroStep, StepResult};

pub struct AdbGenerateStep;

impl MacroStep for AdbGenerateStep {
    fn name(&self) -> &'static str {
        "adb.generate"
    }

    fn description(&self) -> &'static str {
        "Generate Audio Design Brief from game mechanics and volatility"
    }

    fn execute(&self, ctx: &mut MacroContext) -> Result<StepResult, FluxMacroError> {
        let rules = RuleSet::load(&ctx.rules_dir).unwrap_or_else(|_| RuleSet::defaults());

        if ctx.dry_run {
            let event_count = rules
                .mechanics
                .total_events(&ctx.mechanics.iter().map(|m| m.id()).collect::<Vec<_>>());
            return Ok(StepResult::success(format!(
                "Dry-run: would generate ADB with {event_count} audio events"
            )));
        }

        // Generate ADB content
        let adb_md = generate_adb_markdown(ctx, &rules);
        let adb_json = generate_adb_json(ctx, &rules)?;

        // Write files
        let reports_dir = ctx.working_dir.join("Reports");
        std::fs::create_dir_all(&reports_dir)
            .map_err(|e| FluxMacroError::DirectoryCreate(reports_dir.clone(), e))?;

        let md_filename = format!("ADB_{}.md", security::sanitize_filename(&ctx.game_id));
        let json_filename = format!("ADB_{}.json", security::sanitize_filename(&ctx.game_id));

        let md_path = reports_dir.join(&md_filename);
        let json_path = reports_dir.join(&json_filename);

        std::fs::write(&md_path, &adb_md)
            .map_err(|e| FluxMacroError::FileWrite(md_path.clone(), e))?;
        std::fs::write(&json_path, &adb_json)
            .map_err(|e| FluxMacroError::FileWrite(json_path.clone(), e))?;

        // Store in intermediate data
        ctx.set_intermediate(
            "adb",
            serde_json::from_str(&adb_json).unwrap_or(serde_json::Value::Null),
        );

        let mechanic_count = ctx.mechanics.len();
        let event_count = rules
            .mechanics
            .total_events(&ctx.mechanics.iter().map(|m| m.id()).collect::<Vec<_>>());

        ctx.log(
            LogLevel::Info,
            "adb.generate",
            &format!("Generated ADB: {mechanic_count} mechanics, {event_count} events"),
        );

        Ok(StepResult::success(format!(
            "ADB generated: {mechanic_count} mechanics, {event_count} audio events"
        ))
        .with_artifact("adb_markdown".to_string(), md_path)
        .with_artifact("adb_json".to_string(), json_path)
        .with_metric("mechanic_count".to_string(), mechanic_count as f64)
        .with_metric("event_count".to_string(), event_count as f64))
    }

    fn validate(&self, ctx: &MacroContext) -> Result<(), FluxMacroError> {
        if ctx.game_id.is_empty() {
            return Err(FluxMacroError::PreconditionNotMet {
                step: "adb.generate".to_string(),
                precondition: "game_id is required".to_string(),
            });
        }
        Ok(())
    }

    fn estimated_duration_ms(&self) -> u64 {
        2000
    }
}

fn generate_adb_markdown(ctx: &MacroContext, rules: &RuleSet) -> String {
    let mut md = String::with_capacity(8192);

    // Section 1: Game Info
    md.push_str(&format!("# Audio Design Brief — {}\n\n", ctx.game_id));
    md.push_str("## 1. Game Info\n\n");
    md.push_str(&format!("- **Game ID:** {}\n", ctx.game_id));
    md.push_str(&format!("- **Volatility:** {:?}\n", ctx.volatility));
    if let Some(ref theme) = ctx.theme {
        md.push_str(&format!("- **Theme:** {theme}\n"));
    }
    let platforms: Vec<String> = ctx.platforms.iter().map(|p| format!("{p:?}")).collect();
    md.push_str(&format!("- **Platforms:** {}\n", platforms.join(", ")));
    let mechanics: Vec<&str> = ctx.mechanics.iter().map(|m| m.id()).collect();
    md.push_str(&format!("- **Mechanics:** {}\n", mechanics.join(", ")));
    md.push_str("\n");

    // Section 2: Music Plan
    md.push_str("## 2. Music Plan\n\n");
    if let Some(profile) = rules.adb_templates.get_volatility_profile(ctx.volatility) {
        md.push_str(&format!("- **Layer Count:** {}\n", profile.music_layers));
        md.push_str(&format!(
            "- **Layers:** {}\n",
            profile.layer_names.join(", ")
        ));
        md.push_str(&format!(
            "- **Build-up Duration:** {:.1}–{:.1}s\n",
            profile.build_up_duration_range.0, profile.build_up_duration_range.1
        ));
        md.push_str(&format!(
            "- **Dynamic Range:** {:.0} dB\n",
            profile.dynamic_range_db
        ));
        md.push_str(&format!(
            "- **Anticipation Boost:** +{:.0}%\n",
            profile.anticipation_boost_pct
        ));
    }

    // Emotional arcs for mechanics that need music layers
    let music_mechanics: Vec<&str> = ctx
        .mechanics
        .iter()
        .filter_map(|m| {
            rules
                .mechanics
                .get(m.id())
                .filter(|needs| needs.needs_music_layer)
                .map(|_| m.id())
        })
        .collect();

    if !music_mechanics.is_empty() {
        md.push_str("\n### Music Context Transitions\n\n");
        for mech_id in &music_mechanics {
            if let Some(arc) = rules.adb_templates.get_emotional_arc(mech_id) {
                md.push_str(&format!("**{}:** ", arc.mechanic_name));
                let phase_names: Vec<&str> = arc.phases.iter().map(|p| p.name.as_str()).collect();
                md.push_str(&format!("{}\n", phase_names.join(" → ")));
            }
        }
    }
    md.push_str("\n");

    // Section 3: SFX Plan
    md.push_str("## 3. SFX Plan\n\n");
    md.push_str("| Mechanic | Event | Domain | Min Variants | Description |\n");
    md.push_str("|----------|-------|--------|-------------|-------------|\n");
    for mechanic in &ctx.mechanics {
        if let Some(needs) = rules.mechanics.get(mechanic.id()) {
            for event in &needs.events {
                md.push_str(&format!(
                    "| {} | {} | {} | {} | {} |\n",
                    needs.name, event.id, event.domain, event.min_variants, event.description
                ));
            }
        }
    }
    md.push_str("\n");

    // Section 4: VO Plan
    md.push_str("## 4. VO Plan\n\n");
    let vo_events: Vec<String> = ctx
        .mechanics
        .iter()
        .filter_map(|m| rules.mechanics.get(m.id()))
        .flat_map(|needs| needs.events.iter())
        .filter(|e| e.domain == "vo")
        .map(|e| format!("- **{}** — {}", e.id, e.description))
        .collect();
    if vo_events.is_empty() {
        md.push_str("No voiceover events required for selected mechanics.\n");
    } else {
        for event in &vo_events {
            md.push_str(&format!("{event}\n"));
        }
    }
    md.push_str("\n");

    // Section 5: Ducking Rules
    md.push_str("## 5. Ducking Rules\n\n");
    md.push_str("| Source | Target | Attenuation | Attack | Release | Priority |\n");
    md.push_str("|--------|--------|-------------|--------|---------|----------|\n");
    for rule in &rules.adb_templates.ducking_priorities {
        md.push_str(&format!(
            "| {} | {} | {:.0} dB | {:.0}ms | {:.0}ms | {} |\n",
            rule.source,
            rule.target,
            rule.attenuation_db,
            rule.attack_ms,
            rule.release_ms,
            rule.priority
        ));
    }
    md.push_str("\n");

    // Section 6: Loudness Targets
    md.push_str("## 6. Loudness Targets\n\n");
    md.push_str("| Domain | LUFS Target | Tolerance | True Peak Max | Layering Headroom |\n");
    md.push_str("|--------|-------------|-----------|---------------|-------------------|\n");
    let mut domains: Vec<_> = rules.loudness.domains.iter().collect();
    domains.sort_by_key(|(name, _)| (*name).clone());
    for (name, target) in &domains {
        md.push_str(&format!(
            "| {} | {:.0} LUFS | ±{:.1} | {:.1} dBTP | {:.0} dB |\n",
            name.to_uppercase(),
            target.lufs_target,
            target.lufs_tolerance,
            target.true_peak_max,
            target.layering_headroom
        ));
    }
    md.push_str("\n");

    // Section 7: Voice Budget
    md.push_str("## 7. Voice Budget\n\n");
    md.push_str("| Platform | Max Voices |\n");
    md.push_str("|----------|------------|\n");
    for platform in &ctx.platforms {
        md.push_str(&format!(
            "| {:?} | {} |\n",
            platform,
            platform.voice_budget()
        ));
    }
    let suggested = rules
        .mechanics
        .total_suggested_voices(&mechanics);
    md.push_str(&format!("\n**Suggested voices for selected mechanics:** {suggested}\n"));
    md.push_str("\n");

    // Section 8: RTP Mapping
    md.push_str("## 8. RTP Mapping\n\n");
    md.push_str("| RTP Band | Win Frequency | Audio Energy | Celebration Scale |\n");
    md.push_str("|----------|--------------|-------------|-------------------|\n");
    md.push_str("| Low (85-90%) | Frequent small | Moderate base | Minimal |\n");
    md.push_str("| Mid (90-95%) | Balanced | Responsive | Standard |\n");
    md.push_str("| High (95-97%) | Rare but large | Dynamic peaks | Escalated |\n");
    md.push_str("\n");

    // Section 9: Win Tier System
    md.push_str("## 9. Win Tier System\n\n");
    md.push_str("| Tier | Multiplier Range | Celebration Type |\n");
    md.push_str("|------|-----------------|------------------|\n");
    md.push_str("| WIN 1 | 1x–5x bet | Sound effect only |\n");
    md.push_str("| WIN 2 | 5x–20x bet | SFX + music shift |\n");
    md.push_str("| WIN 3 | 20x–50x bet | Full celebration |\n");
    md.push_str("| WIN 4 | 50x–100x bet | Extended celebration |\n");
    md.push_str("| WIN 5 | 100x+ bet | Maximum celebration |\n");
    md.push_str("\n");

    // Section 10: Fatigue Rules
    md.push_str("## 10. Fatigue Rules\n\n");
    md.push_str("| Rule | Warning Threshold | Fail Threshold |\n");
    md.push_str("|------|-------------------|----------------|\n");
    md.push_str("| Same SFX per minute | > 8 | > 15 |\n");
    md.push_str("| Consecutive same variant | > 3 | > 5 |\n");
    md.push_str("| High energy % of session | > 25% | > 40% |\n");
    md.push_str("| Music LVL3+ continuous | > 60s | > 120s |\n");
    md.push_str("| Same loop without variation | > 90s | > 180s |\n");
    md.push_str("| Peak-to-recovery ratio | < 1:2 | < 1:1 |\n");
    md.push_str("\n---\n\n");
    md.push_str("*Generated by FluxMacro ADB Generator*\n");

    md
}

fn generate_adb_json(ctx: &MacroContext, rules: &RuleSet) -> Result<String, FluxMacroError> {
    let mechanic_ids: Vec<&str> = ctx.mechanics.iter().map(|m| m.id()).collect();

    let mut events = Vec::new();
    for mechanic in &ctx.mechanics {
        if let Some(needs) = rules.mechanics.get(mechanic.id()) {
            for event in &needs.events {
                events.push(serde_json::json!({
                    "mechanic": mechanic.id(),
                    "event_id": event.id,
                    "domain": event.domain,
                    "description": event.description,
                    "min_variants": event.min_variants,
                }));
            }
        }
    }

    let profile = rules.adb_templates.get_volatility_profile(ctx.volatility);

    let adb = serde_json::json!({
        "version": "1.0",
        "game_id": ctx.game_id,
        "volatility": format!("{:?}", ctx.volatility),
        "theme": ctx.theme,
        "platforms": ctx.platforms.iter().map(|p| format!("{p:?}")).collect::<Vec<_>>(),
        "mechanics": mechanic_ids,
        "music_plan": {
            "layers": profile.map(|p| p.music_layers).unwrap_or(2),
            "layer_names": profile.map(|p| &p.layer_names),
            "build_up_range": profile.map(|p| [p.build_up_duration_range.0, p.build_up_duration_range.1]),
            "dynamic_range_db": profile.map(|p| p.dynamic_range_db).unwrap_or(6.0),
        },
        "events": events,
        "event_count": events.len(),
        "voice_budget": ctx.platforms.iter().map(|p| serde_json::json!({
            "platform": format!("{p:?}"),
            "max_voices": p.voice_budget(),
        })).collect::<Vec<_>>(),
        "suggested_voices": rules.mechanics.total_suggested_voices(&mechanic_ids),
        "loudness_targets": rules.loudness.domains.iter().map(|(name, t)| {
            (name.clone(), serde_json::json!({
                "lufs_target": t.lufs_target,
                "tolerance": t.lufs_tolerance,
                "true_peak_max": t.true_peak_max,
            }))
        }).collect::<HashMap<String, serde_json::Value>>(),
    });

    Ok(serde_json::to_string_pretty(&adb)?)
}
