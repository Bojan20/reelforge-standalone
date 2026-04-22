/// PHASE 10 — Voice Category Resolver
///
/// Maps one-shot Voice records (returned by `orb_get_active_voices`) into
/// **categories** so the OrbMixer's Nivo 1.5 "category ring" doesn't have to
/// show 130 individual voices — it shows ~15-20 category dots grouped by
/// bus and function:
///
///   SFX bus  → [Spin loop] [Reel stops] [UI clicks] [Win rollup] [Collect]
///   MUS bus  → [Base] [Anticipation] [Feature] [BigWin Tier 1-5]
///   VO bus   → [Char A] [Char B] [Narrator]
///   AMB bus  → [Lobby] [Game idle] [Feature amb]
///   Aux bus  → [Send FX 1] [Send FX 2]
///   Master   → (no sub-cat; aggregate)
///
/// Categorization uses:
///   1. bus_idx (primary axis)
///   2. voice looping flag (spin loop vs one-shot)
///   3. peak energy (optional: high-peak → "big" category bucket)
///
/// Full event-id based categorization is a follow-up (requires FFI payload
/// extension to include event_id per voice). This resolver delivers a
/// **meaningful grouping today without any Rust changes**.

library;

import '../providers/orb_mixer_provider.dart';

/// One of the resolver categories. Keeps the set small so it maps cleanly
/// to a visible category ring (≤ 6 cats per bus → 6 × 6 = 36 max dots).
enum VoiceCategory {
  // SFX
  sfxSpinLoop,
  sfxReelStops,
  sfxUi,
  sfxWinRollup,
  sfxCollect,
  sfxNearMiss,
  sfxOther,
  // Music
  musBase,
  musAnticipation,
  musFeature,
  musBigWin,
  musOther,
  // Voice
  voCharacter,
  voNarrator,
  voAnnouncer,
  voOther,
  // Ambience
  ambLobby,
  ambGame,
  ambFeature,
  ambOther,
  // Aux
  auxSend,
  // Master
  masterAggregate;

  /// Human-readable label for the category ring.
  String get label => switch (this) {
        sfxSpinLoop => 'Spin',
        sfxReelStops => 'Reels',
        sfxUi => 'UI',
        sfxWinRollup => 'Rollup',
        sfxCollect => 'Collect',
        sfxNearMiss => 'Near',
        sfxOther => 'SFX',
        musBase => 'Base',
        musAnticipation => 'Antic',
        musFeature => 'Feat',
        musBigWin => 'BW',
        musOther => 'Mus',
        voCharacter => 'Char',
        voNarrator => 'Narr',
        voAnnouncer => 'Anncr',
        voOther => 'VO',
        ambLobby => 'Lobby',
        ambGame => 'Game',
        ambFeature => 'FeatAmb',
        ambOther => 'Amb',
        auxSend => 'Aux',
        masterAggregate => 'MST',
      };

  /// Which bus this category belongs to (used to position it on the ring
  /// at the bus's fixed angle, then push out radially).
  OrbBusId get bus => switch (this) {
        sfxSpinLoop ||
        sfxReelStops ||
        sfxUi ||
        sfxWinRollup ||
        sfxCollect ||
        sfxNearMiss ||
        sfxOther =>
          OrbBusId.sfx,
        musBase ||
        musAnticipation ||
        musFeature ||
        musBigWin ||
        musOther =>
          OrbBusId.music,
        voCharacter ||
        voNarrator ||
        voAnnouncer ||
        voOther =>
          OrbBusId.voice,
        ambLobby || ambGame || ambFeature || ambOther => OrbBusId.ambience,
        auxSend => OrbBusId.aux,
        masterAggregate => OrbBusId.master,
      };
}

/// Category bucket — aggregates voices into a single renderable ring dot.
class VoiceCategoryBucket {
  final VoiceCategory category;
  final List<OrbVoiceState> voices;
  final double peakL;
  final double peakR;
  final double volume; // average over bucket

  const VoiceCategoryBucket({
    required this.category,
    required this.voices,
    required this.peakL,
    required this.peakR,
    required this.volume,
  });

  double get peak => peakL > peakR ? peakL : peakR;
  int get voiceCount => voices.length;
  bool get isActive => voices.isNotEmpty;
}

/// Resolver: one-shot voices → categorized buckets.
class VoiceCategoryResolver {
  /// Categorize a single voice. Uses bus + looping + peak heuristics —
  /// deterministic for a given voice state so consecutive calls with the
  /// same input always land in the same bucket.
  static VoiceCategory categorize(OrbVoiceState voice) {
    final peak = voice.peakL > voice.peakR ? voice.peakL : voice.peakR;
    switch (voice.bus) {
      case OrbBusId.sfx:
        // Looping SFX on the SFX bus is almost always the spin loop (reels
        // rotating). Short one-shots break down by peak energy + state.
        if (voice.isLooping) return VoiceCategory.sfxSpinLoop;
        // High-peak one-shots → treat as win rollup family (trumpets,
        // fanfara). Low-peak one-shots → reel stops / UI clicks.
        if (peak > 0.55) return VoiceCategory.sfxWinRollup;
        if (peak > 0.30) return VoiceCategory.sfxReelStops;
        return VoiceCategory.sfxUi;
      case OrbBusId.music:
        if (voice.isLooping) {
          // Music beds that keep looping — base or feature depending on peak.
          return peak > 0.55
              ? VoiceCategory.musFeature
              : VoiceCategory.musBase;
        }
        // One-shots on music bus → anticipation stingers / BW moment hits.
        return peak > 0.55
            ? VoiceCategory.musBigWin
            : VoiceCategory.musAnticipation;
      case OrbBusId.voice:
        // Without event_id we can't distinguish characters; bucket all into
        // "Character" and reserve Narrator/Announcer for future FFI work.
        return VoiceCategory.voCharacter;
      case OrbBusId.ambience:
        return voice.isLooping
            ? VoiceCategory.ambGame
            : VoiceCategory.ambFeature;
      case OrbBusId.aux:
        return VoiceCategory.auxSend;
      case OrbBusId.master:
        return VoiceCategory.masterAggregate;
    }
  }

  /// Group active voices into category buckets. Empty categories are
  /// omitted from the result so the ring doesn't show dead dots.
  static List<VoiceCategoryBucket> bucketize(List<OrbVoiceState> voices) {
    final Map<VoiceCategory, List<OrbVoiceState>> groups = {};
    for (final voice in voices) {
      final cat = categorize(voice);
      groups.putIfAbsent(cat, () => []).add(voice);
    }
    final List<VoiceCategoryBucket> result = [];
    for (final entry in groups.entries) {
      double maxL = 0, maxR = 0, sumVol = 0;
      for (final v in entry.value) {
        if (v.peakL > maxL) maxL = v.peakL;
        if (v.peakR > maxR) maxR = v.peakR;
        sumVol += v.volume;
      }
      final avgVol = entry.value.isEmpty ? 0.0 : sumVol / entry.value.length;
      result.add(VoiceCategoryBucket(
        category: entry.key,
        voices: entry.value,
        peakL: maxL,
        peakR: maxR,
        volume: avgVol,
      ));
    }
    return result;
  }

  /// Convenience: bucketize + group by bus for quick lookup.
  static Map<OrbBusId, List<VoiceCategoryBucket>> byBus(
    List<OrbVoiceState> voices,
  ) {
    final buckets = bucketize(voices);
    final Map<OrbBusId, List<VoiceCategoryBucket>> byBusMap = {};
    for (final b in buckets) {
      byBusMap.putIfAbsent(b.category.bus, () => []).add(b);
    }
    return byBusMap;
  }
}
