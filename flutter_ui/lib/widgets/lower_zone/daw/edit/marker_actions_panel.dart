/// Marker Actions Panel — FabFilter-style DAW Lower Zone EDIT tab
///
/// #27: Actions bound to timeline markers. `!actionId` in marker name
/// triggers the action when play cursor passes the marker.
///
/// Features:
/// - View all action markers (markers with `!` prefix)
/// - Enable/disable individual marker actions
/// - Toggle trigger mode (always vs once per session)
/// - Sync from MarkerService automatically
/// - Manual action registration
library;

import 'package:flutter/material.dart';
import '../../../../services/marker_action_service.dart';
import '../../../daw/marker_system.dart';
import '../../../fabfilter/fabfilter_theme.dart';
import '../../../fabfilter/fabfilter_widgets.dart';

class MarkerActionsPanel extends StatefulWidget {
  final void Function(String action, Map<String, dynamic>? params)? onAction;

  const MarkerActionsPanel({super.key, this.onAction});

  @override
  State<MarkerActionsPanel> createState() => _MarkerActionsPanelState();
}

class _MarkerActionsPanelState extends State<MarkerActionsPanel> {
  final _service = MarkerActionService.instance;
  final _markerService = MarkerService.instance;
  String? _selectedMarkerId;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onChanged);
    _markerService.addListener(_onMarkersChanged);
    // Initial sync
    _service.syncFromMarkers(_markerService.markers);
  }

  @override
  void dispose() {
    _service.removeListener(_onChanged);
    _markerService.removeListener(_onMarkersChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _onMarkersChanged() {
    _service.syncFromMarkers(_markerService.markers);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 260, child: _buildMarkerList()),
        const VerticalDivider(width: 1, color: FabFilterColors.border),
        Expanded(flex: 2, child: _buildActionDetails()),
        const VerticalDivider(width: 1, color: FabFilterColors.border),
        SizedBox(width: 200, child: _buildInfoPanel()),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // LEFT: Action Markers List
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildMarkerList() {
    final actions = _service.actions;
    final actionMarkers = _markerService.sortedMarkers
        .where((m) => m.name.startsWith('!'))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
          child: Row(
            children: [
              FabSectionLabel('ACTION MARKERS'),
              const Spacer(),
              _iconBtn(Icons.sync, 'Sync from markers',
                () => _service.syncFromMarkers(_markerService.markers)),
            ],
          ),
        ),
        Expanded(
          child: actionMarkers.isEmpty
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No action markers found.\n\n'
                    'Name a marker with ! prefix\n'
                    'to create an action marker.\n\n'
                    'Example: !setMonitorMode\n'
                    'Example: !mix.toggle_mute',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: FabFilterColors.textTertiary, fontSize: 11),
                  ),
                ))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: actionMarkers.length,
                  itemBuilder: (_, i) {
                    final marker = actionMarkers[i];
                    final action = _service.getAction(marker.id);
                    return _buildMarkerItem(marker, action);
                  },
                ),
        ),
        // All markers section
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
          child: Row(
            children: [
              FabSectionLabel('ALL MARKERS'),
              const Spacer(),
              Text('${_markerService.markers.length}',
                style: TextStyle(fontSize: 10, color: FabFilterColors.textTertiary)),
            ],
          ),
        ),
        SizedBox(
          height: 100,
          child: _markerService.markers.isEmpty
              ? Center(child: Text('No markers',
                  style: TextStyle(color: FabFilterColors.textTertiary, fontSize: 10)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: _markerService.sortedMarkers.length,
                  itemBuilder: (_, i) {
                    final m = _markerService.sortedMarkers[i];
                    final isAction = m.name.startsWith('!');
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 4),
                      child: Row(children: [
                        Icon(isAction ? Icons.bolt : Icons.flag, size: 12,
                          color: isAction ? FabFilterColors.orange : m.color),
                        const SizedBox(width: 4),
                        Expanded(child: Text(m.name, style: TextStyle(
                          fontSize: 10,
                          color: isAction ? FabFilterColors.orange : FabFilterColors.textTertiary,
                        ), overflow: TextOverflow.ellipsis)),
                        Text(_formatTime(m.time), style: TextStyle(
                          fontSize: 9, color: FabFilterColors.textTertiary)),
                      ]),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildMarkerItem(DawMarker marker, MarkerAction? action) {
    final selected = marker.id == _selectedMarkerId;
    final enabled = action?.enabled ?? false;

    return InkWell(
      onTap: () => setState(() => _selectedMarkerId = marker.id),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? FabFilterColors.orange.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: selected
              ? Border.all(color: FabFilterColors.orange.withValues(alpha: 0.4))
              : null,
        ),
        child: Row(
          children: [
            Icon(Icons.bolt, size: 14,
              color: enabled ? FabFilterColors.orange : FabFilterColors.textDisabled),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(marker.name, style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color: enabled ? FabFilterColors.textPrimary : FabFilterColors.textTertiary,
                  ), overflow: TextOverflow.ellipsis),
                  if (action != null)
                    Text('→ ${action.actionId}', style: TextStyle(
                      fontSize: 9, color: FabFilterColors.orange)),
                ],
              ),
            ),
            Text(_formatTime(marker.time), style: TextStyle(
              fontSize: 10, color: FabFilterColors.textTertiary)),
            const SizedBox(width: 4),
            // Enable/disable toggle
            GestureDetector(
              onTap: action != null
                  ? () => _service.toggleEnabled(marker.id)
                  : null,
              child: Container(
                width: 16, height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: enabled
                      ? FabFilterColors.green.withValues(alpha: 0.3)
                      : FabFilterColors.bgMid,
                  border: Border.all(
                    color: enabled ? FabFilterColors.green : FabFilterColors.border,
                  ),
                ),
                child: enabled
                    ? Icon(Icons.check, size: 10, color: FabFilterColors.green)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // CENTER: Action Details
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildActionDetails() {
    final marker = _selectedMarkerId != null
        ? _markerService.markers.where((m) => m.id == _selectedMarkerId).firstOrNull
        : null;
    final action = _selectedMarkerId != null
        ? _service.getAction(_selectedMarkerId!)
        : null;

    if (marker == null || action == null) {
      return Center(child: Text(
        'Select an action marker to view details',
        style: TextStyle(color: FabFilterColors.textTertiary, fontSize: 12),
      ));
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FabSectionLabel('MARKER DETAILS'),
          const SizedBox(height: 8),
          // Marker info row
          Row(children: [
            Icon(Icons.bolt, size: 16, color: FabFilterColors.orange),
            const SizedBox(width: 6),
            Text(marker.name, style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: FabFilterColors.textPrimary)),
          ]),
          const SizedBox(height: 4),
          Text('Time: ${_formatTime(marker.time)}  |  Category: ${marker.category.label}',
            style: TextStyle(fontSize: 10, color: FabFilterColors.textTertiary)),
          const SizedBox(height: 12),

          // Action configuration
          FabSectionLabel('ACTION'),
          const SizedBox(height: 6),
          // Action ID
          Row(children: [
            Text('Action ID: ', style: TextStyle(
              fontSize: 11, color: FabFilterColors.textTertiary)),
            Text(action.actionId, style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: FabFilterColors.orange)),
          ]),
          const SizedBox(height: 4),
          // Params
          if (action.params != null && action.params!.isNotEmpty) ...[
            Text('Params:', style: TextStyle(
              fontSize: 10, color: FabFilterColors.textTertiary)),
            for (final entry in action.params!.entries)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text('${entry.key} = ${entry.value}', style: TextStyle(
                  fontSize: 10, color: FabFilterColors.textSecondary)),
              ),
            const SizedBox(height: 4),
          ],
          const SizedBox(height: 8),

          // Trigger mode
          FabSectionLabel('TRIGGER MODE'),
          const SizedBox(height: 6),
          Row(children: [
            _modeChip('Always', MarkerTriggerMode.always, action),
            const SizedBox(width: 4),
            _modeChip('Once', MarkerTriggerMode.once, action),
          ]),
          const SizedBox(height: 8),

          // Enabled state
          Row(children: [
            Text('Enabled: ', style: TextStyle(
              fontSize: 11, color: FabFilterColors.textTertiary)),
            GestureDetector(
              onTap: () => _service.toggleEnabled(marker.id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: action.enabled
                      ? FabFilterColors.green.withValues(alpha: 0.2)
                      : FabFilterColors.bgMid,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: action.enabled ? FabFilterColors.green : FabFilterColors.border),
                ),
                child: Text(action.enabled ? 'ON' : 'OFF', style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600,
                  color: action.enabled ? FabFilterColors.green : FabFilterColors.textTertiary,
                )),
              ),
            ),
          ]),
          const Spacer(),
          // Remove action
          _actionButton(Icons.delete_outline, 'Remove Action', () {
            _service.unregisterAction(marker.id);
            setState(() => _selectedMarkerId = null);
          }),
        ],
      ),
    );
  }

  Widget _modeChip(String label, MarkerTriggerMode mode, MarkerAction action) {
    final active = action.mode == mode;
    return GestureDetector(
      onTap: () => _service.updateAction(action.markerId, mode: mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? FabFilterColors.orange.withValues(alpha: 0.2) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: active ? FabFilterColors.orange : FabFilterColors.border),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 10,
          color: active ? FabFilterColors.orange : FabFilterColors.textTertiary,
        )),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // RIGHT: Info Panel
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildInfoPanel() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FabSectionLabel('STATUS'),
          const SizedBox(height: 8),
          Text('Action markers: ${_service.count}',
            style: TextStyle(fontSize: 10, color: FabFilterColors.textTertiary)),
          Text('Enabled: ${_service.enabledCount}',
            style: TextStyle(fontSize: 10, color: FabFilterColors.textTertiary)),
          Text('Total markers: ${_markerService.markers.length}',
            style: TextStyle(fontSize: 10, color: FabFilterColors.textTertiary)),
          const SizedBox(height: 12),
          FabSectionLabel('TOLERANCE'),
          const SizedBox(height: 4),
          Text('${_service.triggerToleranceMs.toInt()} ms',
            style: TextStyle(fontSize: 11, color: FabFilterColors.textSecondary)),
          const SizedBox(height: 12),
          FabSectionLabel('USAGE'),
          const SizedBox(height: 4),
          Text(
            'Name a marker with ! prefix\n'
            'to trigger an action when\n'
            'the playhead crosses it.\n\n'
            'Format:\n'
            '!actionId\n'
            '!actionId key=val\n'
            '!cmd.id (command)\n',
            style: TextStyle(fontSize: 10, color: FabFilterColors.textTertiary, height: 1.4),
          ),
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
}
