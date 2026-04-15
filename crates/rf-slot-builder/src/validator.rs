//! Blueprint validator — comprehensive compliance and integrity checking.
//!
//! Covers every scenario a regulator, QA engineer, or platform could ask about:
//! - Math model integrity (RTP bounds, payout caps)
//! - Stage flow integrity (reachability, dead ends, cycles)
//! - Compliance rules (per-jurisdiction, per-node)
//! - Audio binding completeness (all key stages have audio)
//! - Near-miss audio parity (UKGC requirement)
//! - Responsible gambling feature presence
//! - Buy-feature availability check
//! - Jackpot seeding and contribution rate validation

use serde::{Deserialize, Serialize};

use crate::blueprint::SlotBlueprint;
use crate::node::{NodeCategory, TransitionCondition};

// ─── Report types ─────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ValidationSeverity {
    /// Will block certification or platform approval
    Critical,
    /// Should be fixed before submission but won't block
    Warning,
    /// Informational — consider fixing
    Info,
    /// A passed check (for positive confirmation in the report)
    Pass,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ValidationFinding {
    /// Unique rule ID (e.g. "UKGC-RTS-13-NM", "INTEGRITY-DEAD-END")
    pub rule_id: String,
    /// Human description of the finding
    pub message: String,
    /// Severity
    pub severity: ValidationSeverity,
    /// Which node(s) are affected (if any)
    pub affected_nodes: Vec<String>,
    /// Which jurisdiction triggered this (if any)
    pub jurisdiction: Option<String>,
    /// Suggested fix
    pub suggestion: Option<String>,
}

impl ValidationFinding {
    fn pass(rule_id: &str, message: &str) -> Self {
        Self {
            rule_id: rule_id.to_string(),
            message: message.to_string(),
            severity: ValidationSeverity::Pass,
            affected_nodes: vec![],
            jurisdiction: None,
            suggestion: None,
        }
    }

    fn critical(rule_id: &str, message: &str, suggestion: &str) -> Self {
        Self {
            rule_id: rule_id.to_string(),
            message: message.to_string(),
            severity: ValidationSeverity::Critical,
            affected_nodes: vec![],
            jurisdiction: None,
            suggestion: Some(suggestion.to_string()),
        }
    }

    fn warn(rule_id: &str, message: &str) -> Self {
        Self {
            rule_id: rule_id.to_string(),
            message: message.to_string(),
            severity: ValidationSeverity::Warning,
            affected_nodes: vec![],
            jurisdiction: None,
            suggestion: None,
        }
    }

    fn info(rule_id: &str, message: &str) -> Self {
        Self {
            rule_id: rule_id.to_string(),
            message: message.to_string(),
            severity: ValidationSeverity::Info,
            affected_nodes: vec![],
            jurisdiction: None,
            suggestion: None,
        }
    }

    fn with_node(mut self, name: &str) -> Self {
        self.affected_nodes.push(name.to_string());
        self
    }

    fn with_jurisdiction(mut self, j: &str) -> Self {
        self.jurisdiction = Some(j.to_string());
        self
    }

    fn with_suggestion(mut self, s: &str) -> Self {
        self.suggestion = Some(s.to_string());
        self
    }
}

/// Full validation report for a blueprint
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BlueprintReport {
    /// Blueprint title
    pub title: String,
    /// Blueprint version
    pub version: String,
    /// Timestamp (ISO 8601)
    pub timestamp: String,
    /// All findings
    pub findings: Vec<ValidationFinding>,
    /// True if no Critical findings
    pub certifiable: bool,
    /// Jurisdictions validated against
    pub jurisdictions: Vec<String>,
}

impl BlueprintReport {
    pub fn critical_count(&self) -> usize {
        self.findings.iter().filter(|f| f.severity == ValidationSeverity::Critical).count()
    }

    pub fn warning_count(&self) -> usize {
        self.findings.iter().filter(|f| f.severity == ValidationSeverity::Warning).count()
    }

    pub fn pass_count(&self) -> usize {
        self.findings.iter().filter(|f| f.severity == ValidationSeverity::Pass).count()
    }

    pub fn summary(&self) -> String {
        format!(
            "{} critical | {} warnings | {} passed",
            self.critical_count(),
            self.warning_count(),
            self.pass_count()
        )
    }
}

// ─── Validator ────────────────────────────────────────────────────────────────

/// Multi-dimensional blueprint validator.
///
/// Runs all checks and returns a [`BlueprintReport`].
pub struct Validator;

impl Validator {
    /// Run all validation checks against a blueprint.
    pub fn validate(bp: &SlotBlueprint) -> BlueprintReport {
        let mut findings: Vec<ValidationFinding> = Vec::new();

        // ── Integrity checks ─────────────────────────────────────────────
        findings.extend(Self::check_flow_integrity(bp));
        findings.extend(Self::check_math_integrity(bp));
        findings.extend(Self::check_audio_coverage(bp));

        // ── Jurisdiction-specific checks ─────────────────────────────────
        for jurisdiction in &bp.compliance.jurisdictions {
            findings.extend(Self::check_jurisdiction(bp, &jurisdiction.code));
        }

        // ── Feature availability checks ──────────────────────────────────
        findings.extend(Self::check_features(bp));

        // ── Responsible gambling checks ──────────────────────────────────
        findings.extend(Self::check_responsible_gambling(bp));

        let certifiable = findings.iter().all(|f| f.severity != ValidationSeverity::Critical);
        let jurisdictions = bp.compliance.jurisdictions.iter().map(|j| j.code.clone()).collect();

        BlueprintReport {
            title: bp.meta.title.clone(),
            version: bp.meta.version.to_string(),
            timestamp: chrono::Utc::now().to_rfc3339(),
            findings,
            certifiable,
            jurisdictions,
        }
    }

    // ── Flow integrity ────────────────────────────────────────────────────

    fn check_flow_integrity(bp: &SlotBlueprint) -> Vec<ValidationFinding> {
        let mut findings = Vec::new();
        let flow = &bp.flow;

        // Entry node
        let entry_count = flow.nodes.values().filter(|n| n.is_entry).count();
        match entry_count {
            1 => findings.push(ValidationFinding::pass("FLOW-001", "Single entry node present")),
            0 => findings.push(ValidationFinding::critical(
                "FLOW-001",
                "No entry node defined",
                "Mark exactly one node as is_entry=true",
            )),
            _ => findings.push(ValidationFinding::critical(
                "FLOW-001",
                &format!("{entry_count} entry nodes found — only one allowed"),
                "Set is_entry=true on only one node",
            )),
        }

        // Terminal node
        let terminal_count = flow.nodes.values().filter(|n| n.is_terminal).count();
        if terminal_count == 0 {
            findings.push(ValidationFinding::critical(
                "FLOW-002",
                "No terminal node — flow can never complete a round",
                "Add at least one node with is_terminal=true",
            ));
        } else {
            findings.push(ValidationFinding::pass(
                "FLOW-002",
                &format!("{terminal_count} terminal node(s) present"),
            ));
        }

        // Dead-end non-terminal nodes
        let dead_ends: Vec<_> = flow.nodes.values()
            .filter(|n| !n.is_terminal && n.transitions.is_empty())
            .collect();
        for n in dead_ends {
            findings.push(
                ValidationFinding::critical(
                    "FLOW-003",
                    &format!("Node '{}' has no transitions and is not terminal", n.name),
                    "Add at least one outgoing transition or mark as terminal",
                )
                .with_node(&n.name),
            );
        }
        if flow.nodes.values().all(|n| n.is_terminal || !n.transitions.is_empty()) {
            findings.push(ValidationFinding::pass("FLOW-003", "No dead-end nodes"));
        }

        // Dangling transitions
        let mut dangling = false;
        for node in flow.nodes.values() {
            for t in &node.transitions {
                if !flow.nodes.contains_key(&t.to) {
                    findings.push(
                        ValidationFinding::critical(
                            "FLOW-004",
                            &format!("Node '{}' has transition to non-existent node '{}'", node.name, t.to),
                            "Remove the transition or add the missing target node",
                        )
                        .with_node(&node.name),
                    );
                    dangling = true;
                }
            }
        }
        if !dangling {
            findings.push(ValidationFinding::pass("FLOW-004", "All transition targets exist"));
        }

        // Orphan nodes
        let reachable: std::collections::HashSet<_> =
            flow.reachable_nodes().iter().map(|n| n.id.clone()).collect();
        let orphans: Vec<_> = flow.nodes.values()
            .filter(|n| !reachable.contains(&n.id))
            .collect();
        for o in orphans {
            findings.push(
                ValidationFinding::warn(
                    "FLOW-005",
                    &format!("Node '{}' is not reachable from entry", o.name),
                )
                .with_node(&o.name)
                .with_suggestion("Connect this node into the flow or remove it"),
            );
        }

        // Unintended cycles
        let cycles = flow.detect_cycles();
        if cycles.is_empty() {
            findings.push(ValidationFinding::pass("FLOW-006", "No unintended cycles detected"));
        } else {
            for cycle in cycles {
                let names: Vec<_> = cycle.iter()
                    .filter_map(|id| flow.nodes.get(id).map(|n| n.name.as_str()))
                    .collect();
                findings.push(
                    ValidationFinding::warn(
                        "FLOW-006",
                        &format!("Potential unintended cycle: {:?}", names),
                    )
                    .with_suggestion("If intentional (e.g. free spins loop), declare with allow_loop()"),
                );
            }
        }

        findings
    }

    // ── Math integrity ────────────────────────────────────────────────────

    fn check_math_integrity(bp: &SlotBlueprint) -> Vec<ValidationFinding> {
        let mut findings = Vec::new();
        let math = &bp.math;

        // RTP bounds (generic industry standard)
        if math.rtp_target < 0.85 {
            findings.push(ValidationFinding::critical(
                "MATH-001",
                &format!("RTP target {:.1}% is below industry minimum 85%", math.rtp_target * 100.0),
                "Set rtp_target to at least 0.85",
            ));
        } else if math.rtp_target > 0.999 {
            findings.push(ValidationFinding::warn(
                "MATH-001",
                &format!("RTP target {:.1}% is unusually high", math.rtp_target * 100.0),
            ));
        } else {
            findings.push(ValidationFinding::pass(
                "MATH-001",
                &format!("RTP target {:.1}% is within acceptable range", math.rtp_target * 100.0),
            ));
        }

        // Volatility range
        if math.volatility == 0 || math.volatility > 10 {
            findings.push(ValidationFinding::warn(
                "MATH-002",
                &format!("Volatility index {} is outside range 1-10", math.volatility),
            ));
        } else {
            findings.push(ValidationFinding::pass("MATH-002", "Volatility index is in range 1-10"));
        }

        // Max payout cap
        if math.max_payout > 250_000.0 {
            findings.push(
                ValidationFinding::warn(
                    "MATH-003",
                    &format!("Max payout cap {:.0}x exceeds common platform limits", math.max_payout),
                )
                .with_suggestion("Many platforms cap at 25,000× or 50,000× bet"),
            );
        } else {
            findings.push(ValidationFinding::pass(
                "MATH-003",
                &format!("Max payout cap {:.0}x", math.max_payout),
            ));
        }

        // Hit frequency
        if math.hit_frequency <= 0.0 || math.hit_frequency > 1.0 {
            findings.push(ValidationFinding::critical(
                "MATH-004",
                &format!("Hit frequency {} is not in range (0.0, 1.0]", math.hit_frequency),
                "Set hit_frequency between 0.001 and 1.0",
            ));
        } else {
            findings.push(ValidationFinding::pass(
                "MATH-004",
                &format!("Hit frequency {:.1}%", math.hit_frequency * 100.0),
            ));
        }

        // Jackpot config
        for (name, jp) in &math.jackpots {
            if jp.fixed_amount.is_none() && jp.contribution_rate.is_none() {
                findings.push(ValidationFinding::critical(
                    "MATH-005",
                    &format!("Jackpot '{name}' has neither fixed_amount nor contribution_rate"),
                    "Set either fixed_amount or contribution_rate",
                ));
            }
            if let Some(rate) = jp.contribution_rate {
                if rate <= 0.0 || rate > 0.1 {
                    findings.push(ValidationFinding::warn(
                        "MATH-005",
                        &format!("Jackpot '{name}' contribution rate {rate:.3} seems unusual (expected 0.001-0.05)"),
                    ));
                }
            }
        }

        findings
    }

    // ── Audio coverage ────────────────────────────────────────────────────

    fn check_audio_coverage(bp: &SlotBlueprint) -> Vec<ValidationFinding> {
        let mut findings = Vec::new();
        let flow = &bp.flow;

        // Key stage categories that MUST have audio
        let critical_categories = [
            NodeCategory::Win,
            NodeCategory::Feature,
            NodeCategory::Jackpot,
        ];

        for node in flow.nodes.values() {
            if critical_categories.contains(&node.category) {
                if node.audio.on_enter.is_empty() && node.audio.on_loop.is_empty() {
                    findings.push(
                        ValidationFinding::warn(
                            "AUDIO-001",
                            &format!("Node '{}' ({:?}) has no audio binding", node.name, node.category),
                        )
                        .with_node(&node.name)
                        .with_suggestion("Add at least one entry audio event for this node"),
                    );
                }
            }
        }

        // Idle loop must have audio
        let idle_without_audio: Vec<_> = flow.nodes.values()
            .filter(|n| n.category == NodeCategory::Idle && n.audio.on_loop.is_empty())
            .collect();
        for n in idle_without_audio {
            findings.push(
                ValidationFinding::info(
                    "AUDIO-002",
                    &format!("Idle node '{}' has no looping audio — player will hear silence", n.name),
                )
                .with_node(&n.name),
            );
        }

        if findings.is_empty() {
            findings.push(ValidationFinding::pass(
                "AUDIO-001",
                "All critical-category nodes have audio bindings",
            ));
        }

        findings
    }

    // ── Jurisdiction checks ────────────────────────────────────────────────

    fn check_jurisdiction(bp: &SlotBlueprint, code: &str) -> Vec<ValidationFinding> {
        let mut findings = Vec::new();
        let math = &bp.math;
        let flow = &bp.flow;

        let profile = bp.compliance.jurisdictions.iter().find(|j| j.code == code);
        let Some(profile) = profile else { return findings };

        // RTP check
        if math.rtp_target < profile.min_rtp {
            findings.push(
                ValidationFinding::critical(
                    &format!("{code}-RTP-MIN"),
                    &format!("{code}: RTP {:.1}% below minimum {:.1}%",
                        math.rtp_target * 100.0, profile.min_rtp * 100.0),
                    &format!("Increase rtp_target to at least {}", profile.min_rtp),
                )
                .with_jurisdiction(code),
            );
        }
        if math.rtp_target > profile.max_rtp {
            findings.push(
                ValidationFinding::critical(
                    &format!("{code}-RTP-MAX"),
                    &format!("{code}: RTP {:.1}% exceeds maximum {:.1}%",
                        math.rtp_target * 100.0, profile.max_rtp * 100.0),
                    &format!("Decrease rtp_target to at most {}", profile.max_rtp),
                )
                .with_jurisdiction(code),
            );
        }

        // Win cap
        if let Some(cap) = profile.win_cap_multiplier {
            if math.max_payout > cap {
                findings.push(
                    ValidationFinding::critical(
                        &format!("{code}-WIN-CAP"),
                        &format!("{code}: max payout {:.0}x exceeds jurisdiction cap {:.0}x",
                            math.max_payout, cap),
                        &format!("Set math.max_payout to at most {cap}"),
                    )
                    .with_jurisdiction(code),
                );
            }
        }

        // Buy feature check
        if !profile.buy_feature_allowed && math.buy_feature_cost.is_some() {
            findings.push(
                ValidationFinding::critical(
                    &format!("{code}-BUY-FEAT"),
                    &format!("{code}: Buy Feature is not allowed in this jurisdiction"),
                    "Remove buy_feature_cost from math config for this market",
                )
                .with_jurisdiction(code),
            );
        }

        // Autoplay check — check for autoplay node
        if !profile.autoplay_allowed {
            let has_autoplay_transition = flow.nodes.values().any(|n| {
                n.transitions.iter().any(|t| {
                    matches!(t.condition, TransitionCondition::AutoplayActive)
                })
            });
            if has_autoplay_transition {
                findings.push(
                    ValidationFinding::critical(
                        &format!("{code}-AUTOPLAY"),
                        &format!("{code}: Autoplay transitions present but not allowed in jurisdiction"),
                        "Remove AutoplayActive transition conditions for this market",
                    )
                    .with_jurisdiction(code),
                );
            }
        }

        // Near-miss audio parity
        if profile.near_miss_audio_parity {
            let near_miss_nodes: Vec<_> = flow.nodes.values()
                .filter(|n| n.stage_type == "near_miss")
                .collect();
            for nm in near_miss_nodes {
                // Check compliance rule is declared on this node
                let has_parity_rule = nm.compliance.iter().any(|r| {
                    matches!(r.constraint, crate::node::ComplianceConstraint::NearMissAudioParity)
                });
                if !has_parity_rule {
                    findings.push(
                        ValidationFinding::critical(
                            &format!("{code}-NM-AUDIO"),
                            &format!("{code}: Near-miss node '{}' missing NearMissAudioParity compliance rule", nm.name),
                            "Add ComplianceRule with NearMissAudioParity constraint to this node",
                        )
                        .with_node(&nm.name)
                        .with_jurisdiction(code),
                    );
                }
            }
        }

        // Minimum spin duration
        if profile.min_spin_duration_ms > 0 {
            // Check spin nodes have min display >= jurisdiction requirement
            let slow_spins: Vec<_> = flow.nodes.values()
                .filter(|n| n.category == NodeCategory::Spin
                    && n.is_entry == false
                    && n.min_display_ms < profile.min_spin_duration_ms
                    && n.stage_type == "ui_spin_press")
                .collect();
            for n in slow_spins {
                findings.push(
                    ValidationFinding::warn(
                        &format!("{code}-SPIN-SPEED"),
                        &format!("{code}: Spin node '{}' min_display_ms {} < required {}ms",
                            n.name, n.min_display_ms, profile.min_spin_duration_ms),
                    )
                    .with_node(&n.name)
                    .with_jurisdiction(code)
                    .with_suggestion(&format!("Set min_display_ms to at least {}", profile.min_spin_duration_ms)),
                );
            }
        }

        if findings.iter().all(|f| f.severity != ValidationSeverity::Critical) {
            findings.push(ValidationFinding::pass(
                &format!("{code}-OVERALL"),
                &format!("{code}: No critical violations found"),
            ).with_jurisdiction(code));
        }

        findings
    }

    // ── Feature checks ────────────────────────────────────────────────────

    fn check_features(bp: &SlotBlueprint) -> Vec<ValidationFinding> {
        let mut findings = Vec::new();
        let flow = &bp.flow;

        let has_feature = flow.nodes.values().any(|n| n.category == NodeCategory::Feature);
        let has_bonus = flow.nodes.values().any(|n| n.category == NodeCategory::Bonus);
        let has_jackpot = flow.nodes.values().any(|n| n.category == NodeCategory::Jackpot);

        if !has_feature && !has_bonus {
            findings.push(ValidationFinding::info(
                "FEAT-001",
                "No feature or bonus rounds defined — consider adding Free Spins or Bonus Game for player retention",
            ));
        } else {
            findings.push(ValidationFinding::pass("FEAT-001", "Feature/bonus rounds present"));
        }

        if has_jackpot && bp.math.jackpots.is_empty() {
            findings.push(ValidationFinding::critical(
                "FEAT-002",
                "Jackpot nodes exist in flow but no jackpot configuration in math model",
                "Add jackpot configuration to math.jackpots",
            ));
        }

        // Check buy-feature flow connectivity
        if bp.math.buy_feature_cost.is_some() {
            let has_buy_transition = flow.nodes.values().any(|n| {
                n.transitions.iter().any(|t| matches!(t.condition, TransitionCondition::BuyFeature))
            });
            if !has_buy_transition {
                findings.push(ValidationFinding::warn(
                    "FEAT-003",
                    "buy_feature_cost is set in math but no BuyFeature transition in flow",
                ).with_suggestion("Add a BuyFeature transition from idle/entry node to the feature trigger"));
            }
        }

        findings
    }

    // ── Responsible gambling ──────────────────────────────────────────────

    fn check_responsible_gambling(bp: &SlotBlueprint) -> Vec<ValidationFinding> {
        let mut findings = Vec::new();
        let flow = &bp.flow;

        // Check if any node handles RG limit
        let handles_rg = flow.nodes.values().any(|n| {
            n.transitions.iter().any(|t| matches!(t.condition, TransitionCondition::RGLimitReached))
        });

        // Check if any jurisdiction requires RG message
        let rg_required = bp.compliance.jurisdictions.iter().any(|j| j.rg_message_required);

        if rg_required && !handles_rg {
            findings.push(
                ValidationFinding::warn(
                    "RG-001",
                    "Active jurisdiction requires RG features but no RGLimitReached transition found in flow",
                )
                .with_suggestion("Add RGLimitReached transition from critical nodes to a pause/exit state"),
            );
        } else if handles_rg {
            findings.push(ValidationFinding::pass("RG-001", "RG limit transition present"));
        }

        // Check session duration handling
        let has_session_limit = bp.compliance.jurisdictions.iter().any(|j| j.session_limit_minutes.is_some());
        let handles_session = flow.nodes.values().any(|n| {
            n.transitions.iter().any(|t| matches!(t.condition, TransitionCondition::SessionDurationExceeded { .. }))
        });

        if has_session_limit && !handles_session {
            findings.push(
                ValidationFinding::warn(
                    "RG-002",
                    "Jurisdiction has session_limit_minutes but no SessionDurationExceeded transition in flow",
                )
                .with_suggestion("Handle session timeouts in the flow for this jurisdiction"),
            );
        }

        findings
    }
}
