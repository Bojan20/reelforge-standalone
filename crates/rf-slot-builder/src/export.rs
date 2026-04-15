//! Blueprint export — serialize blueprints for deployment, marketplace, and hot-reload.
//!
//! Supported export formats:
//! - **JSON** — human-readable, version-controllable, hot-reload ready
//! - **Compact JSON** — minified for deployment bundles
//! - **Manifest** — machine-readable compliance summary only
//! - **Flow DOT** — Graphviz format for flow visualization

use serde::{Deserialize, Serialize};

use crate::blueprint::SlotBlueprint;
use crate::validator::{BlueprintReport, Validator, ValidationSeverity};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExportFormat {
    /// Pretty-printed JSON
    Json,
    /// Minified JSON (for production bundles)
    JsonCompact,
    /// Compliance manifest only
    ComplianceManifest,
    /// Graphviz DOT format (flow visualization)
    FlowDot,
}

/// Export result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BlueprintExport {
    /// Export format name
    pub format: String,
    /// Exported content
    pub content: String,
    /// Blueprint fingerprint at time of export
    pub fingerprint: String,
    /// Export timestamp
    pub exported_at: String,
}

impl BlueprintExport {
    pub fn export(blueprint: &SlotBlueprint, format: ExportFormat) -> Result<Self, String> {
        let content = match format {
            ExportFormat::Json => {
                serde_json::to_string_pretty(blueprint)
                    .map_err(|e| format!("JSON serialization failed: {e}"))?
            }
            ExportFormat::JsonCompact => {
                serde_json::to_string(blueprint)
                    .map_err(|e| format!("JSON serialization failed: {e}"))?
            }
            ExportFormat::ComplianceManifest => {
                Self::build_compliance_manifest(blueprint)?
            }
            ExportFormat::FlowDot => {
                Self::build_flow_dot(blueprint)
            }
        };

        Ok(Self {
            format: format!("{format:?}"),
            content,
            fingerprint: blueprint.fingerprint(),
            exported_at: chrono::Utc::now().to_rfc3339(),
        })
    }

    fn build_compliance_manifest(blueprint: &SlotBlueprint) -> Result<String, String> {
        let report: BlueprintReport = Validator::validate(blueprint);

        let manifest = serde_json::json!({
            "blueprint": {
                "title": blueprint.meta.title,
                "version": blueprint.meta.version.to_string(),
                "author": blueprint.meta.author,
                "fingerprint": blueprint.fingerprint(),
            },
            "math": {
                "rtp_target": blueprint.math.rtp_target,
                "volatility": blueprint.math.volatility,
                "max_payout": blueprint.math.max_payout,
                "hit_frequency": blueprint.math.hit_frequency,
                "buy_feature_available": blueprint.math.buy_feature_cost.is_some(),
                "jackpot_tiers": blueprint.math.jackpots.keys().collect::<Vec<_>>(),
            },
            "flow": {
                "node_count": blueprint.flow.node_count(),
                "transition_count": blueprint.flow.transition_count(),
                "has_feature": blueprint.flow.nodes.values()
                    .any(|n| n.category == crate::node::NodeCategory::Feature),
                "has_bonus": blueprint.flow.nodes.values()
                    .any(|n| n.category == crate::node::NodeCategory::Bonus),
                "has_jackpot": blueprint.flow.nodes.values()
                    .any(|n| n.category == crate::node::NodeCategory::Jackpot),
            },
            "compliance": {
                "jurisdictions": blueprint.compliance.jurisdictions.iter()
                    .map(|j| j.code.as_str())
                    .collect::<Vec<_>>(),
                "certifiable": report.certifiable,
                "summary": report.summary(),
                "critical_count": report.critical_count(),
                "warning_count": report.warning_count(),
                "findings": report.findings.iter()
                    .filter(|f| f.severity != ValidationSeverity::Pass)
                    .map(|f| serde_json::json!({
                        "rule_id": f.rule_id,
                        "severity": format!("{:?}", f.severity),
                        "message": f.message,
                        "jurisdiction": f.jurisdiction,
                        "affected_nodes": f.affected_nodes,
                        "suggestion": f.suggestion,
                    }))
                    .collect::<Vec<_>>(),
            },
            "exported_at": chrono::Utc::now().to_rfc3339(),
        });

        serde_json::to_string_pretty(&manifest)
            .map_err(|e| format!("Manifest serialization failed: {e}"))
    }

    fn build_flow_dot(blueprint: &SlotBlueprint) -> String {
        let flow = &blueprint.flow;
        let mut dot = String::new();

        dot.push_str(&format!(
            "digraph \"{}\" {{\n  rankdir=LR;\n  node [shape=box, style=filled];\n\n",
            blueprint.meta.title
        ));

        // Node styles by category
        for node in flow.nodes.values() {
            let color = match node.category {
                crate::node::NodeCategory::Idle => "#2d3561",
                crate::node::NodeCategory::Spin => "#1a6b4a",
                crate::node::NodeCategory::Win => "#c07d10",
                crate::node::NodeCategory::Feature => "#7c3aed",
                crate::node::NodeCategory::Cascade => "#166534",
                crate::node::NodeCategory::Bonus => "#0d9488",
                crate::node::NodeCategory::Gamble => "#dc2626",
                crate::node::NodeCategory::Jackpot => "#991b1b",
                crate::node::NodeCategory::UI => "#374151",
                crate::node::NodeCategory::FlowControl => "#4b5563",
                crate::node::NodeCategory::Custom => "#6b7280",
            };

            let shape = if node.is_entry {
                "ellipse"
            } else if node.is_terminal {
                "doublecircle"
            } else {
                "box"
            };

            dot.push_str(&format!(
                "  \"{}\" [label=\"{}\", fillcolor=\"{}\", fontcolor=white, shape={}];\n",
                node.id.short(),
                node.name,
                color,
                shape
            ));
        }

        dot.push('\n');

        // Edges
        for node in flow.nodes.values() {
            for t in &node.transitions {
                let label = t.label.as_deref().unwrap_or("");
                if let Some(target) = flow.nodes.get(&t.to) {
                    dot.push_str(&format!(
                        "  \"{}\" -> \"{}\" [label=\"{}\"];\n",
                        node.id.short(),
                        target.id.short(),
                        label
                    ));
                }
            }
        }

        dot.push_str("}\n");
        dot
    }
}
