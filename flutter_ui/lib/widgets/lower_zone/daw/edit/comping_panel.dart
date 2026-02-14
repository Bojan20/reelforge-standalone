// Comping Panel — DAW Lower Zone EDIT tab
// Professional take lanes and comp region management (Pro Tools/Cubase style)

import 'package:flutter/material.dart';
import '../../../../providers/comping_provider.dart';
import '../../../../models/comping_models.dart';
import '../../lower_zone_types.dart';

class CompingPanel extends StatefulWidget {
  final int? selectedTrackId;
  final void Function(String action, Map<String, dynamic>? params)? onAction;

  const CompingPanel({super.key, this.selectedTrackId, this.onAction});

  @override
  State<CompingPanel> createState() => _CompingPanelState();
}

class _CompingPanelState extends State<CompingPanel> {
  final _provider = CompingProvider();
  String? _selectedLaneId;
  String? _selectedTakeId;

  @override
  void initState() {
    super.initState();
    _provider.addListener(_onChanged);
  }

  @override
  void dispose() {
    _provider.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  CompState? get _trackState {
    final trackId = widget.selectedTrackId;
    if (trackId == null) return null;
    return _provider.getCompState(trackId.toString());
  }

  @override
  Widget build(BuildContext context) {
    final trackState = _trackState;
    if (widget.selectedTrackId == null) {
      return _buildNoTrack();
    }

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(trackState),
          const SizedBox(height: 8),
          Expanded(
            child: trackState == null || trackState.lanes.isEmpty
                ? _buildEmptyState()
                : _buildLanesView(trackState),
          ),
        ],
      ),
    );
  }

  Widget _buildNoTrack() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.layers, size: 32, color: Colors.white24),
          const SizedBox(height: 8),
          Text('Select a track to manage takes',
              style: LowerZoneTypography.label.copyWith(color: Colors.white38)),
        ],
      ),
    );
  }

  Widget _buildHeader(CompState? state) {
    return Row(
      children: [
        const Icon(Icons.layers, size: 16, color: Colors.cyan),
        const SizedBox(width: 6),
        Text('COMPING', style: LowerZoneTypography.title.copyWith(color: Colors.white70)),
        const SizedBox(width: 8),
        if (state != null) ...[
          _buildModeBadge(state.mode),
          const Spacer(),
          // Lane count
          Text('${state.lanes.length} lanes',
              style: LowerZoneTypography.badge.copyWith(color: Colors.white38)),
          const SizedBox(width: 8),
          // Quick actions
          _buildActionButton(Icons.add, 'Add Lane', () {
            _provider.createLane(widget.selectedTrackId!.toString(), name: 'Lane ${(state.lanes.length) + 1}');
          }),
          _buildActionButton(Icons.auto_fix_high, 'Promote Best', () {
            _provider.promoteBestTakes(widget.selectedTrackId!.toString());
          }),
          _buildActionButton(Icons.delete_sweep, 'Delete Bad', () {
            _provider.deleteBadTakes(widget.selectedTrackId!.toString());
          }),
          _buildActionButton(Icons.call_merge, 'Flatten', () {
            _provider.flattenComp(widget.selectedTrackId!.toString(), '/tmp/comp_output.wav');
            widget.onAction?.call('flattenComp', {'trackId': widget.selectedTrackId});
          }),
        ] else ...[
          const Spacer(),
          _buildActionButton(Icons.add, 'Create First Lane', () {
            _provider.createLane(widget.selectedTrackId!.toString(), name: 'Lane 1');
          }),
        ],
      ],
    );
  }

  Widget _buildModeBadge(CompMode mode) {
    final (label, color) = switch (mode) {
      CompMode.single => ('SINGLE', Colors.blue),
      CompMode.comp => ('COMP', Colors.orange),
      CompMode.auditAll => ('AUDIT ALL', Colors.green),
    };
    return GestureDetector(
      onTap: () {
        final next = CompMode.values[(mode.index + 1) % CompMode.values.length];
        _provider.setCompMode(widget.selectedTrackId!.toString(), next);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(label,
            style: LowerZoneTypography.badge.copyWith(color: color, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: Colors.white54),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.library_add, size: 32, color: Colors.white24),
          const SizedBox(height: 8),
          Text('No recording lanes',
              style: LowerZoneTypography.label.copyWith(color: Colors.white38)),
          const SizedBox(height: 4),
          Text('Add a lane to start recording takes',
              style: LowerZoneTypography.badge.copyWith(color: Colors.white24)),
        ],
      ),
    );
  }

  Widget _buildLanesView(CompState state) {
    return ListView.builder(
      itemCount: state.lanes.length,
      itemBuilder: (context, index) {
        final lane = state.lanes[index];
        return _buildLaneRow(lane, index, state);
      },
    );
  }

  Widget _buildLaneRow(RecordingLane lane, int index, CompState state) {
    final isSelected = _selectedLaneId == lane.id;
    final isActive = state.activeLane?.id == lane.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isSelected
            ? Colors.cyan.withOpacity(0.1)
            : Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isActive
              ? Colors.cyan.withOpacity(0.5)
              : isSelected
                  ? Colors.cyan.withOpacity(0.3)
                  : Colors.white.withOpacity(0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Lane header
          InkWell(
            onTap: () => setState(() => _selectedLaneId = isSelected ? null : lane.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  // Active indicator
                  GestureDetector(
                    onTap: () => _provider.setActiveLane(widget.selectedTrackId!.toString(), index),
                    child: Icon(
                      isActive ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      size: 14,
                      color: isActive ? Colors.cyan : Colors.white38,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(lane.name,
                      style: LowerZoneTypography.label.copyWith(
                          color: isActive ? Colors.cyan : Colors.white70)),
                  const Spacer(),
                  // Take count
                  Text('${lane.takes.length} takes',
                      style: LowerZoneTypography.badge.copyWith(color: Colors.white38)),
                  const SizedBox(width: 6),
                  // Mute
                  GestureDetector(
                    onTap: () => _provider.toggleLaneMute(widget.selectedTrackId!.toString(), lane.id),
                    child: Icon(
                      lane.muted ? Icons.volume_off : Icons.volume_up,
                      size: 14,
                      color: lane.muted ? Colors.red : Colors.white38,
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Delete
                  GestureDetector(
                    onTap: () => _provider.deleteLane(widget.selectedTrackId!.toString(), lane.id),
                    child: const Icon(Icons.close, size: 14, color: Colors.white24),
                  ),
                ],
              ),
            ),
          ),
          // Takes list (expanded)
          if (isSelected && lane.takes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 8, 4),
              child: Column(
                children: lane.takes.map((take) => _buildTakeItem(take, lane)).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTakeItem(Take take, RecordingLane lane) {
    final isSelected = _selectedTakeId == take.id;
    final ratingColor = switch (take.rating) {
      TakeRating.best => Colors.green,
      TakeRating.good => Colors.lightGreen,
      TakeRating.okay => Colors.yellow,
      TakeRating.bad => Colors.red,
      TakeRating.none => Colors.white38,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: isSelected ? Colors.cyan.withOpacity(0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(3),
      ),
      child: InkWell(
        onTap: () => setState(() => _selectedTakeId = isSelected ? null : take.id),
        child: Row(
          children: [
            // Rating star
            GestureDetector(
              onTap: () {
                final next = TakeRating.values[(take.rating.index + 1) % TakeRating.values.length];
                _provider.setTakeRating(widget.selectedTrackId!.toString(), take.id, next);
              },
              child: Icon(Icons.star, size: 12, color: ratingColor),
            ),
            const SizedBox(width: 4),
            Text(take.displayName,
                style: LowerZoneTypography.badge.copyWith(
                    color: take.muted ? Colors.white24 : Colors.white54)),
            const Spacer(),
            // Gain
            Text('${(take.gain * 100).toInt()}%',
                style: LowerZoneTypography.badge.copyWith(color: Colors.white24)),
            const SizedBox(width: 4),
            // Mute toggle
            GestureDetector(
              onTap: () => _provider.toggleTakeMute(widget.selectedTrackId!.toString(), take.id),
              child: Icon(
                take.muted ? Icons.visibility_off : Icons.visibility,
                size: 12,
                color: take.muted ? Colors.red.shade300 : Colors.white30,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
