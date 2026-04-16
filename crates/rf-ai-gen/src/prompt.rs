//! T8.1: Text prompt → audio descriptor parser.
//!
//! Converts free-text audio descriptions into structured AudioDescriptor objects.
//! Uses keyword-matching and rule-based NLP — zero external dependencies.
//!
//! Design principle: SLOT DOMAIN FIRST. All rules tuned for slot game audio.

use serde::{Deserialize, Serialize};

/// Emotional tone of the audio
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum AudioMood {
    Epic,
    Celebratory,
    Tense,
    Relaxed,
    Mysterious,
    Playful,
    Dramatic,
    Neutral,
}

/// Musical / sound design style
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum AudioStyle {
    Orchestral,
    Electronic,
    Retro8Bit,
    Cinematic,
    Jazz,
    Latin,
    Asian,
    Medieval,
    Mechanical,
    Ambient,
    Coin,
    Sparkle,
    Percussion,
    Unknown,
}

/// Instrument hints for generation
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum InstrumentHint {
    Brass,
    Strings,
    Piano,
    Guitar,
    Drums,
    Synthesizer,
    Marimba,
    Bells,
    Choir,
    Coin,
    Mechanical,
}

/// Slot audio event category
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum EventCategory {
    Win,
    BaseGame,
    Feature,
    Jackpot,
    Ambient,
    UI,
    Transition,
    NearMiss,
}

impl EventCategory {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Win => "Win",
            Self::BaseGame => "BaseGame",
            Self::Feature => "Feature",
            Self::Jackpot => "Jackpot",
            Self::Ambient => "Ambient",
            Self::UI => "UI",
            Self::Transition => "Transition",
            Self::NearMiss => "NearMiss",
        }
    }
}

/// Audio tier (matches slot quality tiers)
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum AudioTier {
    /// Subtle, minimal impact
    Subtle,
    /// Standard quality
    Standard,
    /// Premium quality
    Premium,
    /// Flagship, maximum impact
    Flagship,
}

impl AudioTier {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Subtle => "subtle",
            Self::Standard => "standard",
            Self::Premium => "premium",
            Self::Flagship => "flagship",
        }
    }
}

/// Structured audio descriptor extracted from a text prompt (T8.1)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioDescriptor {
    /// Original prompt text
    pub prompt: String,
    /// Detected event category
    pub category: EventCategory,
    /// Audio tier (quality/impact level)
    pub tier: AudioTier,
    /// Estimated duration in milliseconds (0 = infer from type)
    pub duration_ms: u32,
    /// Suggested voice count (polyphony layers)
    pub voice_count: u8,
    /// Whether the audio should loop
    pub can_loop: bool,
    /// Whether this event is required (essential for gameplay)
    pub is_required: bool,
    /// Emotional mood
    pub mood: AudioMood,
    /// Sound design style
    pub style: AudioStyle,
    /// Instrument hints
    pub instruments: Vec<InstrumentHint>,
    /// Tempo in BPM (0 = atonal/non-rhythmic)
    pub tempo_bpm: u32,
    /// Additional generation tags (keywords for the AI model)
    pub generation_tags: Vec<String>,
    /// Confidence score (0.0–1.0) of the extraction
    pub confidence: f64,
}

impl AudioDescriptor {
    /// Generate a natural-language description for the AI backend
    pub fn to_generation_prompt(&self) -> String {
        let mut parts = Vec::new();

        // Style prefix
        match &self.style {
            AudioStyle::Orchestral => parts.push("orchestral".to_string()),
            AudioStyle::Electronic => parts.push("electronic".to_string()),
            AudioStyle::Retro8Bit => parts.push("8-bit chiptune".to_string()),
            AudioStyle::Cinematic => parts.push("cinematic".to_string()),
            AudioStyle::Jazz => parts.push("jazz".to_string()),
            AudioStyle::Latin => parts.push("latin".to_string()),
            AudioStyle::Asian => parts.push("asian instrumental".to_string()),
            AudioStyle::Medieval => parts.push("medieval fantasy".to_string()),
            AudioStyle::Mechanical => parts.push("mechanical".to_string()),
            AudioStyle::Ambient => parts.push("ambient".to_string()),
            _ => {}
        }

        // Mood
        match &self.mood {
            AudioMood::Epic => parts.push("epic".to_string()),
            AudioMood::Celebratory => parts.push("celebratory".to_string()),
            AudioMood::Tense => parts.push("tense building".to_string()),
            AudioMood::Relaxed => parts.push("relaxed".to_string()),
            AudioMood::Mysterious => parts.push("mysterious".to_string()),
            AudioMood::Playful => parts.push("playful upbeat".to_string()),
            AudioMood::Dramatic => parts.push("dramatic".to_string()),
            AudioMood::Neutral => {}
        }

        // Category-specific phrasing
        let cat_phrase = match &self.category {
            EventCategory::Win => "winning fanfare sound effect",
            EventCategory::Jackpot => "jackpot celebration sound effect with coins",
            EventCategory::BaseGame => "slot machine sound effect",
            EventCategory::Feature => "bonus feature trigger sound effect",
            EventCategory::Ambient => "casino ambient music loop",
            EventCategory::UI => "UI click sound effect",
            EventCategory::Transition => "transition whoosh sound effect",
            EventCategory::NearMiss => "near miss tense sound effect",
        };
        parts.push(cat_phrase.to_string());

        // Instruments
        if !self.instruments.is_empty() {
            let inst_str: Vec<&str> = self.instruments.iter().map(|i| match i {
                InstrumentHint::Brass => "brass",
                InstrumentHint::Strings => "strings",
                InstrumentHint::Piano => "piano",
                InstrumentHint::Guitar => "guitar",
                InstrumentHint::Drums => "drums",
                InstrumentHint::Synthesizer => "synth",
                InstrumentHint::Marimba => "marimba",
                InstrumentHint::Bells => "bells",
                InstrumentHint::Choir => "choir",
                InstrumentHint::Coin => "coin sounds",
                InstrumentHint::Mechanical => "mechanical ratchet",
            }).collect();
            parts.push(format!("with {}", inst_str.join(", ")));
        }

        // Duration hint
        if self.duration_ms > 0 {
            let secs = self.duration_ms / 1000;
            if secs > 0 {
                parts.push(format!("{} seconds", secs));
            }
        }

        // Custom generation tags
        parts.extend(self.generation_tags.iter().cloned());

        parts.join(" ")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// PromptParser
// ─────────────────────────────────────────────────────────────────────────────

/// Rule-based text prompt parser for slot audio descriptions.
///
/// Maps natural language → AudioDescriptor using keyword matching.
/// Designed for slot domain — all rules tuned for iGaming audio.
pub struct PromptParser;

impl PromptParser {
    /// Parse a text prompt into an AudioDescriptor.
    pub fn parse(prompt: &str) -> AudioDescriptor {
        let lower = prompt.to_lowercase();
        let tokens: Vec<&str> = lower.split_whitespace().collect();

        let category = Self::detect_category(&lower, &tokens);
        let tier = Self::detect_tier(&lower, &tokens, &category);
        let mood = Self::detect_mood(&lower, &tokens);
        let style = Self::detect_style(&lower, &tokens);
        let instruments = Self::detect_instruments(&lower);
        let can_loop = Self::detect_loop(&lower, &tokens);
        let duration_ms = Self::estimate_duration(&category, &tier, can_loop, &lower);
        let voice_count = Self::estimate_voice_count(&category, &tier);
        let is_required = Self::detect_required(&category);
        let tempo_bpm = Self::detect_tempo(&lower, &mood);
        let generation_tags = Self::extract_tags(&lower);
        let confidence = Self::compute_confidence(&tokens, &category, &style);

        AudioDescriptor {
            prompt: prompt.to_string(),
            category,
            tier,
            duration_ms,
            voice_count,
            can_loop,
            is_required,
            mood,
            style,
            instruments,
            tempo_bpm,
            generation_tags,
            confidence,
        }
    }

    fn detect_category(lower: &str, tokens: &[&str]) -> EventCategory {
        // Near-miss FIRST (before win check — "almost winning" contains "win")
        if lower.contains("near miss") || lower.contains("near-miss") || lower.contains("near_miss")
            || lower.contains("almost") && (lower.contains("won") || lower.contains("winning")) {
            return EventCategory::NearMiss;
        }
        // Jackpot — only explicit jackpot keyword (not "mega win" which is a win tier)
        if lower.contains("jackpot") {
            return EventCategory::Jackpot;
        }
        // Base game with reel/mechanical BEFORE UI click (reel stop has "stop" and "click")
        if lower.contains("reel") || lower.contains("mechanical") && !lower.contains("win") {
            return EventCategory::BaseGame;
        }
        // Win signals
        if lower.contains("win") || lower.contains("fanfare") || lower.contains("celebration")
            || lower.contains("victory") || lower.contains("triumph") {
            return EventCategory::Win;
        }
        // Feature/bonus
        if lower.contains("bonus") || lower.contains("feature") || lower.contains("free spin")
            || lower.contains("trigger") || lower.contains("scatter") {
            return EventCategory::Feature;
        }
        // Ambient/music
        if lower.contains("ambient") || lower.contains("background") || lower.contains("music")
            || lower.contains("loop") || lower.contains("atmosphere") || lower.contains("bed") {
            return EventCategory::Ambient;
        }
        // UI — only if no reel/mechanical context
        if (lower.contains("click") || lower.contains("button") || lower.contains("tap")
            || lower.contains("ui ") || lower.contains("press"))
            && !lower.contains("reel") && !lower.contains("mechanical") {
            return EventCategory::UI;
        }
        // Transition
        if lower.contains("transition") || lower.contains("whoosh") || lower.contains("sweep")
            || lower.contains("reveal") {
            return EventCategory::Transition;
        }
        // Base game (spin, stop, slot)
        if lower.contains("spin") || lower.contains("stop") || lower.contains("slot") {
            return EventCategory::BaseGame;
        }
        // Default: base game
        let _ = tokens;
        EventCategory::BaseGame
    }

    fn detect_tier(lower: &str, _tokens: &[&str], category: &EventCategory) -> AudioTier {
        // Explicit tier keywords
        if lower.contains("flagship") || lower.contains("mega") || lower.contains("super")
            || lower.contains("ultimate") || lower.contains("grand") || lower.contains("maximum") {
            return AudioTier::Flagship;
        }
        if lower.contains("premium") || lower.contains("major") || lower.contains("big win")
            || lower.contains("high quality") || lower.contains("cinematic") {
            return AudioTier::Premium;
        }
        if lower.contains("subtle") || lower.contains("minimal") || lower.contains("soft")
            || lower.contains("quiet") || lower.contains("click") || lower.contains("tick") {
            return AudioTier::Subtle;
        }

        // Category-based default tiers
        match category {
            EventCategory::Jackpot   => AudioTier::Flagship,
            EventCategory::Win       => AudioTier::Standard,
            EventCategory::Feature   => AudioTier::Premium,
            EventCategory::NearMiss  => AudioTier::Subtle,
            EventCategory::Ambient   => AudioTier::Standard,
            EventCategory::UI        => AudioTier::Subtle,
            EventCategory::Transition => AudioTier::Subtle,
            EventCategory::BaseGame  => AudioTier::Subtle,
        }
    }

    fn detect_mood(lower: &str, _tokens: &[&str]) -> AudioMood {
        if lower.contains("epic") || lower.contains("powerful") || lower.contains("massive") {
            return AudioMood::Epic;
        }
        if lower.contains("celebrat") || lower.contains("celebratory") || lower.contains("festive")
            || lower.contains("happy") || lower.contains("joyful") {
            return AudioMood::Celebratory;
        }
        if lower.contains("tense") || lower.contains("suspense") || lower.contains("anxiety")
            || lower.contains("thrilling") || lower.contains("building") {
            return AudioMood::Tense;
        }
        if lower.contains("relaxed") || lower.contains("calm") || lower.contains("peaceful")
            || lower.contains("gentle") || lower.contains("chill") {
            return AudioMood::Relaxed;
        }
        if lower.contains("mysterious") || lower.contains("dark") || lower.contains("eerie")
            || lower.contains("ominous") {
            return AudioMood::Mysterious;
        }
        if lower.contains("playful") || lower.contains("fun") || lower.contains("whimsical")
            || lower.contains("quirky") || lower.contains("cartoon") {
            return AudioMood::Playful;
        }
        if lower.contains("dramatic") || lower.contains("intense") || lower.contains("climax") {
            return AudioMood::Dramatic;
        }
        AudioMood::Neutral
    }

    fn detect_style(lower: &str, _tokens: &[&str]) -> AudioStyle {
        if lower.contains("orchestral") || lower.contains("orchestra")
            || lower.contains("symphony") || lower.contains("classical") {
            return AudioStyle::Orchestral;
        }
        if lower.contains("electronic") || lower.contains("synth") || lower.contains("edm")
            || lower.contains("electronic") {
            return AudioStyle::Electronic;
        }
        if lower.contains("8-bit") || lower.contains("8 bit") || lower.contains("chiptune")
            || lower.contains("retro") || lower.contains("pixel") {
            return AudioStyle::Retro8Bit;
        }
        if lower.contains("cinematic") || lower.contains("blockbuster") || lower.contains("film") {
            return AudioStyle::Cinematic;
        }
        if lower.contains("jazz") || lower.contains("swing") || lower.contains("blues") {
            return AudioStyle::Jazz;
        }
        if lower.contains("latin") || lower.contains("salsa") || lower.contains("samba")
            || lower.contains("mariachi") {
            return AudioStyle::Latin;
        }
        if lower.contains("asian") || lower.contains("chinese") || lower.contains("japanese")
            || lower.contains("oriental") || lower.contains("erhu") || lower.contains("koto") {
            return AudioStyle::Asian;
        }
        if lower.contains("medieval") || lower.contains("fantasy") || lower.contains("celtic")
            || lower.contains("lute") || lower.contains("tavern") {
            return AudioStyle::Medieval;
        }
        if lower.contains("mechanical") || lower.contains("reel") || lower.contains("click")
            || lower.contains("ratchet") {
            return AudioStyle::Mechanical;
        }
        if lower.contains("ambient") || lower.contains("atmospheric") || lower.contains("drone") {
            return AudioStyle::Ambient;
        }
        if lower.contains("coin") || lower.contains("money") || lower.contains("credits") {
            return AudioStyle::Coin;
        }
        if lower.contains("sparkle") || lower.contains("twinkle") || lower.contains("shimmer") {
            return AudioStyle::Sparkle;
        }
        AudioStyle::Unknown
    }

    fn detect_instruments(lower: &str) -> Vec<InstrumentHint> {
        let mut hints = Vec::new();
        if lower.contains("brass") || lower.contains("trumpet") || lower.contains("trombone")
            || lower.contains("horn") { hints.push(InstrumentHint::Brass); }
        if lower.contains("string") || lower.contains("violin") || lower.contains("cello")
            || lower.contains("orchestra") { hints.push(InstrumentHint::Strings); }
        if lower.contains("piano") || lower.contains("keyboard") { hints.push(InstrumentHint::Piano); }
        if lower.contains("guitar") { hints.push(InstrumentHint::Guitar); }
        if lower.contains("drum") || lower.contains("percussion") || lower.contains("beat")
            || lower.contains("rhythm") { hints.push(InstrumentHint::Drums); }
        if lower.contains("synth") || lower.contains("electronic") { hints.push(InstrumentHint::Synthesizer); }
        if lower.contains("marimba") || lower.contains("xylophone") || lower.contains("vibraphone")
            { hints.push(InstrumentHint::Marimba); }
        if lower.contains("bell") || lower.contains("chime") || lower.contains("sparkle")
            || lower.contains("twinkle") { hints.push(InstrumentHint::Bells); }
        if lower.contains("choir") || lower.contains("vocal") || lower.contains("ah") || lower.contains("ooh")
            { hints.push(InstrumentHint::Choir); }
        if lower.contains("coin") || lower.contains("money") || lower.contains("rattle")
            { hints.push(InstrumentHint::Coin); }
        if lower.contains("mechanical") || lower.contains("ratchet") || lower.contains("click")
            { hints.push(InstrumentHint::Mechanical); }
        hints
    }

    fn detect_loop(lower: &str, tokens: &[&str]) -> bool {
        lower.contains("loop") || lower.contains("looping") || lower.contains("cycl")
            || lower.contains("continuous") || lower.contains("ambient") || lower.contains("bed")
            || tokens.contains(&"repeat")
    }

    fn estimate_duration(category: &EventCategory, tier: &AudioTier, can_loop: bool, lower: &str) -> u32 {
        // Explicit duration keywords
        if lower.contains("short") || lower.contains("quick") || lower.contains("brief") {
            return match category {
                EventCategory::UI => 100,
                _ => 500,
            };
        }
        if lower.contains("long") || lower.contains("extended") {
            return match category {
                EventCategory::Ambient => 0, // loop, no fixed duration
                EventCategory::Win => 12_000,
                _ => 8_000,
            };
        }

        if can_loop { return 0; } // looping = no fixed duration

        match (category, tier) {
            (EventCategory::UI, _) => 100,
            (EventCategory::BaseGame, AudioTier::Subtle) => 150,
            (EventCategory::BaseGame, _) => 500,
            (EventCategory::Transition, _) => 800,
            (EventCategory::NearMiss, _) => 2_000,
            (EventCategory::Win, AudioTier::Subtle) => 1_000,
            (EventCategory::Win, AudioTier::Standard) => 3_000,
            (EventCategory::Win, AudioTier::Premium) => 6_000,
            (EventCategory::Win, AudioTier::Flagship) => 10_000,
            (EventCategory::Feature, _) => 4_000,
            (EventCategory::Jackpot, _) => 12_000,
            (EventCategory::Ambient, _) => 0, // loop
        }
    }

    fn estimate_voice_count(category: &EventCategory, tier: &AudioTier) -> u8 {
        match (category, tier) {
            (EventCategory::UI, _) => 1,
            (EventCategory::BaseGame, AudioTier::Subtle) => 1,
            (EventCategory::BaseGame, _) => 2,
            (EventCategory::NearMiss, _) => 2,
            (EventCategory::Transition, _) => 2,
            (EventCategory::Win, AudioTier::Subtle) => 2,
            (EventCategory::Win, AudioTier::Standard) => 3,
            (EventCategory::Win, AudioTier::Premium) => 5,
            (EventCategory::Win, AudioTier::Flagship) => 6,
            (EventCategory::Feature, _) => 4,
            (EventCategory::Jackpot, _) => 8,
            (EventCategory::Ambient, _) => 4,
        }
    }

    fn detect_required(category: &EventCategory) -> bool {
        matches!(category, EventCategory::BaseGame | EventCategory::Win | EventCategory::UI)
    }

    fn detect_tempo(lower: &str, mood: &AudioMood) -> u32 {
        if lower.contains("fast") || lower.contains("energetic") || lower.contains("upbeat") {
            return 140;
        }
        if lower.contains("slow") || lower.contains("calm") || lower.contains("gentle") {
            return 70;
        }
        if lower.contains("medium") || lower.contains("moderate") {
            return 100;
        }
        match mood {
            AudioMood::Epic | AudioMood::Dramatic => 120,
            AudioMood::Celebratory => 140,
            AudioMood::Tense => 130,
            AudioMood::Relaxed => 75,
            AudioMood::Playful => 120,
            _ => 0,
        }
    }

    fn extract_tags(lower: &str) -> Vec<String> {
        let tag_keywords = &[
            "glitter", "sparkle", "coins", "golden", "silver", "magic", "fire",
            "thunder", "ice", "water", "wind", "earth", "space", "neon",
            "vintage", "modern", "futuristic", "ancient", "royal", "pirate",
            "aztec", "egypt", "ninja", "dragon", "phoenix", "luck", "fortune",
        ];
        tag_keywords.iter()
            .filter(|&&t| lower.contains(t))
            .map(|&t| t.to_string())
            .collect()
    }

    fn compute_confidence(tokens: &[&str], category: &EventCategory, style: &AudioStyle) -> f64 {
        let mut score = 0.5_f64;

        // More tokens = more context = higher confidence
        let token_bonus = (tokens.len() as f64 * 0.02).min(0.2);
        score += token_bonus;

        // Non-default category/style signals mean keywords were found
        if !matches!(category, EventCategory::BaseGame) { score += 0.1; }
        if !matches!(style, AudioStyle::Unknown) { score += 0.1; }

        score.clamp(0.1, 1.0)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_jackpot_detection() {
        let d = PromptParser::parse("epic jackpot celebration with brass fanfare and coins");
        assert_eq!(d.category, EventCategory::Jackpot);
        assert_eq!(d.tier, AudioTier::Flagship);
        assert!(d.instruments.contains(&InstrumentHint::Brass));
        assert!(d.instruments.contains(&InstrumentHint::Coin));
    }

    #[test]
    fn test_win_detection_with_orchestral_style() {
        let d = PromptParser::parse("orchestral victory fanfare, triumphant strings");
        assert_eq!(d.category, EventCategory::Win);
        assert_eq!(d.style, AudioStyle::Orchestral);
        assert!(d.instruments.contains(&InstrumentHint::Strings));
    }

    #[test]
    fn test_ambient_loop_detection() {
        let d = PromptParser::parse("relaxed casino ambient background music loop");
        assert_eq!(d.category, EventCategory::Ambient);
        assert!(d.can_loop);
        assert_eq!(d.duration_ms, 0);
        assert_eq!(d.mood, AudioMood::Relaxed);
    }

    #[test]
    fn test_ui_click_detection() {
        let d = PromptParser::parse("short subtle UI click button press");
        assert_eq!(d.category, EventCategory::UI);
        assert_eq!(d.tier, AudioTier::Subtle);
        assert!(d.duration_ms <= 200);
        assert_eq!(d.voice_count, 1);
    }

    #[test]
    fn test_feature_trigger_detection() {
        let d = PromptParser::parse("bonus feature trigger with dramatic build up");
        assert_eq!(d.category, EventCategory::Feature);
        assert_eq!(d.mood, AudioMood::Dramatic);
    }

    #[test]
    fn test_near_miss_detection() {
        let d = PromptParser::parse("tense near miss sound, almost won");
        assert_eq!(d.category, EventCategory::NearMiss);
        assert_eq!(d.mood, AudioMood::Tense);
    }

    #[test]
    fn test_retro_style_detection() {
        let d = PromptParser::parse("8-bit chiptune win sound retro arcade");
        assert_eq!(d.style, AudioStyle::Retro8Bit);
    }

    #[test]
    fn test_generation_prompt_contains_key_parts() {
        let d = PromptParser::parse("epic jackpot win with brass and choir");
        let gen_prompt = d.to_generation_prompt();
        assert!(gen_prompt.contains("jackpot") || gen_prompt.contains("coin"));
    }

    #[test]
    fn test_confidence_increases_with_more_context() {
        let short = PromptParser::parse("win");
        let detailed = PromptParser::parse("epic orchestral jackpot celebration with brass fanfare and coin shower, very loud");
        assert!(detailed.confidence > short.confidence);
    }

    #[test]
    fn test_flagship_win_has_multiple_voices() {
        let d = PromptParser::parse("mega win celebration fanfare ultimate");
        assert!(d.voice_count >= 4);
    }

    #[test]
    fn test_is_required_for_basegame() {
        let d = PromptParser::parse("reel spin mechanical sound");
        assert!(d.is_required);
    }

    #[test]
    fn test_tags_extraction() {
        let d = PromptParser::parse("golden dragon phoenix magic sparkle win");
        assert!(d.generation_tags.contains(&"golden".to_string())
            || d.generation_tags.contains(&"magic".to_string())
            || d.generation_tags.contains(&"sparkle".to_string()));
    }
}
