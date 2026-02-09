//! Memory Manager FFI
//!
//! Soundbank memory budget management exposed to Flutter.
//! Provides:
//! - Soundbank registration and lifecycle
//! - Memory budget tracking (resident + streaming)
//! - LRU-based automatic unloading
//! - Memory statistics for monitoring

use once_cell::sync::Lazy;
use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::ffi::{CStr, CString, c_char};
use std::time::{Duration, Instant};

// ═══════════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Load priority for soundbanks
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum LoadPriority {
    /// Load immediately, keep resident
    Critical = 0,
    /// Load on demand, keep resident
    High = 1,
    /// Load on demand, can unload
    Normal = 2,
    /// Stream from disk
    Streaming = 3,
}

impl Default for LoadPriority {
    fn default() -> Self {
        LoadPriority::Normal
    }
}

/// Memory state
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum MemoryState {
    Normal = 0,
    Warning = 1,
    Critical = 2,
}

/// Sound bank definition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SoundBank {
    pub bank_id: String,
    pub name: String,
    pub estimated_size_bytes: usize,
    pub priority: LoadPriority,
    pub sound_ids: Vec<String>,
    pub is_loaded: bool,
    pub actual_size_bytes: usize,
    #[serde(skip)]
    pub last_used: Option<Instant>,
}

impl SoundBank {
    pub fn new(bank_id: String, name: String, estimated_size_bytes: usize) -> Self {
        Self {
            bank_id,
            name,
            estimated_size_bytes,
            priority: LoadPriority::Normal,
            sound_ids: Vec::new(),
            is_loaded: false,
            actual_size_bytes: 0,
            last_used: None,
        }
    }

    pub fn size_mb(&self) -> f64 {
        self.actual_size_bytes as f64 / (1024.0 * 1024.0)
    }

    pub fn estimated_size_mb(&self) -> f64 {
        self.estimated_size_bytes as f64 / (1024.0 * 1024.0)
    }
}

/// Memory budget configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryBudgetConfig {
    /// Maximum resident memory (bytes)
    pub max_resident_bytes: usize,
    /// Maximum streaming buffer (bytes)
    pub max_streaming_bytes: usize,
    /// Warning threshold (0.0-1.0)
    pub warning_threshold: f64,
    /// Critical threshold (0.0-1.0)
    pub critical_threshold: f64,
    /// Minimum time before unloading (ms)
    pub min_resident_time_ms: u64,
}

impl Default for MemoryBudgetConfig {
    fn default() -> Self {
        Self {
            max_resident_bytes: 64 * 1024 * 1024,  // 64MB
            max_streaming_bytes: 32 * 1024 * 1024, // 32MB
            warning_threshold: 0.75,
            critical_threshold: 0.90,
            min_resident_time_ms: 5000,
        }
    }
}

/// Memory statistics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryStats {
    pub resident_bytes: usize,
    pub resident_max_bytes: usize,
    pub streaming_bytes: usize,
    pub streaming_max_bytes: usize,
    pub loaded_bank_count: usize,
    pub total_bank_count: usize,
    pub state: MemoryState,
    pub resident_percent: f64,
    pub streaming_percent: f64,
    pub resident_mb: f64,
    pub streaming_mb: f64,
}

// ═══════════════════════════════════════════════════════════════════════════════
// MEMORY BUDGET MANAGER
// ═══════════════════════════════════════════════════════════════════════════════

struct MemoryBudgetManager {
    config: MemoryBudgetConfig,
    banks: HashMap<String, SoundBank>,
    current_resident_bytes: usize,
    current_streaming_bytes: usize,
}

impl MemoryBudgetManager {
    fn new(config: MemoryBudgetConfig) -> Self {
        Self {
            config,
            banks: HashMap::new(),
            current_resident_bytes: 0,
            current_streaming_bytes: 0,
        }
    }

    fn resident_percent(&self) -> f64 {
        if self.config.max_resident_bytes == 0 {
            return 0.0;
        }
        self.current_resident_bytes as f64 / self.config.max_resident_bytes as f64
    }

    fn streaming_percent(&self) -> f64 {
        if self.config.max_streaming_bytes == 0 {
            return 0.0;
        }
        self.current_streaming_bytes as f64 / self.config.max_streaming_bytes as f64
    }

    fn state(&self) -> MemoryState {
        let percent = self.resident_percent();
        if percent >= self.config.critical_threshold {
            MemoryState::Critical
        } else if percent >= self.config.warning_threshold {
            MemoryState::Warning
        } else {
            MemoryState::Normal
        }
    }

    fn register_bank(&mut self, bank: SoundBank) {
        self.banks.insert(bank.bank_id.clone(), bank);
    }

    fn load_bank(&mut self, bank_id: &str) -> bool {
        let bank = match self.banks.get_mut(bank_id) {
            Some(b) => b,
            None => return false,
        };

        if bank.is_loaded {
            return false;
        }

        let needed_bytes = bank.estimated_size_bytes;

        // Check if we have space
        if self.current_resident_bytes + needed_bytes > self.config.max_resident_bytes {
            // Try to free space
            if !self.free_space(needed_bytes) {
                return false;
            }
        }

        // Get mutable reference again after free_space
        let bank = self.banks.get_mut(bank_id).unwrap();
        bank.is_loaded = true;
        bank.actual_size_bytes = needed_bytes;
        bank.last_used = Some(Instant::now());
        self.current_resident_bytes += bank.actual_size_bytes;

        true
    }

    fn unload_bank(&mut self, bank_id: &str) -> bool {
        let bank = match self.banks.get_mut(bank_id) {
            Some(b) => b,
            None => return false,
        };

        if !bank.is_loaded {
            return false;
        }

        // Can't unload critical banks
        if bank.priority == LoadPriority::Critical {
            return false;
        }

        let size = bank.actual_size_bytes;
        bank.is_loaded = false;
        bank.actual_size_bytes = 0;
        self.current_resident_bytes = self.current_resident_bytes.saturating_sub(size);

        true
    }

    fn free_space(&mut self, needed_bytes: usize) -> bool {
        let now = Instant::now();
        let min_resident_time = Duration::from_millis(self.config.min_resident_time_ms);

        // Get unloadable bank IDs sorted by last used
        let mut candidates: Vec<(String, Instant, usize)> = self
            .banks
            .values()
            .filter(|b| {
                b.is_loaded
                    && b.priority != LoadPriority::Critical
                    && b.last_used
                        .map(|t| now.duration_since(t) >= min_resident_time)
                        .unwrap_or(true)
            })
            .map(|b| {
                (
                    b.bank_id.clone(),
                    b.last_used.unwrap_or(Instant::now()),
                    b.estimated_size_bytes,
                )
            })
            .collect();

        // Sort by last used (oldest first)
        candidates.sort_by(|a, b| a.1.cmp(&b.1));

        let mut freed = 0usize;
        for (bank_id, _, estimated_size) in candidates {
            if freed >= needed_bytes {
                break;
            }

            if self.unload_bank(&bank_id) {
                freed += estimated_size;
            }
        }

        freed >= needed_bytes
    }

    fn touch_bank(&mut self, bank_id: &str) {
        if let Some(bank) = self.banks.get_mut(bank_id) {
            bank.last_used = Some(Instant::now());
        }
    }

    fn is_bank_loaded(&self, bank_id: &str) -> bool {
        self.banks
            .get(bank_id)
            .map(|b| b.is_loaded)
            .unwrap_or(false)
    }

    fn loaded_banks(&self) -> Vec<&SoundBank> {
        self.banks.values().filter(|b| b.is_loaded).collect()
    }

    fn all_banks(&self) -> Vec<&SoundBank> {
        self.banks.values().collect()
    }

    fn get_stats(&self) -> MemoryStats {
        let resident_mb = self.current_resident_bytes as f64 / (1024.0 * 1024.0);
        let streaming_mb = self.current_streaming_bytes as f64 / (1024.0 * 1024.0);

        MemoryStats {
            resident_bytes: self.current_resident_bytes,
            resident_max_bytes: self.config.max_resident_bytes,
            streaming_bytes: self.current_streaming_bytes,
            streaming_max_bytes: self.config.max_streaming_bytes,
            loaded_bank_count: self.loaded_banks().len(),
            total_bank_count: self.banks.len(),
            state: self.state(),
            resident_percent: self.resident_percent(),
            streaming_percent: self.streaming_percent(),
            resident_mb,
            streaming_mb,
        }
    }

    fn update_config(&mut self, config: MemoryBudgetConfig) {
        self.config = config;
    }

    fn clear(&mut self) {
        // Unload all banks
        let bank_ids: Vec<String> = self.banks.keys().cloned().collect();
        for bank_id in bank_ids {
            self.unload_bank(&bank_id);
        }
        self.banks.clear();
        self.current_resident_bytes = 0;
        self.current_streaming_bytes = 0;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GLOBAL STATE
// ═══════════════════════════════════════════════════════════════════════════════

static MEMORY_MANAGER: Lazy<RwLock<MemoryBudgetManager>> =
    Lazy::new(|| RwLock::new(MemoryBudgetManager::new(MemoryBudgetConfig::default())));

// ═══════════════════════════════════════════════════════════════════════════════
// C FFI FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════════

/// Initialize memory manager with config (JSON)
#[unsafe(no_mangle)]
pub extern "C" fn memory_manager_init(config_json: *const c_char) {
    let config = if config_json.is_null() {
        MemoryBudgetConfig::default()
    } else {
        let c_str = unsafe { CStr::from_ptr(config_json) };
        match c_str.to_str() {
            Ok(s) => serde_json::from_str(s).unwrap_or_default(),
            Err(_) => MemoryBudgetConfig::default(),
        }
    };

    let mut manager = MEMORY_MANAGER.write();
    *manager = MemoryBudgetManager::new(config);
}

/// Update memory manager config (JSON)
#[unsafe(no_mangle)]
pub extern "C" fn memory_manager_update_config(config_json: *const c_char) {
    if config_json.is_null() {
        return;
    }

    let c_str = unsafe { CStr::from_ptr(config_json) };
    if let Ok(s) = c_str.to_str() {
        if let Ok(config) = serde_json::from_str::<MemoryBudgetConfig>(s) {
            MEMORY_MANAGER.write().update_config(config);
        }
    }
}

/// Register a soundbank (JSON)
#[unsafe(no_mangle)]
pub extern "C" fn memory_manager_register_bank(bank_json: *const c_char) -> i32 {
    if bank_json.is_null() {
        return 0;
    }

    let c_str = unsafe { CStr::from_ptr(bank_json) };
    match c_str.to_str() {
        Ok(s) => match serde_json::from_str::<SoundBank>(s) {
            Ok(bank) => {
                MEMORY_MANAGER.write().register_bank(bank);
                1
            }
            Err(_) => 0,
        },
        Err(_) => 0,
    }
}

/// Load a soundbank
#[unsafe(no_mangle)]
pub extern "C" fn memory_manager_load_bank(bank_id: *const c_char) -> i32 {
    if bank_id.is_null() {
        return 0;
    }

    let c_str = unsafe { CStr::from_ptr(bank_id) };
    match c_str.to_str() {
        Ok(id) => {
            if MEMORY_MANAGER.write().load_bank(id) {
                1
            } else {
                0
            }
        }
        Err(_) => 0,
    }
}

/// Unload a soundbank
#[unsafe(no_mangle)]
pub extern "C" fn memory_manager_unload_bank(bank_id: *const c_char) -> i32 {
    if bank_id.is_null() {
        return 0;
    }

    let c_str = unsafe { CStr::from_ptr(bank_id) };
    match c_str.to_str() {
        Ok(id) => {
            if MEMORY_MANAGER.write().unload_bank(id) {
                1
            } else {
                0
            }
        }
        Err(_) => 0,
    }
}

/// Touch (mark as recently used) a soundbank
#[unsafe(no_mangle)]
pub extern "C" fn memory_manager_touch_bank(bank_id: *const c_char) {
    if bank_id.is_null() {
        return;
    }

    let c_str = unsafe { CStr::from_ptr(bank_id) };
    if let Ok(id) = c_str.to_str() {
        MEMORY_MANAGER.write().touch_bank(id);
    }
}

/// Check if a soundbank is loaded
#[unsafe(no_mangle)]
pub extern "C" fn memory_manager_is_bank_loaded(bank_id: *const c_char) -> i32 {
    if bank_id.is_null() {
        return 0;
    }

    let c_str = unsafe { CStr::from_ptr(bank_id) };
    match c_str.to_str() {
        Ok(id) => {
            if MEMORY_MANAGER.read().is_bank_loaded(id) {
                1
            } else {
                0
            }
        }
        Err(_) => 0,
    }
}

/// Get memory statistics (JSON)
#[unsafe(no_mangle)]
pub extern "C" fn memory_manager_get_stats_json() -> *mut c_char {
    let stats = MEMORY_MANAGER.read().get_stats();
    let json = serde_json::to_string(&stats).unwrap_or_else(|_| "{}".to_string());
    CString::new(json).unwrap().into_raw()
}

/// Get current memory state (0=Normal, 1=Warning, 2=Critical)
#[unsafe(no_mangle)]
pub extern "C" fn memory_manager_get_state() -> i32 {
    MEMORY_MANAGER.read().state() as i32
}

/// Get resident memory usage in bytes
#[unsafe(no_mangle)]
pub extern "C" fn memory_manager_get_resident_bytes() -> usize {
    MEMORY_MANAGER.read().current_resident_bytes
}

/// Get resident memory percentage (0.0-1.0)
#[unsafe(no_mangle)]
pub extern "C" fn memory_manager_get_resident_percent() -> f64 {
    MEMORY_MANAGER.read().resident_percent()
}

/// Get loaded bank count
#[unsafe(no_mangle)]
pub extern "C" fn memory_manager_get_loaded_bank_count() -> usize {
    MEMORY_MANAGER.read().loaded_banks().len()
}

/// Get total bank count
#[unsafe(no_mangle)]
pub extern "C" fn memory_manager_get_total_bank_count() -> usize {
    MEMORY_MANAGER.read().banks.len()
}

/// Get all banks as JSON array
#[unsafe(no_mangle)]
pub extern "C" fn memory_manager_get_banks_json() -> *mut c_char {
    let manager = MEMORY_MANAGER.read();
    let banks: Vec<&SoundBank> = manager.all_banks();

    // Convert to serializable format with last_used as Option<u64> (ms since epoch simulation)
    #[derive(Serialize)]
    struct BankInfo {
        bank_id: String,
        name: String,
        estimated_size_bytes: usize,
        priority: LoadPriority,
        sound_ids: Vec<String>,
        is_loaded: bool,
        actual_size_bytes: usize,
    }

    let infos: Vec<BankInfo> = banks
        .into_iter()
        .map(|b| BankInfo {
            bank_id: b.bank_id.clone(),
            name: b.name.clone(),
            estimated_size_bytes: b.estimated_size_bytes,
            priority: b.priority,
            sound_ids: b.sound_ids.clone(),
            is_loaded: b.is_loaded,
            actual_size_bytes: b.actual_size_bytes,
        })
        .collect();

    let json = serde_json::to_string(&infos).unwrap_or_else(|_| "[]".to_string());
    CString::new(json).unwrap().into_raw()
}

/// Clear all banks and reset memory
#[unsafe(no_mangle)]
pub extern "C" fn memory_manager_clear() {
    MEMORY_MANAGER.write().clear();
}

/// Free a string allocated by memory manager
#[unsafe(no_mangle)]
pub extern "C" fn memory_manager_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            drop(CString::from_raw(ptr));
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_memory_manager_basic() {
        let mut manager = MemoryBudgetManager::new(MemoryBudgetConfig {
            max_resident_bytes: 100 * 1024 * 1024, // 100MB
            ..Default::default()
        });

        // Register a bank
        let bank = SoundBank {
            bank_id: "test_bank".to_string(),
            name: "Test Bank".to_string(),
            estimated_size_bytes: 10 * 1024 * 1024, // 10MB
            priority: LoadPriority::Normal,
            sound_ids: vec!["sound1".to_string()],
            is_loaded: false,
            actual_size_bytes: 0,
            last_used: None,
        };
        manager.register_bank(bank);

        // Load the bank
        assert!(manager.load_bank("test_bank"));
        assert!(manager.is_bank_loaded("test_bank"));
        assert_eq!(manager.loaded_banks().len(), 1);

        // Check stats
        let stats = manager.get_stats();
        assert_eq!(stats.loaded_bank_count, 1);
        assert_eq!(stats.total_bank_count, 1);
        assert!(stats.resident_bytes > 0);

        // Unload the bank
        assert!(manager.unload_bank("test_bank"));
        assert!(!manager.is_bank_loaded("test_bank"));
        assert_eq!(manager.loaded_banks().len(), 0);
    }

    #[test]
    fn test_memory_manager_lru_unload() {
        let mut manager = MemoryBudgetManager::new(MemoryBudgetConfig {
            max_resident_bytes: 25 * 1024 * 1024, // 25MB - enough for 2 banks
            min_resident_time_ms: 0,              // Allow immediate unload
            ..Default::default()
        });

        // Register 3 banks of 10MB each
        for i in 0..3 {
            let bank = SoundBank {
                bank_id: format!("bank_{}", i),
                name: format!("Bank {}", i),
                estimated_size_bytes: 10 * 1024 * 1024,
                priority: LoadPriority::Normal,
                sound_ids: vec![],
                is_loaded: false,
                actual_size_bytes: 0,
                last_used: None,
            };
            manager.register_bank(bank);
        }

        // Load first two banks
        assert!(manager.load_bank("bank_0"));
        assert!(manager.load_bank("bank_1"));
        assert_eq!(manager.loaded_banks().len(), 2);

        // Loading third should trigger LRU unload of bank_0
        assert!(manager.load_bank("bank_2"));
        assert!(!manager.is_bank_loaded("bank_0")); // Unloaded (oldest)
        assert!(manager.is_bank_loaded("bank_1"));
        assert!(manager.is_bank_loaded("bank_2"));
    }

    #[test]
    fn test_critical_bank_protection() {
        let mut manager = MemoryBudgetManager::new(MemoryBudgetConfig::default());

        let bank = SoundBank {
            bank_id: "critical_bank".to_string(),
            name: "Critical Bank".to_string(),
            estimated_size_bytes: 10 * 1024 * 1024,
            priority: LoadPriority::Critical,
            sound_ids: vec![],
            is_loaded: false,
            actual_size_bytes: 0,
            last_used: None,
        };
        manager.register_bank(bank);

        assert!(manager.load_bank("critical_bank"));
        assert!(!manager.unload_bank("critical_bank")); // Can't unload critical
        assert!(manager.is_bank_loaded("critical_bank"));
    }
}
