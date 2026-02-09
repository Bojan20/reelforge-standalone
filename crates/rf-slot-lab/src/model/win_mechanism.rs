//! Win Mechanism — How wins are evaluated

use serde::{Deserialize, Serialize};

/// Win evaluation mechanism
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum WinMechanism {
    /// Traditional paylines (e.g., 20 fixed lines)
    Paylines {
        /// Number of paylines
        count: u16,
        /// Line patterns (optional, uses standard if not specified)
        #[serde(default)]
        patterns: Vec<PaylinePattern>,
    },

    /// Ways to win (e.g., 243 ways, 1024 ways)
    Ways {
        /// Maximum possible ways (calculated from grid)
        #[serde(default)]
        max_ways: u64,
        /// Minimum symbols for a way win
        #[serde(default = "default_min_symbols")]
        min_symbols: u8,
    },

    /// Cluster pays (matching adjacent symbols)
    ClusterPays {
        /// Minimum cluster size for a win
        min_cluster: u8,
        /// Allow diagonal connections
        #[serde(default)]
        allow_diagonal: bool,
    },

    /// All pays (any position counts)
    AllPays {
        /// Minimum symbols needed
        min_symbols: u8,
    },

    /// Megaways (variable rows per reel)
    Megaways {
        /// Row range per reel (min, max)
        row_range: (u8, u8),
        /// Maximum possible ways
        #[serde(default)]
        max_ways: u64,
    },
}

fn default_min_symbols() -> u8 {
    3
}

/// A payline pattern definition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PaylinePattern {
    /// Line index (0-based)
    pub index: u8,
    /// Row positions for each reel (0 = top)
    pub positions: Vec<u8>,
}

impl PaylinePattern {
    /// Create a straight horizontal line
    pub fn straight(index: u8, row: u8, reels: u8) -> Self {
        Self {
            index,
            positions: vec![row; reels as usize],
        }
    }

    /// Create a V-shaped line
    pub fn v_shape(index: u8, reels: u8, rows: u8) -> Self {
        let mid = reels / 2;
        let positions = (0..reels)
            .map(|i| {
                if i <= mid {
                    i.min(rows - 1)
                } else {
                    (reels - 1 - i).min(rows - 1)
                }
            })
            .collect();
        Self { index, positions }
    }

    /// Create an inverted V-shaped line
    pub fn inverted_v(index: u8, reels: u8, rows: u8) -> Self {
        let mid = reels / 2;
        let positions = (0..reels)
            .map(|i| {
                let v = if i <= mid { i } else { reels - 1 - i };
                (rows - 1).saturating_sub(v)
            })
            .collect();
        Self { index, positions }
    }
}

impl WinMechanism {
    /// Standard 20 paylines for 5x3 grid
    pub fn standard_20_paylines() -> Self {
        Self::Paylines {
            count: 20,
            patterns: Vec::new(), // Use default patterns
        }
    }

    /// 243 ways (3^5 for 5 reels, 3 rows each)
    pub fn ways_243() -> Self {
        Self::Ways {
            max_ways: 243,
            min_symbols: 3,
        }
    }

    /// 1024 ways (4^5 for 5 reels, 4 rows each)
    pub fn ways_1024() -> Self {
        Self::Ways {
            max_ways: 1024,
            min_symbols: 3,
        }
    }

    /// Cluster pays with minimum 5 symbols
    pub fn cluster_5() -> Self {
        Self::ClusterPays {
            min_cluster: 5,
            allow_diagonal: false,
        }
    }

    /// Megaways with 2-7 rows per reel
    pub fn megaways_standard() -> Self {
        Self::Megaways {
            row_range: (2, 7),
            max_ways: 117649, // 7^6
        }
    }

    /// Check if this is a payline-based mechanism
    pub fn is_paylines(&self) -> bool {
        matches!(self, Self::Paylines { .. })
    }

    /// Check if this is a ways-based mechanism
    pub fn is_ways(&self) -> bool {
        matches!(self, Self::Ways { .. } | Self::Megaways { .. })
    }

    /// Check if this is cluster-based
    pub fn is_cluster(&self) -> bool {
        matches!(self, Self::ClusterPays { .. })
    }

    /// Get minimum symbols needed for a win
    pub fn min_symbols(&self) -> u8 {
        match self {
            Self::Paylines { .. } => 3,
            Self::Ways { min_symbols, .. } => *min_symbols,
            Self::ClusterPays { min_cluster, .. } => *min_cluster,
            Self::AllPays { min_symbols } => *min_symbols,
            Self::Megaways { .. } => 3,
        }
    }
}

impl Default for WinMechanism {
    fn default() -> Self {
        Self::standard_20_paylines()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_payline_patterns() {
        let straight = PaylinePattern::straight(0, 1, 5);
        assert_eq!(straight.positions, vec![1, 1, 1, 1, 1]);

        let v = PaylinePattern::v_shape(1, 5, 3);
        assert_eq!(v.positions, vec![0, 1, 2, 1, 0]);
    }

    #[test]
    fn test_win_mechanism_checks() {
        let paylines = WinMechanism::standard_20_paylines();
        assert!(paylines.is_paylines());
        assert!(!paylines.is_ways());

        let ways = WinMechanism::ways_243();
        assert!(ways.is_ways());
        assert!(!ways.is_paylines());

        let cluster = WinMechanism::cluster_5();
        assert!(cluster.is_cluster());
        assert_eq!(cluster.min_symbols(), 5);
    }

    #[test]
    fn test_serialization() {
        let mechanism = WinMechanism::Ways {
            max_ways: 243,
            min_symbols: 3,
        };

        let json = serde_json::to_string(&mechanism).unwrap();
        assert!(json.contains("ways"));

        let parsed: WinMechanism = serde_json::from_str(&json).unwrap();
        assert!(parsed.is_ways());
    }
}
