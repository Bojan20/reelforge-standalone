/// SPEC-15: Selection Memory Slot
///
/// Snapshot of a panel layout configuration for instant recall.
/// Persisted to ~/.fluxforge/selection_memory.json (max 9 slots).
///
/// Save:    Cmd+Shift+[1-9] (hold 400ms)
/// Restore: Cmd+[1-9] (tap)
/// Default: Cmd+0

/// Panel visibility + zoom state for a single composition slot.
class SelectionMemorySlot {
  /// Human-readable name — "Slot N" or custom label
  final String name;
  /// Left zone visible
  final bool leftVisible;
  /// Right zone visible
  final bool rightVisible;
  /// Lower zone visible
  final bool lowerVisible;
  /// Timeline zoom level (pixels per second)
  final double timelineZoom;
  /// Short auto-generated description (e.g. "DAW • EDIT tab")
  final String? previewLabel;
  /// When this slot was saved (epoch 0 = empty)
  final int savedAtMs;

  const SelectionMemorySlot({
    required this.name,
    this.leftVisible = true,
    this.rightVisible = true,
    this.lowerVisible = true,
    this.timelineZoom = 50,
    this.previewLabel,
    this.savedAtMs = 0,
  });

  /// Empty slot sentinel
  static const empty = SelectionMemorySlot(name: 'Empty', savedAtMs: 0);

  bool get isEmpty => savedAtMs == 0;

  DateTime get savedAt => DateTime.fromMillisecondsSinceEpoch(savedAtMs);

  factory SelectionMemorySlot.now({
    required String name,
    bool leftVisible = true,
    bool rightVisible = true,
    bool lowerVisible = true,
    double timelineZoom = 50,
    String? previewLabel,
  }) {
    return SelectionMemorySlot(
      name: name,
      leftVisible: leftVisible,
      rightVisible: rightVisible,
      lowerVisible: lowerVisible,
      timelineZoom: timelineZoom,
      previewLabel: previewLabel,
      savedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory SelectionMemorySlot.fromJson(Map<String, dynamic> json) {
    return SelectionMemorySlot(
      name: json['name'] as String? ?? 'Slot',
      leftVisible: json['leftVisible'] as bool? ?? true,
      rightVisible: json['rightVisible'] as bool? ?? true,
      lowerVisible: json['lowerVisible'] as bool? ?? true,
      timelineZoom: (json['timelineZoom'] as num?)?.toDouble() ?? 50,
      previewLabel: json['previewLabel'] as String?,
      savedAtMs: json['savedAtMs'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'leftVisible': leftVisible,
        'rightVisible': rightVisible,
        'lowerVisible': lowerVisible,
        'timelineZoom': timelineZoom,
        'previewLabel': previewLabel,
        'savedAtMs': savedAtMs,
      };

  SelectionMemorySlot copyWith({
    String? name,
    bool? leftVisible,
    bool? rightVisible,
    bool? lowerVisible,
    double? timelineZoom,
    String? previewLabel,
    int? savedAtMs,
  }) =>
      SelectionMemorySlot(
        name: name ?? this.name,
        leftVisible: leftVisible ?? this.leftVisible,
        rightVisible: rightVisible ?? this.rightVisible,
        lowerVisible: lowerVisible ?? this.lowerVisible,
        timelineZoom: timelineZoom ?? this.timelineZoom,
        previewLabel: previewLabel ?? this.previewLabel,
        savedAtMs: savedAtMs ?? this.savedAtMs,
      );

  @override
  String toString() => 'SelectionMemorySlot($name, saved: $savedAt)';
}
