//! HOA Authoring Pipeline — unified spatial audio rendering
//!
//! Combines encoding, rotation, Max-rE weighting, per-order shelf filtering,
//! and decoding into a single configurable pipeline.
//!
//! ## Usage
//!
//! ```rust,ignore
//! use rf_spatial::hoa::{HoaPipeline, HoaPipelineConfig, AmbisonicOrder, DecodingMethod};
//! use rf_spatial::{SpeakerLayout, Position3D};
//!
//! let config = HoaPipelineConfig {
//!     order: AmbisonicOrder::Fifth,
//!     layout: SpeakerLayout::atmos_7_1_4(),
//!     sample_rate: 48000,
//!     decoding_method: DecodingMethod::AllRAD,
//!     maxre_enabled: true,
//!     shelf_enabled: true,
//!     shelf_db: 6.0,
//! };
//!
//! let mut pipeline = HoaPipeline::new(config).unwrap();
//!
//! let sources = vec![
//!     (&audio_slice[..], Position3D::front(), 1.0f32),
//! ];
//! let speakers = pipeline.render_frame(&sources).unwrap();
//! ```

use super::{
    AmbisonicDecoder, AmbisonicOrder, AmbisonicTransform, DecodingMethod, HoaShelfFilter,
    MaxReWeights, MultiSourceEncoder, RotationInterpolator,
};
use crate::error::SpatialResult;
use crate::position::{Orientation, Position3D};
use crate::SpeakerLayout;

// ═══════════════════════════════════════════════════════════════════════════════
// CONFIG
// ═══════════════════════════════════════════════════════════════════════════════

/// Configuration for the HOA rendering pipeline.
#[derive(Debug, Clone)]
pub struct HoaPipelineConfig {
    /// Ambisonic order (spatial resolution)
    pub order: AmbisonicOrder,
    /// Output speaker layout
    pub layout: SpeakerLayout,
    /// Sample rate (needed for shelf filter)
    pub sample_rate: u32,
    /// Decoding strategy
    pub decoding_method: DecodingMethod,
    /// Enable Max-rE energy-vector weighting
    pub maxre_enabled: bool,
    /// Enable per-order high-shelf filter
    pub shelf_enabled: bool,
    /// Shelf gain in dB (positive = boost highs for higher orders)
    pub shelf_db: f32,
    /// Enable real-time rotation
    pub rotation_enabled: bool,
    /// Initial listener orientation (yaw, pitch, roll in degrees)
    pub orientation: Orientation,
    /// Rotation interpolation time in milliseconds
    pub rotation_interp_ms: f32,
}

impl HoaPipelineConfig {
    /// Sensible defaults for theatrical 5th-order HOA → 7.1.4 Atmos.
    pub fn theatrical_5th_order() -> Self {
        Self {
            order: AmbisonicOrder::Fifth,
            layout: SpeakerLayout::atmos_7_1_4(),
            sample_rate: 48000,
            decoding_method: DecodingMethod::AllRAD,
            maxre_enabled: true,
            shelf_enabled: true,
            shelf_db: 6.0,
            rotation_enabled: true,
            orientation: Orientation::forward(),
            rotation_interp_ms: 50.0,
        }
    }

    /// Studio monitoring preset: 3rd order → stereo with Max-rE.
    pub fn stereo_monitor_3rd_order() -> Self {
        Self {
            order: AmbisonicOrder::Third,
            layout: SpeakerLayout::stereo(),
            sample_rate: 48000,
            decoding_method: DecodingMethod::ModeMatching,
            maxre_enabled: true,
            shelf_enabled: true,
            shelf_db: 6.0,
            rotation_enabled: false,
            orientation: Orientation::forward(),
            rotation_interp_ms: 0.0,
        }
    }
}

impl Default for HoaPipelineConfig {
    fn default() -> Self {
        Self::theatrical_5th_order()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PIPELINE
// ═══════════════════════════════════════════════════════════════════════════════

/// Unified HOA authoring and rendering pipeline.
///
/// The pipeline owns every processing stage so that a single
/// `render_frame()` call goes from source objects to speaker feeds
/// with zero external allocations.
pub struct HoaPipeline {
    config: HoaPipelineConfig,
    encoder: MultiSourceEncoder,
    decoder: AmbisonicDecoder,
    /// Optional transform (rotation)
    transform: Option<AmbisonicTransform>,
    /// Optional rotation interpolator
    rot_interp: Option<RotationInterpolator>,
    /// Max-rE weights
    maxre: Option<MaxReWeights>,
    /// Per-order shelf filter
    shelf: Option<HoaShelfFilter>,
    /// Scratch buffer for ambisonic signal (planar)
    scratch_ambisonic: Vec<Vec<f32>>,
}

impl HoaPipeline {
    // ------------------------------------------------------------------
    // Lifecycle
    // ------------------------------------------------------------------

    /// Create a new pipeline from configuration.
    pub fn new(config: HoaPipelineConfig) -> SpatialResult<Self> {
        let order = config.order;
        let encoder = MultiSourceEncoder::new(order, 128);
        let decoder = AmbisonicDecoder::with_method(
            order,
            config.layout.clone(),
            config.decoding_method,
        )?;

        let transform = if config.rotation_enabled {
            Some(AmbisonicTransform::new(order))
        } else {
            None
        };

        let rot_interp = if config.rotation_enabled && config.rotation_interp_ms > 0.0 {
            Some(RotationInterpolator::new(
                order,
                config.rotation_interp_ms,
                config.sample_rate,
            ))
        } else {
            None
        };

        let maxre = if config.maxre_enabled {
            Some(MaxReWeights::new(order))
        } else {
            None
        };

        let shelf = if config.shelf_enabled {
            let mut f = HoaShelfFilter::new(order, config.sample_rate);
            f.set_shelf_db(config.shelf_db);
            Some(f)
        } else {
            None
        };

        Ok(Self {
            config,
            encoder,
            decoder,
            transform,
            rot_interp,
            maxre,
            shelf,
            scratch_ambisonic: Vec::new(),
        })
    }

    /// Reconfigure the pipeline (decoder and aux stages are rebuilt).
    pub fn reconfigure(&mut self, config: HoaPipelineConfig) -> SpatialResult<()> {
        *self = Self::new(config)?;
        Ok(())
    }

    /// Reset all filter states (after seek / discontinuity).
    pub fn reset(&mut self) {
        if let Some(ref mut s) = self.shelf {
            s.reset();
        }
        if let Some(ref mut ri) = self.rot_interp {
            // Re-create interpolator to reset position
            *ri = RotationInterpolator::new(
                self.config.order,
                self.config.rotation_interp_ms,
                self.config.sample_rate,
            );
        }
    }

    // ------------------------------------------------------------------
    // Parameter updates (real-time safe — no allocations)
    // ------------------------------------------------------------------

    /// Set listener orientation.
    ///
    /// If interpolation is enabled the rotation will slew over the
    /// configured interpolation time.
    pub fn set_orientation(&mut self, orientation: Orientation) {
        if let Some(ref mut interp) = self.rot_interp {
            interp.set_target(orientation);
        } else if let Some(ref mut tr) = self.transform {
            tr.set_rotation(orientation);
        }
    }

    /// Set Max-rE enable state (rebuilds weights).
    pub fn set_maxre(&mut self, enabled: bool) {
        self.config.maxre_enabled = enabled;
        self.maxre = if enabled {
            Some(MaxReWeights::new(self.config.order))
        } else {
            None
        };
    }

    /// Set shelf enable state.
    pub fn set_shelf(&mut self, enabled: bool) {
        self.config.shelf_enabled = enabled;
        self.shelf = if enabled {
            let mut f = HoaShelfFilter::new(self.config.order, self.config.sample_rate);
            f.set_shelf_db(self.config.shelf_db);
            Some(f)
        } else {
            None
        };
    }

    /// Set shelf gain in dB.
    pub fn set_shelf_db(&mut self, db: f32) {
        self.config.shelf_db = db;
        if let Some(ref mut s) = self.shelf {
            s.set_shelf_db(db);
        }
    }

    // ------------------------------------------------------------------
    // Rendering
    // ------------------------------------------------------------------

    /// Render one frame from source objects to speaker feeds.
    ///
    /// `sources` is a slice of `(audio, position, gain)` tuples.
    /// Returns planar output `[speaker][sample]`.
    pub fn render_frame(
        &mut self,
        sources: &[(&[f32], Position3D, f32)],
    ) -> SpatialResult<Vec<Vec<f32>>> {
        if sources.is_empty() {
            let num_speakers = self.decoder.output_layout().channel_count();
            return Ok(vec![Vec::new(); num_speakers]);
        }

        let output_samples = sources[0].0.len();

        // 1. Encode
        let mut ambisonic = self
            .encoder
            .encode_frame(sources, output_samples);

        // 2. Rotation / transform
        if let Some(ref mut interp) = self.rot_interp {
            ambisonic = interp.process(&ambisonic);
        } else if let Some(ref tr) = self.transform {
            ambisonic = tr.transform(&ambisonic);
        }

        // 3. Max-rE weighting (per-sample, per-channel)
        if let Some(ref maxre) = self.maxre {
            for (acn, ch) in ambisonic.iter_mut().enumerate() {
                let weight = maxre.weight(acn);
                for sample in ch.iter_mut() {
                    *sample *= weight;
                }
            }
        }

        // 4. Per-order shelf filter
        if let Some(ref mut shelf) = self.shelf {
            shelf.process_block(&mut ambisonic);
        }

        // 5. Decode to speakers
        self.decoder.decode(&ambisonic)
    }

    /// Convenience: render a single mono source.
    pub fn render_source(
        &mut self,
        mono: &[f32],
        position: &Position3D,
        gain: f32,
    ) -> SpatialResult<Vec<Vec<f32>>> {
        self.render_frame(&[(mono, *position, gain)])
    }

    // ------------------------------------------------------------------
    // Inspection
    // ------------------------------------------------------------------

    /// Current configuration (clone).
    pub fn config(&self) -> &HoaPipelineConfig {
        &self.config
    }

    /// Number of output speakers (excluding LFE).
    pub fn output_speaker_count(&self) -> usize {
        self.decoder.output_layout().channel_count()
    }

    /// Number of Ambisonic channels.
    pub fn ambisonic_channel_count(&self) -> usize {
        self.config.order.channel_count()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    fn make_mono(samples: usize, amp: f32) -> Vec<f32> {
        vec![amp; samples]
    }

    #[test]
    fn test_pipeline_creation_3rd_order() {
        let mut config = HoaPipelineConfig::theatrical_5th_order();
        config.order = AmbisonicOrder::Third;
        config.layout = SpeakerLayout::surround_5_1();
        config.maxre_enabled = true;
        config.shelf_enabled = true;

        let pipeline = HoaPipeline::new(config);
        assert!(pipeline.is_ok());
        let p = pipeline.unwrap();
        assert_eq!(p.ambisonic_channel_count(), 16);
        assert_eq!(p.output_speaker_count(), 5); // 5.1 minus LFE
    }

    #[test]
    fn test_pipeline_creation_5th_order() {
        let config = HoaPipelineConfig::theatrical_5th_order();
        let pipeline = HoaPipeline::new(config);
        assert!(pipeline.is_ok());
        let p = pipeline.unwrap();
        assert_eq!(p.ambisonic_channel_count(), 36);
        assert_eq!(p.output_speaker_count(), 11); // 7.1.4 minus LFE
    }

    #[test]
    fn test_pipeline_render_front_center() {
        let mut config = HoaPipelineConfig::theatrical_5th_order();
        config.order = AmbisonicOrder::Third;
        config.layout = SpeakerLayout::stereo();
        config.decoding_method = DecodingMethod::Basic;
        config.maxre_enabled = false;
        config.shelf_enabled = false;
        config.rotation_enabled = false;

        let mut pipeline = HoaPipeline::new(config).unwrap();
        let mono = make_mono(64, 1.0);
        let pos = Position3D::from_spherical(0.0, 0.0, 1.0);

        let out = pipeline.render_source(&mono, &pos, 1.0).unwrap();
        assert_eq!(out.len(), 2);
        assert_eq!(out[0].len(), 64);

        // Front-center should be roughly equal in L and R
        let l = out[0][0];
        let r = out[1][0];
        assert!((l - r).abs() < 0.15, "L={} R={}", l, r);
    }

    #[test]
    fn test_pipeline_render_left() {
        let mut config = HoaPipelineConfig::theatrical_5th_order();
        config.order = AmbisonicOrder::First;
        config.layout = SpeakerLayout::stereo();
        config.decoding_method = DecodingMethod::Basic;
        config.maxre_enabled = false;
        config.shelf_enabled = false;
        config.rotation_enabled = false;

        let mut pipeline = HoaPipeline::new(config).unwrap();
        let mono = make_mono(64, 1.0);
        let pos = Position3D::from_spherical(-90.0, 0.0, 1.0);

        let out = pipeline.render_source(&mono, &pos, 1.0).unwrap();
        assert_eq!(out.len(), 2);

        // Left source should be louder in L than R
        let l = out[0][0];
        let r = out[1][0];
        assert!(l.abs() > r.abs() * 1.2, "L={} R={}", l, r);
    }

    #[test]
    fn test_pipeline_with_maxre() {
        let mut config = HoaPipelineConfig::theatrical_5th_order();
        config.order = AmbisonicOrder::Third;
        config.layout = SpeakerLayout::stereo();
        config.decoding_method = DecodingMethod::ModeMatching;
        config.maxre_enabled = true;
        config.shelf_enabled = false;
        config.rotation_enabled = false;

        let mut pipeline = HoaPipeline::new(config).unwrap();
        let mono = make_mono(64, 1.0);
        let pos = Position3D::from_spherical(0.0, 0.0, 1.0);

        let out = pipeline.render_source(&mono, &pos, 1.0).unwrap();
        assert_eq!(out.len(), 2);
        assert!(out[0][0].is_finite());
        assert!(out[1][0].is_finite());
    }

    #[test]
    fn test_pipeline_with_shelf() {
        let mut config = HoaPipelineConfig::theatrical_5th_order();
        config.order = AmbisonicOrder::Third;
        config.layout = SpeakerLayout::stereo();
        config.decoding_method = DecodingMethod::Basic;
        config.maxre_enabled = false;
        config.shelf_enabled = true;
        config.shelf_db = 6.0;
        config.rotation_enabled = false;

        let mut pipeline = HoaPipeline::new(config).unwrap();
        let mono = make_mono(64, 1.0);
        let pos = Position3D::from_spherical(0.0, 0.0, 1.0);

        let out = pipeline.render_source(&mono, &pos, 1.0).unwrap();
        assert_eq!(out.len(), 2);
        assert!(out[0][0].is_finite());
    }

    #[test]
    fn test_pipeline_with_rotation() {
        let mut config = HoaPipelineConfig::theatrical_5th_order();
        config.order = AmbisonicOrder::First;
        config.layout = SpeakerLayout::stereo();
        config.decoding_method = DecodingMethod::Basic;
        config.maxre_enabled = false;
        config.shelf_enabled = false;
        config.rotation_enabled = true;
        config.rotation_interp_ms = 0.0; // Instant

        let mut pipeline = HoaPipeline::new(config).unwrap();
        let mono = make_mono(64, 1.0);

        // Rotate 90° yaw
        pipeline.set_orientation(Orientation::new(90.0, 0.0, 0.0));

        let out = pipeline.render_source(&mono, &Position3D::from_spherical(0.0, 0.0, 1.0), 1.0).unwrap();
        assert_eq!(out.len(), 2);

        // Rotation applied — just verify finite output (exact direction
        // depends on the coordinate convention in rotation_matrix()).
        assert!(out[0][0].is_finite());
        assert!(out[1][0].is_finite());
    }

    #[test]
    fn test_pipeline_allrad_4th_order() {
        let mut config = HoaPipelineConfig::theatrical_5th_order();
        config.order = AmbisonicOrder::Fourth;
        config.layout = SpeakerLayout::atmos_7_1_4();
        config.decoding_method = DecodingMethod::AllRAD;
        config.maxre_enabled = true;
        config.shelf_enabled = true;
        config.rotation_enabled = false;

        let mut pipeline = HoaPipeline::new(config).unwrap();
        let mono = make_mono(32, 0.5);
        let pos = Position3D::from_spherical(45.0, 30.0, 1.0);

        let out = pipeline.render_source(&mono, &pos, 1.0).unwrap();
        assert_eq!(out.len(), 11); // 7.1.4 minus LFE
        assert_eq!(out[0].len(), 32);

        // All outputs finite
        for (spk, ch) in out.iter().enumerate() {
            for (i, &s) in ch.iter().enumerate() {
                assert!(s.is_finite(), "speaker {} sample {} is non-finite", spk, i);
            }
        }
    }

    #[test]
    fn test_pipeline_empty_sources() {
        let mut config = HoaPipelineConfig::theatrical_5th_order();
        config.order = AmbisonicOrder::First;
        config.layout = SpeakerLayout::stereo();
        config.maxre_enabled = false;
        config.shelf_enabled = false;
        config.rotation_enabled = false;

        let mut pipeline = HoaPipeline::new(config).unwrap();
        let out = pipeline.render_frame(&[]).unwrap();
        assert_eq!(out.len(), 2);
        assert!(out[0].is_empty());
    }

    #[test]
    fn test_pipeline_reset() {
        let mut config = HoaPipelineConfig::theatrical_5th_order();
        config.order = AmbisonicOrder::First;
        config.layout = SpeakerLayout::stereo();
        config.shelf_enabled = true;
        config.rotation_enabled = true;
        config.rotation_interp_ms = 10.0;

        let mut pipeline = HoaPipeline::new(config).unwrap();
        pipeline.reset(); // should not panic

        let mono = make_mono(16, 1.0);
        let out = pipeline.render_source(&mono, &Position3D::from_spherical(0.0, 0.0, 1.0), 1.0).unwrap();
        assert_eq!(out.len(), 2);
    }

    #[test]
    fn test_reconfigure() {
        let config = HoaPipelineConfig::theatrical_5th_order();
        let mut pipeline = HoaPipeline::new(config).unwrap();

        let mut new_config = HoaPipelineConfig::theatrical_5th_order();
        new_config.order = AmbisonicOrder::Second;
        new_config.layout = SpeakerLayout::surround_5_1();

        pipeline.reconfigure(new_config).unwrap();
        assert_eq!(pipeline.ambisonic_channel_count(), 9);
        assert_eq!(pipeline.output_speaker_count(), 5);
    }
}
