// Selection Provider — SPEC-03/04 foundation
//
// Single source of truth for "what is currently selected" across the app.
// Inspectors and adaptive toolbars listen to this provider and adapt.
//
// Usage:
//   final sel = GetIt.instance<SelectionProvider>();
//   sel.selectTrack(trackId: 5);
//   sel.selectAudioClip(clipId: 'clip_42', trackId: 5);
//   sel.clear();
//
//   // Listen
//   ChangeNotifierProvider.value(
//     value: GetIt.instance<SelectionProvider>(),
//     child: ContextualInspector(),
//   );

import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════

/// Selection variant. Drives which Inspector/Toolbar section renders.
enum SelectionType {
  /// Nothing selected — show project overview
  none,
  /// Track selected (mixer channel, arrangement track)
  track,
  /// Audio clip on timeline
  audioClip,
  /// MIDI clip on timeline
  midiClip,
  /// Tempo / time-signature / arrangement marker
  marker,
  /// Plugin instance (insert FX, instrument)
  plugin,
  /// Slot stage (Aurexis stage event)
  slotStage,
  /// Slot reel (HELIX reel binding target)
  slotReel,
}

/// Immutable selection snapshot. Pass via .copyWith().
@immutable
class Selection {
  final SelectionType type;
  final int? trackId;
  final String? clipId;
  final String? markerId;
  final String? pluginId;
  final String? stageId;
  final int? reelIndex;

  const Selection({
    this.type = SelectionType.none,
    this.trackId,
    this.clipId,
    this.markerId,
    this.pluginId,
    this.stageId,
    this.reelIndex,
  });

  static const empty = Selection();

  /// True if anything beyond .none is selected.
  bool get hasSelection => type != SelectionType.none;

  /// Quick predicate accessors for adaptive UIs.
  bool get isTrack => type == SelectionType.track;
  bool get isAudioClip => type == SelectionType.audioClip;
  bool get isMidiClip => type == SelectionType.midiClip;
  bool get isClip => isAudioClip || isMidiClip;
  bool get isMarker => type == SelectionType.marker;
  bool get isPlugin => type == SelectionType.plugin;
  bool get isSlotStage => type == SelectionType.slotStage;
  bool get isSlotReel => type == SelectionType.slotReel;

  @override
  bool operator ==(Object other) =>
      other is Selection &&
      other.type == type &&
      other.trackId == trackId &&
      other.clipId == clipId &&
      other.markerId == markerId &&
      other.pluginId == pluginId &&
      other.stageId == stageId &&
      other.reelIndex == reelIndex;

  @override
  int get hashCode =>
      Object.hash(type, trackId, clipId, markerId, pluginId, stageId, reelIndex);

  @override
  String toString() {
    if (type == SelectionType.none) return 'Selection<none>';
    final parts = <String>[type.name];
    if (trackId != null) parts.add('track=$trackId');
    if (clipId != null) parts.add('clip=$clipId');
    if (markerId != null) parts.add('marker=$markerId');
    if (pluginId != null) parts.add('plugin=$pluginId');
    if (stageId != null) parts.add('stage=$stageId');
    if (reelIndex != null) parts.add('reel=$reelIndex');
    return 'Selection<${parts.join(' ')}>';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

/// Central selection state. Single source of truth for adaptive UIs.
class SelectionProvider extends ChangeNotifier {
  Selection _selection = Selection.empty;

  Selection get selection => _selection;
  SelectionType get type => _selection.type;
  bool get hasSelection => _selection.hasSelection;

  void _set(Selection next) {
    if (next == _selection) return;
    _selection = next;
    notifyListeners();
  }

  /// Clear selection (deselect-all).
  void clear() => _set(Selection.empty);

  /// Track selected on timeline / mixer.
  void selectTrack(int trackId) =>
      _set(Selection(type: SelectionType.track, trackId: trackId));

  /// Audio clip selected on timeline.
  void selectAudioClip({required String clipId, int? trackId}) => _set(Selection(
        type: SelectionType.audioClip,
        clipId: clipId,
        trackId: trackId,
      ));

  /// MIDI clip selected on timeline.
  void selectMidiClip({required String clipId, int? trackId}) => _set(Selection(
        type: SelectionType.midiClip,
        clipId: clipId,
        trackId: trackId,
      ));

  /// Tempo / time-sig / arrangement marker selected.
  void selectMarker(String markerId) =>
      _set(Selection(type: SelectionType.marker, markerId: markerId));

  /// Plugin instance selected (e.g. clicked in mixer slot).
  void selectPlugin({required String pluginId, int? trackId}) => _set(Selection(
        type: SelectionType.plugin,
        pluginId: pluginId,
        trackId: trackId,
      ));

  /// Slot stage selected (HELIX assignment target).
  void selectSlotStage(String stageId) =>
      _set(Selection(type: SelectionType.slotStage, stageId: stageId));

  /// Slot reel selected (HELIX reel binding target).
  void selectSlotReel(int reelIndex) =>
      _set(Selection(type: SelectionType.slotReel, reelIndex: reelIndex));
}
