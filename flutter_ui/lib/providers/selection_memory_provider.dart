/// SPEC-15: Selection Memory Provider
///
/// Manages 9 layout snapshot slots with Cmd+[1-9] recall and
/// Cmd+Shift+[1-9] (hold 400ms) save.
///
/// Persisted to SharedPreferences key: 'selection_memory_slots'

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/selection_memory_slot.dart';

/// Callback for applying a saved slot to the layout state
typedef SelectionMemoryApplyCallback = void Function(SelectionMemorySlot slot);

class SelectionMemoryProvider extends ChangeNotifier {
  static const int kMaxSlots = 9;
  static const String _prefsKey = 'selection_memory_slots';

  SelectionMemoryProvider();

  /// 9 slots indexed 0–8 (Cmd+1..9)
  final List<SelectionMemorySlot> _slots = List.filled(
    kMaxSlots,
    SelectionMemorySlot.empty,
    growable: false,
  );

  /// Callback wired by engine_connected_layout to apply a slot
  SelectionMemoryApplyCallback? onApply;

  List<SelectionMemorySlot> get slots => List.unmodifiable(_slots);

  SelectionMemorySlot slotAt(int index) {
    assert(index >= 0 && index < kMaxSlots);
    return _slots[index];
  }

  bool isOccupied(int index) => !_slots[index].isEmpty;

  /// Initialize from SharedPreferences
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
        for (int i = 0; i < list.length && i < kMaxSlots; i++) {
          _slots[i] = SelectionMemorySlot.fromJson(list[i] as Map<String, dynamic>);
        }
        notifyListeners();
      }
    } catch (_) {
      // First run or corrupt prefs — start empty
    }
  }

  /// Save current layout state to slot [index] (0-based).
  Future<void> saveSlot({
    required int index,
    required bool leftVisible,
    required bool rightVisible,
    required bool lowerVisible,
    required double timelineZoom,
    String? previewLabel,
  }) async {
    assert(index >= 0 && index < kMaxSlots);
    _slots[index] = SelectionMemorySlot.now(
      name: 'Slot ${index + 1}',
      leftVisible: leftVisible,
      rightVisible: rightVisible,
      lowerVisible: lowerVisible,
      timelineZoom: timelineZoom,
      previewLabel: previewLabel,
    );
    notifyListeners();
    await _persist();
  }

  /// Restore slot [index] by calling [onApply].
  void restoreSlot(int index) {
    assert(index >= 0 && index < kMaxSlots);
    final slot = _slots[index];
    if (slot.isEmpty) return;
    onApply?.call(slot);
  }

  /// Clear slot [index].
  Future<void> clearSlot(int index) async {
    assert(index >= 0 && index < kMaxSlots);
    _slots[index] = SelectionMemorySlot.empty;
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_slots.map((s) => s.toJson()).toList());
      await prefs.setString(_prefsKey, json);
    } catch (_) {}
  }
}
