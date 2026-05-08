//! SOFA / AES69 HRTF file I/O
//!
//! This module provides loaders for standardized HRTF databases.
//!
//! ## Supported formats
//!
//! | Format | Extension | Status | Notes |
//! |--------|-----------|--------|-------|
//! | FluxForge HRTF | `.ffhrtf` (JSON+WAV) | **Full** | Native interchange format |
//! | SOFA (SimpleFreeFieldHRIR) | `.sofa` | **Stub** | HDF5 backend not linked (see below) |
//! | CIPIC (interleaved float) | `.mat` | **Planned** | Requires v5 MAT parser |
//!
//! ## SOFA / HDF5 note
//!
//! Full SOFA support needs an HDF5 library binding (`hdf5` or `hdf5-sys`).
//! Adding it pulls in a C library dependency and complicates cross-compilation
//! (iOS, WebAssembly).  For that reason the native `.ffhrtf` format is the
//! recommended path for shipping content.  If you need to convert an existing
//! SOFA file, use the Python helper in `tools/convert_sofa.py` (NumPy + h5py)
//! to emit `.ffhrtf`.
//!
//! ## FluxForge HRTF format (`.ffhrtf`)
//!
//! A ZIP-like bundle containing:
//! * `manifest.json` — metadata (sample rate, grid resolution, subject info)
//! * `hrir_left.raw` — all left-ear HRIRs concatenated (f32 little-endian)
//! * `hrir_right.raw` — all right-ear HRIRs concatenated (f32 little-endian)
//! * `positions.json` — array of `(azimuth, elevation)` in degrees, one per HRIR

use super::{HrirPair, HrtfDatabase};
use serde::{Deserialize, Serialize};

use std::path::Path;

// ═══════════════════════════════════════════════════════════════════════════
// FLUXFORGE HRTF MANIFEST
// ═══════════════════════════════════════════════════════════════════════════

/// Manifest for a `.ffhrtf` bundle.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HrtfManifest {
    /// Format version
    pub version: String,
    /// Sample rate in Hz
    pub sample_rate: u32,
    /// HRIR length in samples
    pub filter_length: usize,
    /// Azimuth grid resolution in degrees
    pub azimuth_resolution: f32,
    /// Elevation grid resolution in degrees
    pub elevation_resolution: f32,
    /// Subject identifier
    pub subject_id: String,
    /// Number of measurements in the bundle
    pub measurement_count: usize,
    /// Optional anthropometric data
    pub anthropometry: Option<super::AnthropometricProfile>,
}

impl Default for HrtfManifest {
    fn default() -> Self {
        Self {
            version: "1.0.0".into(),
            sample_rate: 48000,
            filter_length: 128,
            azimuth_resolution: 5.0,
            elevation_resolution: 5.0,
            subject_id: "unknown".into(),
            measurement_count: 0,
            anthropometry: None,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// IN-MEMORY HRIR DATASET
// ═══════════════════════════════════════════════════════════════════════════

/// A flat collection of HRIR measurements ready to be inserted into an
/// `HrtfDatabase`.
#[derive(Debug, Clone)]
pub struct HrirDataset {
    /// Sample rate
    pub sample_rate: u32,
    /// HRIR length
    pub filter_length: usize,
    /// Measurements: (azimuth_deg, elevation_deg, left, right)
    pub measurements: Vec<(f32, f32, Vec<f32>, Vec<f32>)>,
}

impl HrirDataset {
    /// Build an `HrtfDatabase` from this dataset.
    pub fn into_database(self) -> HrtfDatabase {
        let mut db = HrtfDatabase::new(self.sample_rate);
        for (az, el, left, right) in self.measurements {
            let pair = HrirPair {
                left,
                right,
                itd_samples: 0.0,
            };
            db.add_hrir(az, el, pair);
        }
        db
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// FFHRTF LOADER / SAVER
// ═══════════════════════════════════════════════════════════════════════════

/// Load a `.ffhrtf` bundle from a directory (the directory contains the
/// manifest and raw files).
pub fn load_ffhrtf_dir<P: AsRef<Path>>(path: P) -> crate::error::SpatialResult<HrirDataset> {
    let path = path.as_ref();
    let manifest_path = path.join("manifest.json");
    let positions_path = path.join("positions.json");
    let left_path = path.join("hrir_left.raw");
    let right_path = path.join("hrir_right.raw");

    let manifest_json = std::fs::read_to_string(&manifest_path)?;
    let manifest: HrtfManifest = serde_json::from_str(&manifest_json)
        .map_err(|e| crate::error::SpatialError::SofaError(e.to_string()))?;

    let positions_json = std::fs::read_to_string(&positions_path)?;
    let positions: Vec<(f32, f32)> = serde_json::from_str(&positions_json)
        .map_err(|e| crate::error::SpatialError::SofaError(e.to_string()))?;

    let left_raw = std::fs::read(&left_path)?;
    let right_raw = std::fs::read(&right_path)?;

    // Decode f32 little-endian from raw bytes
    let left_samples = bytes_to_f32_vec(&left_raw);
    let right_samples = bytes_to_f32_vec(&right_raw);

    let n = positions.len();
    let fl = manifest.filter_length;

    if left_samples.len() != n * fl || right_samples.len() != n * fl {
        return Err(crate::error::SpatialError::ProcessingError(format!(
            "sample count mismatch: expected {}x{}={}, got left={} right={}",
            n,
            fl,
            n * fl,
            left_samples.len(),
            right_samples.len()
        )));
    }

    let mut measurements = Vec::with_capacity(n);
    for (i, &(az, el)) in positions.iter().enumerate() {
        let l = left_samples[i * fl..(i + 1) * fl].to_vec();
        let r = right_samples[i * fl..(i + 1) * fl].to_vec();
        measurements.push((az, el, l, r));
    }

    Ok(HrirDataset {
        sample_rate: manifest.sample_rate,
        filter_length: fl,
        measurements,
    })
}

/// Save a `.ffhrtf` bundle to a directory.
pub fn save_ffhrtf_dir<P: AsRef<Path>>(
    path: P,
    manifest: &HrtfManifest,
    dataset: &HrirDataset,
) -> crate::error::SpatialResult<()> {
    let path = path.as_ref();
    std::fs::create_dir_all(path)?;

    let mut manifest = manifest.clone();
    manifest.measurement_count = dataset.measurements.len();

    let manifest_json = serde_json::to_string_pretty(&manifest)
        .map_err(|e| crate::error::SpatialError::SofaError(e.to_string()))?;
    std::fs::write(path.join("manifest.json"), manifest_json)?;

    let positions: Vec<(f32, f32)> = dataset
        .measurements
        .iter()
        .map(|(az, el, _, _)| (*az, *el))
        .collect();
    let positions_json = serde_json::to_string_pretty(&positions)
        .map_err(|e| crate::error::SpatialError::SofaError(e.to_string()))?;
    std::fs::write(path.join("positions.json"), positions_json)?;

    let mut left_bytes = Vec::new();
    let mut right_bytes = Vec::new();
    for (_, _, l, r) in &dataset.measurements {
        for &s in l {
            left_bytes.extend_from_slice(&s.to_le_bytes());
        }
        for &s in r {
            right_bytes.extend_from_slice(&s.to_le_bytes());
        }
    }

    std::fs::write(path.join("hrir_left.raw"), left_bytes)?;
    std::fs::write(path.join("hrir_right.raw"), right_bytes)?;

    Ok(())
}

// ═══════════════════════════════════════════════════════════════════════════
// SOFA STUB
// ═══════════════════════════════════════════════════════════════════════════

/// Attempt to load a SOFA file.
///
/// Currently returns an error pointing users to the `.ffhrtf` conversion
/// workflow.  Full HDF5 support is gated behind the non-default `sofa-hdf5`
/// feature which links the system C HDF5 library.
pub fn load_sofa<P: AsRef<Path>>(_path: P) -> crate::error::SpatialResult<HrirDataset> {
    Err(crate::error::SpatialError::SofaError(
        "Native SOFA/HDF5 loading is not enabled in this build. \
         Convert the file to .ffhrtf format using tools/convert_sofa.py"
            .into(),
    ))
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════════

fn bytes_to_f32_vec(bytes: &[u8]) -> Vec<f32> {
    let mut vec = Vec::with_capacity(bytes.len() / 4);
    for chunk in bytes.chunks_exact(4) {
        let arr: [u8; 4] = chunk.try_into().unwrap();
        vec.push(f32::from_le_bytes(arr));
    }
    vec
}

// ═══════════════════════════════════════════════════════════════════════════
// CONVENIENCE: EXPORT EXISTING DATABASE TO FFHRTF
// ═══════════════════════════════════════════════════════════════════════════

/// Export an existing `HrtfDatabase` into an `HrirDataset` + manifest.
///
/// This is lossy: the ITD stored in each `HrirPair` is embedded into the
/// time-domain HRIR (it already is in our synthetic generator) so the
/// round-trip is stable.
pub fn export_database(
    db: &HrtfDatabase,
    subject_id: &str,
    anthropometry: Option<super::AnthropometricProfile>,
) -> (HrtfManifest, HrirDataset) {
    // We need to enumerate the database.  HrtfDatabase doesn't expose its
    // internal HashMap directly, so we iterate over a reasonable grid and
    // collect whatever is present.
    let mut measurements = Vec::new();

    // Try the standard 5° grid first
    for az in (-180..=175).step_by(5) {
        for el in (-40..=90).step_by(5) {
            if let Some(hrir) = db.get_hrir(az as f32, el as f32) {
                measurements.push((
                    az as f32,
                    el as f32,
                    hrir.left.clone(),
                    hrir.right.clone(),
                ));
            }
        }
    }

    let sample_rate = db.sample_rate();
    let filter_length = db.filter_length();

    let manifest = HrtfManifest {
        version: "1.0.0".into(),
        sample_rate,
        filter_length,
        azimuth_resolution: 5.0,
        elevation_resolution: 5.0,
        subject_id: subject_id.into(),
        measurement_count: measurements.len(),
        anthropometry,
    };

    let dataset = HrirDataset {
        sample_rate,
        filter_length,
        measurements,
    };

    (manifest, dataset)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::binaural::personalized::{personalize, AnthropometricProfile};

    #[test]
    fn test_roundtrip_ffhrtf() {
        let tmp = std::env::temp_dir().join("fluxforge_test_hrtf");
        let _ = std::fs::remove_dir_all(&tmp);

        // Generate a small database
        let db = personalize(AnthropometricProfile::default(), 48000);

        // Export
        let (manifest, dataset) = export_database(&db, "test_subject", None);
        assert_eq!(manifest.sample_rate, 48000);
        assert!(dataset.measurements.len() > 0);

        // Save
        save_ffhrtf_dir(&tmp, &manifest, &dataset).unwrap();

        // Load back
        let loaded = load_ffhrtf_dir(&tmp).unwrap();
        assert_eq!(loaded.sample_rate, 48000);
        assert_eq!(loaded.measurements.len(), dataset.measurements.len());

        // Verify first measurement matches
        let original_first = &dataset.measurements[0];
        let loaded_first = &loaded.measurements[0];
        assert_eq!(original_first.0, loaded_first.0); // azimuth
        assert_eq!(original_first.1, loaded_first.1); // elevation
        assert_eq!(original_first.2.len(), loaded_first.2.len());

        let max_diff: f32 = original_first
            .2
            .iter()
            .zip(loaded_first.2.iter())
            .map(|(a, b)| (a - b).abs())
            .fold(0.0f32, f32::max);
        assert!(max_diff < 1e-6, "round-trip max_diff too large: {max_diff}");

        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn test_sofa_stub_errors_gracefully() {
        let result = load_sofa("/dev/null/nonexistent.sofa");
        assert!(result.is_err());
        let msg = format!("{}", result.unwrap_err());
        assert!(msg.contains(".ffhrtf"), "error should mention .ffhrtf workaround");
    }
}
