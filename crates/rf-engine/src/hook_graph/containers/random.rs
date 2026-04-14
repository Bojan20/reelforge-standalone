//! RandomContainer — Weighted random selection with repeat avoidance.
//! Supports: shuffle, weighted, avoid-last-N, seeded RNG for determinism.

pub struct WeightedEntry {
    pub index: usize,
    pub weight: f32,
}

pub struct RandomContainer {
    entries: Vec<WeightedEntry>,
    _total_weight: f32,
    avoid_last_n: usize,
    history: Vec<usize>,
    seed: u64,
    state: u64,
}

impl RandomContainer {
    pub fn new(weights: &[f32], avoid_last_n: usize, seed: u64) -> Self {
        let entries: Vec<_> = weights.iter().enumerate()
            .map(|(i, &w)| WeightedEntry { index: i, weight: w.max(0.001) })
            .collect();
        let _total_weight = entries.iter().map(|e| e.weight).sum();
        Self {
            entries,
            _total_weight,
            avoid_last_n,
            history: Vec::with_capacity(avoid_last_n + 1),
            seed,
            state: seed,
        }
    }

    pub fn select(&mut self) -> usize {
        if self.entries.is_empty() { return 0; }
        if self.entries.len() == 1 { return self.entries[0].index; }

        let eff_weight = self.effective_total_weight();
        let mut threshold = self.next_random() * eff_weight;
        let mut selected = self.entries.last().unwrap().index;

        for entry in &self.entries {
            if self.history.iter().rev().take(self.avoid_last_n).any(|&h| h == entry.index) {
                continue;
            }
            threshold -= entry.weight;
            if threshold <= 0.0 {
                selected = entry.index;
                break;
            }
        }

        self.push_history(selected);
        selected
    }

    fn is_avoided(&self, index: usize) -> bool {
        if self.avoid_last_n == 0 { return false; }
        self.history.iter().rev().take(self.avoid_last_n).any(|&h| h == index)
    }

    fn effective_total_weight(&self) -> f32 {
        self.entries.iter()
            .filter(|e| !self.is_avoided(e.index))
            .map(|e| e.weight)
            .sum()
    }

    fn push_history(&mut self, index: usize) {
        self.history.push(index);
        if self.history.len() > self.avoid_last_n + 2 {
            self.history.remove(0);
        }
    }

    // xorshift64 — deterministic, zero-alloc
    fn next_random(&mut self) -> f32 {
        self.state ^= self.state << 13;
        self.state ^= self.state >> 7;
        self.state ^= self.state << 17;
        (self.state as f32) / (u64::MAX as f32)
    }

    pub fn reset(&mut self) {
        self.history.clear();
        self.state = self.seed;
    }
}
