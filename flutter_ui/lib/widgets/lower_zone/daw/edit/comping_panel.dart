// Comping Panel — DAW Lower Zone EDIT tab
// FabFilter-style take lane management & comping (Pro Tools/Cubase style)

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../../providers/comping_provider.dart';
import '../../../../models/comping_models.dart';
import '../../../fabfilter/fabfilter_theme.dart';
import '../../../fabfilter/fabfilter_widgets.dart';

class CompingPanel extends StatefulWidget {
  final int? selectedTrackId;
  final void Function(String action, Map<String, dynamic>? params)? onAction;

  const CompingPanel({super.key, this.selectedTrackId, this.onAction});

  @override
  State<CompingPanel> createState() => _CompingPanelState();
}

class _CompingPanelState extends State<CompingPanel> {
  final _provider = GetIt.instance<CompingProvider>();
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

  String get _trackId => widget.selectedTrackId?.toString() ?? '';

  CompState? get _trackState {
    if (widget.selectedTrackId == null) return null;
    return _provider.getCompState(_trackId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (widget.selectedTrackId == null) return _buildNoTrack();

    final state = _trackState;

    return Container(
      decoration: FabFilterDecorations.panel(),
      child: Column(
        children: [
          _buildHeader(state),
          Expanded(
            child: state == null || state.lanes.isEmpty
                ? _buildEmptyState()
                : _buildLanesView(state),
          ),
          if (state != null && state.lanes.isNotEmpty) _buildActionBar(state),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader(CompState? state) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FabFilterColors.bgDeep,
        border: Border(
          bottom: BorderSide(color: FabFilterColors.cyan.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          // Title
          Text('FF COMP', style: FabFilterText.sectionHeader.copyWith(
            color: FabFilterColors.cyan, fontSize: 10, letterSpacing: 1.2,
          )),
          const SizedBox(width: 8),
          // Mode selector
          if (state != null)
            _buildModeSelector(state.mode)
          else
            Text('NO STATE', style: FabFilterText.paramLabel.copyWith(
              color: FabFilterColors.textDisabled, fontSize: 8,
            )),
          const Spacer(),
          // Lane count badge
          if (state != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: FabFilterColors.bgMid,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: FabFilterColors.borderSubtle),
              ),
              child: Text('${state.lanes.length} LN',
                style: FabFilterText.paramLabel.copyWith(
                  color: FabFilterColors.textSecondary, fontSize: 8,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          // Add lane
          _buildHeaderAction(Icons.add, 'Add Lane', () {
            final st = _trackState;
            _provider.createLane(_trackId,
              name: 'Lane ${(st?.lanes.length ?? 0) + 1}',
            );
          }),
        ],
      ),
    );
  }

  Widget _buildModeSelector(CompMode mode) {
    return FabEnumSelector(
      label: '',
      value: mode.index,
      options: const ['SGL', 'CMP', 'ALL'],
      color: FabFilterColors.cyan,
      onChanged: (i) => _provider.setCompMode(_trackId, CompMode.values[i]),
    );
  }

  Widget _buildHeaderAction(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 20, height: 20,
          decoration: BoxDecoration(
            color: FabFilterColors.bgMid,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: FabFilterColors.borderSubtle),
          ),
          child: Icon(icon, size: 12, color: FabFilterColors.textSecondary),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EMPTY / NO TRACK
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildNoTrack() {
    return Container(
      decoration: FabFilterDecorations.panel(),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.layers, size: 28, color: FabFilterColors.textDisabled),
            const SizedBox(height: 6),
            Text('SELECT A TRACK',
              style: FabFilterText.sectionHeader.copyWith(
                color: FabFilterColors.textTertiary, letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 2),
            Text('to manage take lanes',
              style: FabFilterText.paramLabel.copyWith(
                color: FabFilterColors.textDisabled, fontSize: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.library_add, size: 28, color: FabFilterColors.textDisabled),
          const SizedBox(height: 6),
          Text('NO RECORDING LANES',
            style: FabFilterText.sectionHeader.copyWith(
              color: FabFilterColors.textTertiary, letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => _provider.createLane(_trackId, name: 'Lane 1'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: FabFilterDecorations.toggleActive(FabFilterColors.cyan),
              child: Text('+ CREATE LANE', style: FabFilterText.paramLabel.copyWith(
                color: FabFilterColors.cyan, fontSize: 9, fontWeight: FontWeight.bold,
              )),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LANES LIST
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLanesView(CompState state) {
    return ListView.builder(
      padding: const EdgeInsets.all(6),
      itemCount: state.lanes.length,
      itemBuilder: (context, index) {
        final lane = state.lanes[index];
        return _buildLaneCard(lane, index, state);
      },
    );
  }

  Widget _buildLaneCard(RecordingLane lane, int index, CompState state) {
    final isSelected = _selectedLaneId == lane.id;
    final isActive = state.activeLane?.id == lane.id;
    final laneColor = lane.color ?? getLaneColor(index);
    final totalTakes = lane.takes.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isSelected ? FabFilterColors.bgElevated : FabFilterColors.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isActive
              ? laneColor.withValues(alpha: 0.6)
              : isSelected
                  ? FabFilterColors.cyan.withValues(alpha: 0.3)
                  : FabFilterColors.borderSubtle,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          // Lane header row
          GestureDetector(
            onTap: () => setState(() => _selectedLaneId = isSelected ? null : lane.id),
            child: Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  // Active radio
                  GestureDetector(
                    onTap: () => _provider.setActiveLane(_trackId, index),
                    child: Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isActive ? laneColor : Colors.transparent,
                        border: Border.all(
                          color: isActive ? laneColor : FabFilterColors.textTertiary,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Lane name
                  Expanded(
                    child: Text(lane.displayName,
                      style: FabFilterText.paramLabel.copyWith(
                        color: isActive ? laneColor : FabFilterColors.textSecondary,
                        fontSize: 9, fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Take count meter
                  if (totalTakes > 0)
                    SizedBox(
                      width: 50,
                      child: FabHorizontalMeter(
                        label: '',
                        value: totalTakes.toDouble(),
                        maxValue: 10,
                        color: laneColor,
                        height: 8,
                        showLabel: false,
                        displayText: '$totalTakes',
                      ),
                    ),
                  const SizedBox(width: 4),
                  // Mute toggle
                  GestureDetector(
                    onTap: () => _provider.toggleLaneMute(_trackId, lane.id),
                    child: Container(
                      width: 16, height: 16,
                      decoration: BoxDecoration(
                        color: lane.muted
                            ? FabFilterColors.red.withValues(alpha: 0.2)
                            : FabFilterColors.bgSurface,
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(
                          color: lane.muted ? FabFilterColors.red : FabFilterColors.borderSubtle,
                        ),
                      ),
                      child: Icon(
                        lane.muted ? Icons.volume_off : Icons.volume_up,
                        size: 10,
                        color: lane.muted ? FabFilterColors.red : FabFilterColors.textTertiary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  // Delete lane
                  GestureDetector(
                    onTap: () => _provider.deleteLane(_trackId, lane.id),
                    child: Icon(Icons.close, size: 12, color: FabFilterColors.textDisabled),
                  ),
                ],
              ),
            ),
          ),
          // Expanded take list
          if (isSelected && lane.takes.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: FabFilterColors.borderSubtle),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(18, 3, 6, 4),
              child: Column(
                children: lane.takes.map((take) => _buildTakeRow(take, laneColor)).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAKE ROW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTakeRow(Take take, Color laneColor) {
    final isSelected = _selectedTakeId == take.id;

    return GestureDetector(
      onTap: () => setState(() => _selectedTakeId = isSelected ? null : take.id),
      child: Container(
        height: 22,
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? FabFilterColors.cyan.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          children: [
            // Rating buttons row
            _buildRatingButton(take, TakeRating.best, '\u2605', FabFilterColors.yellow),
            _buildRatingButton(take, TakeRating.good, '\u2713', FabFilterColors.green),
            _buildRatingButton(take, TakeRating.okay, '\u25CB', FabFilterColors.orange),
            _buildRatingButton(take, TakeRating.bad, '\u2717', FabFilterColors.red),
            _buildRatingButton(take, TakeRating.none, '\u2014', FabFilterColors.textDisabled),
            const SizedBox(width: 6),
            // Take name
            Expanded(
              child: Text(take.displayName,
                style: FabFilterText.paramLabel.copyWith(
                  color: take.muted ? FabFilterColors.textDisabled : FabFilterColors.textSecondary,
                  fontSize: 9,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Gain display
            Text('${(take.gain * 100).toInt()}%',
              style: FabFilterText.paramLabel.copyWith(
                color: FabFilterColors.textDisabled, fontSize: 7,
              ),
            ),
            const SizedBox(width: 4),
            // Mute toggle
            GestureDetector(
              onTap: () => _provider.toggleTakeMute(_trackId, take.id),
              child: Icon(
                take.muted ? Icons.visibility_off : Icons.visibility,
                size: 11,
                color: take.muted ? FabFilterColors.red : FabFilterColors.textDisabled,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingButton(Take take, TakeRating rating, String symbol, Color color) {
    final isActive = take.rating == rating;
    return GestureDetector(
      onTap: () => _provider.setTakeRating(_trackId, take.id, rating),
      child: Container(
        width: 16, height: 14,
        margin: const EdgeInsets.only(right: 2),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: isActive ? color : FabFilterColors.borderSubtle,
            width: isActive ? 1 : 0.5,
          ),
        ),
        child: Center(
          child: Text(symbol, style: TextStyle(
            color: isActive ? color : FabFilterColors.textDisabled,
            fontSize: 8, fontWeight: FontWeight.bold,
          )),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTION BAR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildActionBar(CompState state) {
    final hasBest = state.allTakes.any((t) => t.rating == TakeRating.best);
    final hasBad = state.allTakes.any((t) => t.rating == TakeRating.bad);

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FabFilterColors.bgDeep,
        border: Border(
          top: BorderSide(color: FabFilterColors.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          // Promote Best
          FabCompactToggle(
            label: 'PROMOTE',
            active: hasBest,
            color: FabFilterColors.green,
            onToggle: hasBest
                ? () => _provider.promoteBestTakes(_trackId)
                : () {},
          ),
          const SizedBox(width: 4),
          // Delete Bad
          FabCompactToggle(
            label: 'DEL BAD',
            active: hasBad,
            color: FabFilterColors.red,
            onToggle: hasBad
                ? () => _provider.deleteBadTakes(_trackId)
                : () {},
          ),
          const SizedBox(width: 4),
          // Flatten
          FabCompactToggle(
            label: 'FLATTEN',
            active: state.compRegions.isNotEmpty,
            color: FabFilterColors.orange,
            onToggle: () {
              _provider.flattenComp(_trackId, '/tmp/comp_output.wav');
              widget.onAction?.call('flattenComp', {'trackId': widget.selectedTrackId});
            },
          ),
          const Spacer(),
          // Summary stats
          Text(
            '${state.allTakes.length} takes',
            style: FabFilterText.paramLabel.copyWith(
              color: FabFilterColors.textDisabled, fontSize: 8,
            ),
          ),
        ],
      ),
    );
  }
}
