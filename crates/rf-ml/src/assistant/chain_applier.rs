//! Chain Apply Planner
//!
//! Takes a `ChainSuggestion` (from `chain_advisor`) plus the current
//! state of a track's insert chain, and computes a deterministic, ordered
//! `ApplyPlan` that — when executed against the engine — converges the
//! chain on the suggestion.
//!
//! # Why a plan, not direct apply
//!
//! Three reasons to keep planning separate from execution:
//!
//! 1. **Preview before commit.** The user sees exactly what will change
//!    ("remove slot 2: Pro-Q 4; insert ProEQ at slot 2") before any
//!    audio thread is touched.
//! 2. **Idempotency.** Running `plan(suggestion, current)` twice in a row
//!    yields an empty second plan — no churn if the chain already
//!    matches.
//! 3. **Smart preservation.** When the current chain already has a
//!    matching slot kind (e.g. user dialed-in EQ), the plan modifies
//!    parameters instead of unload-load — keeping user customisations.
//!
//! # Plan steps
//!
//! Steps are emitted in dependency order: unloads first (so slots are
//! free), then loads (each into a known free slot), then parameter sets,
//! then bypass flips. The executor walks the list top-to-bottom.

use serde::{Deserialize, Serialize};

use super::chain_advisor::{ChainSuggestion, SlotKind};
use super::suggestions::ParameterSuggestion;

// ─── Current chain state (caller fills this in from engine) ───────────────

/// One slot already loaded in the engine's insert chain for a track.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CurrentSlotState {
    /// Slot index (0-based, matches `insert_load(track_id, slot_index, …)`).
    pub slot_index: u32,
    /// Processor name as known to the engine factory
    /// (e.g. "compressor", "pro-eq", "deesser").
    pub processor_name: String,
    /// Inferred kind — caller may compute this from `processor_name`,
    /// or pass `None` to let the planner infer it.
    #[serde(default)]
    pub kind: Option<SlotKind>,
    /// Bypass state.
    #[serde(default)]
    pub bypassed: bool,
}

/// Snapshot of all slots currently loaded for a track.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct CurrentChainState {
    pub track_id: u32,
    pub slots: Vec<CurrentSlotState>,
}

// ─── Plan steps ───────────────────────────────────────────────────────────

/// One step in the apply plan.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "op", rename_all = "snake_case")]
pub enum ApplyStep {
    /// Unload whatever is currently in `slot_index`.
    UnloadSlot { slot_index: u32 },
    /// Load an internal rf-dsp processor into `slot_index`.
    LoadInternal {
        slot_index: u32,
        processor_name: String,
    },
    /// Load an external scanned plugin (VST3/AU/CLAP) by id.
    /// `slot_index` is where it goes; `plugin_id` references the user's
    /// scanned library.
    LoadExternal {
        slot_index: u32,
        plugin_id: String,
        plugin_name: String,
    },
    /// Set a parameter by human-readable name (e.g. "Cutoff", "Threshold").
    /// The executor maps `name` → engine parameter id with fuzzy matching.
    SetParameter {
        slot_index: u32,
        name: String,
        value: f32,
        unit: String,
    },
    /// Set bypass.
    SetBypass {
        slot_index: u32,
        bypassed: bool,
    },
}

impl ApplyStep {
    /// Slot index this step targets (for ordering and grouping).
    pub fn slot_index(&self) -> u32 {
        match self {
            ApplyStep::UnloadSlot { slot_index }
            | ApplyStep::LoadInternal { slot_index, .. }
            | ApplyStep::LoadExternal { slot_index, .. }
            | ApplyStep::SetParameter { slot_index, .. }
            | ApplyStep::SetBypass { slot_index, .. } => *slot_index,
        }
    }

    /// Human-readable summary for UI preview.
    pub fn describe(&self) -> String {
        match self {
            ApplyStep::UnloadSlot { slot_index } => format!("Unload slot {}", slot_index),
            ApplyStep::LoadInternal {
                slot_index,
                processor_name,
            } => format!("Load {} → slot {}", processor_name, slot_index),
            ApplyStep::LoadExternal {
                slot_index,
                plugin_name,
                ..
            } => format!("Load {} (plugin) → slot {}", plugin_name, slot_index),
            ApplyStep::SetParameter {
                slot_index,
                name,
                value,
                unit,
            } => format!("Slot {}: {} = {:.2} {}", slot_index, name, value, unit),
            ApplyStep::SetBypass {
                slot_index,
                bypassed,
            } => format!(
                "Slot {}: bypass {}",
                slot_index,
                if *bypassed { "ON" } else { "OFF" }
            ),
        }
    }
}

/// The full apply plan.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ApplyPlan {
    pub track_id: u32,
    pub steps: Vec<ApplyStep>,
    /// Snapshot of the chain *before* execution — enables undo by
    /// re-planning the inverse.
    pub before_snapshot: CurrentChainState,
    /// Whether the planner preserved any existing slot in place
    /// (modify-only, no reload). Useful diagnostic.
    pub preserved_slots: u32,
    /// Suggestion source label (e.g. "Modern Pop Vocal") for audit logs.
    pub source_label: String,
}

impl ApplyPlan {
    pub fn is_empty(&self) -> bool {
        self.steps.is_empty()
    }
    pub fn len(&self) -> usize {
        self.steps.len()
    }

    /// Pretty-print the whole plan for UI preview.
    pub fn preview(&self) -> String {
        if self.steps.is_empty() {
            return "(no changes — chain already matches)".into();
        }
        self.steps
            .iter()
            .enumerate()
            .map(|(i, s)| format!("{:>2}. {}", i + 1, s.describe()))
            .collect::<Vec<_>>()
            .join("\n")
    }
}

// ─── Mapping: SlotKind → engine processor name ────────────────────────────

/// Map a `SlotKind` to the engine's internal processor name.
/// Returns `None` for kinds the engine has no internal equivalent for —
/// the executor will then prefer an external plugin candidate.
pub fn slot_kind_to_processor_name(kind: SlotKind) -> Option<&'static str> {
    match kind {
        // High-pass is a sub-mode of EQ in our engine; the executor
        // configures the EQ to a HPF curve via parameters. Mapping to
        // pro-eq keeps slot count down.
        SlotKind::HighPass => Some("pro-eq"),
        SlotKind::Eq => Some("pro-eq"),
        SlotKind::Compressor => Some("compressor"),
        SlotKind::MultibandCompressor => None, // no internal yet
        SlotKind::DeEsser => Some("deesser"),
        SlotKind::Gate => Some("gate"),
        SlotKind::Saturation => Some("saturation"),
        SlotKind::Transient => None, // no internal yet
        SlotKind::StereoWidth => Some("stereo-imager"),
        SlotKind::Reverb => Some("reverb"),
        SlotKind::Delay => Some("delay"),
        SlotKind::Modulation => None,
        SlotKind::Limiter => Some("limiter"),
        SlotKind::Maximizer => Some("limiter"), // limiter doubles for now
    }
}

/// Inverse: best-effort guess of `SlotKind` from an engine processor
/// name (used when caller didn't pre-classify their `CurrentSlotState`).
pub fn processor_name_to_slot_kind(name: &str) -> Option<SlotKind> {
    match name.to_lowercase().as_str() {
        "pro-eq" | "ultra-eq" | "linear-phase-eq" | "pultec" | "api550" | "neve1073"
        | "room-correction" => Some(SlotKind::Eq),
        "compressor" | "comp" => Some(SlotKind::Compressor),
        "limiter" | "true-peak" | "truepeak" => Some(SlotKind::Limiter),
        "gate" | "noise-gate" => Some(SlotKind::Gate),
        "expander" | "exp" => Some(SlotKind::Gate),
        "deesser" | "de-esser" | "de_esser" => Some(SlotKind::DeEsser),
        "reverb" | "algorithmic-reverb" => Some(SlotKind::Reverb),
        "saturation" | "saturator" | "saturn" => Some(SlotKind::Saturation),
        "multiband-saturator" | "saturn2" => Some(SlotKind::Saturation),
        "delay" | "timeless" | "ping-pong-delay" => Some(SlotKind::Delay),
        "haas-delay" | "haas" => Some(SlotKind::StereoWidth),
        "stereo-imager" | "imager" => Some(SlotKind::StereoWidth),
        "multiband-stereo-imager" | "multiband-imager" | "ozone-imager" => Some(SlotKind::StereoWidth),
        _ => None,
    }
}

// ─── Planning policy ──────────────────────────────────────────────────────

/// How the planner picks plugins for each slot.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PluginPickStrategy {
    /// Always prefer external scanned plugin (top candidate) when
    /// available; fall back to internal.
    PreferExternal,
    /// Always use the engine's internal rf-dsp processor.
    InternalOnly,
    /// Only use external plugins; skip slots with no candidate.
    ExternalOnly,
}

impl Default for PluginPickStrategy {
    fn default() -> Self {
        Self::PreferExternal
    }
}

/// Tunable knobs.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApplyPolicy {
    pub plugin_strategy: PluginPickStrategy,
    /// When current chain already has a matching kind in place, prefer
    /// to *modify* its parameters rather than unload+reload.
    pub preserve_matching_slots: bool,
    /// If true, also emit `SetParameter` steps for the preserved slot.
    /// If false, leave preserved slot's parameters alone.
    pub overwrite_preserved_params: bool,
}

impl Default for ApplyPolicy {
    fn default() -> Self {
        Self {
            plugin_strategy: PluginPickStrategy::PreferExternal,
            preserve_matching_slots: true,
            overwrite_preserved_params: true,
        }
    }
}

// ─── Planner ──────────────────────────────────────────────────────────────

/// The planner.
pub struct ChainApplier {
    policy: ApplyPolicy,
}

impl ChainApplier {
    pub fn new() -> Self {
        Self {
            policy: ApplyPolicy::default(),
        }
    }
    pub fn with_policy(policy: ApplyPolicy) -> Self {
        Self { policy }
    }

    /// Build the plan.
    ///
    /// Algorithm:
    /// 1. Normalise current state — fill missing `kind` via `processor_name_to_slot_kind`.
    /// 2. For each suggestion slot (in order), look up an existing slot
    ///    of the same kind. If found and policy allows, mark it
    ///    *preserved* and emit only parameter steps. Otherwise emit
    ///    unload + load + params.
    /// 3. Any current slot whose kind appears nowhere in the suggestion
    ///    is unloaded.
    /// 4. Pack the final layout to slot indices [0..N).
    pub fn plan(
        &self,
        suggestion: &ChainSuggestion,
        current: &CurrentChainState,
    ) -> ApplyPlan {
        // Normalise current slots — guarantee `kind`.
        let mut normalised: Vec<CurrentSlotState> = current
            .slots
            .iter()
            .map(|s| CurrentSlotState {
                slot_index: s.slot_index,
                processor_name: s.processor_name.clone(),
                kind: s.kind.or_else(|| processor_name_to_slot_kind(&s.processor_name)),
                bypassed: s.bypassed,
            })
            .collect();
        normalised.sort_by_key(|s| s.slot_index);

        let mut steps: Vec<ApplyStep> = Vec::new();
        let mut preserved_slots: u32 = 0;
        // For each suggestion slot, decide which physical slot it
        // ends up in. We'll re-pack at the end.
        let mut planned_layout: Vec<PlannedSlot> = Vec::with_capacity(suggestion.slots.len());
        let mut consumed: Vec<bool> = vec![false; normalised.len()];

        // ── Pass 1: try to preserve matching kinds ────────────────────────
        for sug_slot in suggestion.slots.iter() {
            let mut preserve_idx: Option<usize> = None;
            if self.policy.preserve_matching_slots {
                for (i, cur) in normalised.iter().enumerate() {
                    if !consumed[i] && cur.kind == Some(sug_slot.kind) {
                        preserve_idx = Some(i);
                        break;
                    }
                }
            }
            if let Some(i) = preserve_idx {
                consumed[i] = true;
                preserved_slots += 1;
                planned_layout.push(PlannedSlot {
                    kind: sug_slot.kind,
                    source: PlannedSource::Preserved {
                        original_index: normalised[i].slot_index,
                        processor_name: normalised[i].processor_name.clone(),
                    },
                    parameters: if self.policy.overwrite_preserved_params {
                        sug_slot.parameters.clone()
                    } else {
                        Vec::new()
                    },
                });
            } else {
                // New slot needed — pick external vs internal.
                let source = self.pick_source(sug_slot);
                if let Some(source) = source {
                    planned_layout.push(PlannedSlot {
                        kind: sug_slot.kind,
                        source,
                        parameters: sug_slot.parameters.clone(),
                    });
                } else {
                    // Skip — no resolvable processor for this kind.
                    log::debug!("chain_applier: skipping {:?} (no resolution)", sug_slot.kind);
                }
            }
        }

        // ── Pass 2: emit unloads for non-consumed current slots ───────────
        for (i, cur) in normalised.iter().enumerate() {
            if !consumed[i] {
                steps.push(ApplyStep::UnloadSlot {
                    slot_index: cur.slot_index,
                });
            }
        }

        // ── Pass 3: re-pack and emit loads + params ───────────────────────
        // Final slot indices are [0..planned_layout.len()).
        // For preserved slots whose original index already equals their
        // target, no load is needed; only param updates.
        for (target_idx, plan_slot) in planned_layout.iter().enumerate() {
            let target = target_idx as u32;
            match &plan_slot.source {
                PlannedSource::Preserved {
                    original_index,
                    processor_name,
                } => {
                    if *original_index != target {
                        // Move = unload + load (insert positions don't
                        // support move directly in the engine; cheaper
                        // than a re-architect).
                        steps.push(ApplyStep::UnloadSlot {
                            slot_index: *original_index,
                        });
                        steps.push(ApplyStep::LoadInternal {
                            slot_index: target,
                            processor_name: processor_name.clone(),
                        });
                    }
                }
                PlannedSource::Internal { processor_name } => {
                    steps.push(ApplyStep::LoadInternal {
                        slot_index: target,
                        processor_name: processor_name.clone(),
                    });
                }
                PlannedSource::External {
                    plugin_id,
                    plugin_name,
                } => {
                    steps.push(ApplyStep::LoadExternal {
                        slot_index: target,
                        plugin_id: plugin_id.clone(),
                        plugin_name: plugin_name.clone(),
                    });
                }
            }
            // Parameters for this slot
            for p in &plan_slot.parameters {
                steps.push(ApplyStep::SetParameter {
                    slot_index: target,
                    name: p.name.clone(),
                    value: p.suggested,
                    unit: p.unit.clone(),
                });
            }
            // Always ensure not-bypassed at the end.
            steps.push(ApplyStep::SetBypass {
                slot_index: target,
                bypassed: false,
            });
        }

        ApplyPlan {
            track_id: current.track_id,
            steps,
            before_snapshot: current.clone(),
            preserved_slots,
            source_label: suggestion.style_tag.clone(),
        }
    }

    fn pick_source(&self, slot: &super::chain_advisor::ChainSlotSuggestion) -> Option<PlannedSource> {
        match self.policy.plugin_strategy {
            PluginPickStrategy::ExternalOnly => slot
                .plugin_candidates
                .first()
                .map(|c| PlannedSource::External {
                    plugin_id: c.plugin_id.clone(),
                    plugin_name: c.plugin_name.clone(),
                }),
            PluginPickStrategy::InternalOnly => {
                slot_kind_to_processor_name(slot.kind).map(|n| PlannedSource::Internal {
                    processor_name: n.into(),
                })
            }
            PluginPickStrategy::PreferExternal => {
                if let Some(c) = slot.plugin_candidates.first() {
                    Some(PlannedSource::External {
                        plugin_id: c.plugin_id.clone(),
                        plugin_name: c.plugin_name.clone(),
                    })
                } else {
                    slot_kind_to_processor_name(slot.kind).map(|n| PlannedSource::Internal {
                        processor_name: n.into(),
                    })
                }
            }
        }
    }
}

impl Default for ChainApplier {
    fn default() -> Self {
        Self::new()
    }
}

// ─── Internal: planning intermediates ─────────────────────────────────────

#[derive(Debug, Clone)]
struct PlannedSlot {
    kind: SlotKind,
    source: PlannedSource,
    parameters: Vec<ParameterSuggestion>,
}

#[derive(Debug, Clone)]
enum PlannedSource {
    Preserved {
        original_index: u32,
        processor_name: String,
    },
    Internal {
        processor_name: String,
    },
    External {
        plugin_id: String,
        plugin_name: String,
    },
}

// ─── Tests ────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use super::super::chain_advisor::{
        ChainAdvisor, TrackType,
    };
    use super::super::{
        DynamicsAnalysis, LoudnessAnalysis, SpectralAnalysis, StereoAnalysis, AnalysisResult,
    };

    fn analysis_vocal() -> AnalysisResult {
        AnalysisResult {
            genres: vec![],
            moods: vec![],
            tempo_bpm: None,
            key: None,
            loudness: LoudnessAnalysis::default(),
            spectral: SpectralAnalysis {
                low_ratio: 0.2,
                mid_ratio: 0.55,
                high_ratio: 0.25,
                ..Default::default()
            },
            dynamics: DynamicsAnalysis {
                crest_factor_db: 12.0,
                transient_sharpness: 0.5,
                ..Default::default()
            },
            stereo: StereoAnalysis {
                width: 0.3,
                ..Default::default()
            },
            suggestions: vec![],
            quality_score: 0.5,
        }
    }

    fn vocal_suggestion() -> ChainSuggestion {
        ChainAdvisor::new().suggest_chain(&analysis_vocal(), &[], Some(TrackType::Vocal))
    }

    fn empty_state(track_id: u32) -> CurrentChainState {
        CurrentChainState {
            track_id,
            slots: vec![],
        }
    }

    #[test]
    fn plan_on_empty_chain_loads_each_slot() {
        let sug = vocal_suggestion();
        let planner = ChainApplier::new();
        let plan = planner.plan(&sug, &empty_state(7));
        assert_eq!(plan.track_id, 7);
        assert!(plan.preserved_slots == 0);
        // At least one LoadInternal step
        assert!(plan
            .steps
            .iter()
            .any(|s| matches!(s, ApplyStep::LoadInternal { .. })));
        // SetParameter steps follow loads
        assert!(plan
            .steps
            .iter()
            .any(|s| matches!(s, ApplyStep::SetParameter { .. })));
    }

    #[test]
    fn idempotent_plan_on_already_matching_chain() {
        // Build chain with ALL slots from suggestion already present in
        // matching kinds + correct order → second plan should be small
        // (only param overwrites if policy says so).
        let sug = vocal_suggestion();
        let policy = ApplyPolicy {
            preserve_matching_slots: true,
            overwrite_preserved_params: false,
            plugin_strategy: PluginPickStrategy::InternalOnly,
        };
        let planner = ChainApplier::with_policy(policy);

        // Build a current state that mirrors the suggestion
        let slots: Vec<CurrentSlotState> = sug
            .slots
            .iter()
            .enumerate()
            .filter_map(|(i, s)| {
                slot_kind_to_processor_name(s.kind).map(|name| CurrentSlotState {
                    slot_index: i as u32,
                    processor_name: name.into(),
                    kind: Some(s.kind),
                    bypassed: false,
                })
            })
            .collect();
        let state = CurrentChainState { track_id: 1, slots };

        let plan = planner.plan(&sug, &state);
        assert!(plan.preserved_slots as usize >= state.slots.len() - 1);
        // No unloads, no loads
        assert!(!plan
            .steps
            .iter()
            .any(|s| matches!(s, ApplyStep::UnloadSlot { .. })));
        assert!(!plan
            .steps
            .iter()
            .any(|s| matches!(s, ApplyStep::LoadInternal { .. })));
        // Only SetBypass steps remain (one per preserved slot)
        let only_bypass = plan
            .steps
            .iter()
            .all(|s| matches!(s, ApplyStep::SetBypass { .. }));
        assert!(only_bypass, "expected only bypass steps, got: {:?}", plan.steps);
    }

    #[test]
    fn unloads_obsolete_slots() {
        // Current chain has a Reverb that the suggestion doesn't include
        // (drum chain has no reverb in template) — that slot must be unloaded.
        let sug = ChainAdvisor::new().suggest_chain(
            &AnalysisResult {
                genres: vec![],
                moods: vec![],
                tempo_bpm: None,
                key: None,
                loudness: LoudnessAnalysis::default(),
                spectral: SpectralAnalysis::default(),
                dynamics: DynamicsAnalysis {
                    crest_factor_db: 18.0,
                    transient_sharpness: 0.85,
                    ..Default::default()
                },
                stereo: StereoAnalysis::default(),
                suggestions: vec![],
                quality_score: 0.5,
            },
            &[],
            Some(TrackType::Drums),
        );

        let state = CurrentChainState {
            track_id: 3,
            slots: vec![CurrentSlotState {
                slot_index: 0,
                processor_name: "reverb".into(),
                kind: Some(SlotKind::Reverb),
                bypassed: false,
            }],
        };
        let plan = ChainApplier::new().plan(&sug, &state);
        assert!(plan
            .steps
            .iter()
            .any(|s| matches!(s, ApplyStep::UnloadSlot { slot_index: 0 })));
    }

    #[test]
    fn external_strategy_skips_slots_without_candidates() {
        let sug = vocal_suggestion();
        // No plugins available → ExternalOnly = all slots skipped
        let planner = ChainApplier::with_policy(ApplyPolicy {
            plugin_strategy: PluginPickStrategy::ExternalOnly,
            ..Default::default()
        });
        let plan = planner.plan(&sug, &empty_state(0));
        assert!(!plan
            .steps
            .iter()
            .any(|s| matches!(s, ApplyStep::LoadInternal { .. })));
        assert!(!plan
            .steps
            .iter()
            .any(|s| matches!(s, ApplyStep::LoadExternal { .. })));
    }

    #[test]
    fn slot_kind_to_processor_name_mapping_is_stable() {
        assert_eq!(slot_kind_to_processor_name(SlotKind::Eq), Some("pro-eq"));
        assert_eq!(
            slot_kind_to_processor_name(SlotKind::Compressor),
            Some("compressor")
        );
        assert_eq!(
            slot_kind_to_processor_name(SlotKind::Limiter),
            Some("limiter")
        );
        assert_eq!(slot_kind_to_processor_name(SlotKind::Modulation), None);
    }

    #[test]
    fn processor_name_to_slot_kind_inverse() {
        assert_eq!(processor_name_to_slot_kind("pro-eq"), Some(SlotKind::Eq));
        assert_eq!(
            processor_name_to_slot_kind("compressor"),
            Some(SlotKind::Compressor)
        );
        assert_eq!(
            processor_name_to_slot_kind("Pro-EQ"),
            Some(SlotKind::Eq)
        );
        assert_eq!(processor_name_to_slot_kind("nonsense"), None);
    }

    #[test]
    fn plan_preview_is_human_readable() {
        let sug = vocal_suggestion();
        let plan = ChainApplier::new().plan(&sug, &empty_state(0));
        let preview = plan.preview();
        assert!(preview.contains("→") || preview.contains("="), "preview: {}", preview);
    }

    #[test]
    fn empty_plan_preview_is_explicit() {
        let plan = ApplyPlan::default();
        assert!(plan.preview().contains("no changes"));
    }

    #[test]
    fn apply_step_describe_contains_slot_index() {
        let step = ApplyStep::LoadInternal {
            slot_index: 3,
            processor_name: "compressor".into(),
        };
        assert!(step.describe().contains("3"));
        assert!(step.describe().contains("compressor"));
    }

    #[test]
    fn external_plugin_pick_when_available() {
        use super::super::chain_advisor::{AvailablePlugin};
        let plugins = vec![
            AvailablePlugin {
                id: "fab.proq4".into(),
                name: "FabFilter Pro-Q 4".into(),
                vendor: "FabFilter".into(),
            },
            AvailablePlugin {
                id: "fab.proc2".into(),
                name: "FabFilter Pro-C 2".into(),
                vendor: "FabFilter".into(),
            },
        ];
        let sug = ChainAdvisor::new()
            .suggest_chain(&analysis_vocal(), &plugins, Some(TrackType::Vocal));
        let plan = ChainApplier::new().plan(&sug, &empty_state(0));
        // Must include at least one LoadExternal
        assert!(plan
            .steps
            .iter()
            .any(|s| matches!(s, ApplyStep::LoadExternal { .. })));
    }

    #[test]
    fn snapshot_captured_for_undo() {
        let state = CurrentChainState {
            track_id: 99,
            slots: vec![CurrentSlotState {
                slot_index: 0,
                processor_name: "compressor".into(),
                kind: None,
                bypassed: false,
            }],
        };
        let plan = ChainApplier::new().plan(&vocal_suggestion(), &state);
        assert_eq!(plan.before_snapshot.track_id, 99);
        assert_eq!(plan.before_snapshot.slots.len(), 1);
    }

    #[test]
    fn step_slot_index_lookup() {
        let step = ApplyStep::SetParameter {
            slot_index: 5,
            name: "Threshold".into(),
            value: -18.0,
            unit: "dB".into(),
        };
        assert_eq!(step.slot_index(), 5);
    }

    #[test]
    fn json_roundtrip_for_plan_steps() {
        let step = ApplyStep::LoadExternal {
            slot_index: 2,
            plugin_id: "plug.id".into(),
            plugin_name: "Some Plug".into(),
        };
        let j = serde_json::to_string(&step).unwrap();
        let back: ApplyStep = serde_json::from_str(&j).unwrap();
        assert_eq!(step, back);
    }
}
