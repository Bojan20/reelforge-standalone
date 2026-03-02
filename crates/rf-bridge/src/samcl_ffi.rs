//! SAMCL: Spectral Allocation & Masking FFI Bridge
//!
//! Exposes SAMCL functions via C FFI. Uses the shared AUREXIS ENGINE global
//! from aurexis_ffi.rs since SpectralAllocator lives inside AurexisEngine.

use std::ffi::{CString, c_char};
use std::ptr;

use crate::aurexis_ffi::ENGINE;
use rf_aurexis::spectral::{SpectralAllocator, SpectralRole};

// ═══════════════════════════════════════════════════════════════════════════════
// VOICE SPECTRAL ASSIGNMENT
// ═══════════════════════════════════════════════════════════════════════════════

/// Assign a spectral role to a voice. Returns 1 on success.
#[unsafe(no_mangle)]
pub extern "C" fn samcl_assign_role(
    voice_id: u32,
    role_index: u8,
    priority: i32,
    harmonic_layers: u32,
) -> i32 {
    let role = match SpectralRole::from_index(role_index) {
        Some(r) => r,
        None => return 0,
    };
    if let Some(ref mut engine) = *ENGINE.write() {
        return if engine.spectral_allocator_mut().assign_role(
            voice_id,
            role,
            priority,
            harmonic_layers,
        ) {
            1
        } else {
            0
        };
    }
    0
}

/// Remove a voice from spectral tracking. Returns 1 on success.
#[unsafe(no_mangle)]
pub extern "C" fn samcl_remove_voice(voice_id: u32) -> i32 {
    if let Some(ref mut engine) = *ENGINE.write() {
        return if engine.spectral_allocator_mut().remove_voice(voice_id) {
            1
        } else {
            0
        };
    }
    0
}

/// Clear all spectral voice assignments. Returns 1 on success.
#[unsafe(no_mangle)]
pub extern "C" fn samcl_clear() -> i32 {
    if let Some(ref mut engine) = *ENGINE.write() {
        engine.spectral_allocator_mut().clear();
        return 1;
    }
    0
}

/// Compute spectral allocation and masking. Returns 1 on success.
#[unsafe(no_mangle)]
pub extern "C" fn samcl_compute() -> i32 {
    if let Some(ref mut engine) = *ENGINE.write() {
        engine.spectral_allocator_mut().compute();
        return 1;
    }
    0
}

// ═══════════════════════════════════════════════════════════════════════════════
// SPECTRAL QUERIES
// ═══════════════════════════════════════════════════════════════════════════════

/// Get SCI_ADV value from last computation.
#[unsafe(no_mangle)]
pub extern "C" fn samcl_get_sci_adv() -> f64 {
    if let Some(ref engine) = *ENGINE.read() {
        return engine.spectral_allocator().last_output().sci_adv;
    }
    0.0
}

/// Get collision count from last computation.
#[unsafe(no_mangle)]
pub extern "C" fn samcl_get_collision_count() -> u32 {
    if let Some(ref engine) = *ENGINE.read() {
        return engine.spectral_allocator().last_output().collision_count;
    }
    0
}

/// Get slot shift count from last computation.
#[unsafe(no_mangle)]
pub extern "C" fn samcl_get_slot_shifts() -> u32 {
    if let Some(ref engine) = *ENGINE.read() {
        return engine.spectral_allocator().last_output().slot_shifts;
    }
    0
}

/// Check if aggressive carve is active.
#[unsafe(no_mangle)]
pub extern "C" fn samcl_is_aggressive_carve() -> i32 {
    if let Some(ref engine) = *ENGINE.read() {
        return if engine
            .spectral_allocator()
            .last_output()
            .aggressive_carve_active
        {
            1
        } else {
            0
        };
    }
    0
}

/// Get voice count in spectral allocator.
#[unsafe(no_mangle)]
pub extern "C" fn samcl_voice_count() -> u32 {
    if let Some(ref engine) = *ENGINE.read() {
        return engine.spectral_allocator().voice_count() as u32;
    }
    0
}

/// Get band density for a specific role (0-9).
#[unsafe(no_mangle)]
pub extern "C" fn samcl_band_density(role_index: u8) -> u32 {
    if role_index > 9 {
        return 0;
    }
    if let Some(ref engine) = *ENGINE.read() {
        return engine.spectral_allocator().last_output().band_density[role_index as usize];
    }
    0
}

/// Get all band densities (10 values). Caller provides buffer.
#[unsafe(no_mangle)]
pub extern "C" fn samcl_all_band_densities(out_densities: *mut u32) -> i32 {
    if out_densities.is_null() {
        return 0;
    }
    if let Some(ref engine) = *ENGINE.read() {
        let densities = &engine.spectral_allocator().last_output().band_density;
        unsafe {
            for i in 0..10 {
                *out_densities.add(i) = densities[i];
            }
        }
        return 1;
    }
    0
}

// ═══════════════════════════════════════════════════════════════════════════════
// SPECTRAL ROLE INFO
// ═══════════════════════════════════════════════════════════════════════════════

/// Get spectral role count (always 10).
#[unsafe(no_mangle)]
pub extern "C" fn samcl_role_count() -> u32 {
    SpectralRole::COUNT as u32
}

/// Get spectral role name. Caller must free with samcl_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn samcl_role_name(role_index: u8) -> *mut c_char {
    let role = match SpectralRole::from_index(role_index) {
        Some(r) => r,
        None => return ptr::null_mut(),
    };
    if let Ok(s) = CString::new(role.name()) {
        return s.into_raw();
    }
    ptr::null_mut()
}

/// Get spectral role frequency band (low_hz, high_hz).
#[unsafe(no_mangle)]
pub extern "C" fn samcl_role_band(
    role_index: u8,
    out_low_hz: *mut f64,
    out_high_hz: *mut f64,
) -> i32 {
    if out_low_hz.is_null() || out_high_hz.is_null() {
        return 0;
    }
    let role = match SpectralRole::from_index(role_index) {
        Some(r) => r,
        None => return 0,
    };
    let band = role.band();
    unsafe {
        *out_low_hz = band.low_hz;
        *out_high_hz = band.high_hz;
    }
    1
}

/// Get harmonic density limit for a spectral role.
#[unsafe(no_mangle)]
pub extern "C" fn samcl_harmonic_density_limit(role_index: u8) -> u32 {
    match SpectralRole::from_index(role_index) {
        Some(r) => r.harmonic_density_limit(),
        None => 0,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BAKE OUTPUT (SAMCL-12)
// ═══════════════════════════════════════════════════════════════════════════════

/// Get band config JSON. Caller must free with samcl_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn samcl_band_config_json() -> *mut c_char {
    if let Ok(json) = SpectralAllocator::band_config_json() {
        if let Ok(s) = CString::new(json) {
            return s.into_raw();
        }
    }
    ptr::null_mut()
}

/// Get role assignment JSON. Caller must free with samcl_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn samcl_role_assignment_json() -> *mut c_char {
    if let Some(ref engine) = *ENGINE.read() {
        if let Ok(json) = engine.spectral_allocator().role_assignment_json() {
            if let Ok(s) = CString::new(json) {
                return s.into_raw();
            }
        }
    }
    ptr::null_mut()
}

/// Get collision rules JSON. Caller must free with samcl_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn samcl_collision_rules_json() -> *mut c_char {
    if let Ok(json) = SpectralAllocator::collision_rules_json() {
        if let Ok(s) = CString::new(json) {
            return s.into_raw();
        }
    }
    ptr::null_mut()
}

/// Get shift curves JSON. Caller must free with samcl_free_string.
#[unsafe(no_mangle)]
pub extern "C" fn samcl_shift_curves_json() -> *mut c_char {
    if let Some(ref engine) = *ENGINE.read() {
        if let Ok(json) = engine.spectral_allocator().shift_curves_json() {
            if let Ok(s) = CString::new(json) {
                return s.into_raw();
            }
        }
    }
    ptr::null_mut()
}

// ═══════════════════════════════════════════════════════════════════════════════
// MEMORY MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════════

/// Free a string returned by samcl_* functions.
#[unsafe(no_mangle)]
pub extern "C" fn samcl_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            drop(CString::from_raw(ptr));
        }
    }
}
