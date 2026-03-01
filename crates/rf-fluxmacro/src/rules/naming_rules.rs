// ============================================================================
// rf-fluxmacro — Naming Rules
// ============================================================================
// FM-10: NamingRuleSet — domain/pattern validation for asset naming.
// Naming scheme: <domain>_<feature>_<event>_<variant>_<v#>
// ============================================================================

use serde::{Deserialize, Serialize};

/// Complete naming rule configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NamingRuleSet {
    /// Naming pattern template.
    pub pattern: String,
    /// Separator character (default: underscore).
    pub separator: char,
    /// Allowed audio domains with their prefixes.
    pub domains: Vec<DomainRule>,
    /// Max length per segment.
    pub max_feature_len: usize,
    pub max_event_len: usize,
    /// Allowed variant characters (default: a-z).
    pub variant_chars: String,
    /// Version prefix (default: "v").
    pub version_prefix: String,
    /// Required sample rate (Hz).
    pub required_sample_rate: u32,
    /// Minimum bit depth.
    pub min_bit_depth: u16,
    /// Allowed file extensions.
    pub allowed_extensions: Vec<String>,
    /// Domain heuristics for auto-classification.
    pub heuristics: Vec<NamingHeuristic>,
}

/// A domain rule defining an allowed audio domain prefix.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DomainRule {
    /// Domain identifier (e.g., "ui", "sfx", "mus", "vo", "amb").
    pub id: String,
    /// Display name.
    pub name: String,
    /// File prefix (e.g., "ui_", "sfx_").
    pub prefix: String,
}

/// Heuristic for auto-detecting wrong domain classification.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NamingHeuristic {
    /// Keywords that suggest this domain.
    pub keywords: Vec<String>,
    /// The expected domain.
    pub expected_domain: String,
}

impl Default for NamingRuleSet {
    fn default() -> Self {
        Self {
            pattern: "<domain>_<feature>_<event>_<variant>_<v#>".to_string(),
            separator: '_',
            domains: vec![
                DomainRule {
                    id: "ui".to_string(),
                    name: "UI".to_string(),
                    prefix: "ui_".to_string(),
                },
                DomainRule {
                    id: "sfx".to_string(),
                    name: "SFX".to_string(),
                    prefix: "sfx_".to_string(),
                },
                DomainRule {
                    id: "mus".to_string(),
                    name: "Music".to_string(),
                    prefix: "mus_".to_string(),
                },
                DomainRule {
                    id: "vo".to_string(),
                    name: "Voice Over".to_string(),
                    prefix: "vo_".to_string(),
                },
                DomainRule {
                    id: "amb".to_string(),
                    name: "Ambience".to_string(),
                    prefix: "amb_".to_string(),
                },
            ],
            max_feature_len: 20,
            max_event_len: 30,
            variant_chars: "abcdefghijklmnopqrstuvwxyz".to_string(),
            version_prefix: "v".to_string(),
            required_sample_rate: 48000,
            min_bit_depth: 16,
            allowed_extensions: vec![
                "wav".to_string(),
                "flac".to_string(),
                "ogg".to_string(),
                "mp3".to_string(),
            ],
            heuristics: vec![
                NamingHeuristic {
                    keywords: vec![
                        "click".to_string(),
                        "button".to_string(),
                        "hover".to_string(),
                        "toggle".to_string(),
                        "menu".to_string(),
                    ],
                    expected_domain: "ui".to_string(),
                },
                NamingHeuristic {
                    keywords: vec![
                        "reel".to_string(),
                        "spin".to_string(),
                        "stop".to_string(),
                        "impact".to_string(),
                        "cascade".to_string(),
                        "land".to_string(),
                    ],
                    expected_domain: "sfx".to_string(),
                },
                NamingHeuristic {
                    keywords: vec![
                        "loop".to_string(),
                        "music".to_string(),
                        "theme".to_string(),
                        "layer".to_string(),
                        "stinger".to_string(),
                    ],
                    expected_domain: "mus".to_string(),
                },
                NamingHeuristic {
                    keywords: vec![
                        "narrator".to_string(),
                        "announce".to_string(),
                        "voice".to_string(),
                        "speech".to_string(),
                    ],
                    expected_domain: "vo".to_string(),
                },
                NamingHeuristic {
                    keywords: vec![
                        "ambient".to_string(),
                        "atmosphere".to_string(),
                        "background".to_string(),
                        "room".to_string(),
                    ],
                    expected_domain: "amb".to_string(),
                },
            ],
        }
    }
}

impl NamingRuleSet {
    /// Validate a filename against the naming rules.
    /// Returns a list of violations (empty = valid).
    pub fn validate_filename(&self, filename: &str) -> Vec<String> {
        let mut violations = Vec::new();

        // Strip extension
        let name = match filename.rsplit_once('.') {
            Some((stem, ext)) => {
                if !self
                    .allowed_extensions
                    .iter()
                    .any(|e| e.eq_ignore_ascii_case(ext))
                {
                    violations.push(format!(
                        "unsupported extension '.{ext}' — allowed: {}",
                        self.allowed_extensions.join(", ")
                    ));
                }
                stem
            }
            None => {
                violations.push("missing file extension".to_string());
                filename
            }
        };

        // Split by separator
        let parts: Vec<&str> = name.split(self.separator).collect();

        // Must have at least domain + event
        if parts.len() < 2 {
            violations.push(format!(
                "too few segments: expected at least <domain>{sep}<event>, got '{name}'",
                sep = self.separator
            ));
            return violations;
        }

        // Check domain
        let domain = parts[0];
        if !self.domains.iter().any(|d| d.id == domain) {
            let valid: Vec<&str> = self.domains.iter().map(|d| d.id.as_str()).collect();
            violations.push(format!(
                "unknown domain '{domain}' — expected one of: {}",
                valid.join(", ")
            ));
        }

        // Check for uppercase or special characters in segments
        for (i, part) in parts.iter().enumerate() {
            if part.is_empty() {
                violations.push(format!("empty segment at position {i}"));
                continue;
            }

            // Skip variant and version segments
            if i >= 3 {
                continue;
            }

            if part.chars().any(|c| c.is_ascii_uppercase()) {
                violations.push(format!("segment '{part}' contains uppercase characters"));
            }

            if part
                .chars()
                .any(|c| !c.is_ascii_alphanumeric() && c != '-')
            {
                violations.push(format!(
                    "segment '{part}' contains special characters"
                ));
            }
        }

        // Check feature length (segment 1)
        if parts.len() > 1 && parts[1].len() > self.max_feature_len {
            violations.push(format!(
                "feature segment '{}' exceeds max length {} chars",
                parts[1], self.max_feature_len
            ));
        }

        // Check event length (segment 2)
        if parts.len() > 2 && parts[2].len() > self.max_event_len {
            violations.push(format!(
                "event segment '{}' exceeds max length {} chars",
                parts[2], self.max_event_len
            ));
        }

        violations
    }

    /// Use heuristics to suggest the correct domain for a filename.
    pub fn suggest_domain(&self, filename: &str) -> Option<&str> {
        let lower = filename.to_lowercase();
        for heuristic in &self.heuristics {
            if heuristic
                .keywords
                .iter()
                .any(|kw| lower.contains(kw.as_str()))
            {
                return Some(&heuristic.expected_domain);
            }
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn valid_filenames() {
        let rules = NamingRuleSet::default();
        assert!(rules.validate_filename("sfx_reel_stop_a_v1.wav").is_empty());
        assert!(rules.validate_filename("mus_base_loop.flac").is_empty());
        assert!(rules.validate_filename("ui_button_click_b_v2.ogg").is_empty());
        assert!(rules.validate_filename("vo_narrator_welcome.wav").is_empty());
        assert!(rules.validate_filename("amb_background_forest.wav").is_empty());
    }

    #[test]
    fn invalid_domain() {
        let rules = NamingRuleSet::default();
        let v = rules.validate_filename("bad_reel_stop.wav");
        assert!(!v.is_empty());
        assert!(v[0].contains("unknown domain"));
    }

    #[test]
    fn uppercase_violation() {
        let rules = NamingRuleSet::default();
        let v = rules.validate_filename("sfx_Reel_Stop.wav");
        assert!(!v.is_empty());
        assert!(v.iter().any(|s| s.contains("uppercase")));
    }

    #[test]
    fn domain_heuristics() {
        let rules = NamingRuleSet::default();
        assert_eq!(rules.suggest_domain("click_sound"), Some("ui"));
        assert_eq!(rules.suggest_domain("reel_stop_impact"), Some("sfx"));
        assert_eq!(rules.suggest_domain("base_theme_loop"), Some("mus"));
        assert_eq!(rules.suggest_domain("narrator_welcome"), Some("vo"));
        assert_eq!(rules.suggest_domain("background_forest"), Some("amb"));
        assert_eq!(rules.suggest_domain("unknown_xyz"), None);
    }
}
