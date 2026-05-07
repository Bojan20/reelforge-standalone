// Panel Layout Provider — SPEC-2B.3.2
//
// Per-project smart panel memory.
// Remembers the active tab/sub-tab and panel visibility for each project,
// identified by projectPath (or a synthetic key for unsaved projects).
//
// Persisted to SharedPreferences key: 'panel_layout_memory_v1'
//
// Usage:
//   final provider = GetIt.instance<PanelLayoutProvider>();
//   provider.save(projectId: path, memory: PanelLayoutMemory(...));
//   final mem = provider.restore(projectId: path);
//
// Wire in: call save() whenever tab/visibility changes, call restore() when
// project switches (SlotLabProjectProvider.loadProject / newProject).

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MODEL
// ═══════════════════════════════════════════════════════════════════════════

/// Per-project panel layout snapshot.
///
/// All fields are nullable — null means "use default / don't restore".
/// This way we can add fields in the future without breaking old persisted data.
@immutable
class PanelLayoutMemory {
  /// Which HELIX dock super-tab was open (stores tab index as string, e.g. "0").
  final String? activeHelixDockTab;

  /// Which DAW Lower Zone super-tab was open (stores DawSuperTab name, e.g. "browse").
  final String? activeDawLowerTab;

  /// SlotLab left panel tab index (maps to _LeftPanelTab enum index).
  final int? slotLabLeftTab;

  /// SlotLab right panel tab index (maps to _RightPanelTab enum index).
  final int? slotLabRightTab;

  /// SlotLab lower zone super-tab index (maps to SlotLabSuperTab.index).
  final int? slotLabLowerSuperTab;

  /// Panel visibility flags.
  final bool leftVisible;
  final bool rightVisible;
  final bool lowerVisible;

  /// When this snapshot was taken (for debugging / stale-eviction).
  final DateTime savedAt;

  const PanelLayoutMemory({
    this.activeHelixDockTab,
    this.activeDawLowerTab,
    this.slotLabLeftTab,
    this.slotLabRightTab,
    this.slotLabLowerSuperTab,
    this.leftVisible = true,
    this.rightVisible = true,
    this.lowerVisible = true,
    required this.savedAt,
  });

  /// Default state — all panels visible, no tab override.
  factory PanelLayoutMemory.defaults() => PanelLayoutMemory(
        leftVisible: true,
        rightVisible: true,
        lowerVisible: true,
        savedAt: DateTime.now(),
      );

  factory PanelLayoutMemory.fromJson(Map<String, dynamic> json) {
    return PanelLayoutMemory(
      activeHelixDockTab: json['activeHelixDockTab'] as String?,
      activeDawLowerTab: json['activeDawLowerTab'] as String?,
      slotLabLeftTab: (json['slotLabLeftTab'] as num?)?.toInt(),
      slotLabRightTab: (json['slotLabRightTab'] as num?)?.toInt(),
      slotLabLowerSuperTab: (json['slotLabLowerSuperTab'] as num?)?.toInt(),
      leftVisible: (json['leftVisible'] as bool?) ?? true,
      rightVisible: (json['rightVisible'] as bool?) ?? true,
      lowerVisible: (json['lowerVisible'] as bool?) ?? true,
      savedAt: json['savedAt'] != null
          ? DateTime.tryParse(json['savedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        if (activeHelixDockTab != null) 'activeHelixDockTab': activeHelixDockTab,
        if (activeDawLowerTab != null) 'activeDawLowerTab': activeDawLowerTab,
        if (slotLabLeftTab != null) 'slotLabLeftTab': slotLabLeftTab,
        if (slotLabRightTab != null) 'slotLabRightTab': slotLabRightTab,
        if (slotLabLowerSuperTab != null) 'slotLabLowerSuperTab': slotLabLowerSuperTab,
        'leftVisible': leftVisible,
        'rightVisible': rightVisible,
        'lowerVisible': lowerVisible,
        'savedAt': savedAt.toIso8601String(),
      };

  PanelLayoutMemory copyWith({
    String? activeHelixDockTab,
    String? activeDawLowerTab,
    int? slotLabLeftTab,
    int? slotLabRightTab,
    int? slotLabLowerSuperTab,
    bool? leftVisible,
    bool? rightVisible,
    bool? lowerVisible,
  }) =>
      PanelLayoutMemory(
        activeHelixDockTab: activeHelixDockTab ?? this.activeHelixDockTab,
        activeDawLowerTab: activeDawLowerTab ?? this.activeDawLowerTab,
        slotLabLeftTab: slotLabLeftTab ?? this.slotLabLeftTab,
        slotLabRightTab: slotLabRightTab ?? this.slotLabRightTab,
        slotLabLowerSuperTab: slotLabLowerSuperTab ?? this.slotLabLowerSuperTab,
        leftVisible: leftVisible ?? this.leftVisible,
        rightVisible: rightVisible ?? this.rightVisible,
        lowerVisible: lowerVisible ?? this.lowerVisible,
        savedAt: DateTime.now(),
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

/// Manages per-project panel layout memory.
///
/// Projects are keyed by their file path (or a stable synthetic key for
/// unsaved projects: "unsaved:projectName").
///
/// The provider holds the entire memory map in RAM (bounded to [kMaxEntries]
/// entries) and persists it lazily to SharedPreferences.
class PanelLayoutProvider extends ChangeNotifier {
  static const String _prefsKey = 'panel_layout_memory_v1';

  /// Maximum number of project entries we store.
  /// LRU eviction: when map exceeds this, the oldest entry is dropped.
  static const int kMaxEntries = 50;

  /// All known project layout memories, keyed by projectId.
  final Map<String, PanelLayoutMemory> _memories = {};

  /// Currently active project id. Null when no project is open.
  String? _activeProjectId;

  String? get activeProjectId => _activeProjectId;

  /// Return memory for [projectId], or null if not yet persisted.
  PanelLayoutMemory? restore(String projectId) => _memories[projectId];

  /// Return memory for [projectId], falling back to defaults when absent.
  PanelLayoutMemory restoreOrDefaults(String projectId) =>
      _memories[projectId] ?? PanelLayoutMemory.defaults();

  // ═══════════════════════════════════════════════════════════════════════════
  // PROJECT SWITCH
  // ═══════════════════════════════════════════════════════════════════════════

  /// Called when the active project changes.
  ///
  /// Returns the persisted [PanelLayoutMemory] for the new project, or null
  /// when the project has no saved layout (caller should apply defaults).
  PanelLayoutMemory? switchProject(String newProjectId) {
    _activeProjectId = newProjectId;
    notifyListeners();
    return _memories[newProjectId];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SAVE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Save a complete [PanelLayoutMemory] for [projectId] and persist async.
  Future<void> save({
    required String projectId,
    required PanelLayoutMemory memory,
  }) async {
    _evictIfNeeded(projectId);
    _memories[projectId] = memory;
    notifyListeners();
    await _persist();
  }

  /// Patch specific fields of an existing memory entry.
  /// Safe to call on every tab/visibility toggle — only persists if something
  /// actually changed.
  Future<void> patch({
    required String projectId,
    String? activeHelixDockTab,
    String? activeDawLowerTab,
    int? slotLabLeftTab,
    int? slotLabRightTab,
    int? slotLabLowerSuperTab,
    bool? leftVisible,
    bool? rightVisible,
    bool? lowerVisible,
  }) async {
    final current = _memories[projectId] ?? PanelLayoutMemory.defaults();
    final updated = current.copyWith(
      activeHelixDockTab: activeHelixDockTab,
      activeDawLowerTab: activeDawLowerTab,
      slotLabLeftTab: slotLabLeftTab,
      slotLabRightTab: slotLabRightTab,
      slotLabLowerSuperTab: slotLabLowerSuperTab,
      leftVisible: leftVisible,
      rightVisible: rightVisible,
      lowerVisible: lowerVisible,
    );

    // Deep equality check: avoid unnecessary writes.
    final old = _memories[projectId];
    if (old != null &&
        old.activeHelixDockTab == updated.activeHelixDockTab &&
        old.activeDawLowerTab == updated.activeDawLowerTab &&
        old.slotLabLeftTab == updated.slotLabLeftTab &&
        old.slotLabRightTab == updated.slotLabRightTab &&
        old.slotLabLowerSuperTab == updated.slotLabLowerSuperTab &&
        old.leftVisible == updated.leftVisible &&
        old.rightVisible == updated.rightVisible &&
        old.lowerVisible == updated.lowerVisible) {
      return; // Nothing changed
    }

    _evictIfNeeded(projectId);
    _memories[projectId] = updated;
    // No notifyListeners — callers only need the data on restore, not on save
    await _persist();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INIT / PERSIST
  // ═══════════════════════════════════════════════════════════════════════════

  /// Load from SharedPreferences. Call once at startup.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final Map<String, dynamic> decoded = jsonDecode(raw) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          try {
            _memories[entry.key] =
                PanelLayoutMemory.fromJson(entry.value as Map<String, dynamic>);
          } catch (_) {
            // Corrupt entry — skip
          }
        }
        notifyListeners();
      }
    } catch (_) {
      // First run or corrupt prefs — start empty
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        {for (final e in _memories.entries) e.key: e.value.toJson()},
      );
      await prefs.setString(_prefsKey, encoded);
    } catch (_) {}
  }

  /// LRU eviction: if we already have [kMaxEntries] and the new entry is not
  /// already present, remove the oldest one (sorted by savedAt).
  void _evictIfNeeded(String incomingKey) {
    if (_memories.length < kMaxEntries) return;
    if (_memories.containsKey(incomingKey)) return; // updating existing — no eviction

    // Find oldest by savedAt
    String? oldest;
    DateTime? oldestTime;
    for (final e in _memories.entries) {
      final t = e.value.savedAt;
      if (oldestTime == null || t.isBefore(oldestTime)) {
        oldest = e.key;
        oldestTime = t;
      }
    }
    if (oldest != null) {
      _memories.remove(oldest);
    }
  }
}
