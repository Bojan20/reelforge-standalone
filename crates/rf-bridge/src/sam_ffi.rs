//! SAM: Smart Authoring Mode FFI Bridge
//!
//! Exposes SmartAuthoringEngine via C FFI. Single global instance.

use std::ffi::{c_char, CString};
use std::ptr;

use once_cell::sync::Lazy;
use parking_lot::RwLock;

use rf_aurexis::sam::engine::{SmartAuthoringEngine, AuthoringMode, WizardStep};
use rf_aurexis::sam::archetypes::{SlotArchetype, MarketTarget};
use rf_aurexis::sam::controls::SmartControl;

// ═══════════════════════════════════════════════════════════════════════════════
// GLOBAL STATE
// ═══════════════════════════════════════════════════════════════════════════════

static SAM: Lazy<RwLock<SmartAuthoringEngine>> = Lazy::new(|| RwLock::new(SmartAuthoringEngine::new()));

// ═══════════════════════════════════════════════════════════════════════════════
// LIFECYCLE
// ═══════════════════════════════════════════════════════════════════════════════

/// Reset SAM to default state.
#[unsafe(no_mangle)]
pub extern "C" fn sam_reset() -> i32 {
    SAM.write().reset();
    1
}

// ═══════════════════════════════════════════════════════════════════════════════
// MODE
// ═══════════════════════════════════════════════════════════════════════════════

/// Get current mode: 0=Smart, 1=Advanced, 2=Debug.
#[unsafe(no_mangle)]
pub extern "C" fn sam_mode() -> i32 {
    SAM.read().mode() as i32
}

/// Set mode: 0=Smart, 1=Advanced, 2=Debug.
#[unsafe(no_mangle)]
pub extern "C" fn sam_set_mode(mode_index: u8) -> i32 {
    match AuthoringMode::from_index(mode_index) {
        Some(mode) => { SAM.write().set_mode(mode); 1 }
        None => 0,
    }
}

/// Get mode name. Caller must free with sam_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn sam_mode_name() -> *mut c_char {
    let name = SAM.read().mode().name();
    if let Ok(s) = CString::new(name) { s.into_raw() } else { ptr::null_mut() }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WIZARD
// ═══════════════════════════════════════════════════════════════════════════════

/// Get current wizard step index (0–8).
#[unsafe(no_mangle)]
pub extern "C" fn sam_wizard_step() -> u8 {
    SAM.read().wizard_step().index()
}

/// Set wizard step by index (0–8).
#[unsafe(no_mangle)]
pub extern "C" fn sam_set_wizard_step(step_index: u8) -> i32 {
    match WizardStep::from_index(step_index) {
        Some(step) => { SAM.write().set_wizard_step(step); 1 }
        None => 0,
    }
}

/// Advance to next wizard step. Returns 1 if advanced, 0 if at end.
#[unsafe(no_mangle)]
pub extern "C" fn sam_wizard_next() -> i32 {
    if SAM.write().wizard_next() { 1 } else { 0 }
}

/// Go to previous wizard step. Returns 1 if went back, 0 if at start.
#[unsafe(no_mangle)]
pub extern "C" fn sam_wizard_prev() -> i32 {
    if SAM.write().wizard_prev() { 1 } else { 0 }
}

/// Get wizard progress (0.0–1.0).
#[unsafe(no_mangle)]
pub extern "C" fn sam_wizard_progress() -> f64 {
    SAM.read().wizard_progress()
}

/// Get wizard step count (always 9).
#[unsafe(no_mangle)]
pub extern "C" fn sam_wizard_step_count() -> u32 {
    WizardStep::COUNT as u32
}

/// Get wizard step name. Caller must free with sam_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn sam_wizard_step_name(step_index: u8) -> *mut c_char {
    match WizardStep::from_index(step_index) {
        Some(step) => {
            if let Ok(s) = CString::new(step.name()) { s.into_raw() } else { ptr::null_mut() }
        }
        None => ptr::null_mut(),
    }
}

/// Get wizard step description. Caller must free with sam_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn sam_wizard_step_description(step_index: u8) -> *mut c_char {
    match WizardStep::from_index(step_index) {
        Some(step) => {
            if let Ok(s) = CString::new(step.description()) { s.into_raw() } else { ptr::null_mut() }
        }
        None => ptr::null_mut(),
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ARCHETYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Get archetype count (always 8).
#[unsafe(no_mangle)]
pub extern "C" fn sam_archetype_count() -> u32 {
    SlotArchetype::COUNT as u32
}

/// Get archetype name by index. Caller must free with sam_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn sam_archetype_name(index: u8) -> *mut c_char {
    match SlotArchetype::from_index(index) {
        Some(a) => {
            if let Ok(s) = CString::new(a.name()) { s.into_raw() } else { ptr::null_mut() }
        }
        None => ptr::null_mut(),
    }
}

/// Get archetype description by index. Caller must free with sam_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn sam_archetype_description(index: u8) -> *mut c_char {
    match SlotArchetype::from_index(index) {
        Some(a) => {
            if let Ok(s) = CString::new(a.description()) { s.into_raw() } else { ptr::null_mut() }
        }
        None => ptr::null_mut(),
    }
}

/// Select archetype (applies defaults). Returns 1 on success.
#[unsafe(no_mangle)]
pub extern "C" fn sam_select_archetype(index: u8) -> i32 {
    match SlotArchetype::from_index(index) {
        Some(a) => { SAM.write().select_archetype(a); 1 }
        None => 0,
    }
}

/// Get selected archetype index. Returns -1 if none.
#[unsafe(no_mangle)]
pub extern "C" fn sam_selected_archetype() -> i32 {
    SAM.read().archetype().map_or(-1, |a| a as i32)
}

// ═══════════════════════════════════════════════════════════════════════════════
// VOLATILITY & MARKET
// ═══════════════════════════════════════════════════════════════════════════════

/// Get current volatility.
#[unsafe(no_mangle)]
pub extern "C" fn sam_volatility() -> f64 {
    SAM.read().state().volatility
}

/// Set volatility (clamped to archetype range if selected).
#[unsafe(no_mangle)]
pub extern "C" fn sam_set_volatility(value: f64) -> i32 {
    SAM.write().set_volatility(value);
    1
}

/// Get archetype volatility range (min, default, max).
#[unsafe(no_mangle)]
pub extern "C" fn sam_volatility_min() -> f64 {
    SAM.read().archetype()
        .map_or(0.0, |a| a.defaults().volatility.min)
}

#[unsafe(no_mangle)]
pub extern "C" fn sam_volatility_max() -> f64 {
    SAM.read().archetype()
        .map_or(1.0, |a| a.defaults().volatility.max)
}

#[unsafe(no_mangle)]
pub extern "C" fn sam_volatility_default() -> f64 {
    SAM.read().archetype()
        .map_or(0.5, |a| a.defaults().volatility.default)
}

/// Get market: 0=Casual, 1=Standard, 2=Premium.
#[unsafe(no_mangle)]
pub extern "C" fn sam_market() -> i32 {
    SAM.read().state().market as i32
}

/// Set market: 0=Casual, 1=Standard, 2=Premium.
#[unsafe(no_mangle)]
pub extern "C" fn sam_set_market(index: u8) -> i32 {
    match MarketTarget::from_index(index) {
        Some(m) => { SAM.write().set_market(m); 1 }
        None => 0,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SMART CONTROLS
// ═══════════════════════════════════════════════════════════════════════════════

/// Get smart control count (always 11).
#[unsafe(no_mangle)]
pub extern "C" fn sam_control_count() -> u32 {
    SmartControl::COUNT as u32
}

/// Get smart control value (0.0–1.0). Returns -1.0 if invalid index.
#[unsafe(no_mangle)]
pub extern "C" fn sam_control_value(control_index: u8) -> f64 {
    match SmartControl::from_index(control_index) {
        Some(c) => SAM.read().get_control(c),
        None => -1.0,
    }
}

/// Set smart control value (0.0–1.0).
#[unsafe(no_mangle)]
pub extern "C" fn sam_set_control_value(control_index: u8, value: f64) -> i32 {
    match SmartControl::from_index(control_index) {
        Some(c) => { SAM.write().set_control(c, value); 1 }
        None => 0,
    }
}

/// Get smart control name. Caller must free with sam_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn sam_control_name(control_index: u8) -> *mut c_char {
    match SmartControl::from_index(control_index) {
        Some(c) => {
            if let Ok(s) = CString::new(c.name()) { s.into_raw() } else { ptr::null_mut() }
        }
        None => ptr::null_mut(),
    }
}

/// Get smart control group: 0=Energy, 1=Clarity, 2=Stability. Returns -1 if invalid.
#[unsafe(no_mangle)]
pub extern "C" fn sam_control_group(control_index: u8) -> i32 {
    match SmartControl::from_index(control_index) {
        Some(c) => c.group() as i32,
        None => -1,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUTO-CONFIGURE
// ═══════════════════════════════════════════════════════════════════════════════

/// Run auto-configuration (applies archetype + volatility + market to controls).
#[unsafe(no_mangle)]
pub extern "C" fn sam_auto_configure() -> i32 {
    SAM.write().auto_configure();
    1
}

/// Check if auto-configured.
#[unsafe(no_mangle)]
pub extern "C" fn sam_is_auto_configured() -> i32 {
    if SAM.read().state().auto_configured { 1 } else { 0 }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GDD & AIL & CERTIFICATION STATUS
// ═══════════════════════════════════════════════════════════════════════════════

/// Set GDD imported flag.
#[unsafe(no_mangle)]
pub extern "C" fn sam_set_gdd_imported(imported: i32) -> i32 {
    SAM.write().set_gdd_imported(imported != 0);
    1
}

/// Check if GDD imported.
#[unsafe(no_mangle)]
pub extern "C" fn sam_gdd_imported() -> i32 {
    if SAM.read().state().gdd_imported { 1 } else { 0 }
}

/// Set AIL result.
#[unsafe(no_mangle)]
pub extern "C" fn sam_set_ail_result(passed: i32, score: f64) -> i32 {
    SAM.write().set_ail_result(passed != 0, score);
    1
}

/// Check if AIL passed.
#[unsafe(no_mangle)]
pub extern "C" fn sam_ail_passed() -> i32 {
    if SAM.read().state().ail_passed { 1 } else { 0 }
}

/// Get AIL score from SAM state.
#[unsafe(no_mangle)]
pub extern "C" fn sam_ail_score() -> f64 {
    SAM.read().state().ail_score
}

/// Set certification status.
#[unsafe(no_mangle)]
pub extern "C" fn sam_set_certified(certified: i32) -> i32 {
    SAM.write().set_certified(certified != 0);
    1
}

/// Check if certified.
#[unsafe(no_mangle)]
pub extern "C" fn sam_is_certified() -> i32 {
    if SAM.read().state().certified { 1 } else { 0 }
}

// ═══════════════════════════════════════════════════════════════════════════════
// JSON OUTPUT
// ═══════════════════════════════════════════════════════════════════════════════

/// Get full SAM state as JSON. Caller must free with sam_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn sam_state_json() -> *mut c_char {
    if let Ok(json) = SAM.read().state_json() {
        if let Ok(s) = CString::new(json) {
            return s.into_raw();
        }
    }
    ptr::null_mut()
}

// ═══════════════════════════════════════════════════════════════════════════════
// MEMORY MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════════

/// Free a string returned by sam_* functions.
#[unsafe(no_mangle)]
pub extern "C" fn sam_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            drop(CString::from_raw(ptr));
        }
    }
}
