//! IR Spectrum Cache
//!
//! Caches pre-computed FFT spectra for impulse responses:
//! - Binary cache files (.irspec) stored alongside IR files
//! - SHA-256 hash validation for cache invalidation
//! - Thread-safe LRU memory cache
//! - ~10-50x faster IR loading (skip FFT computation)

use parking_lot::RwLock;
use rustfft::num_complex::Complex64;
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::fs::{self, File};
use std::io::{BufReader, BufWriter, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::SystemTime;

/// Cache file magic number
const CACHE_MAGIC: [u8; 4] = *b"IRSP";

/// Cache file version
const CACHE_VERSION: u32 = 1;

/// Maximum memory cache entries
const MAX_MEMORY_CACHE: usize = 32;

/// Cached spectrum data
#[derive(Clone)]
pub struct CachedSpectrum {
    /// Pre-computed FFT partitions (frequency domain)
    pub partitions: Vec<Vec<Complex64>>,
    /// Partition sizes
    pub partition_sizes: Vec<usize>,
    /// Original IR length
    pub ir_length: usize,
    /// Sample rate used for computation
    pub sample_rate: f64,
    /// Number of channels
    pub channels: u8,
    /// Source file hash for validation
    pub source_hash: [u8; 32],
}

impl CachedSpectrum {
    /// Write to binary cache file
    pub fn write_to_file(&self, path: &Path) -> std::io::Result<()> {
        let file = File::create(path)?;
        let mut writer = BufWriter::new(file);

        // Header
        writer.write_all(&CACHE_MAGIC)?;
        writer.write_all(&CACHE_VERSION.to_le_bytes())?;
        writer.write_all(&self.source_hash)?;
        writer.write_all(&(self.ir_length as u64).to_le_bytes())?;
        writer.write_all(&self.sample_rate.to_le_bytes())?;
        writer.write_all(&[self.channels])?;

        // Partitions count
        let num_partitions = self.partitions.len() as u32;
        writer.write_all(&num_partitions.to_le_bytes())?;

        // Each partition
        for (i, partition) in self.partitions.iter().enumerate() {
            let size = self.partition_sizes.get(i).copied().unwrap_or(partition.len()) as u32;
            writer.write_all(&size.to_le_bytes())?;

            let num_complex = partition.len() as u32;
            writer.write_all(&num_complex.to_le_bytes())?;

            for c in partition {
                writer.write_all(&c.re.to_le_bytes())?;
                writer.write_all(&c.im.to_le_bytes())?;
            }
        }

        writer.flush()
    }

    /// Read from binary cache file
    pub fn read_from_file(path: &Path) -> std::io::Result<Self> {
        let file = File::open(path)?;
        let mut reader = BufReader::new(file);

        // Header
        let mut magic = [0u8; 4];
        reader.read_exact(&mut magic)?;
        if magic != CACHE_MAGIC {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "Invalid cache magic",
            ));
        }

        let mut version_bytes = [0u8; 4];
        reader.read_exact(&mut version_bytes)?;
        let version = u32::from_le_bytes(version_bytes);
        if version != CACHE_VERSION {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "Cache version mismatch",
            ));
        }

        let mut source_hash = [0u8; 32];
        reader.read_exact(&mut source_hash)?;

        let mut ir_length_bytes = [0u8; 8];
        reader.read_exact(&mut ir_length_bytes)?;
        let ir_length = u64::from_le_bytes(ir_length_bytes) as usize;

        let mut sample_rate_bytes = [0u8; 8];
        reader.read_exact(&mut sample_rate_bytes)?;
        let sample_rate = f64::from_le_bytes(sample_rate_bytes);

        let mut channels_byte = [0u8; 1];
        reader.read_exact(&mut channels_byte)?;
        let channels = channels_byte[0];

        // Partitions count
        let mut num_partitions_bytes = [0u8; 4];
        reader.read_exact(&mut num_partitions_bytes)?;
        let num_partitions = u32::from_le_bytes(num_partitions_bytes) as usize;

        let mut partitions = Vec::with_capacity(num_partitions);
        let mut partition_sizes = Vec::with_capacity(num_partitions);

        for _ in 0..num_partitions {
            let mut size_bytes = [0u8; 4];
            reader.read_exact(&mut size_bytes)?;
            let size = u32::from_le_bytes(size_bytes) as usize;
            partition_sizes.push(size);

            let mut num_complex_bytes = [0u8; 4];
            reader.read_exact(&mut num_complex_bytes)?;
            let num_complex = u32::from_le_bytes(num_complex_bytes) as usize;

            let mut partition = Vec::with_capacity(num_complex);
            for _ in 0..num_complex {
                let mut re_bytes = [0u8; 8];
                let mut im_bytes = [0u8; 8];
                reader.read_exact(&mut re_bytes)?;
                reader.read_exact(&mut im_bytes)?;
                partition.push(Complex64::new(
                    f64::from_le_bytes(re_bytes),
                    f64::from_le_bytes(im_bytes),
                ));
            }
            partitions.push(partition);
        }

        Ok(Self {
            partitions,
            partition_sizes,
            ir_length,
            sample_rate,
            channels,
            source_hash,
        })
    }
}

/// Memory cache entry with LRU tracking
struct CacheEntry {
    spectrum: Arc<CachedSpectrum>,
    last_access: SystemTime,
}

/// IR Spectrum Cache Manager
pub struct IrCache {
    /// Memory cache (path hash -> spectrum)
    memory_cache: RwLock<HashMap<[u8; 32], CacheEntry>>,
    /// Cache directory for disk cache
    cache_dir: Option<PathBuf>,
    /// Enable disk caching
    disk_cache_enabled: bool,
}

impl IrCache {
    /// Create new cache manager
    pub fn new() -> Self {
        Self {
            memory_cache: RwLock::new(HashMap::new()),
            cache_dir: None,
            disk_cache_enabled: true,
        }
    }

    /// Create with custom cache directory
    pub fn with_cache_dir(cache_dir: PathBuf) -> Self {
        let _ = fs::create_dir_all(&cache_dir);
        Self {
            memory_cache: RwLock::new(HashMap::new()),
            cache_dir: Some(cache_dir),
            disk_cache_enabled: true,
        }
    }

    /// Enable/disable disk caching
    pub fn set_disk_cache_enabled(&mut self, enabled: bool) {
        self.disk_cache_enabled = enabled;
    }

    /// Compute hash of IR file
    pub fn compute_hash(ir_path: &Path) -> std::io::Result<[u8; 32]> {
        let data = fs::read(ir_path)?;
        let mut hasher = Sha256::new();
        hasher.update(&data);
        let result = hasher.finalize();
        let mut hash = [0u8; 32];
        hash.copy_from_slice(&result);
        Ok(hash)
    }

    /// Compute hash from raw samples
    pub fn compute_samples_hash(samples: &[f64], sample_rate: f64, channels: u8) -> [u8; 32] {
        let mut hasher = Sha256::new();
        hasher.update(&sample_rate.to_le_bytes());
        hasher.update(&[channels]);
        for s in samples {
            hasher.update(&s.to_le_bytes());
        }
        let result = hasher.finalize();
        let mut hash = [0u8; 32];
        hash.copy_from_slice(&result);
        hash
    }

    /// Get cache file path for IR
    fn cache_path(&self, ir_path: &Path) -> PathBuf {
        if let Some(ref cache_dir) = self.cache_dir {
            let hash = Self::compute_hash(ir_path).unwrap_or([0; 32]);
            let hash_str = hex::encode(&hash[..8]);
            cache_dir.join(format!("{}.irspec", hash_str))
        } else {
            // Store alongside IR file
            ir_path.with_extension("irspec")
        }
    }

    /// Try to load spectrum from cache
    pub fn get(&self, ir_path: &Path) -> Option<Arc<CachedSpectrum>> {
        let hash = Self::compute_hash(ir_path).ok()?;

        // Try memory cache first
        {
            let mut cache = self.memory_cache.write();
            if let Some(entry) = cache.get_mut(&hash) {
                entry.last_access = SystemTime::now();
                return Some(Arc::clone(&entry.spectrum));
            }
        }

        // Try disk cache
        if self.disk_cache_enabled {
            let cache_path = self.cache_path(ir_path);
            if cache_path.exists() {
                if let Ok(spectrum) = CachedSpectrum::read_from_file(&cache_path) {
                    // Validate hash matches
                    if spectrum.source_hash == hash {
                        let spectrum = Arc::new(spectrum);

                        // Add to memory cache
                        self.add_to_memory_cache(hash, Arc::clone(&spectrum));

                        return Some(spectrum);
                    } else {
                        // Hash mismatch - cache is stale, delete it
                        let _ = fs::remove_file(&cache_path);
                    }
                }
            }
        }

        None
    }

    /// Try to load spectrum by hash (for in-memory IRs)
    pub fn get_by_hash(&self, hash: &[u8; 32]) -> Option<Arc<CachedSpectrum>> {
        let mut cache = self.memory_cache.write();
        if let Some(entry) = cache.get_mut(hash) {
            entry.last_access = SystemTime::now();
            return Some(Arc::clone(&entry.spectrum));
        }
        None
    }

    /// Store spectrum in cache
    pub fn put(&self, ir_path: &Path, spectrum: CachedSpectrum) -> std::io::Result<()> {
        let hash = Self::compute_hash(ir_path)?;

        // Add to memory cache
        self.add_to_memory_cache(hash, Arc::new(spectrum.clone()));

        // Write to disk cache
        if self.disk_cache_enabled {
            let cache_path = self.cache_path(ir_path);
            spectrum.write_to_file(&cache_path)?;
        }

        Ok(())
    }

    /// Store spectrum by hash (for in-memory IRs)
    pub fn put_by_hash(&self, hash: [u8; 32], spectrum: CachedSpectrum) {
        self.add_to_memory_cache(hash, Arc::new(spectrum));
    }

    /// Add to memory cache with LRU eviction
    fn add_to_memory_cache(&self, hash: [u8; 32], spectrum: Arc<CachedSpectrum>) {
        let mut cache = self.memory_cache.write();

        // Evict oldest if at capacity
        if cache.len() >= MAX_MEMORY_CACHE {
            let oldest = cache
                .iter()
                .min_by_key(|(_, entry)| entry.last_access)
                .map(|(k, _)| *k);

            if let Some(key) = oldest {
                cache.remove(&key);
            }
        }

        cache.insert(
            hash,
            CacheEntry {
                spectrum,
                last_access: SystemTime::now(),
            },
        );
    }

    /// Clear all caches
    pub fn clear(&self) {
        self.memory_cache.write().clear();

        if let Some(ref cache_dir) = self.cache_dir {
            if let Ok(entries) = fs::read_dir(cache_dir) {
                for entry in entries.flatten() {
                    if entry.path().extension().map_or(false, |e| e == "irspec") {
                        let _ = fs::remove_file(entry.path());
                    }
                }
            }
        }
    }

    /// Get cache statistics
    pub fn stats(&self) -> CacheStats {
        let cache = self.memory_cache.read();
        let memory_entries = cache.len();
        let memory_bytes: usize = cache
            .values()
            .map(|e| {
                e.spectrum
                    .partitions
                    .iter()
                    .map(|p| p.len() * 16)
                    .sum::<usize>()
            })
            .sum();

        let mut disk_entries = 0;
        let mut disk_bytes = 0u64;

        if let Some(ref cache_dir) = self.cache_dir {
            if let Ok(entries) = fs::read_dir(cache_dir) {
                for entry in entries.flatten() {
                    if entry.path().extension().map_or(false, |e| e == "irspec") {
                        disk_entries += 1;
                        disk_bytes += entry.metadata().map(|m| m.len()).unwrap_or(0);
                    }
                }
            }
        }

        CacheStats {
            memory_entries,
            memory_bytes,
            disk_entries,
            disk_bytes,
        }
    }
}

impl Default for IrCache {
    fn default() -> Self {
        Self::new()
    }
}

/// Cache statistics
#[derive(Debug, Clone)]
pub struct CacheStats {
    /// Number of entries in memory cache
    pub memory_entries: usize,
    /// Total bytes in memory cache
    pub memory_bytes: usize,
    /// Number of entries in disk cache
    pub disk_entries: usize,
    /// Total bytes in disk cache
    pub disk_bytes: u64,
}

/// Global IR cache instance
static IR_CACHE: std::sync::OnceLock<IrCache> = std::sync::OnceLock::new();

/// Get global IR cache
pub fn global_cache() -> &'static IrCache {
    IR_CACHE.get_or_init(IrCache::new)
}

/// Initialize global cache with custom directory
pub fn init_global_cache(cache_dir: PathBuf) {
    let _ = IR_CACHE.set(IrCache::with_cache_dir(cache_dir));
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn test_cache_stats() {
        let cache = IrCache::new();
        let stats = cache.stats();
        assert_eq!(stats.memory_entries, 0);
    }

    #[test]
    fn test_cached_spectrum_roundtrip() {
        let temp_dir = TempDir::new().unwrap();
        let cache_path = temp_dir.path().join("test.irspec");

        let spectrum = CachedSpectrum {
            partitions: vec![
                vec![Complex64::new(1.0, 0.5), Complex64::new(0.5, 0.25)],
                vec![Complex64::new(0.25, 0.125)],
            ],
            partition_sizes: vec![64, 128],
            ir_length: 1024,
            sample_rate: 48000.0,
            channels: 2,
            source_hash: [42u8; 32],
        };

        spectrum.write_to_file(&cache_path).unwrap();
        let loaded = CachedSpectrum::read_from_file(&cache_path).unwrap();

        assert_eq!(loaded.ir_length, spectrum.ir_length);
        assert_eq!(loaded.sample_rate, spectrum.sample_rate);
        assert_eq!(loaded.channels, spectrum.channels);
        assert_eq!(loaded.partitions.len(), spectrum.partitions.len());
        assert_eq!(loaded.source_hash, spectrum.source_hash);
    }

    #[test]
    fn test_memory_cache_lru() {
        let cache = IrCache::new();

        // Fill cache beyond capacity
        for i in 0..MAX_MEMORY_CACHE + 5 {
            let mut hash = [0u8; 32];
            hash[0] = i as u8;

            let spectrum = CachedSpectrum {
                partitions: vec![],
                partition_sizes: vec![],
                ir_length: i,
                sample_rate: 48000.0,
                channels: 1,
                source_hash: hash,
            };

            cache.put_by_hash(hash, spectrum);
        }

        let stats = cache.stats();
        assert!(stats.memory_entries <= MAX_MEMORY_CACHE);
    }

    #[test]
    fn test_compute_samples_hash() {
        let samples1 = vec![1.0, 2.0, 3.0];
        let samples2 = vec![1.0, 2.0, 3.0];
        let samples3 = vec![1.0, 2.0, 4.0];

        let hash1 = IrCache::compute_samples_hash(&samples1, 48000.0, 1);
        let hash2 = IrCache::compute_samples_hash(&samples2, 48000.0, 1);
        let hash3 = IrCache::compute_samples_hash(&samples3, 48000.0, 1);

        assert_eq!(hash1, hash2);
        assert_ne!(hash1, hash3);
    }
}
