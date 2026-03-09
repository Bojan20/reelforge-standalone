/// Region Playlist Panel — FabFilter-style DAW Lower Zone EDIT tab
///
/// #26: Non-linear playback with independent region ordering.
///
/// Features:
/// - Create/manage named playlists
/// - Add region entries by start/end time
/// - Per-entry loop count, fade, and gain
/// - Drag reorder entries
/// - Playback controls (play/pause/stop/skip)
library;

import 'package:flutter/material.dart';
import '../../../../services/region_playlist_service.dart';
import '../../../fabfilter/fabfilter_theme.dart';
import '../../../fabfilter/fabfilter_widgets.dart';

class RegionPlaylistPanel extends StatefulWidget {
  final void Function(String action, Map<String, dynamic>? params)? onAction;

  const RegionPlaylistPanel({super.key, this.onAction});

  @override
  State<RegionPlaylistPanel> createState() => _RegionPlaylistPanelState();
}

class _RegionPlaylistPanelState extends State<RegionPlaylistPanel> {
  final _service = RegionPlaylistService.instance;
  String? _selectedPlaylistId;

  // New playlist form
  late TextEditingController _playlistNameCtrl;
  late FocusNode _playlistNameFocus;
  bool _showAddPlaylist = false;

  // New entry form
  late TextEditingController _entryLabelCtrl;
  late TextEditingController _entryStartCtrl;
  late TextEditingController _entryEndCtrl;
  late TextEditingController _entryLoopCtrl;
  late FocusNode _entryLabelFocus;
  late FocusNode _entryStartFocus;
  late FocusNode _entryEndFocus;
  late FocusNode _entryLoopFocus;
  bool _showAddEntry = false;

  @override
  void initState() {
    super.initState();
    _playlistNameCtrl = TextEditingController();
    _playlistNameFocus = FocusNode();
    _entryLabelCtrl = TextEditingController();
    _entryStartCtrl = TextEditingController(text: '0.0');
    _entryEndCtrl = TextEditingController(text: '10.0');
    _entryLoopCtrl = TextEditingController(text: '0');
    _entryLabelFocus = FocusNode();
    _entryStartFocus = FocusNode();
    _entryEndFocus = FocusNode();
    _entryLoopFocus = FocusNode();
    _service.addListener(_onChanged);
  }

  @override
  void dispose() {
    _playlistNameCtrl.dispose();
    _playlistNameFocus.dispose();
    _entryLabelCtrl.dispose();
    _entryStartCtrl.dispose();
    _entryEndCtrl.dispose();
    _entryLoopCtrl.dispose();
    _entryLabelFocus.dispose();
    _entryStartFocus.dispose();
    _entryEndFocus.dispose();
    _entryLoopFocus.dispose();
    _service.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  RegionPlaylist? get _selectedPlaylist =>
      _selectedPlaylistId != null ? _service.getPlaylist(_selectedPlaylistId!) : null;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 220, child: _buildPlaylistList()),
        const VerticalDivider(width: 1, color: FabFilterColors.border),
        Expanded(flex: 2, child: _buildEntriesEditor()),
        const VerticalDivider(width: 1, color: FabFilterColors.border),
        SizedBox(width: 200, child: _buildControlsPanel()),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // LEFT: Playlist List
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildPlaylistList() {
    final lists = _service.playlists;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
          child: Row(
            children: [
              FabSectionLabel('PLAYLISTS'),
              const Spacer(),
              _iconBtn(Icons.add, 'New Playlist',
                () => setState(() => _showAddPlaylist = !_showAddPlaylist)),
            ],
          ),
        ),
        if (_showAddPlaylist) _buildAddPlaylistForm(),
        Expanded(
          child: lists.isEmpty
              ? Center(child: Text('No playlists.\nClick + to create.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: FabFilterColors.textTertiary, fontSize: 11)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: lists.length,
                  itemBuilder: (_, i) => _buildPlaylistItem(lists[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildAddPlaylistForm() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          Expanded(child: SizedBox(height: 26, child: TextField(
            controller: _playlistNameCtrl,
            focusNode: _playlistNameFocus,
            style: const TextStyle(fontSize: 11, color: FabFilterColors.textPrimary),
            decoration: _inputDeco('Playlist name...'),
            onSubmitted: (_) => _createPlaylist(),
          ))),
          const SizedBox(width: 4),
          _iconBtn(Icons.check, 'Create', _createPlaylist),
        ],
      ),
    );
  }

  void _createPlaylist() {
    final name = _playlistNameCtrl.text.trim();
    if (name.isEmpty) return;
    final id = 'playlist_${DateTime.now().millisecondsSinceEpoch}';
    _service.addPlaylist(RegionPlaylist(id: id, name: name, entries: []));
    _playlistNameCtrl.clear();
    setState(() {
      _showAddPlaylist = false;
      _selectedPlaylistId = id;
    });
  }

  Widget _buildPlaylistItem(RegionPlaylist pl) {
    final selected = pl.id == _selectedPlaylistId;
    final isActive = pl.id == _service.activePlaylistId;
    return InkWell(
      onTap: () => setState(() => _selectedPlaylistId = pl.id),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? FabFilterColors.cyan.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: selected
              ? Border.all(color: FabFilterColors.cyan.withValues(alpha: 0.4))
              : null,
        ),
        child: Row(
          children: [
            Icon(
              isActive ? Icons.play_circle_filled : Icons.playlist_play,
              size: 14,
              color: isActive ? FabFilterColors.green
                  : selected ? FabFilterColors.cyan : FabFilterColors.textTertiary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pl.name, style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected ? FabFilterColors.textPrimary : FabFilterColors.textSecondary,
                  ), overflow: TextOverflow.ellipsis),
                  if (pl.description != null)
                    Text(pl.description!, style: TextStyle(
                      fontSize: 9, color: FabFilterColors.textTertiary,
                    ), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Text('${pl.entryCount}', style: TextStyle(
              fontSize: 10, color: FabFilterColors.textTertiary)),
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // CENTER: Entries Editor
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildEntriesEditor() {
    final pl = _selectedPlaylist;
    if (pl == null) {
      return Center(child: Text('Select a playlist to view entries',
        style: TextStyle(color: FabFilterColors.textTertiary, fontSize: 12)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
          child: Row(
            children: [
              FabSectionLabel('ENTRIES'),
              const SizedBox(width: 8),
              Text(pl.name, style: const TextStyle(fontSize: 11, color: FabFilterColors.cyan)),
              const Spacer(),
              Text(_formatTime(pl.totalDuration), style: TextStyle(
                fontSize: 10, color: FabFilterColors.textTertiary)),
              const SizedBox(width: 8),
              _iconBtn(Icons.add, 'Add Entry',
                () => setState(() => _showAddEntry = !_showAddEntry)),
            ],
          ),
        ),
        if (_showAddEntry) _buildAddEntryForm(),
        Expanded(
          child: pl.entries.isEmpty
              ? Center(child: Text('No entries. Click + to add region entries.',
                  style: TextStyle(color: FabFilterColors.textTertiary, fontSize: 11)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: pl.entries.length,
                  itemBuilder: (_, i) => _buildEntryItem(pl, i),
                ),
        ),
      ],
    );
  }

  Widget _buildAddEntryForm() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 26, child: TextField(
            controller: _entryLabelCtrl,
            focusNode: _entryLabelFocus,
            style: const TextStyle(fontSize: 11, color: FabFilterColors.textPrimary),
            decoration: _inputDeco('Region label...'),
          )),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: SizedBox(height: 26, child: TextField(
              controller: _entryStartCtrl,
              focusNode: _entryStartFocus,
              style: const TextStyle(fontSize: 11, color: FabFilterColors.textPrimary),
              decoration: _inputDeco('Start (s)'),
              keyboardType: TextInputType.number,
            ))),
            const SizedBox(width: 4),
            Expanded(child: SizedBox(height: 26, child: TextField(
              controller: _entryEndCtrl,
              focusNode: _entryEndFocus,
              style: const TextStyle(fontSize: 11, color: FabFilterColors.textPrimary),
              decoration: _inputDeco('End (s)'),
              keyboardType: TextInputType.number,
            ))),
            const SizedBox(width: 4),
            SizedBox(width: 60, height: 26, child: TextField(
              controller: _entryLoopCtrl,
              focusNode: _entryLoopFocus,
              style: const TextStyle(fontSize: 11, color: FabFilterColors.textPrimary),
              decoration: _inputDeco('Loops'),
              keyboardType: TextInputType.number,
            )),
          ]),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            _iconBtn(Icons.close, 'Cancel', () => setState(() => _showAddEntry = false)),
            const SizedBox(width: 4),
            _iconBtn(Icons.check, 'Add', _addEntry),
          ]),
        ],
      ),
    );
  }

  void _addEntry() {
    final plId = _selectedPlaylistId;
    if (plId == null) return;

    final label = _entryLabelCtrl.text.trim();
    if (label.isEmpty) return;

    final start = double.tryParse(_entryStartCtrl.text) ?? 0;
    final end = double.tryParse(_entryEndCtrl.text) ?? 10;
    final loops = int.tryParse(_entryLoopCtrl.text) ?? 0;

    if (end <= start) return;

    final id = 'entry_${DateTime.now().millisecondsSinceEpoch}';
    _service.addEntry(plId, PlaylistEntry(
      id: id,
      label: label,
      startTime: start,
      endTime: end,
      loopCount: loops,
    ));
    _entryLabelCtrl.clear();
    setState(() => _showAddEntry = false);
  }

  Widget _buildEntryItem(RegionPlaylist pl, int index) {
    final entry = pl.entries[index];
    final isCurrent = index == pl.currentIndex &&
        _service.activePlaylistId == pl.id;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: isCurrent ? FabFilterColors.green.withValues(alpha: 0.1) : FabFilterColors.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: isCurrent
            ? Border.all(color: FabFilterColors.green.withValues(alpha: 0.3))
            : Border.all(color: FabFilterColors.border.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          // Position number
          SizedBox(width: 20, child: Text('${index + 1}', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              color: isCurrent ? FabFilterColors.green : FabFilterColors.textTertiary))),
          const SizedBox(width: 6),
          // Play indicator / skip-to button
          GestureDetector(
            onTap: () {
              if (_service.state == PlaylistState.playing) {
                _service.skipToEntry(pl.id, index);
              }
            },
            child: Icon(
              isCurrent ? Icons.play_arrow : Icons.chevron_right,
              size: 14,
              color: isCurrent ? FabFilterColors.green : FabFilterColors.textTertiary,
            ),
          ),
          const SizedBox(width: 4),
          // Label + time range
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.label, style: TextStyle(fontSize: 11,
                  color: isCurrent ? FabFilterColors.textPrimary : FabFilterColors.textSecondary),
                  overflow: TextOverflow.ellipsis),
                Row(children: [
                  Text('${_formatTime(entry.startTime)} → ${_formatTime(entry.endTime)}',
                    style: TextStyle(fontSize: 9, color: FabFilterColors.textTertiary)),
                  if (entry.loopCount != 0) ...[
                    const SizedBox(width: 6),
                    Text(entry.loopCount < 0 ? '∞' : '×${entry.loopCount + 1}',
                      style: TextStyle(fontSize: 9, color: FabFilterColors.orange)),
                  ],
                ]),
              ],
            ),
          ),
          // Duration
          Text(_formatTime(entry.duration), style: TextStyle(
            fontSize: 10, color: FabFilterColors.textTertiary)),
          const SizedBox(width: 4),
          // Reorder
          _iconBtn(Icons.arrow_upward, 'Move Up',
            index > 0 ? () => _service.moveEntryUp(pl.id, index) : null),
          _iconBtn(Icons.arrow_downward, 'Move Down',
            index < pl.entries.length - 1 ? () => _service.moveEntryDown(pl.id, index) : null),
          _iconBtn(Icons.close, 'Remove',
            () => _service.removeEntry(pl.id, entry.id)),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // RIGHT: Controls Panel
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildControlsPanel() {
    final pl = _selectedPlaylist;
    final isActive = pl != null && pl.id == _service.activePlaylistId;
    final isPlaying = _service.state == PlaylistState.playing && isActive;
    final isPaused = _service.state == PlaylistState.paused && isActive;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FabSectionLabel('TRANSPORT'),
          const SizedBox(height: 8),
          // Play / Pause
          _actionButton(
            isPlaying ? Icons.pause : Icons.play_arrow,
            isPlaying ? 'Pause' : 'Play',
            pl != null && !pl.isEmpty
                ? () {
                    if (isPlaying) {
                      _service.pause();
                    } else if (isPaused) {
                      _service.resume();
                    } else {
                      _service.play(pl.id);
                    }
                    widget.onAction?.call('regionPlaylistPlay', {'playlistId': pl.id});
                  }
                : null,
          ),
          const SizedBox(height: 4),
          // Stop
          _actionButton(Icons.stop, 'Stop',
            isActive ? () => _service.stop() : null),
          const SizedBox(height: 4),
          // Skip Previous / Next
          Row(children: [
            Expanded(child: _actionButton(Icons.skip_previous, 'Prev',
              isActive ? () => _service.skipPrevious() : null)),
            const SizedBox(width: 4),
            Expanded(child: _actionButton(Icons.skip_next, 'Next',
              isActive ? () => _service.skipNext() : null)),
          ]),
          const SizedBox(height: 12),
          FabSectionLabel('MANAGE'),
          const SizedBox(height: 4),
          _actionButton(Icons.copy, 'Duplicate',
            pl != null ? () => _service.duplicatePlaylist(pl.id) : null),
          const SizedBox(height: 4),
          _actionButton(Icons.delete_outline, 'Delete',
            pl != null ? () {
              _service.removePlaylist(pl.id);
              setState(() => _selectedPlaylistId = null);
            } : null),
          const Spacer(),
          // Status info
          if (pl != null) ...[
            const Divider(color: FabFilterColors.border, height: 16),
            Text('Entries: ${pl.entryCount}',
              style: TextStyle(fontSize: 10, color: FabFilterColors.textTertiary)),
            Text('Total: ${_formatTime(pl.totalDuration)}',
              style: TextStyle(fontSize: 10, color: FabFilterColors.textTertiary)),
            if (isActive && pl.currentEntry != null)
              Text('Now: ${pl.currentEntry!.label}',
                style: TextStyle(fontSize: 10, color: FabFilterColors.green)),
          ],
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════════════════════

  String _formatTime(double seconds) {
    final m = (seconds / 60).floor();
    final s = (seconds % 60).toStringAsFixed(1);
    return '$m:${s.padLeft(4, '0')}';
  }

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
            border: Border.all(color: FabFilterColors.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14,
                color: enabled ? FabFilterColors.textSecondary : FabFilterColors.textDisabled),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 11,
                color: enabled ? FabFilterColors.textSecondary : FabFilterColors.textDisabled)),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: FabFilterColors.textTertiary, fontSize: 11),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
