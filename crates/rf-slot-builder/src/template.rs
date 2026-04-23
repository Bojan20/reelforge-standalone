//! Built-in slot templates — ready-to-use blueprints for common slot archetypes.
//!
//! Templates provide a complete, validated starting point.
//! Studios can use them as-is, tweak parameters, or fork and extend.
//!
//! ## Available templates
//!
//! | Template | Reels | Rows | Mechanic | Features |
//! |----------|-------|------|----------|----------|
//! | Classic5x3 | 5 | 3 | Paylines | Free Spins |
//! | Megaways | 6 | variable | Ways | Free Spins + Cascade |
//! | ClusterPays | 7 | 7 | Cluster | Free Spins |
//! | CascadeReels | 5 | 5 | Ways + Cascade | Free Spins |
//! | HoldAndSpin | 5 | 3 | Fixed reels | Hold & Spin |
//! | BuyFeature | 5 | 3 | Paylines | Free Spins + Buy |
//! | Jackpot | 5 | 3 | Paylines | Jackpot Wheel |
//! | MultiLevel | 5 | 3 | Paylines | Multi-level bonus |

use crate::binding::{AudioBinding, AudioEventRef};
use crate::blueprint::{BlueprintMeta, ComplianceConfig, JurisdictionProfile, MathConfig, SlotBlueprint};
use crate::flow::StageFlow;
use crate::node::{
    NodeCategory, NodeId, StageNode, StageTransition, TransitionCondition,
};

/// Built-in slot template selector
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SlotTemplate {
    /// Classic 5×3 slot with paylines and free spins
    Classic5x3,
    /// Megaways™-style with variable rows and cascading reels
    Megaways,
    /// Cluster pays (no paylines, connected symbol groups)
    ClusterPays,
    /// Cascading/tumbling reels with multiplier trail
    CascadeReels,
    /// Hold and Spin (lock winning symbols, respin)
    HoldAndSpin,
    /// Classic 5×3 with Buy Feature button
    BuyFeature,
    /// Jackpot wheel bonus (Mini/Minor/Major/Grand)
    Jackpot,
    /// Multi-level bonus game (pick-a-path style)
    MultiLevelBonus,
}

impl SlotTemplate {
    /// Build a complete [`SlotBlueprint`] for this template.
    /// The returned blueprint is valid and ready to execute.
    pub fn build(&self) -> SlotBlueprint {
        match self {
            Self::Classic5x3 => build_classic_5x3(),
            Self::Megaways => build_megaways(),
            Self::ClusterPays => build_cluster_pays(),
            Self::CascadeReels => build_cascade_reels(),
            Self::HoldAndSpin => build_hold_and_spin(),
            Self::BuyFeature => build_buy_feature(),
            Self::Jackpot => build_jackpot(),
            Self::MultiLevelBonus => build_multi_level_bonus(),
        }
    }

    pub fn name(&self) -> &'static str {
        match self {
            Self::Classic5x3 => "Classic 5×3",
            Self::Megaways => "Megaways™ Style",
            Self::ClusterPays => "Cluster Pays",
            Self::CascadeReels => "Cascade Reels",
            Self::HoldAndSpin => "Hold & Spin",
            Self::BuyFeature => "Buy Feature",
            Self::Jackpot => "Jackpot Wheel",
            Self::MultiLevelBonus => "Multi-Level Bonus",
        }
    }
}

// ─── Classic 5×3 ─────────────────────────────────────────────────────────────

fn build_classic_5x3() -> SlotBlueprint {
    // ── Node IDs ──
    let idle_id       = NodeId::from_static("c5x3::idle");
    let spin_id       = NodeId::from_static("c5x3::spin");
    let reel_stop_id  = NodeId::from_static("c5x3::reel_stop");
    let evaluate_id   = NodeId::from_static("c5x3::evaluate");
    let no_win_id     = NodeId::from_static("c5x3::no_win");
    let win_id        = NodeId::from_static("c5x3::win_present");
    let rollup_id     = NodeId::from_static("c5x3::rollup");
    let settle_id     = NodeId::from_static("c5x3::settle");
    let bigwin_id     = NodeId::from_static("c5x3::bigwin");
    let feature_trig  = NodeId::from_static("c5x3::feature_trigger");
    let fs_spin_id    = NodeId::from_static("c5x3::fs_spin");
    let fs_eval_id    = NodeId::from_static("c5x3::fs_evaluate");
    let fs_win_id     = NodeId::from_static("c5x3::fs_win");
    let fs_end_id     = NodeId::from_static("c5x3::fs_end");

    // ── Nodes ──
    let idle = StageNode::new("Idle", "idle_loop")
        .with_id(idle_id)
        .with_category(NodeCategory::Idle)
        .as_entry()
        .with_visual(50.0, 200.0, "#2d3561")
        .with_audio(
            AudioBinding::default()
                .looping(AudioEventRef::new("idle_loop").with_fade(500, 500))
                .with_dna()
        )
        .add_transition(StageTransition::always(spin_id.clone()).with_label("SPIN PRESS")
            .with_condition(TransitionCondition::UserConfirm))
        .add_transition(
            StageTransition {
                id: uuid::Uuid::new_v4(),
                to: spin_id.clone(),
                condition: TransitionCondition::BuyFeature,
                priority: crate::node::TransitionPriority(250),
                delay_ms: 0,
                label: Some("BUY FEATURE".to_string()),
            }
        );

    let spin = StageNode::new("Spin", "ui_spin_press")
        .with_id(spin_id)
        .with_category(NodeCategory::Spin)
        .with_visual(250.0, 200.0, "#1a6b4a")
        .with_audio(
            AudioBinding::default()
                .enter(AudioEventRef::new("spin_start"))
                .looping(AudioEventRef::new("reel_spin_loop").with_fade(50, 300))
        )
        .add_transition(StageTransition::always(reel_stop_id.clone()));

    let reel_stop = StageNode::new("Reels Stopping", "reel_stop")
        .with_id(reel_stop_id)
        .with_category(NodeCategory::Spin)
        .with_visual(450.0, 200.0, "#1a6b4a")
        .interruptible()
        .with_audio(
            AudioBinding::default()
                .enter(AudioEventRef::new("reel_stop_all"))
                .exit(AudioEventRef::new("reel_spin_loop_stop").with_fade(0, 200))
        )
        .add_transition(StageTransition::always(evaluate_id.clone()));

    let evaluate = StageNode::new("Evaluate Wins", "evaluate_wins")
        .with_id(evaluate_id)
        .with_category(NodeCategory::Spin)
        .with_visual(650.0, 200.0, "#1a6b4a")
        .with_max_display(200)
        .add_transition(StageTransition::on_feature(feature_trig.clone(), None))
        .add_transition(StageTransition::on_win(win_id.clone(), Some(0.01)))
        .add_transition(StageTransition::on_no_win(no_win_id.clone()));

    let no_win = StageNode::new("No Win", "spin_end")
        .with_id(no_win_id)
        .with_category(NodeCategory::Win)
        .with_visual(850.0, 100.0, "#555577")
        .with_max_display(300)
        .as_terminal()
        .with_audio(AudioBinding::default().enter(AudioEventRef::new("no_win_settle")));

    let win_present = StageNode::new("Win Present", "win_present")
        .with_id(win_id)
        .with_category(NodeCategory::Win)
        .with_visual(850.0, 200.0, "#c07d10")
        .with_audio(
            AudioBinding::default()
                .enter(AudioEventRef::new("win_fanfare"))
                .duck_music(0.4)
        )
        .add_transition(
            StageTransition {
                id: uuid::Uuid::new_v4(),
                to: bigwin_id.clone(),
                condition: TransitionCondition::BigWinTier {
                    tier: crate::node::BigWinTierCondition::AtLeast { min_multiplier: 15.0 },
                },
                priority: crate::node::TransitionPriority(230),
                delay_ms: 0,
                label: Some("BIG WIN".to_string()),
            }
        )
        .add_transition(StageTransition::always(rollup_id.clone()));

    let rollup = StageNode::new("Rollup", "rollup_start")
        .with_id(rollup_id.clone())
        .with_category(NodeCategory::Win)
        .with_visual(1050.0, 200.0, "#c07d10")
        .with_audio(
            AudioBinding::default()
                .looping(AudioEventRef::new("rollup_tick").with_fade(0, 500))
                .exit(AudioEventRef::new("rollup_end"))
        )
        .add_transition(
            StageTransition {
                id: uuid::Uuid::new_v4(),
                to: settle_id.clone(),
                condition: TransitionCondition::TimeoutMs { ms: 0 },
                priority: crate::node::TransitionPriority(100),
                delay_ms: 0,
                label: Some("ROLLUP DONE".to_string()),
            }
        )
        .add_transition(StageTransition::always(settle_id.clone()));

    let bigwin = StageNode::new("Big Win", "bigwin_tier")
        .with_id(bigwin_id)
        .with_category(NodeCategory::Win)
        .with_visual(1050.0, 50.0, "#e8a020")
        .with_min_display(2000)
        .with_max_display(8000)
        .with_audio(
            AudioBinding::default()
                .enter(AudioEventRef::new("bigwin_sting"))
                .looping(AudioEventRef::new("bigwin_loop"))
                .duck_music(0.1)
        )
        .interruptible()
        .add_transition(StageTransition::always(rollup_id.clone()));

    let settle = StageNode::new("Settle", "spin_end")
        .with_id(settle_id)
        .with_category(NodeCategory::Win)
        .with_visual(1250.0, 200.0, "#2d3561")
        .as_terminal()
        .with_max_display(500);

    // ── Feature trigger ──
    let feature_trigger = StageNode::new("Feature Trigger", "feature_enter")
        .with_id(feature_trig)
        .with_category(NodeCategory::Feature)
        .with_visual(850.0, 350.0, "#7c3aed")
        .with_min_display(2000)
        .with_audio(
            AudioBinding::default()
                .enter(AudioEventRef::new("feature_trigger_sting"))
                .duck_music(0.0)
        )
        .add_transition(StageTransition::always(fs_spin_id.clone()));

    let fs_spin = StageNode::new("Free Spin", "ui_spin_press")
        .with_id(fs_spin_id.clone())
        .with_category(NodeCategory::Feature)
        .with_visual(1050.0, 350.0, "#7c3aed")
        .with_audio(
            AudioBinding::default()
                .enter(AudioEventRef::new("fs_spin_start"))
                .looping(AudioEventRef::new("fs_reel_loop"))
                .with_dna()
        )
        .add_transition(StageTransition::always(fs_eval_id.clone()));

    let fs_evaluate = StageNode::new("Free Spin Evaluate", "evaluate_wins")
        .with_id(fs_eval_id)
        .with_category(NodeCategory::Feature)
        .with_visual(1250.0, 350.0, "#7c3aed")
        .with_max_display(200)
        .add_transition(
            StageTransition {
                id: uuid::Uuid::new_v4(),
                to: fs_spin_id.clone(),
                condition: TransitionCondition::Retrigger,
                priority: crate::node::TransitionPriority(240),
                delay_ms: 500,
                label: Some("RETRIGGER".to_string()),
            }
        )
        .add_transition(
            StageTransition {
                id: uuid::Uuid::new_v4(),
                to: fs_end_id.clone(),
                condition: TransitionCondition::CounterReached {
                    counter_id: "free_spins".to_string(),
                    target: 0,
                },
                priority: crate::node::TransitionPriority(220),
                delay_ms: 0,
                label: Some("FS DONE".to_string()),
            }
        )
        .add_transition(StageTransition::on_win(fs_win_id.clone(), Some(0.01)))
        .add_transition(StageTransition::always(fs_spin_id.clone()));

    let fs_win = StageNode::new("Free Spin Win", "win_present")
        .with_id(fs_win_id)
        .with_category(NodeCategory::Feature)
        .with_visual(1450.0, 350.0, "#7c3aed")
        .with_audio(
            AudioBinding::default()
                .enter(AudioEventRef::new("fs_win_fanfare"))
        )
        .add_transition(StageTransition::always(fs_spin_id));

    let fs_end = StageNode::new("Free Spins End", "feature_exit")
        .with_id(fs_end_id)
        .with_category(NodeCategory::Feature)
        .with_visual(1650.0, 350.0, "#7c3aed")
        .with_min_display(1500)
        .with_audio(
            AudioBinding::default()
                .enter(AudioEventRef::new("feature_end_sting"))
                .exit(AudioEventRef::new("base_music_fade_in").with_fade(2000, 0))
        )
        .add_transition(StageTransition::always(rollup_id));

    // ── Build flow ──
    let flow = StageFlow::builder()
        .node(idle)
        .node(spin)
        .node(reel_stop)
        .node(evaluate)
        .node(no_win)
        .node(win_present)
        .node(rollup)
        .node(bigwin)
        .node(settle)
        .node(feature_trigger)
        .node(fs_spin.clone())
        .node(fs_evaluate)
        .node(fs_win)
        .node(fs_end)
        .allow_loop(fs_spin.id)  // free-spins loop is intentional
        .build()
        .expect("Classic 5x3 template must be valid");

    let meta = BlueprintMeta::new("Classic 5×3", "FluxForge Templates");

    SlotBlueprint::new(meta, MathConfig::empty(5, 3), flow)
        .with_compliance(ComplianceConfig {
            jurisdictions: vec![
                JurisdictionProfile::ukgc(),
                JurisdictionProfile::mga(),
                JurisdictionProfile::sweden(),
            ],
            auto_validate: true,
            audit_endpoint: None,
            include_manifest: true,
        })
}

// ─── Megaways ─────────────────────────────────────────────────────────────────

fn build_megaways() -> SlotBlueprint {
    let idle_id      = NodeId::from_static("mw::idle");
    let spin_id      = NodeId::from_static("mw::spin");
    let stop_id      = NodeId::from_static("mw::stop");
    let eval_id      = NodeId::from_static("mw::eval");
    let cascade_id   = NodeId::from_static("mw::cascade");
    let win_id       = NodeId::from_static("mw::win");
    let settle_id    = NodeId::from_static("mw::settle");
    let feat_id      = NodeId::from_static("mw::feature");
    let fs_id        = NodeId::from_static("mw::fs_spin");

    let idle = StageNode::new("Idle", "idle_loop")
        .with_id(idle_id)
        .as_entry().with_category(NodeCategory::Idle)
        .with_visual(50.0, 200.0, "#1e293b")
        .add_transition(StageTransition::always(spin_id.clone())
            .with_condition(TransitionCondition::UserConfirm));

    let spin = StageNode::new("Megaways Spin", "ui_spin_press")
        .with_id(spin_id)
        .with_category(NodeCategory::Spin).with_visual(250.0, 200.0, "#0f4c75")
        .with_audio(AudioBinding::default().enter(AudioEventRef::new("mw_spin_start"))
            .looping(AudioEventRef::new("mw_reel_loop")))
        .add_transition(StageTransition::always(stop_id.clone()));

    let stop = StageNode::new("Reels Stop", "reel_stop")
        .with_id(stop_id)
        .with_category(NodeCategory::Spin).with_visual(450.0, 200.0, "#0f4c75")
        .add_transition(StageTransition::always(eval_id.clone()));

    let eval = StageNode::new("Evaluate", "evaluate_wins")
        .with_id(eval_id.clone())
        .with_category(NodeCategory::Spin).with_visual(650.0, 200.0, "#0f4c75")
        .with_max_display(200)
        .add_transition(StageTransition::on_feature(feat_id.clone(), None))
        .add_transition(StageTransition::on_win(cascade_id.clone(), Some(0.01)))
        .add_transition(StageTransition::on_no_win(settle_id.clone()));

    let cascade = StageNode::new("Cascade Step", "cascade_start")
        .with_id(cascade_id)
        .with_category(NodeCategory::Cascade).with_visual(850.0, 250.0, "#166534")
        .with_audio(AudioBinding::default()
            .enter(AudioEventRef::new("cascade_drop"))
            .with_rtpc("cascade_multiplier", 1.0))
        .add_transition(
            StageTransition {
                id: uuid::Uuid::new_v4(),
                to: eval_id.clone(),
                condition: TransitionCondition::CascadeOccurred,
                priority: crate::node::TransitionPriority(220),
                delay_ms: 400,
                label: Some("NEXT CASCADE".to_string()),
            }
        )
        .add_transition(StageTransition::on_win(win_id.clone(), Some(0.01)));

    let win = StageNode::new("Win Present", "win_present")
        .with_id(win_id)
        .with_category(NodeCategory::Win).with_visual(1050.0, 200.0, "#92400e")
        .with_audio(AudioBinding::default().enter(AudioEventRef::new("mw_win_sting")))
        .add_transition(StageTransition::always(settle_id.clone()));

    let settle = StageNode::new("Settle", "spin_end")
        .with_id(settle_id.clone())
        .with_category(NodeCategory::Win)
        .as_terminal().with_visual(1250.0, 200.0, "#1e293b");

    let feat = StageNode::new("Feature Trigger", "feature_enter")
        .with_id(feat_id)
        .with_category(NodeCategory::Feature).with_visual(850.0, 350.0, "#7c3aed")
        .with_audio(AudioBinding::default().enter(AudioEventRef::new("mw_feature_trigger")))
        .add_transition(StageTransition::always(fs_id.clone()));

    let fs = StageNode::new("Free Spin (Megaways)", "ui_spin_press")
        .with_id(fs_id)
        .with_category(NodeCategory::Feature).with_visual(1050.0, 350.0, "#7c3aed")
        .add_transition(StageTransition {
            id: uuid::Uuid::new_v4(),
            to: settle_id,
            condition: TransitionCondition::FeatureTriggered { feature_id: None },
            priority: crate::node::TransitionPriority(100),
            delay_ms: 0,
            label: Some("FS DONE".to_string()),
        })
        .add_transition(StageTransition::always(eval_id));

    let flow = StageFlow::builder()
        .nodes([idle, spin, stop, eval, cascade, win, settle, feat, fs.clone()])
        .allow_loop(fs.id)
        .build()
        .expect("Megaways template valid");

    SlotBlueprint::new(BlueprintMeta::new("Megaways Style", "FluxForge Templates"),
        MathConfig::empty(6, 7), flow)
}

// ─── Cluster Pays ────────────────────────────────────────────────────────────

fn build_cluster_pays() -> SlotBlueprint {
    let idle_id   = NodeId::from_static("cp::idle");
    let spin_id   = NodeId::from_static("cp::spin");
    let eval_id   = NodeId::from_static("cp::eval");
    let explode_id = NodeId::from_static("cp::explode");
    let settle_id = NodeId::from_static("cp::settle");

    let idle = StageNode::new("Idle", "idle_loop").with_id(idle_id).as_entry()
        .with_category(NodeCategory::Idle).with_visual(50.0, 200.0, "#0f172a")
        .add_transition(StageTransition::always(spin_id.clone())
            .with_condition(TransitionCondition::UserConfirm));

    let spin = StageNode::new("Cluster Spin", "ui_spin_press")
        .with_id(spin_id)
        .with_category(NodeCategory::Spin).with_visual(250.0, 200.0, "#1d4ed8")
        .with_audio(AudioBinding::default().enter(AudioEventRef::new("cluster_spin")))
        .add_transition(StageTransition::always(eval_id.clone()));

    let eval = StageNode::new("Cluster Evaluate", "evaluate_wins")
        .with_id(eval_id.clone())
        .with_category(NodeCategory::Spin).with_visual(450.0, 200.0, "#1d4ed8")
        .with_max_display(300)
        .add_transition(StageTransition::on_win(explode_id.clone(), Some(0.01)))
        .add_transition(StageTransition::on_no_win(settle_id.clone()));

    let explode = StageNode::new("Cluster Explode + Refill", "cascade_step")
        .with_id(explode_id)
        .with_category(NodeCategory::Cascade).with_visual(650.0, 200.0, "#7c3aed")
        .with_audio(AudioBinding::default()
            .enter(AudioEventRef::new("cluster_explode"))
            .enter(AudioEventRef::new("cluster_refill")))
        .add_transition(StageTransition {
            id: uuid::Uuid::new_v4(),
            to: eval_id,
            condition: TransitionCondition::CascadeOccurred,
            priority: crate::node::TransitionPriority(200),
            delay_ms: 300,
            label: Some("REFILL → EVAL".to_string()),
        })
        .add_transition(StageTransition::always(settle_id.clone()));

    let settle = StageNode::new("Settle", "spin_end").with_id(settle_id).as_terminal()
        .with_visual(850.0, 200.0, "#0f172a");

    let flow = StageFlow::builder()
        .nodes([idle, spin, eval, explode.clone(), settle])
        .allow_loop(explode.id)
        .build()
        .expect("ClusterPays template valid");

    SlotBlueprint::new(BlueprintMeta::new("Cluster Pays", "FluxForge Templates"),
        MathConfig::empty(7, 7), flow)
}

// ─── Cascade Reels ───────────────────────────────────────────────────────────

fn build_cascade_reels() -> SlotBlueprint {
    let idle_id   = NodeId::from_static("cr::idle");
    let spin_id   = NodeId::from_static("cr::spin");
    let eval_id   = NodeId::from_static("cr::eval");
    let cascade_id = NodeId::from_static("cr::cascade");
    let win_id    = NodeId::from_static("cr::win");
    let settle_id = NodeId::from_static("cr::settle");

    let idle = StageNode::new("Idle", "idle_loop").with_id(idle_id).as_entry()
        .with_category(NodeCategory::Idle).with_visual(50.0, 200.0, "#1c1917")
        .add_transition(StageTransition::always(spin_id.clone())
            .with_condition(TransitionCondition::UserConfirm));

    let spin = StageNode::new("Spin", "ui_spin_press")
        .with_id(spin_id)
        .with_category(NodeCategory::Spin).with_visual(250.0, 200.0, "#9a3412")
        .add_transition(StageTransition::always(eval_id.clone()));

    let eval = StageNode::new("Evaluate", "evaluate_wins")
        .with_id(eval_id.clone())
        .with_category(NodeCategory::Spin).with_visual(450.0, 200.0, "#9a3412")
        .add_transition(StageTransition::on_win(cascade_id.clone(), Some(0.01)))
        .add_transition(StageTransition::on_no_win(settle_id.clone()));

    let cascade = StageNode::new("Cascade Drop", "cascade_step")
        .with_id(cascade_id)
        .with_category(NodeCategory::Cascade).with_visual(650.0, 200.0, "#b45309")
        .with_audio(AudioBinding::default()
            .enter(AudioEventRef::new("cascade_drop"))
            .with_rtpc("cascade_level", 1.0))
        .add_transition(StageTransition {
            id: uuid::Uuid::new_v4(),
            to: eval_id,
            condition: TransitionCondition::CascadeOccurred,
            priority: crate::node::TransitionPriority(210),
            delay_ms: 350,
            label: Some("ANOTHER CASCADE".to_string()),
        })
        .add_transition(StageTransition::on_win(win_id.clone(), Some(0.01)));

    let win = StageNode::new("Win Present", "win_present")
        .with_id(win_id)
        .with_category(NodeCategory::Win).with_visual(850.0, 200.0, "#b45309")
        .add_transition(StageTransition::always(settle_id.clone()));

    let settle = StageNode::new("Settle", "spin_end").with_id(settle_id).as_terminal()
        .with_visual(1050.0, 200.0, "#1c1917");

    let flow = StageFlow::builder()
        .nodes([idle, spin, eval, cascade.clone(), win, settle])
        .allow_loop(cascade.id)
        .build()
        .expect("CascadeReels template valid");

    SlotBlueprint::new(BlueprintMeta::new("Cascade Reels", "FluxForge Templates"),
        MathConfig::empty(5, 5), flow)
}

// ─── Hold & Spin ─────────────────────────────────────────────────────────────

fn build_hold_and_spin() -> SlotBlueprint {
    let idle_id   = NodeId::from_static("hs::idle");
    let spin_id   = NodeId::from_static("hs::spin");
    let eval_id   = NodeId::from_static("hs::eval");
    let hold_id   = NodeId::from_static("hs::hold");
    let respin_id = NodeId::from_static("hs::respin");
    let settle_id = NodeId::from_static("hs::settle");

    let idle = StageNode::new("Idle", "idle_loop").with_id(idle_id).as_entry()
        .with_category(NodeCategory::Idle).with_visual(50.0, 200.0, "#0c4a6e")
        .add_transition(StageTransition::always(spin_id.clone())
            .with_condition(TransitionCondition::UserConfirm));

    let spin = StageNode::new("Spin", "ui_spin_press")
        .with_id(spin_id)
        .with_category(NodeCategory::Spin).with_visual(250.0, 200.0, "#075985")
        .add_transition(StageTransition::always(eval_id.clone()));

    let eval = StageNode::new("Evaluate", "evaluate_wins")
        .with_id(eval_id)
        .with_category(NodeCategory::Spin).with_visual(450.0, 200.0, "#075985")
        .add_transition(StageTransition::on_feature(hold_id.clone(), Some("hold_and_spin".to_string())))
        .add_transition(StageTransition::on_no_win(settle_id.clone()))
        .add_transition(StageTransition::on_win(settle_id.clone(), None));

    let hold = StageNode::new("Hold & Spin Init", "feature_enter")
        .with_id(hold_id)
        .with_category(NodeCategory::Feature).with_visual(650.0, 350.0, "#0369a1")
        .with_audio(AudioBinding::default().enter(AudioEventRef::new("hold_spin_trigger")))
        .add_transition(StageTransition::always(respin_id.clone()));

    let respin = StageNode::new("Respin", "ui_spin_press")
        .with_id(respin_id.clone())
        .with_category(NodeCategory::Feature).with_visual(850.0, 350.0, "#0369a1")
        .with_audio(AudioBinding::default()
            .enter(AudioEventRef::new("respin_start"))
            .looping(AudioEventRef::new("respin_loop")))
        .add_transition(StageTransition {
            id: uuid::Uuid::new_v4(),
            to: respin_id,
            condition: TransitionCondition::FeatureTriggered { feature_id: None },
            priority: crate::node::TransitionPriority(220),
            delay_ms: 300,
            label: Some("RESPIN AGAIN".to_string()),
        })
        .add_transition(StageTransition {
            id: uuid::Uuid::new_v4(),
            to: settle_id.clone(),
            condition: TransitionCondition::CounterReached {
                counter_id: "respins".to_string(),
                target: 3,
            },
            priority: crate::node::TransitionPriority(200),
            delay_ms: 0,
            label: Some("RESPINS DONE".to_string()),
        })
        .add_transition(StageTransition::always(settle_id.clone()));

    let settle = StageNode::new("Settle", "spin_end").with_id(settle_id).as_terminal()
        .with_visual(1050.0, 200.0, "#0c4a6e");

    let flow = StageFlow::builder()
        .nodes([idle, spin, eval, hold, respin.clone(), settle])
        .allow_loop(respin.id)
        .build()
        .expect("HoldAndSpin template valid");

    SlotBlueprint::new(BlueprintMeta::new("Hold & Spin", "FluxForge Templates"),
        MathConfig::empty(5, 3), flow)
}

// ─── Buy Feature ─────────────────────────────────────────────────────────────

fn build_buy_feature() -> SlotBlueprint {
    // Extends Classic 5x3 with a buy-feature entry path
    let mut bp = build_classic_5x3();
    bp.meta = BlueprintMeta::new("Buy Feature Slot", "FluxForge Templates");
    bp.math.buy_feature_cost = Some(100.0); // 100x bet
    bp
}

// ─── Jackpot ─────────────────────────────────────────────────────────────────

fn build_jackpot() -> SlotBlueprint {
    let idle_id   = NodeId::from_static("jp::idle");
    let spin_id   = NodeId::from_static("jp::spin");
    let eval_id   = NodeId::from_static("jp::eval");
    let jp_trig   = NodeId::from_static("jp::trigger");
    let jp_build  = NodeId::from_static("jp::buildup");
    let jp_reveal = NodeId::from_static("jp::reveal");
    let jp_cel    = NodeId::from_static("jp::celebration");
    let win_id    = NodeId::from_static("jp::win");
    let settle_id = NodeId::from_static("jp::settle");

    let idle = StageNode::new("Idle", "idle_loop").with_id(idle_id).as_entry()
        .with_category(NodeCategory::Idle).with_visual(50.0, 200.0, "#1a0533")
        .add_transition(StageTransition::always(spin_id.clone())
            .with_condition(TransitionCondition::UserConfirm));

    let spin = StageNode::new("Spin", "ui_spin_press")
        .with_id(spin_id)
        .with_category(NodeCategory::Spin).with_visual(250.0, 200.0, "#4c1d95")
        .add_transition(StageTransition::always(eval_id.clone()));

    let eval = StageNode::new("Evaluate", "evaluate_wins")
        .with_id(eval_id)
        .with_category(NodeCategory::Spin).with_visual(450.0, 200.0, "#4c1d95")
        .add_transition(StageTransition {
            id: uuid::Uuid::new_v4(),
            to: jp_trig.clone(),
            condition: TransitionCondition::JackpotTier { tier: crate::node::JackpotTierCondition::Any },
            priority: crate::node::TransitionPriority(250),
            delay_ms: 0,
            label: Some("JACKPOT!".to_string()),
        })
        .add_transition(StageTransition::on_win(win_id.clone(), Some(0.01)))
        .add_transition(StageTransition::on_no_win(settle_id.clone()));

    let jp_trigger = StageNode::new("Jackpot Trigger", "jackpot_trigger")
        .with_id(jp_trig)
        .with_category(NodeCategory::Jackpot).with_visual(650.0, 350.0, "#7c2d12")
        .with_min_display(1000)
        .with_audio(AudioBinding::default()
            .enter(AudioEventRef::new("jackpot_trigger_sting"))
            .duck_music(0.0))
        .add_transition(StageTransition::always(jp_build.clone()));

    let jp_buildup = StageNode::new("Jackpot Buildup", "jackpot_buildup")
        .with_id(jp_build)
        .with_category(NodeCategory::Jackpot).with_visual(850.0, 350.0, "#7c2d12")
        .with_min_display(2000)
        .with_audio(AudioBinding::default()
            .looping(AudioEventRef::new("jackpot_buildup_loop"))
            .exit(AudioEventRef::new("jackpot_buildup_end")))
        .add_transition(StageTransition::always(jp_reveal.clone()));

    let jp_reveal_node = StageNode::new("Jackpot Reveal", "jackpot_reveal")
        .with_id(jp_reveal)
        .with_category(NodeCategory::Jackpot).with_visual(1050.0, 350.0, "#991b1b")
        .with_audio(AudioBinding::default()
            .enter(AudioEventRef::new("jackpot_reveal_sting")))
        .add_transition(StageTransition::always(jp_cel.clone()));

    let jp_celebration = StageNode::new("Jackpot Celebration", "jackpot_celebration")
        .with_id(jp_cel)
        .with_category(NodeCategory::Jackpot).with_visual(1250.0, 350.0, "#dc2626")
        .with_min_display(5000)
        .interruptible()
        .with_audio(AudioBinding::default()
            .looping(AudioEventRef::new("jackpot_celebration_loop"))
            .duck_music(0.0))
        .add_transition(StageTransition::always(settle_id.clone()));

    let win = StageNode::new("Win Present", "win_present")
        .with_id(win_id)
        .with_category(NodeCategory::Win).with_visual(650.0, 200.0, "#78350f")
        .add_transition(StageTransition::always(settle_id.clone()));

    let settle = StageNode::new("Settle", "spin_end").with_id(settle_id).as_terminal()
        .with_visual(850.0, 200.0, "#1a0533");

    let flow = StageFlow::builder()
        .nodes([idle, spin, eval, jp_trigger, jp_buildup, jp_reveal_node, jp_celebration, win, settle])
        .build()
        .expect("Jackpot template valid");

    let mut bp = SlotBlueprint::new(
        BlueprintMeta::new("Jackpot Wheel", "FluxForge Templates"),
        MathConfig::empty(5, 3),
        flow,
    );
    bp.math.jackpots.insert("grand".to_string(), crate::blueprint::JackpotConfig {
        fixed_amount: None,
        contribution_rate: Some(0.02),
        seed_amount: Some(10000.0),
        min_bet: Some(1.0),
    });
    bp
}

// ─── Multi-Level Bonus ────────────────────────────────────────────────────────

fn build_multi_level_bonus() -> SlotBlueprint {
    let idle_id   = NodeId::from_static("mlb::idle");
    let spin_id   = NodeId::from_static("mlb::spin");
    let eval_id   = NodeId::from_static("mlb::eval");
    let b1_id     = NodeId::from_static("mlb::bonus_level1");
    let b2_id     = NodeId::from_static("mlb::bonus_level2");
    let b3_id     = NodeId::from_static("mlb::bonus_level3");
    let b_end_id  = NodeId::from_static("mlb::bonus_end");
    let settle_id = NodeId::from_static("mlb::settle");

    let idle = StageNode::new("Idle", "idle_loop").with_id(idle_id).as_entry()
        .with_category(NodeCategory::Idle).with_visual(50.0, 200.0, "#134e4a")
        .add_transition(StageTransition::always(spin_id.clone())
            .with_condition(TransitionCondition::UserConfirm));

    let spin = StageNode::new("Spin", "ui_spin_press")
        .with_id(spin_id)
        .with_category(NodeCategory::Spin).with_visual(250.0, 200.0, "#115e59")
        .add_transition(StageTransition::always(eval_id.clone()));

    let eval = StageNode::new("Evaluate", "evaluate_wins")
        .with_id(eval_id)
        .with_category(NodeCategory::Spin).with_visual(450.0, 200.0, "#115e59")
        .add_transition(StageTransition::on_feature(b1_id.clone(), Some("bonus".to_string())))
        .add_transition(StageTransition::on_no_win(settle_id.clone()))
        .add_transition(StageTransition::on_win(settle_id.clone(), None));

    let bonus_l1 = StageNode::new("Bonus Level 1 — Pick", "bonus_choice")
        .with_id(b1_id)
        .with_category(NodeCategory::Bonus).with_visual(650.0, 350.0, "#0d9488")
        .with_audio(AudioBinding::default()
            .enter(AudioEventRef::new("bonus_level1_enter")))
        .add_transition(StageTransition {
            id: uuid::Uuid::new_v4(),
            to: b2_id.clone(),
            condition: TransitionCondition::UserConfirm,
            priority: crate::node::TransitionPriority(200),
            delay_ms: 500,
            label: Some("ADVANCE TO L2".to_string()),
        });

    let bonus_l2 = StageNode::new("Bonus Level 2 — Path", "bonus_reveal")
        .with_id(b2_id)
        .with_category(NodeCategory::Bonus).with_visual(850.0, 350.0, "#0d9488")
        .with_audio(AudioBinding::default()
            .enter(AudioEventRef::new("bonus_level2_enter")))
        .add_transition(StageTransition {
            id: uuid::Uuid::new_v4(),
            to: b3_id.clone(),
            condition: TransitionCondition::UserConfirm,
            priority: crate::node::TransitionPriority(200),
            delay_ms: 500,
            label: Some("ADVANCE TO L3".to_string()),
        })
        .add_transition(StageTransition {
            id: uuid::Uuid::new_v4(),
            to: b_end_id.clone(),
            condition: TransitionCondition::GambleResult {
                outcome: crate::node::GambleOutcome::Lose,
            },
            priority: crate::node::TransitionPriority(220),
            delay_ms: 0,
            label: Some("COLLECT".to_string()),
        });

    let bonus_l3 = StageNode::new("Bonus Level 3 — Grand Prize", "bonus_prize_reveal")
        .with_id(b3_id)
        .with_category(NodeCategory::Bonus).with_visual(1050.0, 350.0, "#0f766e")
        .with_min_display(2000)
        .with_audio(AudioBinding::default()
            .enter(AudioEventRef::new("bonus_level3_grand"))
            .duck_music(0.0))
        .add_transition(StageTransition::always(b_end_id.clone()));

    let bonus_end = StageNode::new("Bonus End", "bonus_complete")
        .with_id(b_end_id)
        .with_category(NodeCategory::Bonus).with_visual(1250.0, 350.0, "#134e4a")
        .with_audio(AudioBinding::default()
            .enter(AudioEventRef::new("bonus_end_sting")))
        .add_transition(StageTransition::always(settle_id.clone()));

    let settle = StageNode::new("Settle", "spin_end").with_id(settle_id).as_terminal()
        .with_visual(1450.0, 200.0, "#134e4a");

    let flow = StageFlow::builder()
        .nodes([idle, spin, eval, bonus_l1, bonus_l2, bonus_l3, bonus_end, settle])
        .build()
        .expect("MultiLevelBonus template valid");

    SlotBlueprint::new(
        BlueprintMeta::new("Multi-Level Bonus", "FluxForge Templates"),
        MathConfig::empty(5, 3),
        flow,
    )
}

// ─── Extension trait for StageTransition ─────────────────────────────────────

trait TransitionExt {
    fn with_condition(self, cond: TransitionCondition) -> StageTransition;
}

impl TransitionExt for StageTransition {
    fn with_condition(mut self, cond: TransitionCondition) -> StageTransition {
        self.condition = cond;
        self
    }
}
