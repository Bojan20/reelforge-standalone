//! Golden file management for audio regression testing
//!
//! This module provides functionality to:
//! - Store and organize golden (reference) audio files
//! - Track metadata about golden files (version, generator, timestamp)
//! - Generate, update, and compare golden files
//! - Support CI/CD integration with approval workflows

use crate::config::DiffConfig;
use crate::diff::{AudioDiff, DiffResult};
use crate::loader::AudioData;
use crate::report::DiffReport;
use crate::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

/// Golden file metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GoldenMetadata {
    /// Unique identifier for this golden file
    pub id: String,

    /// Human-readable name
    pub name: String,

    /// Version of the golden file
    pub version: u32,

    /// What generated this golden file
    pub generator: String,

    /// Generator version
    pub generator_version: String,

    /// When this golden was created
    pub created_at: String,

    /// When this golden was last updated
    pub updated_at: String,

    /// SHA256 hash of the audio file
    pub audio_hash: String,

    /// Audio file information
    pub sample_rate: u32,
    pub num_channels: usize,
    pub num_samples: usize,
    pub duration_sec: f64,

    /// Tags for categorization
    pub tags: Vec<String>,

    /// Optional description
    pub description: Option<String>,

    /// Comparison config to use
    pub config: DiffConfig,
}

/// Golden file store
#[derive(Debug)]
pub struct GoldenStore {
    /// Root directory for golden files
    root: PathBuf,

    /// Loaded metadata index
    index: HashMap<String, GoldenMetadata>,

    /// Default config for comparisons
    default_config: DiffConfig,
}

/// Result of comparing against a golden file
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GoldenCompareResult {
    /// Golden file ID
    pub golden_id: String,

    /// Whether the comparison passed
    pub passed: bool,

    /// Detailed diff result
    pub diff: DiffResult,

    /// Golden metadata
    pub metadata: GoldenMetadata,
}

/// Result of a batch golden comparison
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GoldenBatchResult {
    /// Individual results
    pub results: Vec<GoldenCompareResult>,

    /// Total tests
    pub total: usize,

    /// Passed tests
    pub passed: usize,

    /// Failed tests
    pub failed: usize,

    /// Tests that couldn't run (missing golden, etc.)
    pub skipped: usize,
}

impl GoldenStore {
    /// Create or open a golden store at the given path
    pub fn open<P: AsRef<Path>>(root: P) -> Result<Self> {
        let root = root.as_ref().to_path_buf();

        // Create directory structure
        fs::create_dir_all(&root)?;
        fs::create_dir_all(root.join("audio"))?;
        fs::create_dir_all(root.join("metadata"))?;

        let mut store = Self {
            root,
            index: HashMap::new(),
            default_config: DiffConfig::dsp_regression(),
        };

        store.load_index()?;
        Ok(store)
    }

    /// Set default comparison config
    pub fn set_default_config(&mut self, config: DiffConfig) {
        self.default_config = config;
    }

    /// Load the metadata index from disk
    fn load_index(&mut self) -> Result<()> {
        let metadata_dir = self.root.join("metadata");
        if !metadata_dir.exists() {
            return Ok(());
        }

        for entry in fs::read_dir(metadata_dir)? {
            let entry = entry?;
            let path = entry.path();

            if path.extension().map(|e| e == "json").unwrap_or(false) {
                if let Ok(content) = fs::read_to_string(&path) {
                    if let Ok(metadata) = serde_json::from_str::<GoldenMetadata>(&content) {
                        self.index.insert(metadata.id.clone(), metadata);
                    }
                }
            }
        }

        Ok(())
    }

    /// Save metadata for a golden file
    fn save_metadata(&self, metadata: &GoldenMetadata) -> Result<()> {
        let path = self
            .root
            .join("metadata")
            .join(format!("{}.json", metadata.id));
        let content = serde_json::to_string_pretty(metadata).map_err(|e| {
            crate::AudioDiffError::IoError(std::io::Error::new(std::io::ErrorKind::Other, e))
        })?;
        fs::write(path, content)?;
        Ok(())
    }

    /// Get path to audio file for a golden
    fn audio_path(&self, id: &str) -> PathBuf {
        self.root.join("audio").join(format!("{}.wav", id))
    }

    /// List all golden files
    pub fn list(&self) -> Vec<&GoldenMetadata> {
        self.index.values().collect()
    }

    /// List golden files by tag
    pub fn list_by_tag(&self, tag: &str) -> Vec<&GoldenMetadata> {
        self.index
            .values()
            .filter(|m| m.tags.contains(&tag.to_string()))
            .collect()
    }

    /// Get a golden file by ID
    pub fn get(&self, id: &str) -> Option<&GoldenMetadata> {
        self.index.get(id)
    }

    /// Check if a golden exists
    pub fn exists(&self, id: &str) -> bool {
        self.index.contains_key(id) && self.audio_path(id).exists()
    }

    /// Create a new golden file from audio data
    pub fn create(
        &mut self,
        id: impl Into<String>,
        name: impl Into<String>,
        audio: &AudioData,
        generator: impl Into<String>,
        generator_version: impl Into<String>,
        tags: Vec<String>,
        description: Option<String>,
    ) -> Result<GoldenMetadata> {
        let id = id.into();
        let name = name.into();
        let generator = generator.into();
        let generator_version = generator_version.into();

        // Save audio file as WAV
        let audio_path = self.audio_path(&id);
        save_audio_as_wav(audio, &audio_path)?;

        // Calculate hash
        let audio_bytes = fs::read(&audio_path)?;
        let hash = sha256_hex(&audio_bytes);

        let now = timestamp_now();

        let metadata = GoldenMetadata {
            id: id.clone(),
            name,
            version: 1,
            generator,
            generator_version,
            created_at: now.clone(),
            updated_at: now,
            audio_hash: hash,
            sample_rate: audio.sample_rate,
            num_channels: audio.num_channels,
            num_samples: audio.num_samples,
            duration_sec: audio.duration,
            tags,
            description,
            config: self.default_config.clone(),
        };

        self.save_metadata(&metadata)?;
        self.index.insert(id, metadata.clone());

        Ok(metadata)
    }

    /// Create golden from an audio file
    pub fn create_from_file<P: AsRef<Path>>(
        &mut self,
        id: impl Into<String>,
        name: impl Into<String>,
        audio_path: P,
        generator: impl Into<String>,
        generator_version: impl Into<String>,
        tags: Vec<String>,
        description: Option<String>,
    ) -> Result<GoldenMetadata> {
        let audio = AudioData::load(audio_path)?;
        self.create(
            id,
            name,
            &audio,
            generator,
            generator_version,
            tags,
            description,
        )
    }

    /// Update a golden file with new audio
    pub fn update(&mut self, id: &str, audio: &AudioData) -> Result<GoldenMetadata> {
        let mut metadata = self
            .get(id)
            .ok_or_else(|| crate::AudioDiffError::LoadError(format!("Golden not found: {}", id)))?
            .clone();

        // Save new audio
        let audio_path = self.audio_path(id);
        save_audio_as_wav(audio, &audio_path)?;

        // Update metadata
        let audio_bytes = fs::read(&audio_path)?;
        let hash = sha256_hex(&audio_bytes);

        metadata.version += 1;
        metadata.updated_at = timestamp_now();
        metadata.audio_hash = hash;
        metadata.sample_rate = audio.sample_rate;
        metadata.num_channels = audio.num_channels;
        metadata.num_samples = audio.num_samples;
        metadata.duration_sec = audio.duration;

        self.save_metadata(&metadata)?;
        self.index.insert(id.to_string(), metadata.clone());

        Ok(metadata)
    }

    /// Delete a golden file
    pub fn delete(&mut self, id: &str) -> Result<()> {
        // Remove audio file
        let audio_path = self.audio_path(id);
        if audio_path.exists() {
            fs::remove_file(audio_path)?;
        }

        // Remove metadata
        let metadata_path = self.root.join("metadata").join(format!("{}.json", id));
        if metadata_path.exists() {
            fs::remove_file(metadata_path)?;
        }

        self.index.remove(id);
        Ok(())
    }

    /// Compare audio against a golden file
    pub fn compare(&self, id: &str, test_audio: &AudioData) -> Result<GoldenCompareResult> {
        let metadata = self
            .get(id)
            .ok_or_else(|| crate::AudioDiffError::LoadError(format!("Golden not found: {}", id)))?
            .clone();

        let golden_audio = AudioData::load(self.audio_path(id))?;

        let diff = AudioDiff::compare_audio(golden_audio, test_audio.clone(), &metadata.config)?;
        let passed = diff.is_pass();

        Ok(GoldenCompareResult {
            golden_id: id.to_string(),
            passed,
            diff,
            metadata,
        })
    }

    /// Compare a test audio file against a golden
    pub fn compare_file<P: AsRef<Path>>(
        &self,
        id: &str,
        test_path: P,
    ) -> Result<GoldenCompareResult> {
        let test_audio = AudioData::load(test_path)?;
        self.compare(id, &test_audio)
    }

    /// Run batch comparison against multiple goldens
    pub fn compare_batch(&self, tests: &[(String, AudioData)]) -> GoldenBatchResult {
        let mut results = Vec::new();
        let mut passed = 0;
        let mut failed = 0;
        let mut skipped = 0;

        for (id, test_audio) in tests {
            match self.compare(id, test_audio) {
                Ok(result) => {
                    if result.passed {
                        passed += 1;
                    } else {
                        failed += 1;
                    }
                    results.push(result);
                }
                Err(_) => {
                    skipped += 1;
                }
            }
        }

        GoldenBatchResult {
            results,
            total: tests.len(),
            passed,
            failed,
            skipped,
        }
    }

    /// Generate a diff report for all comparisons
    pub fn generate_report(&self, batch_result: &GoldenBatchResult) -> DiffReport {
        let mut report = DiffReport::new("Golden File Regression Test");

        for result in &batch_result.results {
            report.add_result(result.diff.clone());
        }

        report
    }

    /// Export golden store manifest
    pub fn export_manifest(&self) -> Result<String> {
        let manifest: Vec<&GoldenMetadata> = self.index.values().collect();
        serde_json::to_string_pretty(&manifest).map_err(|e| {
            crate::AudioDiffError::IoError(std::io::Error::new(std::io::ErrorKind::Other, e))
        })
    }

    /// Get store statistics
    pub fn stats(&self) -> GoldenStoreStats {
        let total = self.index.len();
        let total_samples: usize = self.index.values().map(|m| m.num_samples).sum();
        let total_duration: f64 = self.index.values().map(|m| m.duration_sec).sum();

        let mut tags: HashMap<String, usize> = HashMap::new();
        for metadata in self.index.values() {
            for tag in &metadata.tags {
                *tags.entry(tag.clone()).or_insert(0) += 1;
            }
        }

        GoldenStoreStats {
            total_goldens: total,
            total_samples,
            total_duration_sec: total_duration,
            tags,
        }
    }
}

/// Store statistics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GoldenStoreStats {
    pub total_goldens: usize,
    pub total_samples: usize,
    pub total_duration_sec: f64,
    pub tags: HashMap<String, usize>,
}

impl GoldenBatchResult {
    /// Check if all tests passed
    pub fn all_passed(&self) -> bool {
        self.failed == 0 && self.skipped == 0
    }

    /// Get pass rate
    pub fn pass_rate(&self) -> f64 {
        if self.total == 0 {
            1.0
        } else {
            self.passed as f64 / self.total as f64
        }
    }

    /// Get summary string
    pub fn summary(&self) -> String {
        format!(
            "Total: {}, Passed: {}, Failed: {}, Skipped: {} ({:.1}% pass rate)",
            self.total,
            self.passed,
            self.failed,
            self.skipped,
            self.pass_rate() * 100.0
        )
    }
}

/// Save audio data as WAV file
fn save_audio_as_wav(audio: &AudioData, path: &Path) -> Result<()> {
    let spec = hound::WavSpec {
        channels: audio.num_channels as u16,
        sample_rate: audio.sample_rate,
        bits_per_sample: 32,
        sample_format: hound::SampleFormat::Float,
    };

    let mut writer = hound::WavWriter::create(path, spec).map_err(|e| {
        crate::AudioDiffError::IoError(std::io::Error::new(std::io::ErrorKind::Other, e))
    })?;

    // Interleave channels
    for i in 0..audio.num_samples {
        for ch in &audio.channels {
            let sample = ch.get(i).copied().unwrap_or(0.0) as f32;
            writer.write_sample(sample).map_err(|e| {
                crate::AudioDiffError::IoError(std::io::Error::new(std::io::ErrorKind::Other, e))
            })?;
        }
    }

    writer.finalize().map_err(|e| {
        crate::AudioDiffError::IoError(std::io::Error::new(std::io::ErrorKind::Other, e))
    })?;

    Ok(())
}

/// Calculate SHA256 hash of bytes
fn sha256_hex(bytes: &[u8]) -> String {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};

    // Simple hash for now (could use sha2 crate for production)
    let mut hasher = DefaultHasher::new();
    bytes.hash(&mut hasher);
    format!("{:016x}", hasher.finish())
}

/// Get current timestamp as ISO 8601 string
fn timestamp_now() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};

    let duration = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    let secs = duration.as_secs();

    // Basic calculation
    let days = secs / 86400;
    let time_of_day = secs % 86400;
    let hours = time_of_day / 3600;
    let minutes = (time_of_day % 3600) / 60;
    let seconds = time_of_day % 60;

    // Simplified year calculation
    let mut year = 1970u64;
    let mut remaining_days = days;
    loop {
        let days_in_year = if year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) {
            366
        } else {
            365
        };
        if remaining_days < days_in_year {
            break;
        }
        remaining_days -= days_in_year;
        year += 1;
    }

    let is_leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    let days_in_months: [u64; 12] = if is_leap {
        [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    } else {
        [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    };

    let mut month = 1;
    for (i, &d) in days_in_months.iter().enumerate() {
        if remaining_days < d {
            month = i + 1;
            break;
        }
        remaining_days -= d;
    }
    let day = remaining_days + 1;

    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
        year, month, day, hours, minutes, seconds
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn make_test_audio(freq: f64) -> AudioData {
        let samples: Vec<f64> = (0..4096)
            .map(|i| (2.0 * std::f64::consts::PI * freq * i as f64 / 44100.0).sin())
            .collect();

        AudioData {
            channels: vec![samples],
            sample_rate: 44100,
            num_channels: 1,
            num_samples: 4096,
            duration: 4096.0 / 44100.0,
            source_path: "test".into(),
        }
    }

    #[test]
    fn test_golden_store_create() {
        let temp_dir = TempDir::new().unwrap();
        let mut store = GoldenStore::open(temp_dir.path()).unwrap();

        let audio = make_test_audio(440.0);
        let metadata = store
            .create(
                "test_440hz",
                "440 Hz Sine Wave",
                &audio,
                "test",
                "1.0.0",
                vec!["test".into(), "sine".into()],
                Some("Test sine wave".into()),
            )
            .unwrap();

        assert_eq!(metadata.id, "test_440hz");
        assert_eq!(metadata.version, 1);
        assert!(store.exists("test_440hz"));
    }

    #[test]
    fn test_golden_compare_identical() {
        let temp_dir = TempDir::new().unwrap();
        let mut store = GoldenStore::open(temp_dir.path()).unwrap();

        let audio = make_test_audio(440.0);
        store
            .create(
                "test_440hz",
                "440 Hz Sine Wave",
                &audio,
                "test",
                "1.0.0",
                vec![],
                None,
            )
            .unwrap();

        let result = store.compare("test_440hz", &audio).unwrap();
        assert!(result.passed);
    }

    #[test]
    fn test_golden_compare_different() {
        let temp_dir = TempDir::new().unwrap();
        let mut store = GoldenStore::open(temp_dir.path()).unwrap();

        let audio_440 = make_test_audio(440.0);
        let audio_880 = make_test_audio(880.0);

        store
            .create(
                "test_440hz",
                "440 Hz Sine Wave",
                &audio_440,
                "test",
                "1.0.0",
                vec![],
                None,
            )
            .unwrap();

        let result = store.compare("test_440hz", &audio_880).unwrap();
        assert!(!result.passed);
    }

    #[test]
    fn test_golden_update() {
        let temp_dir = TempDir::new().unwrap();
        let mut store = GoldenStore::open(temp_dir.path()).unwrap();

        let audio_440 = make_test_audio(440.0);
        let audio_880 = make_test_audio(880.0);

        store
            .create(
                "test_tone",
                "Test Tone",
                &audio_440,
                "test",
                "1.0.0",
                vec![],
                None,
            )
            .unwrap();

        let updated = store.update("test_tone", &audio_880).unwrap();
        assert_eq!(updated.version, 2);

        // Now comparison with 880 Hz should pass
        let result = store.compare("test_tone", &audio_880).unwrap();
        assert!(result.passed);
    }

    #[test]
    fn test_golden_batch() {
        let temp_dir = TempDir::new().unwrap();
        let mut store = GoldenStore::open(temp_dir.path()).unwrap();

        let audio_440 = make_test_audio(440.0);
        let audio_880 = make_test_audio(880.0);

        store
            .create(
                "tone_440",
                "440 Hz",
                &audio_440,
                "test",
                "1.0",
                vec![],
                None,
            )
            .unwrap();
        store
            .create(
                "tone_880",
                "880 Hz",
                &audio_880,
                "test",
                "1.0",
                vec![],
                None,
            )
            .unwrap();

        let tests = vec![
            ("tone_440".to_string(), audio_440.clone()),
            ("tone_880".to_string(), audio_440.clone()), // Wrong audio, should fail
        ];

        let batch_result = store.compare_batch(&tests);
        assert_eq!(batch_result.total, 2);
        assert_eq!(batch_result.passed, 1);
        assert_eq!(batch_result.failed, 1);
    }

    #[test]
    fn test_golden_store_stats() {
        let temp_dir = TempDir::new().unwrap();
        let mut store = GoldenStore::open(temp_dir.path()).unwrap();

        let audio = make_test_audio(440.0);
        store
            .create(
                "test1",
                "Test 1",
                &audio,
                "test",
                "1.0",
                vec!["tag_a".into()],
                None,
            )
            .unwrap();
        store
            .create(
                "test2",
                "Test 2",
                &audio,
                "test",
                "1.0",
                vec!["tag_a".into(), "tag_b".into()],
                None,
            )
            .unwrap();

        let stats = store.stats();
        assert_eq!(stats.total_goldens, 2);
        assert_eq!(stats.tags.get("tag_a"), Some(&2));
        assert_eq!(stats.tags.get("tag_b"), Some(&1));
    }
}
