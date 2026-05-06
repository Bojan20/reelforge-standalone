//! Prompt templates used by the AI Composer pipeline.
//!
//! The composer runs a multi-pass conversation:
//! 1. **THEME_ANALYSIS** — extract motifs, BPM, palette from user description
//! 2. **STAGE_ASSET_MAP** — produce the structured `StageAssetMap` JSON
//! 3. **COMPLIANCE_REPAIR** — re-prompt when RGAI rejects (with violation list)
//! 4. **AUDIO_BRIEF** — generate human-readable PDF brief for sound designers
//! 5. **VOICE_DIRECTION** — script for VO actors / TTS
//! 6. **QUALITY_GRADE** — self-grade the final map (0–100 + critique)

use crate::schema::StageAssetMap;

/// System prompt setting the AI Composer's role and hard constraints.
pub const SYSTEM_BASE: &str = r#"You are FluxForge AI Composer, an expert audio designer for regulated casino slot games.

Hard constraints (non-negotiable):
1. Loss-Disguised-Wins (LDW) MUST have suppressed celebration audio. A win that equals or is less than the bet is a loss in disguise — treat it as such.
2. Near-misses MUST NOT have escalating celebration audio. The audio must NOT trick the player into believing they almost won.
3. Celebration audio MUST be proportional to win size. A 2x win cannot use the same audio as a 100x win.
4. Every required stage in the slot lifecycle MUST have at least one asset.
5. You output ONLY valid JSON matching the supplied schema. No prose, no markdown, no explanation.

Required jurisdictions: UKGC, MGA, SE, NL, AU. If a request would violate any of these, you refuse and return an empty stages array with reviewer_notes explaining why.
"#;

/// Build the user prompt for THEME_ANALYSIS pass.
pub fn theme_analysis_user(description: &str) -> String {
    format!(
        r#"User wants a slot game with this description:

"{}"

Extract:
- Single theme tag (snake_case, e.g. egyptian_temple)
- Mood (3-5 adjectives)
- Target BPM (40-220)
- Suggested instruments / sound palette
- Cultural / historical authenticity notes

Return as JSON object with keys: theme, mood, target_bpm, palette, authenticity_notes."#,
        description.replace('"', "\\\"")
    )
}

/// Build the user prompt for STAGE_ASSET_MAP generation.
pub fn stage_asset_map_user(
    description: &str,
    theme_analysis: &serde_json::Value,
    jurisdictions: &[String],
) -> String {
    let required_stages = StageAssetMap::required_stage_ids().join(", ");
    let jur_list = jurisdictions.join(", ");
    let theme_json = serde_json::to_string_pretty(theme_analysis).unwrap_or_default();

    format!(
        r#"Generate a complete Stage→Asset map for this slot.

User description: "{description}"

Theme analysis (from previous pass):
{theme_json}

Target jurisdictions: {jur_list}

Required stages (every one MUST appear): {required_stages}

For each stage, produce one or more `assets` entries describing:
- kind: loop | oneshot | transition | vo | ambient | sting
- suggested_name: file basename (snake_case)
- mood: short tag (e.g. "anticipation")
- dynamic_level: 0-100
- length_ms: optional
- bus: music | sfx | voice | ambience | aux
- generation_prompt: detailed text suitable for downstream audio generation tools (Suno, Udio, ElevenLabs, etc.)

Set compliance_hints accurately:
- ldw_audio_suppressed: true if you neutralized LDW celebrations
- near_miss_neutralized: true if near-miss audio is non-escalating
- proportional_celebrations: true if WIN_SMALL/MEDIUM/BIG escalate proportionally

Return ONLY the JSON, no prose."#,
        description = description.replace('"', "\\\""),
        theme_json = theme_json,
        jur_list = jur_list,
        required_stages = required_stages,
    )
}

/// Build a re-prompt asking the AI to fix specific compliance violations.
pub fn compliance_repair_user(
    previous_map: &StageAssetMap,
    violations: &[String],
    missing_stages: &[&str],
) -> String {
    let prev_json = serde_json::to_string_pretty(previous_map).unwrap_or_default();
    let v_list = violations.join("\n - ");
    let missing_list = if missing_stages.is_empty() {
        "(none)".to_string()
    } else {
        missing_stages.join(", ")
    };

    format!(
        r#"Your previous output failed validation. Fix every issue and return the corrected JSON.

Previous output:
{prev_json}

Compliance violations:
 - {v_list}

Missing required stages: {missing_list}

Return the FIXED full JSON object. Do not omit any stages, do not change unrelated fields, do not add commentary."#,
        prev_json = prev_json,
        v_list = v_list,
        missing_list = missing_list,
    )
}

/// Build the user prompt for the human-readable AUDIO_BRIEF pass.
pub fn audio_brief_user(map: &StageAssetMap) -> String {
    let map_json = serde_json::to_string_pretty(map).unwrap_or_default();
    format!(
        r#"Convert this Stage→Asset map into a sound designer brief (markdown).

Input:
{map_json}

Output sections:
1. Theme & Mood Overview (2-3 paragraphs)
2. Sonic Palette (instruments, frequency ranges, reference tracks)
3. Stage-by-Stage Direction (each stage: what the player should FEEL, technical notes)
4. Compliance Notes (LDW, near-miss, proportionality — what NOT to do)
5. Production Checklist (what the designer must deliver)

Write for a senior sound designer — assume DAW expertise. No fluff."#,
        map_json = map_json,
    )
}

/// Build the user prompt for VOICE_DIRECTION script generation.
pub fn voice_direction_user(map: &StageAssetMap) -> String {
    let vo_assets: Vec<_> = map
        .stages
        .iter()
        .flat_map(|s| {
            s.assets
                .iter()
                .filter(|a| a.kind == "vo")
                .map(move |a| (s.stage_id.as_str(), a))
        })
        .collect();

    let vo_json = serde_json::to_string_pretty(&vo_assets).unwrap_or_default();

    format!(
        r#"Produce a Voice Director script for these VO assets.

Input (stage_id, asset):
{vo_json}

For each VO asset, produce:
- Suggested line (1-2 short phrases, gambling-appropriate, never patronising)
- Direction notes (energy, pacing, register)
- Recording specs (sample rate 48kHz, mono, target -16 LUFS)
- Compliance check: does this line celebrate a loss? If so, REWRITE.

Output as markdown table."#,
        vo_json = vo_json,
    )
}

/// Build the user prompt for the QUALITY_GRADE self-assessment pass.
pub fn quality_grade_user(map: &StageAssetMap) -> String {
    let map_json = serde_json::to_string_pretty(map).unwrap_or_default();
    format!(
        r#"Grade this Stage→Asset map on a 0-100 scale.

Input:
{map_json}

Evaluation criteria:
- Coverage: every required stage has assets
- Coherence: theme, mood, BPM all consistent
- Compliance: LDW suppressed, near-miss neutralized, proportional celebrations
- Detail: generation_prompts are specific enough for downstream tools to produce usable audio
- Originality: not generic / copy-pasted from common slot tropes

Return JSON: {{ "score": <int 0-100>, "critique": "<2-4 sentences>" }}"#,
        map_json = map_json,
    )
}
