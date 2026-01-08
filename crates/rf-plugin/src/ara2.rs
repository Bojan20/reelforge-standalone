//! ARA2 Plugin Extension Support
//!
//! Audio Random Access 2 (ARA) enables deep integration with
//! plugins like Melodyne and SpectraLayers.
//!
//! NOTE: Full ARA2 requires the Celemony SDK. This module provides
//! the host-side infrastructure that can be connected to the SDK.

use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;

// ============ ARA2 Types ============

/// ARA document controller ID
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct AraDocumentId(pub u64);

/// ARA musical context ID
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct AraMusicalContextId(pub u64);

/// ARA region sequence ID
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct AraRegionSequenceId(pub u64);

/// ARA audio source ID
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct AraAudioSourceId(pub u64);

/// ARA audio modification ID
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct AraAudioModificationId(pub u64);

/// ARA playback region ID
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct AraPlaybackRegionId(pub u64);

// ============ ARA2 Enums ============

/// ARA plugin type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AraPluginType {
    /// Plugin provides audio modifications (like Melodyne)
    AudioModification,
    /// Plugin analyzes audio (like analysis plugins)
    AudioAnalysis,
    /// Plugin does both
    Hybrid,
}

/// ARA content type flags
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct AraContentTypes {
    /// Notes (pitch, timing)
    pub notes: bool,
    /// Tempo map
    pub tempo: bool,
    /// Bar signatures
    pub bar_signatures: bool,
    /// Key signatures
    pub key_signatures: bool,
    /// Tuning
    pub tuning: bool,
    /// Chords
    pub chords: bool,
    /// Static tuning offset
    pub static_tuning_offset: bool,
}

impl Default for AraContentTypes {
    fn default() -> Self {
        Self {
            notes: true,
            tempo: true,
            bar_signatures: true,
            key_signatures: false,
            tuning: false,
            chords: false,
            static_tuning_offset: false,
        }
    }
}

/// ARA transformation flags
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct AraTransformationFlags {
    /// Can modify pitch
    pub pitch: bool,
    /// Can modify formants
    pub formants: bool,
    /// Can modify timing
    pub timing: bool,
    /// Can modify note content
    pub notes: bool,
}

impl Default for AraTransformationFlags {
    fn default() -> Self {
        Self {
            pitch: true,
            formants: true,
            timing: true,
            notes: true,
        }
    }
}

/// ARA playback transformation
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct AraPlaybackTransformation {
    /// Time stretch factor (1.0 = no change)
    pub time_stretch_factor: f64,
    /// Pitch shift in semitones
    pub pitch_shift_semitones: f64,
    /// Formant shift in semitones
    pub formant_shift_semitones: f64,
}

impl Default for AraPlaybackTransformation {
    fn default() -> Self {
        Self {
            time_stretch_factor: 1.0,
            pitch_shift_semitones: 0.0,
            formant_shift_semitones: 0.0,
        }
    }
}

// ============ ARA2 Data Structures ============

/// Musical context for ARA
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AraMusicalContext {
    pub id: AraMusicalContextId,
    pub name: String,
    /// Tempo in BPM
    pub tempo: f64,
    /// Time signature numerator
    pub time_sig_numerator: u8,
    /// Time signature denominator
    pub time_sig_denominator: u8,
    /// Key signature (0-11 for C-B, negative for flats)
    pub key_signature: i8,
    /// Is minor key
    pub is_minor: bool,
}

/// Audio source for ARA
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AraAudioSource {
    pub id: AraAudioSourceId,
    pub name: String,
    /// Persistent ID for project reload
    pub persistent_id: String,
    /// Sample rate
    pub sample_rate: f64,
    /// Number of channels
    pub channel_count: u32,
    /// Duration in samples
    pub sample_count: u64,
    /// Content types available in this source
    pub content_types: AraContentTypes,
    /// Analysis state
    pub analysis_state: AraAnalysisState,
}

/// Analysis state for ARA sources
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AraAnalysisState {
    /// Not yet analyzed
    NotAnalyzed,
    /// Analysis in progress
    Analyzing,
    /// Analysis complete
    Analyzed,
    /// Analysis failed
    Failed,
}

/// Audio modification for ARA
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AraAudioModification {
    pub id: AraAudioModificationId,
    pub name: String,
    /// Source this modifies
    pub audio_source_id: AraAudioSourceId,
    /// Persistent ID
    pub persistent_id: String,
    /// Current transformation
    pub transformation: AraPlaybackTransformation,
}

/// Region sequence for ARA
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AraRegionSequence {
    pub id: AraRegionSequenceId,
    pub name: String,
    /// Musical context
    pub musical_context_id: AraMusicalContextId,
    /// Color for UI
    pub color: [u8; 3],
}

/// Playback region for ARA
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AraPlaybackRegion {
    pub id: AraPlaybackRegionId,
    pub name: String,
    /// Region sequence this belongs to
    pub region_sequence_id: AraRegionSequenceId,
    /// Audio modification
    pub audio_modification_id: AraAudioModificationId,
    /// Start time in playback (samples)
    pub start_in_playback_samples: i64,
    /// Duration in playback (samples)
    pub duration_in_playback_samples: u64,
    /// Start in modification (samples)
    pub start_in_modification_samples: i64,
    /// Duration in modification (samples)
    pub duration_in_modification_samples: u64,
    /// Transformation for this region
    pub transformation: AraPlaybackTransformation,
    /// Transformation flags
    pub transformation_flags: AraTransformationFlags,
}

// ============ ARA2 Document ============

/// ARA document containing all data for a plugin
#[derive(Debug)]
pub struct AraDocument {
    pub id: AraDocumentId,
    pub name: String,
    /// Musical contexts
    pub musical_contexts: HashMap<AraMusicalContextId, AraMusicalContext>,
    /// Audio sources
    pub audio_sources: HashMap<AraAudioSourceId, AraAudioSource>,
    /// Audio modifications
    pub audio_modifications: HashMap<AraAudioModificationId, AraAudioModification>,
    /// Region sequences
    pub region_sequences: HashMap<AraRegionSequenceId, AraRegionSequence>,
    /// Playback regions
    pub playback_regions: HashMap<AraPlaybackRegionId, AraPlaybackRegion>,
    /// ID counters
    next_musical_context_id: u64,
    next_audio_source_id: u64,
    next_audio_modification_id: u64,
    next_region_sequence_id: u64,
    next_playback_region_id: u64,
}

impl AraDocument {
    pub fn new(id: AraDocumentId, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
            musical_contexts: HashMap::new(),
            audio_sources: HashMap::new(),
            audio_modifications: HashMap::new(),
            region_sequences: HashMap::new(),
            playback_regions: HashMap::new(),
            next_musical_context_id: 1,
            next_audio_source_id: 1,
            next_audio_modification_id: 1,
            next_region_sequence_id: 1,
            next_playback_region_id: 1,
        }
    }

    /// Create musical context
    pub fn create_musical_context(&mut self, name: impl Into<String>) -> AraMusicalContextId {
        let id = AraMusicalContextId(self.next_musical_context_id);
        self.next_musical_context_id += 1;

        let context = AraMusicalContext {
            id,
            name: name.into(),
            tempo: 120.0,
            time_sig_numerator: 4,
            time_sig_denominator: 4,
            key_signature: 0, // C
            is_minor: false,
        };

        self.musical_contexts.insert(id, context);
        id
    }

    /// Create audio source
    pub fn create_audio_source(
        &mut self,
        name: impl Into<String>,
        persistent_id: impl Into<String>,
        sample_rate: f64,
        channel_count: u32,
        sample_count: u64,
    ) -> AraAudioSourceId {
        let id = AraAudioSourceId(self.next_audio_source_id);
        self.next_audio_source_id += 1;

        let source = AraAudioSource {
            id,
            name: name.into(),
            persistent_id: persistent_id.into(),
            sample_rate,
            channel_count,
            sample_count,
            content_types: AraContentTypes::default(),
            analysis_state: AraAnalysisState::NotAnalyzed,
        };

        self.audio_sources.insert(id, source);
        id
    }

    /// Create audio modification
    pub fn create_audio_modification(
        &mut self,
        name: impl Into<String>,
        persistent_id: impl Into<String>,
        audio_source_id: AraAudioSourceId,
    ) -> Option<AraAudioModificationId> {
        if !self.audio_sources.contains_key(&audio_source_id) {
            return None;
        }

        let id = AraAudioModificationId(self.next_audio_modification_id);
        self.next_audio_modification_id += 1;

        let modification = AraAudioModification {
            id,
            name: name.into(),
            audio_source_id,
            persistent_id: persistent_id.into(),
            transformation: AraPlaybackTransformation::default(),
        };

        self.audio_modifications.insert(id, modification);
        Some(id)
    }

    /// Create region sequence
    pub fn create_region_sequence(
        &mut self,
        name: impl Into<String>,
        musical_context_id: AraMusicalContextId,
    ) -> Option<AraRegionSequenceId> {
        if !self.musical_contexts.contains_key(&musical_context_id) {
            return None;
        }

        let id = AraRegionSequenceId(self.next_region_sequence_id);
        self.next_region_sequence_id += 1;

        let sequence = AraRegionSequence {
            id,
            name: name.into(),
            musical_context_id,
            color: [100, 150, 200],
        };

        self.region_sequences.insert(id, sequence);
        Some(id)
    }

    /// Create playback region
    pub fn create_playback_region(
        &mut self,
        name: impl Into<String>,
        region_sequence_id: AraRegionSequenceId,
        audio_modification_id: AraAudioModificationId,
        start_in_playback_samples: i64,
        duration_in_playback_samples: u64,
    ) -> Option<AraPlaybackRegionId> {
        if !self.region_sequences.contains_key(&region_sequence_id) {
            return None;
        }
        if !self
            .audio_modifications
            .contains_key(&audio_modification_id)
        {
            return None;
        }

        let id = AraPlaybackRegionId(self.next_playback_region_id);
        self.next_playback_region_id += 1;

        let region = AraPlaybackRegion {
            id,
            name: name.into(),
            region_sequence_id,
            audio_modification_id,
            start_in_playback_samples,
            duration_in_playback_samples,
            start_in_modification_samples: 0,
            duration_in_modification_samples: duration_in_playback_samples,
            transformation: AraPlaybackTransformation::default(),
            transformation_flags: AraTransformationFlags::default(),
        };

        self.playback_regions.insert(id, region);
        Some(id)
    }

    /// Update audio source analysis state
    pub fn set_analysis_state(&mut self, source_id: AraAudioSourceId, state: AraAnalysisState) {
        if let Some(source) = self.audio_sources.get_mut(&source_id) {
            source.analysis_state = state;
        }
    }
}

// ============ ARA2 Host Interface ============

/// Trait for ARA audio reader (provides samples to plugin)
pub trait AraAudioReader: Send + Sync {
    /// Read samples from audio source
    fn read_samples(
        &self,
        source_id: AraAudioSourceId,
        channel: u32,
        start_sample: i64,
        samples: &mut [f64],
    ) -> bool;
}

/// Trait for ARA archive reader/writer
pub trait AraArchive: Send + Sync {
    /// Get size of archived data
    fn get_archive_size(&self) -> usize;

    /// Read archived data
    fn read_archive(&self, buffer: &mut [u8]) -> bool;

    /// Write archived data
    fn write_archive(&mut self, data: &[u8]) -> bool;
}

/// ARA host interface for document controller
pub trait AraDocumentController: Send + Sync {
    /// Notify plugin that document properties changed
    fn notify_document_properties_changed(&self);

    /// Notify plugin that musical context was added
    fn notify_musical_context_added(&self, context_id: AraMusicalContextId);

    /// Notify plugin that musical context content changed
    fn notify_musical_context_content_changed(&self, context_id: AraMusicalContextId);

    /// Notify plugin that audio source was added
    fn notify_audio_source_added(&self, source_id: AraAudioSourceId);

    /// Notify plugin that audio source content changed
    fn notify_audio_source_content_changed(&self, source_id: AraAudioSourceId);

    /// Notify plugin that audio modification was added
    fn notify_audio_modification_added(&self, mod_id: AraAudioModificationId);

    /// Notify plugin that playback region was added
    fn notify_playback_region_added(&self, region_id: AraPlaybackRegionId);

    /// Request plugin to analyze audio source
    fn request_audio_source_analysis(&self, source_id: AraAudioSourceId);

    /// Check if source analysis is complete
    fn is_audio_source_analysis_complete(&self, source_id: AraAudioSourceId) -> bool;
}

// ============ ARA2 Plugin Extension ============

/// ARA plugin extension point
#[derive(Debug)]
pub struct AraPluginExtension {
    /// Plugin type
    pub plugin_type: AraPluginType,
    /// Supported content types for analysis
    pub analyzed_content_types: AraContentTypes,
    /// Transformation flags
    pub transformation_flags: AraTransformationFlags,
    /// Supports partial persistence
    pub supports_partial_persistence: bool,
}

impl Default for AraPluginExtension {
    fn default() -> Self {
        Self {
            plugin_type: AraPluginType::AudioModification,
            analyzed_content_types: AraContentTypes::default(),
            transformation_flags: AraTransformationFlags::default(),
            supports_partial_persistence: true,
        }
    }
}

// ============ ARA2 Manager ============

/// Manager for ARA plugin instances
pub struct AraManager {
    documents: HashMap<AraDocumentId, Arc<RwLock<AraDocument>>>,
    next_document_id: u64,
}

impl AraManager {
    pub fn new() -> Self {
        Self {
            documents: HashMap::new(),
            next_document_id: 1,
        }
    }

    /// Create new ARA document
    pub fn create_document(&mut self, name: impl Into<String>) -> AraDocumentId {
        let id = AraDocumentId(self.next_document_id);
        self.next_document_id += 1;

        let document = AraDocument::new(id, name);
        self.documents.insert(id, Arc::new(RwLock::new(document)));
        id
    }

    /// Get document
    pub fn get_document(&self, id: AraDocumentId) -> Option<Arc<RwLock<AraDocument>>> {
        self.documents.get(&id).cloned()
    }

    /// Remove document
    pub fn remove_document(&mut self, id: AraDocumentId) -> bool {
        self.documents.remove(&id).is_some()
    }

    /// List all documents
    pub fn list_documents(&self) -> Vec<AraDocumentId> {
        self.documents.keys().copied().collect()
    }
}

impl Default for AraManager {
    fn default() -> Self {
        Self::new()
    }
}

// ============ ARA2 Note Content ============

/// Note detected by ARA analysis
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AraNote {
    /// Start time in samples (relative to modification)
    pub start_samples: i64,
    /// Duration in samples
    pub duration_samples: u64,
    /// MIDI note number (can be fractional for microtonal)
    pub pitch: f64,
    /// Velocity (0-1)
    pub velocity: f64,
    /// Probability/confidence (0-1)
    pub probability: f64,
}

/// Tempo entry from ARA analysis
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AraTempo {
    /// Position in samples
    pub position_samples: i64,
    /// Tempo in BPM
    pub bpm: f64,
}

/// Bar signature from ARA analysis
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AraBarSignature {
    /// Position in samples
    pub position_samples: i64,
    /// Numerator
    pub numerator: u8,
    /// Denominator
    pub denominator: u8,
}

/// Key signature from ARA analysis
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AraKeySignature {
    /// Position in samples
    pub position_samples: i64,
    /// Root note (0-11 for C-B)
    pub root: u8,
    /// Is minor
    pub is_minor: bool,
}

/// Content analysis result
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct AraContentAnalysis {
    /// Detected notes
    pub notes: Vec<AraNote>,
    /// Tempo map
    pub tempo_map: Vec<AraTempo>,
    /// Bar signatures
    pub bar_signatures: Vec<AraBarSignature>,
    /// Key signatures
    pub key_signatures: Vec<AraKeySignature>,
}

// ============ Tests ============

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ara_document_creation() {
        let mut manager = AraManager::new();
        let doc_id = manager.create_document("Test Project");

        let doc = manager.get_document(doc_id).unwrap();
        let mut doc = doc.write();

        // Create musical context
        let ctx_id = doc.create_musical_context("Main");
        assert!(doc.musical_contexts.contains_key(&ctx_id));

        // Create audio source
        let source_id = doc.create_audio_source("Vocal", "vocal-001", 48000.0, 1, 480000);
        assert!(doc.audio_sources.contains_key(&source_id));

        // Create modification
        let mod_id = doc
            .create_audio_modification("Vocal Mod", "vocal-mod-001", source_id)
            .unwrap();
        assert!(doc.audio_modifications.contains_key(&mod_id));

        // Create region sequence
        let seq_id = doc.create_region_sequence("Track 1", ctx_id).unwrap();
        assert!(doc.region_sequences.contains_key(&seq_id));

        // Create playback region
        let region_id = doc
            .create_playback_region("Verse 1", seq_id, mod_id, 0, 480000)
            .unwrap();
        assert!(doc.playback_regions.contains_key(&region_id));
    }

    #[test]
    fn test_transformation() {
        let mut transform = AraPlaybackTransformation::default();
        assert_eq!(transform.time_stretch_factor, 1.0);
        assert_eq!(transform.pitch_shift_semitones, 0.0);

        transform.pitch_shift_semitones = 2.0; // Up a whole step
        transform.time_stretch_factor = 0.5; // Half speed
    }
}
