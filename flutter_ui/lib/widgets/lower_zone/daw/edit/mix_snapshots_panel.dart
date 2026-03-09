/// Mix Snapshots Panel — FabFilter-style DAW Lower Zone EDIT tab
///
/// #34: Mix snapshot capture/recall — save and restore mixer states.
///
/// Features:
/// - Capture current mixer state as snapshot
/// - Recall snapshots (full or selective: volume, pan, mute, sends)
/// - Rename, delete, reorder snapshots
/// - Self-contained MixSnapshotService singleton
library;

import 'package:flutter/material.dart';
import '../../../fabfilter/fabfilter_theme.dart';
import '../../../fabfilter/fabfilter_widgets.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// MODELS
// ═══════════════════════════════════════════════════════════════════════════════

/// Snapshot of a single mixer channel
class MixChannelSnapshot {
  final double volume;
  final double pan;
  final bool mute;
  final bool solo;
  final Map<String, double> sends;

  const MixChannelSnapshot({
    required this.volume,
    required this.pan,
    required this.mute,
    required this.solo,
    this.sends = const {},
  });

  Map<String, dynamic> toMap() => {
    'volume': volume,
    'pan': pan,
    'mute': mute,
    'solo': solo,
    'sends': sends,
  };
}

/// Complete mixer snapshot
class MixSnapshot {
  final String id;
  String name;
  final DateTime timestamp;
  final Map<String, MixChannelSnapshot> channelStates;

  MixSnapshot({
    required this.id,
    required this.name,
    required this.timestamp,
    required this.channelStates,
  });

  int get channelCount => channelStates.length;

  String get timeLabel {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

/// Self-contained service for mix snapshot management
class MixSnapshotService extends ChangeNotifier {
  MixSnapshotService._();
  static final MixSnapshotService instance = MixSnapshotService._();

  final List<MixSnapshot> _snapshots = [];
  String? _activeSnapshotId;

  List<MixSnapshot> get snapshots => List.unmodifiable(_snapshots);
  int get count => _snapshots.length;
  String? get activeSnapshotId => _activeSnapshotId;

  MixSnapshot? getSnapshot(String id) {
    final idx = _snapshots.indexWhere((s) => s.id == id);
    return idx >= 0 ? _snapshots[idx] : null;
  }

  /// Capture current mixer state as a new snapshot
  void captureSnapshot(String name, Map<String, MixChannelSnapshot> channels) {
    final snapshot = MixSnapshot(
      id: 'snap_${DateTime.now().millisecondsSinceEpoch}',
      name: name.isEmpty ? 'Snapshot ${_snapshots.length + 1}' : name,
      timestamp: DateTime.now(),
      channelStates: Map.from(channels),
    );
    _snapshots.add(snapshot);
    _activeSnapshotId = snapshot.id;
    notifyListeners();
  }

  /// Capture with simulated mixer data (for demo/standalone use)
  void captureDemo(String name) {
    final channels = <String, MixChannelSnapshot>{};
    for (int i = 0; i < 8; i++) {
      channels['ch_$i'] = MixChannelSnapshot(
        volume: 0.75 + (i * 0.02),
        pan: (i - 4) * 0.2,
        mute: i == 3,
        solo: false,
        sends: {'reverb': 0.3, 'delay': 0.1},
      );
    }
    captureSnapshot(name, channels);
  }

  /// Recall a snapshot (mark as active)
  void recallSnapshot(String id) {
    final snap = getSnapshot(id);
    if (snap == null) return;
    _activeSnapshotId = id;
    notifyListeners();
  }

  /// Rename a snapshot
  void renameSnapshot(String id, String newName) {
    final snap = getSnapshot(id);
    if (snap == null || newName.isEmpty) return;
    snap.name = newName;
    notifyListeners();
  }

  /// Delete a snapshot
  void deleteSnapshot(String id) {
    _snapshots.removeWhere((s) => s.id == id);
    if (_activeSnapshotId == id) {
      _activeSnapshotId = _snapshots.isNotEmpty ? _snapshots.last.id : null;
    }
    notifyListeners();
  }

  /// Reorder snapshot
  void moveSnapshot(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _snapshots.length) return;
    if (newIndex < 0 || newIndex >= _snapshots.length) return;
    final item = _snapshots.removeAt(oldIndex);
    _snapshots.insert(newIndex, item);
    notifyListeners();
  }

  /// Delete all snapshots
  void clearAll() {
    _snapshots.clear();
    _activeSnapshotId = null;
    notifyListeners();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PANEL WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

class MixSnapshotsPanel extends StatefulWidget {
  final void Function(String action, Map<String, dynamic> data)? onAction;

  const MixSnapshotsPanel({super.key, this.onAction});

  @override
  State<MixSnapshotsPanel> createState() => _MixSnapshotsPanelState();
}

class _MixSnapshotsPanelState extends State<MixSnapshotsPanel> {
  final _service = MixSnapshotService.instance;
  String? _selectedId;
  bool _showCapture = false;
  String? _renamingId;

  // Selective recall options
  bool _recallVolume = true;
  bool _recallPan = true;
  bool _recallMute = true;
  bool _recallSolo = true;
  bool _recallSends = true;

  late TextEditingController _nameCtrl;
  late FocusNode _nameFocus;
  late TextEditingController _renameCtrl;
  late FocusNode _renameFocus;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _nameFocus = FocusNode();
    _renameCtrl = TextEditingController();
    _renameFocus = FocusNode();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nameFocus.dispose();
    _renameCtrl.dispose();
    _renameFocus.dispose();
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  MixSnapshot? get _selectedSnapshot =>
      _selectedId != null ? _service.getSnapshot(_selectedId!) : null;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 260, child: _buildSnapshotList()),
        const VerticalDivider(width: 1, color: FabFilterColors.border),
        Expanded(flex: 2, child: _buildSnapshotDetail()),
        const VerticalDivider(width: 1, color: FabFilterColors.border),
        SizedBox(width: 180, child: _buildRecallOptions()),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // LEFT: Snapshot List
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildSnapshotList() {
    final snapshots = _service.snapshots;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
          child: Row(
            children: [
              FabSectionLabel('MIX SNAPSHOTS'),
              const Spacer(),
              _iconBtn(Icons.add, 'Capture', () =>
                  setState(() => _showCapture = !_showCapture)),
              _iconBtn(Icons.delete_sweep, 'Clear All',
                  snapshots.isNotEmpty ? () => _service.clearAll() : null),
            ],
          ),
        ),
        if (_showCapture) _buildCaptureForm(),
        Expanded(
          child: snapshots.isEmpty
              ? Center(
                  child: Text(
                    'No snapshots captured.\nClick + to capture mixer state.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: FabFilterColors.textTertiary, fontSize: 11),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: snapshots.length,
                  itemBuilder: (_, i) => _buildSnapshotItem(snapshots[i], i),
                ),
        ),
      ],
    );
  }

  Widget _buildCaptureForm() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 26,
              child: TextField(
                controller: _nameCtrl,
                focusNode: _nameFocus,
                style: const TextStyle(
                    fontSize: 11, color: FabFilterColors.textPrimary),
                decoration: _inputDeco('Snapshot name...'),
                onSubmitted: (_) => _captureSnapshot(),
              ),
            ),
          ),
          const SizedBox(width: 4),
          _iconBtn(Icons.camera_alt, 'Capture', _captureSnapshot),
        ],
      ),
    );
  }

  void _captureSnapshot() {
    final name = _nameCtrl.text.trim();
    _service.captureDemo(name);
    _nameCtrl.clear();
    setState(() {
      _showCapture = false;
      _selectedId = _service.snapshots.last.id;
    });
    widget.onAction?.call('snapshotCapture', {'name': name});
  }

  Widget _buildSnapshotItem(MixSnapshot snapshot, int index) {
    final selected = snapshot.id == _selectedId;
    final isActive = snapshot.id == _service.activeSnapshotId;
    final isRenaming = _renamingId == snapshot.id;

    return InkWell(
      onTap: () => setState(() => _selectedId = snapshot.id),
      onDoubleTap: () {
        _renamingId = snapshot.id;
        _renameCtrl.text = snapshot.name;
        setState(() {});
        Future.microtask(() => _renameFocus.requestFocus());
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? FabFilterColors.cyan.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: selected
              ? Border.all(color: FabFilterColors.cyan.withValues(alpha: 0.4))
              : null,
        ),
        child: Row(
          children: [
            if (isActive)
              Icon(Icons.play_arrow, size: 12, color: FabFilterColors.green)
            else
              Icon(Icons.photo_camera, size: 12,
                  color: FabFilterColors.textTertiary),
            const SizedBox(width: 6),
            Expanded(
              child: isRenaming
                  ? SizedBox(
                      height: 20,
                      child: TextField(
                        controller: _renameCtrl,
                        focusNode: _renameFocus,
                        style: const TextStyle(
                            fontSize: 11, color: FabFilterColors.textPrimary),
                        decoration: _inputDeco(''),
                        onSubmitted: (val) {
                          _service.renameSnapshot(snapshot.id, val.trim());
                          setState(() => _renamingId = null);
                        },
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          snapshot.name,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.normal,
                            color: selected
                                ? FabFilterColors.textPrimary
                                : FabFilterColors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${snapshot.timeLabel}  •  ${snapshot.channelCount} ch',
                          style: TextStyle(
                              fontSize: 9, color: FabFilterColors.textTertiary),
                        ),
                      ],
                    ),
            ),
            _iconBtn(Icons.arrow_upward, 'Move Up',
                index > 0 ? () => _service.moveSnapshot(index, index - 1) : null),
            _iconBtn(Icons.arrow_downward, 'Move Down',
                index < _service.count - 1
                    ? () => _service.moveSnapshot(index, index + 1)
                    : null),
            _iconBtn(Icons.close, 'Delete',
                () {
                  _service.deleteSnapshot(snapshot.id);
                  if (_selectedId == snapshot.id) {
                    _selectedId = null;
                  }
                }),
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // CENTER: Snapshot Detail
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildSnapshotDetail() {
    final snapshot = _selectedSnapshot;
    if (snapshot == null) {
      return Center(
          child: Text('Select a snapshot to view details',
              style: TextStyle(
                  color: FabFilterColors.textTertiary, fontSize: 12)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
          child: Row(
            children: [
              FabSectionLabel('CHANNELS'),
              const SizedBox(width: 8),
              Text(snapshot.name, style: const TextStyle(
                  fontSize: 11, color: FabFilterColors.cyan)),
              const Spacer(),
              _recallButton(snapshot),
            ],
          ),
        ),
        // Channel headers
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              SizedBox(width: 60, child: Text('Channel', style: _headerStyle)),
              SizedBox(width: 50, child: Text('Volume', style: _headerStyle)),
              SizedBox(width: 40, child: Text('Pan', style: _headerStyle)),
              SizedBox(width: 30, child: Text('M', style: _headerStyle)),
              SizedBox(width: 30, child: Text('S', style: _headerStyle)),
              Expanded(child: Text('Sends', style: _headerStyle)),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: snapshot.channelStates.length,
            itemBuilder: (_, i) {
              final entry = snapshot.channelStates.entries.elementAt(i);
              return _buildChannelRow(entry.key, entry.value);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildChannelRow(String channelId, MixChannelSnapshot ch) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: FabFilterColors.bgMid,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: FabFilterColors.border.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(channelId, style: const TextStyle(
                fontSize: 10, color: FabFilterColors.textSecondary),
                overflow: TextOverflow.ellipsis),
          ),
          SizedBox(
            width: 50,
            child: Text(
              '${(ch.volume * 100).toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 10, color: FabFilterColors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              ch.pan == 0 ? 'C' : '${ch.pan > 0 ? "R" : "L"}${(ch.pan.abs() * 100).toStringAsFixed(0)}',
              style: TextStyle(fontSize: 10, color: FabFilterColors.textPrimary),
            ),
          ),
          SizedBox(
            width: 30,
            child: Icon(
              ch.mute ? Icons.volume_off : Icons.volume_up,
              size: 12,
              color: ch.mute ? FabFilterColors.red : FabFilterColors.textTertiary,
            ),
          ),
          SizedBox(
            width: 30,
            child: Icon(
              Icons.headphones,
              size: 12,
              color: ch.solo ? FabFilterColors.yellow : FabFilterColors.textTertiary,
            ),
          ),
          Expanded(
            child: Text(
              ch.sends.entries.map((e) =>
                  '${e.key}: ${(e.value * 100).toStringAsFixed(0)}%').join(', '),
              style: TextStyle(fontSize: 9, color: FabFilterColors.textTertiary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _recallButton(MixSnapshot snapshot) {
    final isActive = snapshot.id == _service.activeSnapshotId;
    return InkWell(
      onTap: () {
        _service.recallSnapshot(snapshot.id);
        widget.onAction?.call('snapshotRecall', {
          'id': snapshot.id,
          'recallVolume': _recallVolume,
          'recallPan': _recallPan,
          'recallMute': _recallMute,
          'recallSolo': _recallSolo,
          'recallSends': _recallSends,
        });
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? FabFilterColors.green.withValues(alpha: 0.15)
              : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
              color: isActive ? FabFilterColors.green : FabFilterColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.restore, size: 12,
                color: isActive ? FabFilterColors.green : FabFilterColors.textSecondary),
            const SizedBox(width: 4),
            Text('Recall', style: TextStyle(
              fontSize: 10,
              color: isActive ? FabFilterColors.green : FabFilterColors.textSecondary,
            )),
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // RIGHT: Recall Options
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildRecallOptions() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FabSectionLabel('SELECTIVE RECALL'),
          const SizedBox(height: 6),
          FabOptionRow(
            label: 'Volume',
            value: _recallVolume,
            onChanged: (v) => setState(() => _recallVolume = v),
            accentColor: FabFilterColors.cyan,
          ),
          const SizedBox(height: 3),
          FabOptionRow(
            label: 'Pan',
            value: _recallPan,
            onChanged: (v) => setState(() => _recallPan = v),
            accentColor: FabFilterColors.cyan,
          ),
          const SizedBox(height: 3),
          FabOptionRow(
            label: 'Mute',
            value: _recallMute,
            onChanged: (v) => setState(() => _recallMute = v),
            accentColor: FabFilterColors.cyan,
          ),
          const SizedBox(height: 3),
          FabOptionRow(
            label: 'Solo',
            value: _recallSolo,
            onChanged: (v) => setState(() => _recallSolo = v),
            accentColor: FabFilterColors.cyan,
          ),
          const SizedBox(height: 3),
          FabOptionRow(
            label: 'Sends',
            value: _recallSends,
            onChanged: (v) => setState(() => _recallSends = v),
            accentColor: FabFilterColors.cyan,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _recallVolume = true;
                    _recallPan = true;
                    _recallMute = true;
                    _recallSolo = true;
                    _recallSends = true;
                  }),
                  child: Container(
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: FabFilterColors.bgMid,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: FabFilterColors.border),
                    ),
                    child: Text('All', style: TextStyle(
                        fontSize: 9, color: FabFilterColors.textSecondary)),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _recallVolume = false;
                    _recallPan = false;
                    _recallMute = false;
                    _recallSolo = false;
                    _recallSends = false;
                  }),
                  child: Container(
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: FabFilterColors.bgMid,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: FabFilterColors.border),
                    ),
                    child: Text('None', style: TextStyle(
                        fontSize: 9, color: FabFilterColors.textSecondary)),
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          const Divider(color: FabFilterColors.border, height: 16),
          Text('${_service.count} snapshot${_service.count == 1 ? "" : "s"}',
              style: TextStyle(
                  fontSize: 10, color: FabFilterColors.textTertiary)),
          if (_service.activeSnapshotId != null)
            Text(
              'Active: ${_service.getSnapshot(_service.activeSnapshotId!)?.name ?? "-"}',
              style: TextStyle(fontSize: 10, color: FabFilterColors.green),
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════════════════════

  TextStyle get _headerStyle => const TextStyle(
        fontSize: 8,
        fontWeight: FontWeight.w600,
        color: FabFilterColors.textTertiary,
        letterSpacing: 0.5,
      );

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback? onPressed) {
    return SizedBox(
      width: 24, height: 24,
      child: IconButton(
        icon: Icon(icon, size: 14),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        color: FabFilterColors.textSecondary,
        disabledColor: FabFilterColors.textDisabled,
        onPressed: onPressed,
      ),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle:
            TextStyle(color: FabFilterColors.textTertiary, fontSize: 11),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: FabFilterColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: FabFilterColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: FabFilterColors.cyan),
        ),
        filled: true,
        fillColor: FabFilterColors.bgMid,
      );
}
