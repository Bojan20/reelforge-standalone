//! Paytable and win calculation

use serde::{Deserialize, Serialize};

use crate::config::GridSpec;
use crate::symbols::StandardSymbolSet;

/// A payline definition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Payline {
    /// Payline index (0-based)
    pub index: u8,
    /// Row positions for each reel (e.g., [1, 0, 0, 0, 1] for a "V" shape)
    pub positions: Vec<u8>,
}

impl Payline {
    /// Create a straight line (same row across all reels)
    pub fn straight(index: u8, row: u8, reel_count: u8) -> Self {
        Self {
            index,
            positions: vec![row; reel_count as usize],
        }
    }

    /// Create a V-shaped line
    pub fn v_shape(index: u8, reel_count: u8) -> Self {
        let mut positions = Vec::with_capacity(reel_count as usize);
        let mid = reel_count / 2;
        for i in 0..reel_count {
            if i <= mid {
                positions.push(i);
            } else {
                positions.push(reel_count - 1 - i);
            }
        }
        Self { index, positions }
    }

    /// Create an inverted V
    pub fn inverted_v(index: u8, rows: u8, reel_count: u8) -> Self {
        let mut positions = Vec::with_capacity(reel_count as usize);
        let mid = reel_count / 2;
        for i in 0..reel_count {
            if i <= mid {
                positions.push(rows - 1 - i.min(rows - 1));
            } else {
                positions.push((i - mid).min(rows - 1));
            }
        }
        Self { index, positions }
    }
}

/// Standard payline patterns for a 5×3 grid
pub fn standard_20_paylines() -> Vec<Payline> {
    vec![
        // Straight lines
        Payline::straight(0, 1, 5),  // Middle
        Payline::straight(1, 0, 5),  // Top
        Payline::straight(2, 2, 5),  // Bottom
        // V shapes
        Payline { index: 3, positions: vec![0, 1, 2, 1, 0] },
        Payline { index: 4, positions: vec![2, 1, 0, 1, 2] },
        // Zigzag
        Payline { index: 5, positions: vec![0, 0, 1, 2, 2] },
        Payline { index: 6, positions: vec![2, 2, 1, 0, 0] },
        Payline { index: 7, positions: vec![1, 0, 0, 0, 1] },
        Payline { index: 8, positions: vec![1, 2, 2, 2, 1] },
        // W shapes
        Payline { index: 9, positions: vec![0, 1, 0, 1, 0] },
        Payline { index: 10, positions: vec![2, 1, 2, 1, 2] },
        // Diagonal
        Payline { index: 11, positions: vec![0, 1, 1, 1, 0] },
        Payline { index: 12, positions: vec![2, 1, 1, 1, 2] },
        // Steps
        Payline { index: 13, positions: vec![1, 1, 0, 1, 1] },
        Payline { index: 14, positions: vec![1, 1, 2, 1, 1] },
        // Complex
        Payline { index: 15, positions: vec![0, 2, 0, 2, 0] },
        Payline { index: 16, positions: vec![2, 0, 2, 0, 2] },
        Payline { index: 17, positions: vec![1, 0, 1, 0, 1] },
        Payline { index: 18, positions: vec![1, 2, 1, 2, 1] },
        Payline { index: 19, positions: vec![0, 0, 2, 0, 0] },
    ]
}

/// A win result on a single payline
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LineWin {
    /// Payline index
    pub line_index: u8,
    /// Winning symbol ID
    pub symbol_id: u32,
    /// Symbol name
    pub symbol_name: String,
    /// Number of matching symbols
    pub match_count: u8,
    /// Win amount (bet × pay value)
    pub win_amount: f64,
    /// Positions of winning symbols (reel, row)
    pub positions: Vec<(u8, u8)>,
    /// Wild positions included
    pub wild_positions: Vec<(u8, u8)>,
}

/// Scatter win result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScatterWin {
    /// Scatter symbol ID
    pub symbol_id: u32,
    /// Number of scatters
    pub count: u8,
    /// Total bet multiplier
    pub multiplier: f64,
    /// Win amount
    pub win_amount: f64,
    /// Positions of scatters
    pub positions: Vec<(u8, u8)>,
    /// Triggers feature?
    pub triggers_feature: bool,
}

/// Complete paytable
#[derive(Debug, Clone)]
pub struct PayTable {
    /// Symbol definitions
    pub symbols: StandardSymbolSet,
    /// Payline definitions
    pub paylines: Vec<Payline>,
    /// Grid spec reference
    pub grid: GridSpec,
    /// Wild symbol ID
    pub wild_id: u32,
    /// Scatter symbol ID
    pub scatter_id: u32,
    /// Scatter count to trigger feature
    pub scatter_trigger_count: u8,
}

impl PayTable {
    /// Create a standard paytable
    pub fn standard(grid: GridSpec) -> Self {
        let symbols = StandardSymbolSet::new();
        let wild_id = symbols.wild_id().unwrap_or(11);
        let scatter_id = symbols.scatter_id().unwrap_or(12);

        Self {
            symbols,
            paylines: standard_20_paylines(),
            grid,
            wild_id,
            scatter_id,
            scatter_trigger_count: 3,
        }
    }

    /// Create a paytable from GameModel (uses GDD symbols if Custom)
    pub fn from_model(model: &crate::model::GameModel) -> Self {
        // Get symbols from model (converts GDD custom symbols to engine symbols)
        let symbols = model.symbols.to_symbol_set();
        let wild_id = symbols.wild_id().unwrap_or(11);
        let scatter_id = symbols.scatter_id().unwrap_or(12);

        // Get paylines based on win mechanism
        let paylines = if model.win_mechanism.is_paylines() {
            // Use grid.paylines count, fallback to 20 if not set
            let count = if model.grid.paylines > 0 {
                model.grid.paylines as usize
            } else {
                20
            };
            // Use standard paylines, limited to count
            standard_20_paylines()
                .into_iter()
                .take(count)
                .collect()
        } else {
            // For ways/cluster, use no paylines (separate evaluation)
            Vec::new()
        };

        Self {
            symbols,
            paylines,
            grid: model.grid.clone(),
            wild_id,
            scatter_id,
            scatter_trigger_count: 3,
        }
    }

    /// Evaluate wins on a grid
    pub fn evaluate(&self, grid: &[Vec<u32>], bet: f64) -> EvaluationResult {
        let mut line_wins = Vec::new();
        let mut scatter_win = None;
        let bet_per_line = bet / self.paylines.len().max(1) as f64;

        // Evaluate each payline
        for payline in &self.paylines {
            if let Some(win) = self.evaluate_line(grid, payline, bet_per_line) {
                line_wins.push(win);
            }
        }

        // Evaluate scatter
        if let Some(sw) = self.evaluate_scatter(grid, bet) {
            scatter_win = Some(sw);
        }

        // Calculate totals
        let line_total: f64 = line_wins.iter().map(|w| w.win_amount).sum();
        let scatter_total = scatter_win.as_ref().map(|s| s.win_amount).unwrap_or(0.0);
        let total_win = line_total + scatter_total;

        EvaluationResult {
            line_wins,
            scatter_win,
            total_win,
            win_ratio: if bet > 0.0 { total_win / bet } else { 0.0 },
        }
    }

    fn evaluate_line(&self, grid: &[Vec<u32>], payline: &Payline, bet_per_line: f64) -> Option<LineWin> {
        if payline.positions.len() != grid.len() {
            return None;
        }

        // Get symbols on this line
        let line_symbols: Vec<u32> = payline
            .positions
            .iter()
            .enumerate()
            .map(|(reel, &row)| {
                grid.get(reel)
                    .and_then(|r| r.get(row as usize))
                    .copied()
                    .unwrap_or(0)
            })
            .collect();

        // Find first non-wild symbol
        let first_symbol = line_symbols
            .iter()
            .find(|&&s| s != self.wild_id)
            .copied()
            .unwrap_or(self.wild_id);

        // Count consecutive matches from left
        let mut match_count = 0u8;
        let mut positions = Vec::new();
        let mut wild_positions = Vec::new();

        for (reel, &symbol) in line_symbols.iter().enumerate() {
            if symbol == first_symbol || symbol == self.wild_id {
                match_count += 1;
                let row = payline.positions[reel];
                if symbol == self.wild_id {
                    wild_positions.push((reel as u8, row));
                }
                positions.push((reel as u8, row));
            } else {
                break;
            }
        }

        // Minimum 3 for a win
        if match_count < 3 {
            return None;
        }

        // Get pay value
        let symbol = self.symbols.get(first_symbol)?;
        let pay_value = symbol.get_pay(match_count);
        if pay_value <= 0.0 {
            return None;
        }

        Some(LineWin {
            line_index: payline.index,
            symbol_id: first_symbol,
            symbol_name: symbol.name.clone(),
            match_count,
            win_amount: bet_per_line * pay_value,
            positions,
            wild_positions,
        })
    }

    fn evaluate_scatter(&self, grid: &[Vec<u32>], bet: f64) -> Option<ScatterWin> {
        let mut positions = Vec::new();

        // Find all scatter positions
        for (reel, column) in grid.iter().enumerate() {
            for (row, &symbol) in column.iter().enumerate() {
                if symbol == self.scatter_id {
                    positions.push((reel as u8, row as u8));
                }
            }
        }

        let count = positions.len() as u8;
        if count < 3 {
            return None;
        }

        // Get scatter pay
        let scatter = self.symbols.get(self.scatter_id)?;
        let multiplier = scatter.get_pay(count);
        let win_amount = bet * multiplier;

        Some(ScatterWin {
            symbol_id: self.scatter_id,
            count,
            multiplier,
            win_amount,
            positions,
            triggers_feature: count >= self.scatter_trigger_count,
        })
    }
}

/// Result of evaluating a grid
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvaluationResult {
    /// Line wins
    pub line_wins: Vec<LineWin>,
    /// Scatter win (if any)
    pub scatter_win: Option<ScatterWin>,
    /// Total win amount
    pub total_win: f64,
    /// Win-to-bet ratio
    pub win_ratio: f64,
}

impl EvaluationResult {
    /// Check if this is a winning spin
    pub fn is_win(&self) -> bool {
        self.total_win > 0.0
    }

    /// Check if scatter triggered a feature
    pub fn triggers_feature(&self) -> bool {
        self.scatter_win
            .as_ref()
            .is_some_and(|s| s.triggers_feature)
    }

    /// Get win count
    pub fn win_count(&self) -> usize {
        self.line_wins.len() + if self.scatter_win.is_some() { 1 } else { 0 }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_payline_straight() {
        let line = Payline::straight(0, 1, 5);
        assert_eq!(line.positions, vec![1, 1, 1, 1, 1]);
    }

    #[test]
    fn test_paytable_evaluate() {
        let paytable = PayTable::standard(GridSpec::default());

        // Create a winning grid (3 sevens on middle line)
        let grid = vec![
            vec![9, 1, 8],  // Reel 0: Cherry, Seven, Plum
            vec![9, 1, 8],  // Reel 1
            vec![9, 1, 8],  // Reel 2
            vec![9, 5, 8],  // Reel 3: Cherry, Bell, Plum
            vec![9, 6, 8],  // Reel 4: Cherry, Grape, Plum
        ];

        let result = paytable.evaluate(&grid, 1.0);
        assert!(result.is_win());
        assert!(!result.line_wins.is_empty());
    }
}
