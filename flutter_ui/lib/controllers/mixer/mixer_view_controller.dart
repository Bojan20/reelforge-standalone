/// Mixer View Controller — manages mixer UI state
///
/// Controls section visibility, strip width mode, scroll position,
/// spill target, and metering mode. Persists to SharedPreferences.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/mixer_view_models.dart';

class MixerViewController extends ChangeNotifier {
  static const _storageKey = 'fluxforge_mixer_view_state';

  MixerViewState _state = MixerViewState();
  MixerViewState get state => _state;

  // ═══════════════════════════════════════════════════════════════════════
  // SECTION VISIBILITY
  // ═══════════════════════════════════════════════════════════════════════

  Set<MixerSection> get visibleSections => _state.visibleSections;

  bool isSectionVisible(MixerSection section) =>
      _state.isSectionVisible(section);

  void toggleSection(MixerSection section) {
    final updated = Set<MixerSection>.from(_state.visibleSections);
    if (updated.contains(section)) {
      // Don't allow hiding master
      if (section == MixerSection.master) return;
      updated.remove(section);
    } else {
      updated.add(section);
    }
    _state = _state.copyWith(visibleSections: updated);
    notifyListeners();
    _saveToStorage();
  }

  void showSection(MixerSection section) {
    if (_state.visibleSections.contains(section)) return;
    final updated = Set<MixerSection>.from(_state.visibleSections)..add(section);
    _state = _state.copyWith(visibleSections: updated);
    notifyListeners();
    _saveToStorage();
  }

  void hideSection(MixerSection section) {
    if (section == MixerSection.master) return;
    if (!_state.visibleSections.contains(section)) return;
    final updated = Set<MixerSection>.from(_state.visibleSections)..remove(section);
    _state = _state.copyWith(visibleSections: updated);
    notifyListeners();
    _saveToStorage();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // STRIP WIDTH
  // ═══════════════════════════════════════════════════════════════════════

  StripWidthMode get stripWidthMode => _state.stripWidthMode;

  void setStripWidth(StripWidthMode mode) {
    if (_state.stripWidthMode == mode) return;
    _state = _state.copyWith(stripWidthMode: mode);
    notifyListeners();
    _saveToStorage();
  }

  void toggleStripWidth() {
    setStripWidth(
      _state.stripWidthMode == StripWidthMode.narrow
          ? StripWidthMode.regular
          : StripWidthMode.narrow,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // METERING
  // ═══════════════════════════════════════════════════════════════════════

  MixerMeteringMode get meteringMode => _state.meteringMode;

  void setMeteringMode(MixerMeteringMode mode) {
    if (_state.meteringMode == mode) return;
    _state = _state.copyWith(meteringMode: mode);
    notifyListeners();
    _saveToStorage();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SCROLL
  // ═══════════════════════════════════════════════════════════════════════

  double get scrollOffset => _state.scrollOffset;

  void setScrollOffset(double offset) {
    _state = _state.copyWith(scrollOffset: offset);
    // No notifyListeners — scroll is driven by ScrollController
    // No save — scroll offset updates too frequently
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SPILL
  // ═══════════════════════════════════════════════════════════════════════

  String? get spillTargetId => _state.spillTargetId;
  bool get isSpillActive => _state.spillTargetId != null;

  void setSpillTarget(String? targetId) {
    _state = _state.copyWith(spillTargetId: targetId);
    notifyListeners();
  }

  void clearSpill() => setSpillTarget(null);

  // ═══════════════════════════════════════════════════════════════════════
  // FILTER
  // ═══════════════════════════════════════════════════════════════════════

  String get filterQuery => _state.filterQuery;

  void setFilterQuery(String query) {
    _state = _state.copyWith(filterQuery: query);
    notifyListeners();
  }

  void clearFilter() => setFilterQuery('');

  // ═══════════════════════════════════════════════════════════════════════
  // STRIP SECTION VISIBILITY (View > Mix Window Views)
  // ═══════════════════════════════════════════════════════════════════════

  Set<MixerStripSection> get visibleStripSections => _state.visibleStripSections;

  bool isStripSectionVisible(MixerStripSection section) =>
      _state.isStripSectionVisible(section);

  void toggleStripSection(MixerStripSection section) {
    final updated = Set<MixerStripSection>.from(_state.visibleStripSections);
    if (updated.contains(section)) {
      updated.remove(section);
    } else {
      updated.add(section);
    }
    _state = _state.copyWith(visibleStripSections: updated);
    notifyListeners();
    _saveToStorage();
  }

  void showAllStripSections() {
    _state = _state.copyWith(
      visibleStripSections: MixerStripSection.values.toSet(),
    );
    notifyListeners();
    _saveToStorage();
  }

  void resetStripSections() {
    _state = _state.copyWith(
      visibleStripSections: MixerStripSection.defaultVisibleSet,
    );
    notifyListeners();
    _saveToStorage();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PRESETS
  // ═══════════════════════════════════════════════════════════════════════

  void applyPreset(MixerViewPreset preset) {
    _state = _state.copyWith(
      visibleSections: preset.visibleSections,
      stripWidthMode: preset.stripWidth,
    );
    notifyListeners();
    _saveToStorage();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PERSISTENCE
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_storageKey);
      if (json != null) {
        final map = jsonDecode(json) as Map<String, dynamic>;
        _state = MixerViewState.fromJson(map);
        notifyListeners();
      }
    } catch (_) {
      // Use defaults on parse error
    }
  }

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(_state.toJson()));
    } catch (_) {
      // Silent fail
    }
  }
}
