/// Screensets Panel — FabFilter-style DAW Lower Zone EDIT tab
///
/// #34: Screensets — save/recall up to 10 named UI layout snapshots.
///
/// Features:
/// - 10 numbered slots (1-0 keyboard shortcuts)
/// - Save/recall current UI layout state
/// - Rename slots, clear slots
/// - Self-contained ScreensetsService singleton
/// - Persistent Rust FFI storage with in-memory fallback
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import '../../../fabfilter/fabfilter_theme.dart';
import '../../../fabfilter/fabfilter_widgets.dart';
import '../../../../src/rust/native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MODEL
// ═══════════════════════════════════════════════════════════════════════════

class Screenset {
  final int id;
  String name;
  Map<String, dynamic> layoutState;
  DateTime? savedAt;

  Screenset({
    required this.id,
    String? name,
    Map<String, dynamic>? layoutState,
    this.savedAt,
  })  : name = name ?? 'Screenset $id',
        layoutState = layoutState ?? {};

  bool get isEmpty => layoutState.isEmpty;

  Screenset copyWith({
    String? name,
    Map<String, dynamic>? layoutState,
    DateTime? savedAt,
  }) =>
      Screenset(
        id: id,
        name: name ?? this.name,
        layoutState: layoutState ?? Map.of(this.layoutState),
        savedAt: savedAt ?? this.savedAt,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════════════════════

class ScreensetsService extends ChangeNotifier {
  ScreensetsService._() {
    for (int i = 1; i <= 10; i++) {
      _slots[i] = Screenset(id: i);
    }
    _syncFromEngine();
  }

  static final ScreensetsService instance = ScreensetsService._();

  final Map<int, Screenset> _slots = {};
  int _activeSlot = 1;

  NativeFFI? get _ffi {
    final ffi = NativeFFI.instance;
    return ffi.isLoaded ? ffi : null;
  }

  int get activeSlot => _activeSlot;
  List<Screenset> get slots => List.generate(10, (i) => _slots[i + 1]!);

  Screenset? getSlot(int id) => _slots[id];

  /// Load all screenset slots from Rust engine into local state.
  void _syncFromEngine() {
    final ffi = _ffi;
    if (ffi == null) return;

    for (int i = 1; i <= 10; i++) {
      // Rust uses 0-based slots, Dart uses 1-based
      final json = ffi.screensetLoad(i - 1);
      if (json != null) {
        try {
          final data = jsonDecode(json) as Map<String, dynamic>;
          final stateJson = data['state_json'] as String? ?? '{}';
          final savedAtSecs = data['saved_at'] as num? ?? 0;
          Map<String, dynamic> layoutState = {};
          try {
            layoutState = jsonDecode(stateJson) as Map<String, dynamic>;
          } catch (_) {}
          _slots[i] = Screenset(
            id: i,
            name: data['name'] as String? ?? 'Screenset $i',
            layoutState: layoutState,
            savedAt: savedAtSecs > 0
                ? DateTime.fromMillisecondsSinceEpoch(
                    (savedAtSecs * 1000).toInt())
                : null,
          );
        } catch (_) {
          // FFI returned invalid data — keep empty slot
        }
      }
    }
  }

  void saveSlot(int id, Map<String, dynamic> layoutState) {
    final name = _slots[id]?.name ?? 'Screenset $id';

    // Persist to Rust engine (0-based slot index)
    final ffi = _ffi;
    if (ffi != null) {
      final stateJson = jsonEncode(layoutState);
      ffi.screensetSave(id - 1, name, stateJson);
    }

    // Update local state
    _slots[id] = Screenset(
      id: id,
      name: name,
      layoutState: Map.of(layoutState),
      savedAt: DateTime.now(),
    );
    _activeSlot = id;
    notifyListeners();
  }

  Map<String, dynamic>? recallSlot(int id) {
    // Try loading from engine first for freshest data
    final ffi = _ffi;
    if (ffi != null) {
      final json = ffi.screensetLoad(id - 1);
      if (json != null) {
        try {
          final data = jsonDecode(json) as Map<String, dynamic>;
          final stateJson = data['state_json'] as String? ?? '{}';
          final layoutState = jsonDecode(stateJson) as Map<String, dynamic>;
          _activeSlot = id;
          notifyListeners();
          return layoutState;
        } catch (_) {
          // Fall through to local state
        }
      }
    }

    // Fallback to local state
    final slot = _slots[id];
    if (slot == null || slot.isEmpty) return null;
    _activeSlot = id;
    notifyListeners();
    return Map.of(slot.layoutState);
  }

  void renameSlot(int id, String name) {
    final slot = _slots[id];
    if (slot == null) return;

    // Persist to Rust engine
    _ffi?.screensetRename(id - 1, name);

    _slots[id] = slot.copyWith(name: name);
    notifyListeners();
  }

  void clearSlot(int id) {
    // Persist to Rust engine
    _ffi?.screensetClear(id - 1);

    _slots[id] = Screenset(id: id);
    notifyListeners();
  }

  void clearAll() {
    // Persist to Rust engine
    _ffi?.screensetClearAllSlots();

    for (int i = 1; i <= 10; i++) {
      _slots[i] = Screenset(id: i);
    }
    notifyListeners();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PANEL WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class ScreensetsPanel extends StatefulWidget {
  final void Function(String action, Map<String, dynamic> data)? onAction;

  const ScreensetsPanel({super.key, this.onAction});

  @override
  State<ScreensetsPanel> createState() => _ScreensetsPanelState();
}

class _ScreensetsPanelState extends State<ScreensetsPanel> {
  final _service = ScreensetsService.instance;
  int _selectedSlot = 1;
  bool _showRename = false;

  late TextEditingController _renameCtrl;
  late FocusNode _renameFocus;

  static const _kBg = Color(0xFF1A1A24);
  static const _kText = Color(0xFFE0E0E8);
  static const _kBorder = Color(0xFF2A2A32);
  static const _kSecondary = Color(0xFF808088);

  @override
  void initState() {
    super.initState();
    _renameCtrl = TextEditingController();
    _renameFocus = FocusNode();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _renameCtrl.dispose();
    _renameFocus.dispose();
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  Screenset get _selected => _service.getSlot(_selectedSlot)!;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const Divider(height: 1, color: _kBorder),
          _buildSlotButtons(),
          const Divider(height: 1, color: _kBorder),
          Expanded(child: _buildSlotDetail()),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
      child: Row(
        children: [
          FabSectionLabel('SCREENSETS', color: _kSecondary),
          const Spacer(),
          _iconBtn(Icons.delete_sweep, 'Clear All', () => _service.clearAll()),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // SLOT BUTTONS (1-10)
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildSlotButtons() {
    final slots = _service.slots;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: List.generate(10, (i) {
          final slot = slots[i];
          final slotId = i + 1;
          final isSelected = slotId == _selectedSlot;
          final isActive = slotId == _service.activeSlot && !slot.isEmpty;
          final keyLabel = slotId == 10 ? '0' : '$slotId';

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: GestureDetector(
                onTap: () => setState(() => _selectedSlot = slotId),
                onDoubleTap: () {
                  final state = _service.recallSlot(slotId);
                  if (state != null) {
                    widget.onAction?.call('screensetRecall', {
                      'slotId': slotId,
                      'layoutState': state,
                    });
                  }
                },
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? FabFilterColors.cyan.withValues(alpha: 0.15)
                        : slot.isEmpty
                            ? FabFilterColors.bgMid
                            : FabFilterColors.bgElevated,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isActive
                          ? FabFilterColors.cyan
                          : isSelected
                              ? FabFilterColors.cyan.withValues(alpha: 0.4)
                              : _kBorder,
                      width: isActive ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        keyLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isActive
                              ? FabFilterColors.cyan
                              : isSelected
                                  ? _kText
                                  : _kSecondary,
                        ),
                      ),
                      if (!slot.isEmpty)
                        Container(
                          width: 4,
                          height: 4,
                          margin: const EdgeInsets.only(top: 2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isActive
                                ? FabFilterColors.cyan
                                : FabFilterColors.green.withValues(alpha: 0.6),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // SLOT DETAIL
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildSlotDetail() {
    final slot = _selected;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LEFT — info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_showRename) _buildRenameForm() else _buildSlotInfo(slot),
                const SizedBox(height: 8),
                if (slot.savedAt != null) ...[
                  Text(
                    'Saved: ${_formatTime(slot.savedAt!)}',
                    style: const TextStyle(fontSize: 10, color: _kSecondary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'State keys: ${slot.layoutState.length}',
                    style: const TextStyle(fontSize: 10, color: _kSecondary),
                  ),
                ] else
                  const Text(
                    'Empty slot — click Save to store current layout.',
                    style: TextStyle(fontSize: 10, color: _kSecondary),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // RIGHT — actions
          SizedBox(
            width: 160,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _actionButton(Icons.save, 'Save Current', () {
                  // Capture placeholder state — host app provides real state via onAction
                  final state = <String, dynamic>{
                    'savedFrom': 'panel',
                    'timestamp': DateTime.now().toIso8601String(),
                  };
                  _service.saveSlot(_selectedSlot, state);
                  widget.onAction?.call('screensetSave', {
                    'slotId': _selectedSlot,
                  });
                }),
                const SizedBox(height: 4),
                _actionButton(
                  Icons.open_in_new,
                  'Recall',
                  slot.isEmpty
                      ? null
                      : () {
                          final state = _service.recallSlot(_selectedSlot);
                          if (state != null) {
                            widget.onAction?.call('screensetRecall', {
                              'slotId': _selectedSlot,
                              'layoutState': state,
                            });
                          }
                        },
                ),
                const SizedBox(height: 4),
                _actionButton(
                  Icons.edit,
                  'Rename',
                  () {
                    _renameCtrl.text = slot.name;
                    setState(() => _showRename = true);
                    Future.microtask(() => _renameFocus.requestFocus());
                  },
                ),
                const SizedBox(height: 4),
                _actionButton(
                  Icons.clear,
                  'Clear Slot',
                  slot.isEmpty
                      ? null
                      : () => _service.clearSlot(_selectedSlot),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlotInfo(Screenset slot) {
    return Row(
      children: [
        Icon(
          slot.isEmpty ? Icons.crop_square : Icons.check_box_outlined,
          size: 16,
          color: slot.isEmpty ? _kSecondary : FabFilterColors.cyan,
        ),
        const SizedBox(width: 6),
        Text(
          slot.name,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _kText,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Slot ${slot.id}',
          style: const TextStyle(fontSize: 10, color: _kSecondary),
        ),
      ],
    );
  }

  Widget _buildRenameForm() {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 26,
            child: TextField(
              controller: _renameCtrl,
              focusNode: _renameFocus,
              style: const TextStyle(fontSize: 11, color: _kText),
              decoration: _inputDeco('Screenset name...'),
              onSubmitted: (_) => _applyRename(),
            ),
          ),
        ),
        const SizedBox(width: 4),
        _iconBtn(Icons.check, 'Apply', _applyRename),
        _iconBtn(
            Icons.close, 'Cancel', () => setState(() => _showRename = false)),
      ],
    );
  }

  void _applyRename() {
    final name = _renameCtrl.text.trim();
    if (name.isNotEmpty) {
      _service.renameSlot(_selectedSlot, name);
    }
    setState(() => _showRename = false);
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  // ═════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════════════════════

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback? onPressed) {
    return SizedBox(
      width: 24,
      height: 24,
      child: IconButton(
        icon: Icon(icon, size: 14),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        color: _kSecondary,
        disabledColor: FabFilterColors.textDisabled,
        onPressed: onPressed,
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, VoidCallback? onPressed) {
    final enabled = onPressed != null;
    return SizedBox(
      width: double.infinity,
      height: 28,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: enabled ? FabFilterColors.bgMid : FabFilterColors.bgDeep,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 14,
                  color: enabled ? _kSecondary : FabFilterColors.textDisabled),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: enabled
                          ? _kSecondary
                          : FabFilterColors.textDisabled)),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _kSecondary, fontSize: 11),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: _kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: FabFilterColors.cyan),
        ),
        filled: true,
        fillColor: FabFilterColors.bgMid,
      );
}
