//! Chain preset persistence — save/load `FullChainSnapshot` to disk
//! as named, tagged JSON files.
//!
//! Wave 2 Front 5. Front 3 ships built-in chain templates ("Modern Pop
//! Vocal", "Streaming Master"…); Wave 2 Front 3 captures live state
//! into `FullChainSnapshot`. This module turns those snapshots into
//! reusable presets the user owns: "My Vocal Master", "Drum Bus Glue
//! 2026". The store is a flat directory of JSON files — easy to back
//! up, easy to share between machines, no database lock-in.
//!
//! # Layout
//!
//! ```text
//! <preset_dir>/                        (default: ~/.fluxforge/chains/)
//! ├── my_vocal_master.json
//! ├── drum_bus_glue_2026.json
//! └── streaming_master_v2.json
//! ```
//!
//! Each file is a `ChainPreset` with metadata + the snapshot. Filename
//! is the slugified name; the in-file `name` field is the user-visible
//! original.
//!
//! # Versioning
//!
//! Files carry a `format_version` so future schema changes can be
//! migrated. Today's version is `1`.
//!
//! # Concurrency
//!
//! All operations are file-system synchronous. Concurrent writes to
//! the same name are last-writer-wins; the directory is not
//! intentionally hot.

use std::collections::BTreeSet;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

use super::chain_history::FullChainSnapshot;

const FORMAT_VERSION: u32 = 1;

/// Canonical mixing categories — UI uses these as a chip strip.
///
/// The category field is open: users can save a preset with any string,
/// but the chip strip shows these first so muscle memory works across
/// machines / migrations / shared libraries. `category_is_canonical`
/// surfaces this for UI styling.
pub const CANONICAL_CATEGORIES: &[&str] = &[
    "vocal",
    "drums",
    "bass",
    "guitar",
    "synth",
    "instrument",
    "bus",
    "fx",
    "mix",
    "mastering",
];

/// Returns true if `cat` matches a canonical mixing category
/// (case-insensitive, trimmed).
pub fn category_is_canonical(cat: &str) -> bool {
    let needle = cat.trim().to_lowercase();
    CANONICAL_CATEGORIES.iter().any(|c| **c == needle)
}

/// Normalise a category string for storage / matching: trim + lowercase.
/// Empty input returns `None` so callers can distinguish "no category".
pub fn normalise_category(raw: &str) -> Option<String> {
    let n = raw.trim().to_lowercase();
    if n.is_empty() { None } else { Some(n) }
}

// ─── Public types ────────────────────────────────────────────────────────────

/// One saved preset.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChainPreset {
    /// User-visible name (preserved exactly, including spaces/punctuation).
    pub name: String,
    /// Optional human description (a few sentences max — UI hint, not a doc).
    #[serde(default)]
    pub description: String,
    /// Single canonical mixing category (`vocal`, `drums`, `bass`, `bus`,
    /// `mix`, `mastering`, …). Stored as normalised lowercase. None when
    /// the user hasn't classified the preset (legacy presets land here).
    ///
    /// Distinct from `tags` (free-form, multi-valued). The category drives
    /// the top-level chip strip; tags drive the multi-select filter.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub category: Option<String>,
    /// User-defined tags ("vocal", "vintage", "podcast"…).
    #[serde(default)]
    pub tags: Vec<String>,
    /// Captured chain state.
    pub snapshot: FullChainSnapshot,
    /// Schema version. Incremented when on-disk format changes.
    #[serde(default = "default_format_version")]
    pub format_version: u32,
    /// Created at — Unix epoch ms.
    #[serde(default)]
    pub created_ms: u64,
    /// Updated at — Unix epoch ms.
    #[serde(default)]
    pub updated_ms: u64,
}

fn default_format_version() -> u32 {
    FORMAT_VERSION
}

impl ChainPreset {
    pub fn new(
        name: impl Into<String>,
        description: impl Into<String>,
        tags: Vec<String>,
        snapshot: FullChainSnapshot,
    ) -> Self {
        Self::with_category(name, description, None, tags, snapshot)
    }

    /// Construct with an explicit category. Empty/whitespace `category`
    /// is normalised to `None`. Lowercased on the way in.
    pub fn with_category(
        name: impl Into<String>,
        description: impl Into<String>,
        category: Option<String>,
        tags: Vec<String>,
        snapshot: FullChainSnapshot,
    ) -> Self {
        let now = now_ms();
        let normalised_category = category.as_deref().and_then(normalise_category);
        Self {
            name: name.into(),
            description: description.into(),
            category: normalised_category,
            tags,
            snapshot,
            format_version: FORMAT_VERSION,
            created_ms: now,
            updated_ms: now,
        }
    }
}

/// Light metadata projection for browsing the library — `list_presets`
/// returns these so a UI doesn't pay to deserialise every snapshot.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChainPresetMeta {
    pub name: String,
    pub description: String,
    /// Mirrors `ChainPreset.category` for cheap chip-bar filtering.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub category: Option<String>,
    pub tags: Vec<String>,
    pub created_ms: u64,
    pub updated_ms: u64,
    pub slot_count: usize,
    /// On-disk filename (slug + ".json"), useful for explicit deletes.
    pub filename: String,
}

/// Structured filter spec — strictly more expressive than a raw
/// substring search. Each axis is independently optional; the empty
/// spec matches every preset.
///
/// Combination semantics: `AND` across axes (a preset must satisfy
/// every populated axis). Within `tags_any` it is `OR`; within
/// `tags_all` it is `AND`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct PresetFilterSpec {
    /// If set, only presets whose `category` equals (case-insensitive)
    /// one of these are returned. `None` ⇒ no category restriction.
    /// Empty `Vec` is treated as no restriction (forgiving for FFI
    /// callers that always pass an array).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub categories: Option<Vec<String>>,

    /// At least one of these tags must appear on the preset (case-
    /// insensitive). `None` / empty ⇒ skip this axis.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tags_any: Option<Vec<String>>,

    /// All of these tags must appear on the preset (case-insensitive).
    /// `None` / empty ⇒ skip this axis.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tags_all: Option<Vec<String>>,

    /// Substring query across name + description + tags (case-
    /// insensitive). Empty / whitespace ⇒ skip this axis.
    #[serde(default)]
    pub query: String,

    /// If true, only return presets *without* a category.
    /// Mutually exclusive with `categories` — if both are supplied,
    /// `categories` wins. Useful for "show un-classified" toggle.
    #[serde(default)]
    pub uncategorised_only: bool,
}

impl PresetFilterSpec {
    fn is_empty(&self) -> bool {
        let cats_empty = self
            .categories
            .as_ref()
            .map(|v| v.is_empty())
            .unwrap_or(true);
        let any_empty = self
            .tags_any
            .as_ref()
            .map(|v| v.is_empty())
            .unwrap_or(true);
        let all_empty = self
            .tags_all
            .as_ref()
            .map(|v| v.is_empty())
            .unwrap_or(true);
        cats_empty
            && any_empty
            && all_empty
            && self.query.trim().is_empty()
            && !self.uncategorised_only
    }
}

// ─── Errors ──────────────────────────────────────────────────────────────────

#[derive(Debug, thiserror::Error)]
pub enum PresetError {
    #[error("preset name must be non-empty after sanitisation")]
    EmptyName,

    #[error("preset name '{0}' contains only invalid characters")]
    InvalidName(String),

    #[error("preset '{0}' not found")]
    NotFound(String),

    #[error("io error: {0}")]
    Io(#[from] io::Error),

    #[error("serialisation error: {0}")]
    Serde(#[from] serde_json::Error),

    #[error("preset directory could not be resolved (no $HOME?)")]
    NoPresetDir,

    #[error("unsupported format version {found} (this build understands {supported})")]
    UnsupportedVersion { found: u32, supported: u32 },
}

pub type PresetResult<T> = Result<T, PresetError>;

// ─── Path resolution ─────────────────────────────────────────────────────────

/// Resolve the active preset directory.
///
/// Order of precedence:
/// 1. Argument (`override_dir`) if supplied
/// 2. Env var `RF_CHAIN_PRESET_DIR`
/// 3. `$HOME/.fluxforge/chains`
///
/// Creates the directory if missing. Returns `Err(NoPresetDir)` only
/// when no candidate is resolvable (rare: no HOME and no override).
pub fn resolve_preset_dir(override_dir: Option<&Path>) -> PresetResult<PathBuf> {
    let dir = if let Some(p) = override_dir {
        p.to_path_buf()
    } else if let Ok(env) = std::env::var("RF_CHAIN_PRESET_DIR") {
        if env.trim().is_empty() {
            return Err(PresetError::NoPresetDir);
        }
        PathBuf::from(env)
    } else {
        match home_dir() {
            Some(home) => home.join(".fluxforge").join("chains"),
            None => return Err(PresetError::NoPresetDir),
        }
    };
    fs::create_dir_all(&dir)?;
    Ok(dir)
}

/// Home directory resolver — `$HOME` on Unix, `%USERPROFILE%` on Windows.
fn home_dir() -> Option<PathBuf> {
    if let Ok(h) = std::env::var("HOME") {
        if !h.trim().is_empty() {
            return Some(PathBuf::from(h));
        }
    }
    if let Ok(h) = std::env::var("USERPROFILE") {
        if !h.trim().is_empty() {
            return Some(PathBuf::from(h));
        }
    }
    None
}

// ─── Slugification ───────────────────────────────────────────────────────────

/// Convert a user-visible preset name into a safe filesystem slug.
///
/// Rules: lowercase, ASCII letters/digits kept, anything else becomes
/// `_`, leading/trailing `_` trimmed, runs of `_` collapsed, length
/// capped at 80 chars. Returns `Err(InvalidName)` when nothing usable
/// remains (e.g. all emojis).
pub fn slugify(name: &str) -> PresetResult<String> {
    if name.trim().is_empty() {
        return Err(PresetError::EmptyName);
    }
    let mut out = String::with_capacity(name.len());
    let mut last_was_underscore = false;
    for ch in name.chars() {
        if ch.is_ascii_alphanumeric() {
            for lc in ch.to_lowercase() {
                out.push(lc);
            }
            last_was_underscore = false;
        } else if !last_was_underscore {
            out.push('_');
            last_was_underscore = true;
        }
    }
    let trimmed = out.trim_matches('_').to_string();
    if trimmed.is_empty() {
        return Err(PresetError::InvalidName(name.to_string()));
    }
    let truncated: String = trimmed.chars().take(80).collect();
    Ok(truncated)
}

/// Compose the JSON filename for a slug.
fn filename_for(slug: &str) -> String {
    format!("{}.json", slug)
}

fn path_for(dir: &Path, slug: &str) -> PathBuf {
    dir.join(filename_for(slug))
}

// ─── Public store API ────────────────────────────────────────────────────────

/// Save a preset to disk. Existing presets with the same slug are
/// overwritten (`updated_ms` refreshed, `created_ms` preserved).
pub fn save_preset(dir: &Path, preset: &ChainPreset) -> PresetResult<PathBuf> {
    let slug = slugify(&preset.name)?;
    let path = path_for(dir, &slug);

    // Preserve created_ms if file exists; refresh updated_ms.
    let prior_created_ms = if path.exists() {
        match read_preset_file(&path) {
            Ok(prior) => prior.created_ms,
            Err(_) => preset.created_ms,
        }
    } else {
        preset.created_ms
    };

    let mut to_write = preset.clone();
    to_write.format_version = FORMAT_VERSION;
    to_write.created_ms = if prior_created_ms > 0 {
        prior_created_ms
    } else {
        now_ms()
    };
    to_write.updated_ms = now_ms();

    let json = serde_json::to_string_pretty(&to_write)?;
    // Atomic write via rename of a tmp file in the same directory.
    let tmp = dir.join(format!(".{}.tmp", slug));
    fs::write(&tmp, json)?;
    fs::rename(&tmp, &path)?;
    Ok(path)
}

/// Load a preset by user-visible name (slugified internally).
pub fn load_preset(dir: &Path, name: &str) -> PresetResult<ChainPreset> {
    let slug = slugify(name)?;
    let path = path_for(dir, &slug);
    if !path.exists() {
        return Err(PresetError::NotFound(name.to_string()));
    }
    let preset = read_preset_file(&path)?;
    if preset.format_version > FORMAT_VERSION {
        return Err(PresetError::UnsupportedVersion {
            found: preset.format_version,
            supported: FORMAT_VERSION,
        });
    }
    Ok(preset)
}

fn read_preset_file(path: &Path) -> PresetResult<ChainPreset> {
    let bytes = fs::read(path)?;
    let preset: ChainPreset = serde_json::from_slice(&bytes)?;
    Ok(preset)
}

/// Delete a preset by user-visible name. Returns `Ok(true)` if a file
/// was removed, `Ok(false)` if no file existed (idempotent delete).
pub fn delete_preset(dir: &Path, name: &str) -> PresetResult<bool> {
    let slug = slugify(name)?;
    let path = path_for(dir, &slug);
    if !path.exists() {
        return Ok(false);
    }
    fs::remove_file(&path)?;
    Ok(true)
}

/// List all presets in `dir`, sorted by `updated_ms` descending
/// (most recently saved first). Skips files that fail to parse —
/// they're surfaced via a warn log but don't fail the listing.
pub fn list_presets(dir: &Path) -> PresetResult<Vec<ChainPresetMeta>> {
    if !dir.exists() {
        return Ok(Vec::new());
    }
    let mut metas = Vec::new();
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        if path.extension().and_then(|s| s.to_str()) != Some("json") {
            continue;
        }
        // Skip atomic-write tmp files (start with '.').
        if path
            .file_name()
            .and_then(|s| s.to_str())
            .is_some_and(|s| s.starts_with('.'))
        {
            continue;
        }
        match read_preset_file(&path) {
            Ok(preset) => {
                let filename = path
                    .file_name()
                    .and_then(|s| s.to_str())
                    .unwrap_or("")
                    .to_string();
                metas.push(ChainPresetMeta {
                    name: preset.name,
                    description: preset.description,
                    category: preset.category,
                    tags: preset.tags,
                    created_ms: preset.created_ms,
                    updated_ms: preset.updated_ms,
                    slot_count: preset.snapshot.slots.len(),
                    filename,
                });
            }
            Err(e) => {
                log::warn!(
                    "[chain_preset] skipping unreadable preset {:?}: {}",
                    path,
                    e
                );
            }
        }
    }
    metas.sort_by(|a, b| b.updated_ms.cmp(&a.updated_ms));
    Ok(metas)
}

/// Filter `list_presets` by case-insensitive substring match against
/// name/description/tags. Empty query returns the full list.
pub fn search_presets(dir: &Path, query: &str) -> PresetResult<Vec<ChainPresetMeta>> {
    let q = query.trim().to_lowercase();
    let all = list_presets(dir)?;
    if q.is_empty() {
        return Ok(all);
    }
    Ok(all
        .into_iter()
        .filter(|m| meta_matches_query(m, &q))
        .collect())
}

fn meta_matches_query(m: &ChainPresetMeta, q_lower: &str) -> bool {
    if q_lower.is_empty() {
        return true;
    }
    if m.name.to_lowercase().contains(q_lower)
        || m.description.to_lowercase().contains(q_lower)
    {
        return true;
    }
    if m.tags.iter().any(|t| t.to_lowercase().contains(q_lower)) {
        return true;
    }
    if let Some(cat) = m.category.as_deref()
        && cat.to_lowercase().contains(q_lower)
    {
        return true;
    }
    false
}

/// Apply a structured filter to the library. Empty `spec` returns the
/// full list (sorted by `updated_ms` descending — same as `list_presets`).
///
/// Combination semantics:
///   - axes are AND-combined (preset must satisfy every populated axis)
///   - within `tags_any` it's OR
///   - within `tags_all` it's AND
///   - `categories` is OR (preset.category in {…})
///   - `uncategorised_only` is mutually exclusive with `categories`
///     (categories wins if both supplied)
pub fn filter_presets(
    dir: &Path,
    spec: &PresetFilterSpec,
) -> PresetResult<Vec<ChainPresetMeta>> {
    let all = list_presets(dir)?;
    if spec.is_empty() {
        return Ok(all);
    }

    let categories_lc: Option<Vec<String>> = spec.categories.as_ref().and_then(|v| {
        let trimmed: Vec<String> = v
            .iter()
            .map(|c| c.trim().to_lowercase())
            .filter(|c| !c.is_empty())
            .collect();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed)
        }
    });

    let tags_any_lc: Option<Vec<String>> = spec.tags_any.as_ref().and_then(|v| {
        let trimmed: Vec<String> = v
            .iter()
            .map(|t| t.trim().to_lowercase())
            .filter(|t| !t.is_empty())
            .collect();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed)
        }
    });

    let tags_all_lc: Option<Vec<String>> = spec.tags_all.as_ref().and_then(|v| {
        let trimmed: Vec<String> = v
            .iter()
            .map(|t| t.trim().to_lowercase())
            .filter(|t| !t.is_empty())
            .collect();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed)
        }
    });

    let q_lower = spec.query.trim().to_lowercase();

    Ok(all
        .into_iter()
        .filter(|m| {
            // Category axis (categories wins over uncategorised_only when both set).
            if let Some(ref wants) = categories_lc {
                let cat_lc = m.category.as_deref().map(|c| c.to_lowercase());
                if !cat_lc.map(|c| wants.contains(&c)).unwrap_or(false) {
                    return false;
                }
            } else if spec.uncategorised_only && m.category.is_some() {
                return false;
            }

            // tags_any: at least one match
            if let Some(ref wants) = tags_any_lc {
                let preset_tags_lc: Vec<String> =
                    m.tags.iter().map(|t| t.to_lowercase()).collect();
                if !wants.iter().any(|w| preset_tags_lc.iter().any(|t| t == w)) {
                    return false;
                }
            }

            // tags_all: every required tag must be present
            if let Some(ref wants) = tags_all_lc {
                let preset_tags_lc: Vec<String> =
                    m.tags.iter().map(|t| t.to_lowercase()).collect();
                if !wants.iter().all(|w| preset_tags_lc.iter().any(|t| t == w)) {
                    return false;
                }
            }

            // Substring query (across name/desc/tags/category).
            if !q_lower.is_empty() && !meta_matches_query(m, &q_lower) {
                return false;
            }

            true
        })
        .collect())
}

/// Aggregate every distinct tag across the library, sorted alphabetically
/// (case-insensitive). Useful for the multi-select chip strip in the UI.
pub fn list_tags(dir: &Path) -> PresetResult<Vec<String>> {
    let all = list_presets(dir)?;
    let mut set: BTreeSet<String> = BTreeSet::new();
    for m in all {
        for t in m.tags {
            let trimmed = t.trim();
            if !trimmed.is_empty() {
                // Preserve original casing on first sight; later duplicates ignored.
                // BTreeSet de-dupes on the lowercase key by storing lowercase only.
                set.insert(trimmed.to_lowercase());
            }
        }
    }
    Ok(set.into_iter().collect())
}

/// Aggregate every distinct category across the library plus every
/// canonical category (so the chip strip is stable even before the user
/// has saved their first preset).
///
/// Returns a vec of unique lowercase category strings, sorted such that
/// canonical categories come first (in their canonical order) and any
/// user-defined categories follow alphabetically.
pub fn list_categories(dir: &Path) -> PresetResult<Vec<String>> {
    let all = list_presets(dir)?;
    let mut user_set: BTreeSet<String> = BTreeSet::new();
    for m in all {
        if let Some(cat) = m.category {
            let trimmed = cat.trim();
            if !trimmed.is_empty() {
                let lc = trimmed.to_lowercase();
                if !category_is_canonical(&lc) {
                    user_set.insert(lc);
                }
            }
        }
    }

    let mut out: Vec<String> = CANONICAL_CATEGORIES.iter().map(|s| (*s).to_string()).collect();
    out.extend(user_set);
    Ok(out)
}

/// Export a preset to an explicit path. Useful for sharing across
/// machines or backing up to cloud storage.
pub fn export_preset_to(dir: &Path, name: &str, dest: &Path) -> PresetResult<()> {
    let preset = load_preset(dir, name)?;
    let json = serde_json::to_string_pretty(&preset)?;
    if let Some(parent) = dest.parent()
        && !parent.as_os_str().is_empty()
    {
        fs::create_dir_all(parent)?;
    }
    fs::write(dest, json)?;
    Ok(())
}

/// Import a preset from an explicit path into the store. Returns the
/// final on-disk path (slug-derived). Existing presets with the same
/// slug are overwritten.
pub fn import_preset_from(dir: &Path, src: &Path) -> PresetResult<PathBuf> {
    let preset = read_preset_file(src)?;
    if preset.format_version > FORMAT_VERSION {
        return Err(PresetError::UnsupportedVersion {
            found: preset.format_version,
            supported: FORMAT_VERSION,
        });
    }
    save_preset(dir, &preset)
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

// ─── Tests ───────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::assistant::chain_history::{FullSlotSnapshot, SlotParamSnapshot};

    fn tmp_dir(test: &str) -> PathBuf {
        let mut p = std::env::temp_dir();
        p.push(format!(
            "rf_chain_preset_{}_{}",
            test,
            now_ms()
        ));
        fs::create_dir_all(&p).unwrap();
        p
    }

    fn sample_snapshot(track_id: u32) -> FullChainSnapshot {
        FullChainSnapshot::now(
            track_id,
            vec![FullSlotSnapshot {
                slot_index: 0,
                processor_name: "compressor".into(),
                bypassed: false,
                mix: 1.0,
                params: vec![SlotParamSnapshot {
                    index: 0,
                    name: "Threshold".into(),
                    value: -18.0,
                }],
            }],
            "Test Snapshot",
        )
    }

    #[test]
    fn slugify_basic() {
        assert_eq!(slugify("My Vocal Master").unwrap(), "my_vocal_master");
        assert_eq!(slugify("DRUM-bus_2026").unwrap(), "drum_bus_2026");
    }

    #[test]
    fn slugify_collapses_runs_of_separators() {
        assert_eq!(slugify("foo   ---bar").unwrap(), "foo_bar");
    }

    #[test]
    fn slugify_trims_leading_trailing_underscores() {
        assert_eq!(slugify(" — Vocal — ").unwrap(), "vocal");
    }

    #[test]
    fn slugify_rejects_empty() {
        assert!(matches!(slugify("").unwrap_err(), PresetError::EmptyName));
        assert!(matches!(slugify("   ").unwrap_err(), PresetError::EmptyName));
    }

    #[test]
    fn slugify_rejects_all_invalid_chars() {
        // All non-alphanumeric → invalid (only underscores would remain
        // and then be trimmed).
        assert!(matches!(
            slugify("!!! ??? ***").unwrap_err(),
            PresetError::InvalidName(_)
        ));
    }

    #[test]
    fn slugify_caps_length() {
        let long = "x".repeat(200);
        let slug = slugify(&long).unwrap();
        assert_eq!(slug.len(), 80);
    }

    #[test]
    fn save_and_load_roundtrip() {
        let dir = tmp_dir("roundtrip");
        let preset = ChainPreset::new(
            "My Vocal Master",
            "Bright, modern, transparent",
            vec!["vocal".into(), "modern".into()],
            sample_snapshot(7),
        );
        let path = save_preset(&dir, &preset).unwrap();
        assert!(path.exists());
        let loaded = load_preset(&dir, "My Vocal Master").unwrap();
        assert_eq!(loaded.name, "My Vocal Master");
        assert_eq!(loaded.tags, vec!["vocal", "modern"]);
        assert_eq!(loaded.snapshot.track_id, 7);
        assert_eq!(loaded.snapshot.slots[0].processor_name, "compressor");
        assert!(loaded.created_ms > 0);
        assert!(loaded.updated_ms >= loaded.created_ms);
    }

    #[test]
    fn save_overwrite_preserves_created_ms() {
        let dir = tmp_dir("overwrite");
        let mut preset = ChainPreset::new(
            "Same Name",
            "v1",
            vec![],
            sample_snapshot(1),
        );
        save_preset(&dir, &preset).unwrap();
        let loaded_v1 = load_preset(&dir, "Same Name").unwrap();
        let original_created = loaded_v1.created_ms;

        std::thread::sleep(std::time::Duration::from_millis(5));

        preset.description = "v2".into();
        save_preset(&dir, &preset).unwrap();
        let loaded_v2 = load_preset(&dir, "Same Name").unwrap();
        assert_eq!(loaded_v2.created_ms, original_created);
        assert!(loaded_v2.updated_ms >= original_created);
        assert_eq!(loaded_v2.description, "v2");
    }

    #[test]
    fn load_missing_returns_not_found() {
        let dir = tmp_dir("missing");
        let err = load_preset(&dir, "Nope").unwrap_err();
        assert!(matches!(err, PresetError::NotFound(_)));
    }

    #[test]
    fn delete_existing_returns_true() {
        let dir = tmp_dir("delete");
        let preset = ChainPreset::new("Del Me", "", vec![], sample_snapshot(1));
        save_preset(&dir, &preset).unwrap();
        assert!(delete_preset(&dir, "Del Me").unwrap());
        assert!(matches!(
            load_preset(&dir, "Del Me").unwrap_err(),
            PresetError::NotFound(_)
        ));
    }

    #[test]
    fn delete_missing_returns_false() {
        let dir = tmp_dir("delete_missing");
        assert!(!delete_preset(&dir, "Phantom").unwrap());
    }

    #[test]
    fn list_returns_metadata_sorted_by_updated_desc() {
        let dir = tmp_dir("list");
        let p1 = ChainPreset::new("One", "", vec!["a".into()], sample_snapshot(1));
        save_preset(&dir, &p1).unwrap();
        std::thread::sleep(std::time::Duration::from_millis(8));
        let p2 = ChainPreset::new("Two", "", vec!["b".into()], sample_snapshot(2));
        save_preset(&dir, &p2).unwrap();
        let list = list_presets(&dir).unwrap();
        assert_eq!(list.len(), 2);
        // Most recent (Two) first
        assert_eq!(list[0].name, "Two");
        assert_eq!(list[1].name, "One");
        assert_eq!(list[0].slot_count, 1);
    }

    #[test]
    fn list_empty_dir_is_ok() {
        let dir = tmp_dir("empty_list");
        let list = list_presets(&dir).unwrap();
        assert!(list.is_empty());
    }

    #[test]
    fn list_skips_tmp_files() {
        let dir = tmp_dir("tmp_files");
        let preset = ChainPreset::new("Real", "", vec![], sample_snapshot(1));
        save_preset(&dir, &preset).unwrap();
        // Plant a stray .tmp file
        fs::write(dir.join(".real.tmp"), "garbage").unwrap();
        let list = list_presets(&dir).unwrap();
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].name, "Real");
    }

    #[test]
    fn list_skips_unparseable_files() {
        let dir = tmp_dir("unparseable");
        let preset = ChainPreset::new("Good", "", vec![], sample_snapshot(1));
        save_preset(&dir, &preset).unwrap();
        // Plant a malformed JSON file
        fs::write(dir.join("broken.json"), "{ not json").unwrap();
        let list = list_presets(&dir).unwrap();
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].name, "Good");
    }

    #[test]
    fn search_filters_by_name() {
        let dir = tmp_dir("search_name");
        save_preset(&dir, &ChainPreset::new("Pop Vocal", "", vec![], sample_snapshot(1))).unwrap();
        save_preset(&dir, &ChainPreset::new("Drum Bus", "", vec![], sample_snapshot(2))).unwrap();
        let r = search_presets(&dir, "vocal").unwrap();
        assert_eq!(r.len(), 1);
        assert_eq!(r[0].name, "Pop Vocal");
    }

    #[test]
    fn search_filters_by_tag() {
        let dir = tmp_dir("search_tag");
        save_preset(
            &dir,
            &ChainPreset::new("X", "", vec!["vintage".into()], sample_snapshot(1)),
        )
        .unwrap();
        save_preset(
            &dir,
            &ChainPreset::new("Y", "", vec!["modern".into()], sample_snapshot(2)),
        )
        .unwrap();
        let r = search_presets(&dir, "VINTAGE").unwrap(); // case-insensitive
        assert_eq!(r.len(), 1);
        assert_eq!(r[0].name, "X");
    }

    #[test]
    fn search_filters_by_description() {
        let dir = tmp_dir("search_desc");
        save_preset(
            &dir,
            &ChainPreset::new(
                "Custom",
                "Bright vocal chain for podcast",
                vec![],
                sample_snapshot(1),
            ),
        )
        .unwrap();
        let r = search_presets(&dir, "podcast").unwrap();
        assert_eq!(r.len(), 1);
    }

    #[test]
    fn search_empty_query_returns_all() {
        let dir = tmp_dir("search_empty");
        save_preset(&dir, &ChainPreset::new("A", "", vec![], sample_snapshot(1))).unwrap();
        save_preset(&dir, &ChainPreset::new("B", "", vec![], sample_snapshot(2))).unwrap();
        assert_eq!(search_presets(&dir, "").unwrap().len(), 2);
        assert_eq!(search_presets(&dir, "   ").unwrap().len(), 2);
    }

    #[test]
    fn export_and_import_roundtrip() {
        let dir = tmp_dir("export");
        let import_dir = tmp_dir("import");
        save_preset(
            &dir,
            &ChainPreset::new("Source", "exp", vec!["x".into()], sample_snapshot(42)),
        )
        .unwrap();

        let dest = std::env::temp_dir().join(format!("rf_export_{}.json", now_ms()));
        export_preset_to(&dir, "Source", &dest).unwrap();
        assert!(dest.exists());

        let import_path = import_preset_from(&import_dir, &dest).unwrap();
        assert!(import_path.exists());
        let imported = load_preset(&import_dir, "Source").unwrap();
        assert_eq!(imported.snapshot.track_id, 42);

        let _ = fs::remove_file(&dest);
    }

    #[test]
    fn unsupported_version_rejected_on_load() {
        let dir = tmp_dir("version");
        let preset = ChainPreset::new("Future", "", vec![], sample_snapshot(1));
        save_preset(&dir, &preset).unwrap();
        // Tamper file to set format_version=999
        let path = path_for(&dir, "future");
        let mut value: serde_json::Value =
            serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
        value["format_version"] = serde_json::json!(999);
        fs::write(&path, serde_json::to_vec(&value).unwrap()).unwrap();
        let err = load_preset(&dir, "Future").unwrap_err();
        assert!(matches!(err, PresetError::UnsupportedVersion { .. }));
    }

    #[test]
    fn resolve_preset_dir_with_override_creates_dir() {
        let target = std::env::temp_dir().join(format!("rf_pdir_{}", now_ms()));
        assert!(!target.exists());
        let resolved = resolve_preset_dir(Some(&target)).unwrap();
        assert_eq!(resolved, target);
        assert!(target.exists());
        let _ = fs::remove_dir_all(&target);
    }

    #[test]
    fn slug_truncation_does_not_split_on_underscore_boundary_arbitrarily() {
        // Cap at 80 chars; just ensure call doesn't panic on long input.
        let huge: String = "abcdefgh ".repeat(50);
        let slug = slugify(&huge).unwrap();
        assert!(slug.len() <= 80);
        assert!(!slug.starts_with('_'));
        assert!(!slug.ends_with('_'));
    }

    #[test]
    fn save_atomic_no_partial_file_on_serialise_path_error() {
        // Sanity: tmp file naming convention. We can't easily simulate
        // serialisation failure for valid Rust types, but we can check
        // that no `.tmp` lingers after a successful save.
        let dir = tmp_dir("atomic");
        save_preset(
            &dir,
            &ChainPreset::new("Atomic", "", vec![], sample_snapshot(1)),
        )
        .unwrap();
        let entries: Vec<_> = fs::read_dir(&dir)
            .unwrap()
            .filter_map(|e| e.ok())
            .map(|e| e.file_name().to_string_lossy().to_string())
            .collect();
        assert!(entries.iter().any(|n| n == "atomic.json"));
        assert!(!entries.iter().any(|n| n.ends_with(".tmp")));
    }

    #[test]
    fn unicode_name_rejected_when_only_invalid_chars() {
        // An all-emoji name has no ASCII alphanumeric.
        assert!(matches!(
            slugify("🎵🎶🎙️").unwrap_err(),
            PresetError::InvalidName(_)
        ));
    }

    #[test]
    fn unicode_name_with_ascii_chars_works() {
        // Mixed: emoji plus letters keeps the letters.
        let s = slugify("🎵 Vocal Master").unwrap();
        assert!(s.contains("vocal"));
        assert!(s.contains("master"));
    }

    // ─── Wave 2 Front 6 — categories + structured filter ───────────────────

    fn save_with(
        dir: &Path,
        name: &str,
        category: Option<&str>,
        tags: &[&str],
    ) -> PresetResult<()> {
        let preset = ChainPreset::with_category(
            name,
            "",
            category.map(|s| s.to_string()),
            tags.iter().map(|t| t.to_string()).collect(),
            sample_snapshot(1),
        );
        save_preset(dir, &preset).map(|_| ())
    }

    #[test]
    fn category_normalisation_lowercases_and_trims() {
        let dir = tmp_dir("cat_norm");
        save_with(&dir, "P", Some("  VOCAL  "), &[]).unwrap();
        let loaded = load_preset(&dir, "P").unwrap();
        assert_eq!(loaded.category.as_deref(), Some("vocal"));
    }

    #[test]
    fn category_empty_input_becomes_none() {
        let dir = tmp_dir("cat_empty");
        save_with(&dir, "P", Some("   "), &[]).unwrap();
        let loaded = load_preset(&dir, "P").unwrap();
        assert!(loaded.category.is_none());
    }

    #[test]
    fn category_is_canonical_works_case_insensitive() {
        assert!(category_is_canonical("VOCAL"));
        assert!(category_is_canonical("vocal"));
        assert!(category_is_canonical("  Mix  "));
        assert!(!category_is_canonical("foo"));
    }

    #[test]
    fn list_tags_returns_unique_lowercase_sorted() {
        let dir = tmp_dir("tags_agg");
        save_with(&dir, "A", None, &["Modern", "vocal"]).unwrap();
        save_with(&dir, "B", None, &["VOCAL", "vintage"]).unwrap();
        save_with(&dir, "C", None, &[]).unwrap();
        let tags = list_tags(&dir).unwrap();
        // Sorted, lowercase, deduped (vocal once).
        assert_eq!(tags, vec!["modern", "vintage", "vocal"]);
    }

    #[test]
    fn list_categories_includes_canonicals_first() {
        let dir = tmp_dir("cat_agg");
        save_with(&dir, "A", Some("vocal"), &[]).unwrap();
        save_with(&dir, "B", Some("custom-zebra"), &[]).unwrap();
        let cats = list_categories(&dir).unwrap();
        // Canonicals appear in declared order, user-defined "custom-zebra" tail-end.
        assert_eq!(cats[0..CANONICAL_CATEGORIES.len()].to_vec(), {
            let v: Vec<String> = CANONICAL_CATEGORIES
                .iter()
                .map(|s| (*s).to_string())
                .collect();
            v
        });
        assert_eq!(cats.last().unwrap(), "custom-zebra");
    }

    #[test]
    fn list_categories_dedups_user_categories_against_canonical() {
        let dir = tmp_dir("cat_dedup");
        save_with(&dir, "A", Some("VOCAL"), &[]).unwrap(); // canonical
        save_with(&dir, "B", Some("vocal"), &[]).unwrap(); // dupe via case
        save_with(&dir, "C", Some("podcast"), &[]).unwrap(); // user-defined
        let cats = list_categories(&dir).unwrap();
        // No duplicates of "vocal" beyond the canonical set.
        let vocal_count = cats.iter().filter(|c| *c == "vocal").count();
        assert_eq!(vocal_count, 1);
        assert!(cats.contains(&"podcast".to_string()));
    }

    #[test]
    fn filter_empty_spec_returns_full_list() {
        let dir = tmp_dir("filter_empty");
        save_with(&dir, "A", Some("vocal"), &["x"]).unwrap();
        save_with(&dir, "B", Some("drums"), &["y"]).unwrap();
        let r = filter_presets(&dir, &PresetFilterSpec::default()).unwrap();
        assert_eq!(r.len(), 2);
    }

    #[test]
    fn filter_by_single_category() {
        let dir = tmp_dir("filter_cat");
        save_with(&dir, "Vox", Some("vocal"), &[]).unwrap();
        save_with(&dir, "Kik", Some("drums"), &[]).unwrap();
        save_with(&dir, "Bus", Some("bus"), &[]).unwrap();
        let spec = PresetFilterSpec {
            categories: Some(vec!["vocal".into()]),
            ..Default::default()
        };
        let r = filter_presets(&dir, &spec).unwrap();
        assert_eq!(r.len(), 1);
        assert_eq!(r[0].name, "Vox");
    }

    #[test]
    fn filter_by_multiple_categories_or_combine() {
        let dir = tmp_dir("filter_multi_cat");
        save_with(&dir, "Vox", Some("vocal"), &[]).unwrap();
        save_with(&dir, "Kik", Some("drums"), &[]).unwrap();
        save_with(&dir, "Bus", Some("bus"), &[]).unwrap();
        let spec = PresetFilterSpec {
            categories: Some(vec!["vocal".into(), "drums".into()]),
            ..Default::default()
        };
        let r = filter_presets(&dir, &spec).unwrap();
        assert_eq!(r.len(), 2);
        let names: Vec<&str> = r.iter().map(|m| m.name.as_str()).collect();
        assert!(names.contains(&"Vox"));
        assert!(names.contains(&"Kik"));
    }

    #[test]
    fn filter_by_tags_any() {
        let dir = tmp_dir("filter_tags_any");
        save_with(&dir, "A", None, &["modern", "bright"]).unwrap();
        save_with(&dir, "B", None, &["vintage", "warm"]).unwrap();
        save_with(&dir, "C", None, &["dark"]).unwrap();
        let spec = PresetFilterSpec {
            tags_any: Some(vec!["modern".into(), "vintage".into()]),
            ..Default::default()
        };
        let r = filter_presets(&dir, &spec).unwrap();
        assert_eq!(r.len(), 2);
        let names: Vec<&str> = r.iter().map(|m| m.name.as_str()).collect();
        assert!(names.contains(&"A"));
        assert!(names.contains(&"B"));
    }

    #[test]
    fn filter_by_tags_all() {
        let dir = tmp_dir("filter_tags_all");
        save_with(&dir, "A", None, &["modern", "bright"]).unwrap();
        save_with(&dir, "B", None, &["modern"]).unwrap();
        save_with(&dir, "C", None, &["bright"]).unwrap();
        let spec = PresetFilterSpec {
            tags_all: Some(vec!["modern".into(), "bright".into()]),
            ..Default::default()
        };
        let r = filter_presets(&dir, &spec).unwrap();
        assert_eq!(r.len(), 1);
        assert_eq!(r[0].name, "A");
    }

    #[test]
    fn filter_combined_axes_are_anded() {
        let dir = tmp_dir("filter_combined");
        save_with(&dir, "VocalModern", Some("vocal"), &["modern"]).unwrap();
        save_with(&dir, "VocalVintage", Some("vocal"), &["vintage"]).unwrap();
        save_with(&dir, "DrumModern", Some("drums"), &["modern"]).unwrap();
        let spec = PresetFilterSpec {
            categories: Some(vec!["vocal".into()]),
            tags_any: Some(vec!["modern".into()]),
            ..Default::default()
        };
        let r = filter_presets(&dir, &spec).unwrap();
        assert_eq!(r.len(), 1);
        assert_eq!(r[0].name, "VocalModern");
    }

    #[test]
    fn filter_uncategorised_only_excludes_classified() {
        let dir = tmp_dir("filter_uncat");
        save_with(&dir, "Classified", Some("vocal"), &[]).unwrap();
        save_with(&dir, "Loose", None, &[]).unwrap();
        let spec = PresetFilterSpec {
            uncategorised_only: true,
            ..Default::default()
        };
        let r = filter_presets(&dir, &spec).unwrap();
        assert_eq!(r.len(), 1);
        assert_eq!(r[0].name, "Loose");
    }

    #[test]
    fn filter_categories_wins_over_uncategorised_only() {
        let dir = tmp_dir("filter_cat_vs_uncat");
        save_with(&dir, "Classified", Some("vocal"), &[]).unwrap();
        save_with(&dir, "Loose", None, &[]).unwrap();
        let spec = PresetFilterSpec {
            categories: Some(vec!["vocal".into()]),
            uncategorised_only: true, // ignored when categories present
            ..Default::default()
        };
        let r = filter_presets(&dir, &spec).unwrap();
        assert_eq!(r.len(), 1);
        assert_eq!(r[0].name, "Classified");
    }

    #[test]
    fn filter_query_matches_category_name() {
        let dir = tmp_dir("filter_query_cat");
        save_with(&dir, "A", Some("vocal"), &[]).unwrap();
        save_with(&dir, "B", Some("drums"), &[]).unwrap();
        let spec = PresetFilterSpec {
            query: "voc".into(),
            ..Default::default()
        };
        let r = filter_presets(&dir, &spec).unwrap();
        assert_eq!(r.len(), 1);
        assert_eq!(r[0].name, "A");
    }

    #[test]
    fn filter_empty_string_axes_are_treated_as_no_restriction() {
        let dir = tmp_dir("filter_empty_axes");
        save_with(&dir, "A", Some("vocal"), &["modern"]).unwrap();
        save_with(&dir, "B", Some("drums"), &["vintage"]).unwrap();
        // Empty arrays + whitespace query → no axis restricts → all returned.
        let spec = PresetFilterSpec {
            categories: Some(vec![]),
            tags_any: Some(vec!["   ".into()]),
            tags_all: Some(vec!["".into()]),
            query: "   ".into(),
            uncategorised_only: false,
        };
        let r = filter_presets(&dir, &spec).unwrap();
        assert_eq!(r.len(), 2);
    }

    #[test]
    fn category_round_trips_through_save_load() {
        let dir = tmp_dir("cat_roundtrip");
        let preset = ChainPreset::with_category(
            "Bus Glue",
            "Compressor + Saturator",
            Some("Bus".into()),
            vec!["modern".into()],
            sample_snapshot(2),
        );
        save_preset(&dir, &preset).unwrap();
        let loaded = load_preset(&dir, "Bus Glue").unwrap();
        assert_eq!(loaded.category.as_deref(), Some("bus"));
    }

    #[test]
    fn meta_carries_category_for_browsing_without_full_load() {
        let dir = tmp_dir("meta_cat");
        save_with(&dir, "P", Some("mastering"), &[]).unwrap();
        let metas = list_presets(&dir).unwrap();
        assert_eq!(metas.len(), 1);
        assert_eq!(metas[0].category.as_deref(), Some("mastering"));
    }

    #[test]
    fn legacy_preset_without_category_field_loads_as_none() {
        let dir = tmp_dir("legacy");
        // Plant a JSON that mimics format_version=1 minus the `category` field.
        let path = path_for(&dir, "legacy_one");
        let json = serde_json::json!({
            "name": "Legacy One",
            "description": "",
            "tags": ["x"],
            "snapshot": serde_json::to_value(sample_snapshot(1)).unwrap(),
            "format_version": 1,
            "created_ms": 1u64,
            "updated_ms": 2u64,
        });
        fs::write(&path, serde_json::to_vec_pretty(&json).unwrap()).unwrap();
        let loaded = load_preset(&dir, "Legacy One").unwrap();
        assert!(loaded.category.is_none());
        assert_eq!(loaded.tags, vec!["x"]);
    }
}
