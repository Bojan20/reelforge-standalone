/// README Generator — creates human-readable summary of an audio profile.
///
/// Output is plain text suitable for git diff review.
/// Shows all events grouped by category with parameters.

import '../../models/slot_audio_events.dart';
import '../../models/win_tier_config.dart';
import '../../models/slot_lab_models.dart';

class ProfileReadmeGenerator {
  ProfileReadmeGenerator._();

  static const _busNames = ['Master', 'Music', 'SFX', 'Voice', 'Ambience', 'Aux'];

  static String generate({
    required String profileName,
    required List<SlotCompositeEvent> events,
    SlotWinConfiguration? winConfig,
    MusicLayerConfig? musicConfig,
    String? creator,
    int? reelCount,
  }) {
    final buf = StringBuffer();
    final now = DateTime.now().toIso8601String().substring(0, 10);

    buf.writeln('FluxForge Audio Profile: $profileName');
    buf.writeln('Created: $now${creator != null ? ' by $creator' : ''}');
    if (reelCount != null) buf.writeln('Reels: $reelCount');
    buf.writeln('Events: ${events.length}');
    buf.writeln();

    // Group events by category
    final grouped = <String, List<SlotCompositeEvent>>{};
    for (final e in events) {
      final cat = e.category.isNotEmpty ? e.category.toUpperCase() : 'OTHER';
      grouped.putIfAbsent(cat, () => []).add(e);
    }

    // Sort categories
    const catOrder = ['SPIN', 'WIN', 'FEATURE', 'CASCADE', 'MUSIC', 'AMBIENT', 'TRANSITION', 'UI', 'VOICE'];
    final sortedCats = grouped.keys.toList()
      ..sort((a, b) {
        final ia = catOrder.indexOf(a);
        final ib = catOrder.indexOf(b);
        if (ia >= 0 && ib >= 0) return ia.compareTo(ib);
        if (ia >= 0) return -1;
        if (ib >= 0) return 1;
        return a.compareTo(b);
      });

    for (final cat in sortedCats) {
      final catEvents = grouped[cat]!;
      buf.writeln('$cat (${catEvents.length} events):');

      for (final event in catEvents) {
        final stages = event.triggerStages.isNotEmpty
            ? event.triggerStages.join(', ')
            : event.id;

        final playLayers = event.layers.where((l) =>
            l.actionType == 'Play' && l.audioPath.isNotEmpty).toList();

        if (playLayers.isEmpty) {
          buf.writeln('  $stages  — (no audio)');
          continue;
        }

        if (playLayers.length == 1) {
          final l = playLayers.first;
          buf.write('  $stages');
          buf.write('  → ${_shortPath(l.audioPath)}');
          buf.write(' (${_formatParams(l, event)})');
          buf.writeln();
        } else {
          buf.writeln('  $stages  — ${playLayers.length} layers:');
          for (int i = 0; i < playLayers.length; i++) {
            final l = playLayers[i];
            buf.write('    L${i + 1}: ${_shortPath(l.audioPath)}');
            buf.write(' (${_formatParams(l, event)})');
            buf.writeln();
          }
        }
      }
      buf.writeln();
    }

    // Win tiers
    if (winConfig != null) {
      buf.writeln('WIN TIERS:');
      buf.writeln('  Regular: ${winConfig.regularWins.tiers.length} tiers');
      for (final tier in winConfig.regularWins.tiers) {
        buf.writeln('    ${tier.displayLabel}: ${tier.fromMultiplier}x - ${tier.toMultiplier}x (rollup: ${tier.rollupDurationMs}ms)');
      }
      buf.writeln('  Big Win: ${winConfig.bigWins.tiers.length} tiers (threshold: ${winConfig.bigWins.threshold}x)');
      for (final tier in winConfig.bigWins.tiers) {
        final toStr = tier.toMultiplier == double.infinity ? '∞' : '${tier.toMultiplier}x';
        buf.writeln('    Tier ${tier.tierId}: ${tier.fromMultiplier}x - $toStr (${tier.durationMs}ms)');
      }
      buf.writeln();
    }

    // Music layers
    if (musicConfig != null && musicConfig.thresholds.isNotEmpty) {
      buf.writeln('MUSIC LAYERS:');
      buf.writeln('  Layers: ${musicConfig.thresholds.length}');
      for (final t in musicConfig.thresholds) {
        buf.writeln('    L${t.layer}: "${t.label}" (threshold: ${t.minWinRatio}x)');
      }
      buf.writeln('  Upshift: ${musicConfig.upshiftFadeMs}ms | Downshift: ${musicConfig.downshiftFadeMs}ms');
      buf.writeln('  Revert: ${musicConfig.revertMode} (${musicConfig.revertMode == 'spins' ? '${musicConfig.revertSpinCount} spins' : '${musicConfig.revertSeconds}s'})');
      buf.writeln();
    }

    return buf.toString();
  }

  static String _shortPath(String path) {
    final parts = path.split('/');
    return parts.length > 1 ? parts.sublist(parts.length - 2).join('/') : parts.last;
  }

  static String _formatParams(SlotEventLayer layer, SlotCompositeEvent event) {
    final parts = <String>[];
    parts.add('v:${(layer.volume * 100).round()}%');
    if (layer.busId != null && layer.busId! >= 0) {
      parts.add(layer.busId! < _busNames.length ? _busNames[layer.busId!] : 'bus${layer.busId}');
    }
    if (layer.loop || event.looping) parts.add('loop');
    if (layer.fadeInMs > 0) parts.add('fi:${layer.fadeInMs.round()}ms');
    if (layer.fadeOutMs > 0) parts.add('fo:${layer.fadeOutMs.round()}ms');
    if (layer.offsetMs > 0) parts.add('d:${layer.offsetMs.round()}ms');
    return parts.join(', ');
  }
}
