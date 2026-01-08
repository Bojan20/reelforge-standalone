//! Audio classification (genre, mood)

use std::path::Path;

use ndarray::Array2;

use crate::error::{MlError, MlResult};
use crate::inference::{InferenceEngine, InferenceConfig};

/// Music genre
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Genre {
    Pop,
    Rock,
    HipHop,
    RnB,
    Electronic,
    House,
    Techno,
    DrumAndBass,
    Dubstep,
    Trance,
    Ambient,
    Jazz,
    Blues,
    Classical,
    Country,
    Folk,
    Metal,
    Punk,
    Reggae,
    Latin,
    World,
    Soundtrack,
    Indie,
    Alternative,
    Soul,
    Funk,
    Disco,
    Gospel,
    NewAge,
    Experimental,
    Other,
}

impl Genre {
    /// Get all genres
    pub fn all() -> &'static [Genre] {
        &[
            Genre::Pop, Genre::Rock, Genre::HipHop, Genre::RnB,
            Genre::Electronic, Genre::House, Genre::Techno,
            Genre::DrumAndBass, Genre::Dubstep, Genre::Trance,
            Genre::Ambient, Genre::Jazz, Genre::Blues, Genre::Classical,
            Genre::Country, Genre::Folk, Genre::Metal, Genre::Punk,
            Genre::Reggae, Genre::Latin, Genre::World, Genre::Soundtrack,
            Genre::Indie, Genre::Alternative, Genre::Soul, Genre::Funk,
            Genre::Disco, Genre::Gospel, Genre::NewAge, Genre::Experimental,
            Genre::Other,
        ]
    }

    /// Get genre name
    pub fn name(&self) -> &'static str {
        match self {
            Genre::Pop => "Pop",
            Genre::Rock => "Rock",
            Genre::HipHop => "Hip-Hop",
            Genre::RnB => "R&B",
            Genre::Electronic => "Electronic",
            Genre::House => "House",
            Genre::Techno => "Techno",
            Genre::DrumAndBass => "Drum & Bass",
            Genre::Dubstep => "Dubstep",
            Genre::Trance => "Trance",
            Genre::Ambient => "Ambient",
            Genre::Jazz => "Jazz",
            Genre::Blues => "Blues",
            Genre::Classical => "Classical",
            Genre::Country => "Country",
            Genre::Folk => "Folk",
            Genre::Metal => "Metal",
            Genre::Punk => "Punk",
            Genre::Reggae => "Reggae",
            Genre::Latin => "Latin",
            Genre::World => "World",
            Genre::Soundtrack => "Soundtrack",
            Genre::Indie => "Indie",
            Genre::Alternative => "Alternative",
            Genre::Soul => "Soul",
            Genre::Funk => "Funk",
            Genre::Disco => "Disco",
            Genre::Gospel => "Gospel",
            Genre::NewAge => "New Age",
            Genre::Experimental => "Experimental",
            Genre::Other => "Other",
        }
    }

    /// From index
    pub fn from_index(idx: usize) -> Self {
        Self::all().get(idx).copied().unwrap_or(Genre::Other)
    }
}

/// Music mood
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Mood {
    Happy,
    Sad,
    Energetic,
    Calm,
    Aggressive,
    Romantic,
    Melancholic,
    Uplifting,
    Dark,
    Dreamy,
    Intense,
    Peaceful,
    Nostalgic,
    Powerful,
    Playful,
    Serious,
    Mysterious,
    Triumphant,
}

impl Mood {
    /// Get all moods
    pub fn all() -> &'static [Mood] {
        &[
            Mood::Happy, Mood::Sad, Mood::Energetic, Mood::Calm,
            Mood::Aggressive, Mood::Romantic, Mood::Melancholic,
            Mood::Uplifting, Mood::Dark, Mood::Dreamy, Mood::Intense,
            Mood::Peaceful, Mood::Nostalgic, Mood::Powerful,
            Mood::Playful, Mood::Serious, Mood::Mysterious, Mood::Triumphant,
        ]
    }

    /// Get mood name
    pub fn name(&self) -> &'static str {
        match self {
            Mood::Happy => "Happy",
            Mood::Sad => "Sad",
            Mood::Energetic => "Energetic",
            Mood::Calm => "Calm",
            Mood::Aggressive => "Aggressive",
            Mood::Romantic => "Romantic",
            Mood::Melancholic => "Melancholic",
            Mood::Uplifting => "Uplifting",
            Mood::Dark => "Dark",
            Mood::Dreamy => "Dreamy",
            Mood::Intense => "Intense",
            Mood::Peaceful => "Peaceful",
            Mood::Nostalgic => "Nostalgic",
            Mood::Powerful => "Powerful",
            Mood::Playful => "Playful",
            Mood::Serious => "Serious",
            Mood::Mysterious => "Mysterious",
            Mood::Triumphant => "Triumphant",
        }
    }

    /// From index
    pub fn from_index(idx: usize) -> Self {
        Self::all().get(idx).copied().unwrap_or(Mood::Calm)
    }
}

/// Genre classifier using neural network
pub struct GenreClassifier {
    /// Inference model
    model: InferenceEngine,

    /// Sample rate expected by model
    sample_rate: u32,

    /// Segment length for analysis (samples)
    segment_length: usize,

    /// Number of mel bands
    n_mels: usize,
}

impl GenreClassifier {
    /// Create new genre classifier
    pub fn new<P: AsRef<Path>>(model_path: P, use_gpu: bool) -> MlResult<Self> {
        let config = InferenceConfig {
            use_gpu,
            ..Default::default()
        };

        let model = InferenceEngine::new(model_path, config)?;

        Ok(Self {
            model,
            sample_rate: 22050, // Common for music classification
            segment_length: 22050 * 3, // 3 seconds
            n_mels: 128,
        })
    }

    /// Classify genre from audio
    pub fn classify(&mut self, audio: &[f32], channels: usize, sample_rate: u32) -> MlResult<Vec<(Genre, f32)>> {
        // Convert to mono
        let mono: Vec<f32> = if channels == 2 {
            audio.chunks(2)
                .map(|c| (c[0] + c.get(1).copied().unwrap_or(0.0)) / 2.0)
                .collect()
        } else {
            audio.to_vec()
        };

        // Resample if needed (simplified)
        let resampled = if sample_rate != self.sample_rate {
            self.resample(&mono, sample_rate, self.sample_rate)
        } else {
            mono
        };

        // Process segments and average
        let num_segments = (resampled.len() / self.segment_length).max(1);
        let mut genre_scores = vec![0.0f32; Genre::all().len()];

        for seg_idx in 0..num_segments {
            let start = seg_idx * self.segment_length;
            let end = (start + self.segment_length).min(resampled.len());

            let segment = &resampled[start..end];

            // Compute mel spectrogram
            let mel = self.compute_mel_spectrogram(segment)?;

            // Run through model
            let scores = self.model.run_array2(&mel)?;

            // Accumulate scores
            for (i, &score) in scores.iter().enumerate() {
                if i < genre_scores.len() {
                    genre_scores[i] += score;
                }
            }
        }

        // Average and softmax
        let avg_scores: Vec<f32> = genre_scores
            .iter()
            .map(|&s| s / num_segments as f32)
            .collect();

        let softmax = Self::softmax(&avg_scores);

        // Create genre/confidence pairs
        let mut results: Vec<(Genre, f32)> = Genre::all()
            .iter()
            .zip(softmax.iter())
            .map(|(&g, &s)| (g, s))
            .collect();

        // Sort by confidence
        results.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

        Ok(results)
    }

    /// Classify mood from audio
    pub fn classify_mood(&mut self, audio: &[f32], channels: usize, sample_rate: u32) -> MlResult<Vec<(Mood, f32)>> {
        // Similar to genre but with mood model
        // For now, return heuristic-based moods from audio features

        let mono: Vec<f32> = if channels == 2 {
            audio.chunks(2)
                .map(|c| (c[0] + c.get(1).copied().unwrap_or(0.0)) / 2.0)
                .collect()
        } else {
            audio.to_vec()
        };

        // Compute simple features
        let rms = (mono.iter().map(|&s| s * s).sum::<f32>() / mono.len() as f32).sqrt();
        let peak = mono.iter().map(|s| s.abs()).fold(0.0f32, f32::max);
        let crest = peak / rms.max(1e-10);

        // Simple heuristics (real implementation would use ML)
        let mut moods = Vec::new();

        if rms > 0.2 && crest < 3.0 {
            moods.push((Mood::Energetic, 0.7));
            moods.push((Mood::Powerful, 0.5));
        } else if rms < 0.05 {
            moods.push((Mood::Calm, 0.7));
            moods.push((Mood::Peaceful, 0.5));
        }

        if crest > 5.0 {
            moods.push((Mood::Dark, 0.4));
        }

        // Default
        if moods.is_empty() {
            moods.push((Mood::Calm, 0.5));
        }

        Ok(moods)
    }

    /// Simple resampling
    fn resample(&self, audio: &[f32], from_rate: u32, to_rate: u32) -> Vec<f32> {
        let ratio = to_rate as f64 / from_rate as f64;
        let new_len = (audio.len() as f64 * ratio) as usize;

        (0..new_len)
            .map(|i| {
                let pos = i as f64 / ratio;
                let idx = pos.floor() as usize;
                let frac = pos - idx as f64;

                let s0 = audio.get(idx).copied().unwrap_or(0.0) as f64;
                let s1 = audio.get(idx + 1).copied().unwrap_or(s0 as f32) as f64;

                (s0 * (1.0 - frac) + s1 * frac) as f32
            })
            .collect()
    }

    /// Compute mel spectrogram (simplified)
    fn compute_mel_spectrogram(&self, audio: &[f32]) -> MlResult<Array2<f32>> {
        // Simplified mel spectrogram
        // Real implementation would use proper STFT + mel filterbank

        let n_frames = audio.len() / 512 + 1;
        let mel = Array2::<f32>::zeros((self.n_mels, n_frames));

        // TODO: Implement proper mel spectrogram
        Ok(mel)
    }

    /// Softmax activation
    fn softmax(x: &[f32]) -> Vec<f32> {
        let max = x.iter().fold(f32::NEG_INFINITY, |a, &b| a.max(b));
        let exp: Vec<f32> = x.iter().map(|&v| (v - max).exp()).collect();
        let sum: f32 = exp.iter().sum();

        exp.iter().map(|&e| e / sum).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_genre_names() {
        assert_eq!(Genre::Pop.name(), "Pop");
        assert_eq!(Genre::DrumAndBass.name(), "Drum & Bass");
    }

    #[test]
    fn test_mood_names() {
        assert_eq!(Mood::Happy.name(), "Happy");
        assert_eq!(Mood::Melancholic.name(), "Melancholic");
    }

    #[test]
    fn test_softmax() {
        let x = vec![1.0, 2.0, 3.0];
        let s = GenreClassifier::softmax(&x);

        // Sum should be 1
        let sum: f32 = s.iter().sum();
        assert!((sum - 1.0).abs() < 0.001);

        // Largest input should have largest output
        assert!(s[2] > s[1]);
        assert!(s[1] > s[0]);
    }
}
