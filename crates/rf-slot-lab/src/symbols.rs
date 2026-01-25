//! Symbol definitions and reel strips

use serde::{Deserialize, Serialize};

/// Symbol type classification
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[repr(u8)]
pub enum SymbolType {
    /// Regular paying symbol
    Regular = 0,
    /// Wild - substitutes for others
    Wild = 1,
    /// Scatter - triggers features regardless of position
    Scatter = 2,
    /// Bonus - triggers bonus game
    Bonus = 3,
    /// Jackpot symbol
    Jackpot = 4,
    /// Blank/empty position
    Blank = 5,
}

/// A symbol definition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Symbol {
    /// Unique symbol ID
    pub id: u32,
    /// Symbol name (e.g., "HP1", "LP3", "WILD", "SCATTER")
    pub name: String,
    /// Symbol type
    pub symbol_type: SymbolType,
    /// Pay values for 3, 4, 5 of a kind (index 0 = 3oak, etc.)
    pub pay_values: Vec<f64>,
    /// Symbol tier (0 = highest paying, increases for lower)
    pub tier: u8,
    /// Can substitute (for wilds)
    pub substitutes_for: Vec<u32>,
}

impl Symbol {
    /// Create a regular symbol
    pub fn regular(id: u32, name: impl Into<String>, tier: u8, pays: &[f64]) -> Self {
        Self {
            id,
            name: name.into(),
            symbol_type: SymbolType::Regular,
            pay_values: pays.to_vec(),
            tier,
            substitutes_for: Vec::new(),
        }
    }

    /// Create a wild symbol
    pub fn wild(id: u32, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
            symbol_type: SymbolType::Wild,
            pay_values: vec![50.0, 200.0, 1000.0], // Typical wild pays
            tier: 0,
            substitutes_for: Vec::new(), // Filled in by engine
        }
    }

    /// Create a scatter symbol
    pub fn scatter(id: u32, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
            symbol_type: SymbolType::Scatter,
            pay_values: vec![2.0, 5.0, 20.0], // Scatter pays (total bet multiplier)
            tier: 0,
            substitutes_for: Vec::new(),
        }
    }

    /// Create a bonus symbol
    pub fn bonus(id: u32, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
            symbol_type: SymbolType::Bonus,
            pay_values: Vec::new(),
            tier: 0,
            substitutes_for: Vec::new(),
        }
    }

    /// Get pay value for a match count
    pub fn get_pay(&self, match_count: u8) -> f64 {
        if match_count < 3 {
            return 0.0;
        }
        let idx = (match_count - 3) as usize;
        self.pay_values.get(idx).copied().unwrap_or(0.0)
    }

    /// Check if this is a special symbol (wild, scatter, bonus)
    pub fn is_special(&self) -> bool {
        !matches!(self.symbol_type, SymbolType::Regular | SymbolType::Blank)
    }
}

/// A virtual reel strip
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReelStrip {
    /// Symbol IDs in order
    pub symbols: Vec<u32>,
    /// Reel index
    pub reel_index: u8,
}

impl ReelStrip {
    /// Create a new reel strip
    pub fn new(reel_index: u8, symbols: Vec<u32>) -> Self {
        Self { symbols, reel_index }
    }

    /// Get symbol at position (wraps around)
    pub fn symbol_at(&self, position: usize) -> u32 {
        if self.symbols.is_empty() {
            return 0;
        }
        self.symbols[position % self.symbols.len()]
    }

    /// Get total strip length
    pub fn len(&self) -> usize {
        self.symbols.len()
    }

    /// Check if empty
    pub fn is_empty(&self) -> bool {
        self.symbols.is_empty()
    }
}

/// Standard symbol set for a classic 5-reel slot
#[derive(Debug, Clone)]
pub struct StandardSymbolSet {
    pub symbols: Vec<Symbol>,
}

impl StandardSymbolSet {
    /// Create a standard symbol set
    /// Industry-standard naming: HP = High Paying, LP = Low Paying
    /// HP1 is highest paying, LP5 is lowest paying
    pub fn new() -> Self {
        let symbols = vec![
            // High paying (HP1 = highest, HP4 = lowest of high tier)
            Symbol::regular(1, "HP1", 0, &[20.0, 100.0, 500.0]),  // Premium symbol
            Symbol::regular(2, "HP2", 1, &[15.0, 75.0, 300.0]),
            Symbol::regular(3, "HP3", 2, &[10.0, 50.0, 200.0]),
            Symbol::regular(4, "HP4", 3, &[8.0, 40.0, 150.0]),
            // Low paying (LP1 = highest of low tier, LP5 = lowest)
            Symbol::regular(5, "LP1", 4, &[5.0, 25.0, 100.0]),
            Symbol::regular(6, "LP2", 5, &[4.0, 20.0, 80.0]),
            Symbol::regular(7, "LP3", 6, &[3.0, 15.0, 60.0]),
            Symbol::regular(8, "LP4", 7, &[2.0, 10.0, 40.0]),
            Symbol::regular(9, "LP5", 8, &[1.0, 5.0, 20.0]),
            Symbol::regular(10, "LP6", 9, &[1.0, 5.0, 20.0]),
            // Special symbols
            Symbol::wild(11, "WILD"),
            Symbol::scatter(12, "SCATTER"),
            Symbol::bonus(13, "BONUS"),
        ];

        Self { symbols }
    }

    /// Get symbol by ID
    pub fn get(&self, id: u32) -> Option<&Symbol> {
        self.symbols.iter().find(|s| s.id == id)
    }

    /// Get all regular symbol IDs
    pub fn regular_ids(&self) -> Vec<u32> {
        self.symbols
            .iter()
            .filter(|s| s.symbol_type == SymbolType::Regular)
            .map(|s| s.id)
            .collect()
    }

    /// Get wild symbol ID
    pub fn wild_id(&self) -> Option<u32> {
        self.symbols
            .iter()
            .find(|s| s.symbol_type == SymbolType::Wild)
            .map(|s| s.id)
    }

    /// Get scatter symbol ID
    pub fn scatter_id(&self) -> Option<u32> {
        self.symbols
            .iter()
            .find(|s| s.symbol_type == SymbolType::Scatter)
            .map(|s| s.id)
    }

    /// Get bonus symbol ID
    pub fn bonus_id(&self) -> Option<u32> {
        self.symbols
            .iter()
            .find(|s| s.symbol_type == SymbolType::Bonus)
            .map(|s| s.id)
    }
}

impl Default for StandardSymbolSet {
    fn default() -> Self {
        Self::new()
    }
}

/// Generate balanced reel strips for a given symbol set
pub fn generate_balanced_strips(
    symbol_set: &StandardSymbolSet,
    reel_count: u8,
    strip_length: usize,
) -> Vec<ReelStrip> {
    let mut strips = Vec::with_capacity(reel_count as usize);
    let regular_ids = symbol_set.regular_ids();
    let wild_id = symbol_set.wild_id().unwrap_or(11);
    let scatter_id = symbol_set.scatter_id().unwrap_or(12);

    for reel_idx in 0..reel_count {
        let mut symbols = Vec::with_capacity(strip_length);

        // Distribution: more low-paying symbols, fewer high-paying
        for i in 0..strip_length {
            let symbol_id = if i % 20 == 0 && reel_idx > 0 {
                // Wild appears rarely, less on reel 1
                wild_id
            } else if i % 25 == 0 {
                // Scatter appears rarely
                scatter_id
            } else {
                // Regular symbols with weighted distribution
                let tier = ((i * 3) % 10) as u8;
                regular_ids
                    .iter()
                    .find(|&&id| symbol_set.get(id).map(|s| s.tier >= tier).unwrap_or(false))
                    .copied()
                    .unwrap_or(regular_ids[i % regular_ids.len()])
            };
            symbols.push(symbol_id);
        }

        strips.push(ReelStrip::new(reel_idx, symbols));
    }

    strips
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_symbol_pay() {
        let symbol = Symbol::regular(1, "HP1", 0, &[20.0, 100.0, 500.0]);
        assert_eq!(symbol.get_pay(2), 0.0);
        assert_eq!(symbol.get_pay(3), 20.0);
        assert_eq!(symbol.get_pay(4), 100.0);
        assert_eq!(symbol.get_pay(5), 500.0);
    }

    #[test]
    fn test_standard_symbol_set() {
        let set = StandardSymbolSet::new();
        assert!(set.wild_id().is_some());
        assert!(set.scatter_id().is_some());
        assert!(!set.regular_ids().is_empty());
    }

    #[test]
    fn test_reel_strip_wrap() {
        let strip = ReelStrip::new(0, vec![1, 2, 3, 4, 5]);
        assert_eq!(strip.symbol_at(0), 1);
        assert_eq!(strip.symbol_at(5), 1); // Wraps
        assert_eq!(strip.symbol_at(7), 3); // Wraps
    }
}
