//! Audio backend routing.
//!
//! Maps `AssetIntent.kind` (loop, oneshot, transition, vo, ambient, sting,
//! music) → `AudioKind` (Sfx, Tts, Music) → `AudioBackendId`.
//!
//! Customer can override the routing per-kind in Settings (e.g. send `ambient`
//! to Local instead of Suno when air-gapped).

use crate::audio::generator::{AudioBackendId, AudioKind};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Map asset `kind` strings → semantic `AudioKind`.
pub fn classify(kind: &str) -> AudioKind {
    match kind {
        "vo" | "voice" | "tts" => AudioKind::Tts,
        "ambient" | "ambience" | "music" | "bed" | "theme" => AudioKind::Music,
        // loop / oneshot / transition / sting / sfx → SFX
        _ => AudioKind::Sfx,
    }
}

/// Routing table — which backend handles which `AudioKind`.
///
/// Defaults: SFX → ElevenLabs, TTS → ElevenLabs, MUSIC → Suno. Customer can
/// override in Settings (e.g. SFX → Local when offline).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AudioRoutingTable {
    /// Routing entries keyed by `AudioKind`.
    pub map: HashMap<AudioKind, AudioBackendId>,
}

impl AudioRoutingTable {
    /// Default routing: SFX/TTS → ElevenLabs, Music → Suno.
    pub fn defaults() -> Self {
        let mut m = HashMap::new();
        m.insert(AudioKind::Sfx, AudioBackendId::Elevenlabs);
        m.insert(AudioKind::Tts, AudioBackendId::Elevenlabs);
        m.insert(AudioKind::Music, AudioBackendId::Suno);
        Self { map: m }
    }

    /// Air-gapped routing: every kind → Local backend.
    pub fn air_gapped() -> Self {
        let mut m = HashMap::new();
        m.insert(AudioKind::Sfx, AudioBackendId::Local);
        m.insert(AudioKind::Tts, AudioBackendId::Local);
        m.insert(AudioKind::Music, AudioBackendId::Local);
        Self { map: m }
    }

    /// Look up backend for a kind.
    pub fn route(&self, kind: AudioKind) -> AudioBackendId {
        *self.map.get(&kind).unwrap_or(&AudioBackendId::Local)
    }

    /// Override one kind.
    pub fn set(&mut self, kind: AudioKind, backend: AudioBackendId) {
        self.map.insert(kind, backend);
    }
}

impl Default for AudioRoutingTable {
    fn default() -> Self {
        Self::defaults()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn classify_vo() {
        assert_eq!(classify("vo"), AudioKind::Tts);
        assert_eq!(classify("voice"), AudioKind::Tts);
        assert_eq!(classify("tts"), AudioKind::Tts);
    }

    #[test]
    fn classify_ambient() {
        assert_eq!(classify("ambient"), AudioKind::Music);
        assert_eq!(classify("ambience"), AudioKind::Music);
        assert_eq!(classify("music"), AudioKind::Music);
    }

    #[test]
    fn classify_default_sfx() {
        assert_eq!(classify("loop"), AudioKind::Sfx);
        assert_eq!(classify("oneshot"), AudioKind::Sfx);
        assert_eq!(classify("transition"), AudioKind::Sfx);
        assert_eq!(classify("sting"), AudioKind::Sfx);
        assert_eq!(classify("unknown"), AudioKind::Sfx);
    }

    #[test]
    fn defaults_route_correctly() {
        let r = AudioRoutingTable::defaults();
        assert_eq!(r.route(AudioKind::Sfx), AudioBackendId::Elevenlabs);
        assert_eq!(r.route(AudioKind::Tts), AudioBackendId::Elevenlabs);
        assert_eq!(r.route(AudioKind::Music), AudioBackendId::Suno);
    }

    #[test]
    fn air_gapped_routes_local() {
        let r = AudioRoutingTable::air_gapped();
        assert_eq!(r.route(AudioKind::Sfx), AudioBackendId::Local);
        assert_eq!(r.route(AudioKind::Tts), AudioBackendId::Local);
        assert_eq!(r.route(AudioKind::Music), AudioBackendId::Local);
    }

    #[test]
    fn override_one_kind() {
        let mut r = AudioRoutingTable::defaults();
        r.set(AudioKind::Music, AudioBackendId::Local);
        assert_eq!(r.route(AudioKind::Music), AudioBackendId::Local);
        assert_eq!(r.route(AudioKind::Sfx), AudioBackendId::Elevenlabs); // unchanged
    }

    #[test]
    fn round_trip_serde() {
        let r = AudioRoutingTable::defaults();
        let s = serde_json::to_string(&r).unwrap();
        let back: AudioRoutingTable = serde_json::from_str(&s).unwrap();
        assert_eq!(r, back);
    }
}
