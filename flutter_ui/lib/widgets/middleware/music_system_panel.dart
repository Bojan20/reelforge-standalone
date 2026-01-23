/// FluxForge Studio Music System Panel
///
/// Beat/bar synchronized music with stingers and transitions.
/// Perfect for dynamic music in slot games.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/middleware_models.dart';
import '../../providers/middleware_provider.dart';
import '../../theme/fluxforge_theme.dart';

/// Music System Panel Widget
class MusicSystemPanel extends StatefulWidget {
  const MusicSystemPanel({super.key});

  @override
  State<MusicSystemPanel> createState() => _MusicSystemPanelState();
}

class _MusicSystemPanelState extends State<MusicSystemPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int? _selectedSegmentId;
  int? _selectedStingerId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Selector<MiddlewareProvider, MusicSystemData>(
      selector: (_, p) => (
        segments: p.musicSegments,
        stingers: p.stingers,
      ),
      builder: (context, data, _) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: FluxForgeTheme.surfaceDark,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FluxForgeTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildTabBar(),
              const SizedBox(height: 16),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildSegmentsTab(context, data.segments),
                    _buildStingersTab(context, data.stingers),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.music_note, color: Colors.pink, size: 20),
        const SizedBox(width: 8),
        Text(
          'Music System',
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        // Tempo display
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.pink.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.pink.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Icon(Icons.speed, size: 14, color: Colors.pink),
              const SizedBox(width: 4),
              Text(
                '120 BPM',
                style: TextStyle(
                  color: Colors.pink,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: Colors.pink.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        labelColor: Colors.pink,
        unselectedLabelColor: FluxForgeTheme.textSecondary,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        tabs: const [
          Tab(text: 'Segments'),
          Tab(text: 'Stingers'),
        ],
      ),
    );
  }

  Widget _buildSegmentsTab(BuildContext context, List<MusicSegment> segments) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Segment list
        SizedBox(
          width: 250,
          child: _buildSegmentList(context, segments),
        ),
        const SizedBox(width: 16),
        // Segment editor
        Expanded(
          child: _buildSegmentEditor(context, segments),
        ),
      ],
    );
  }

  Widget _buildSegmentList(BuildContext context, List<MusicSegment> segments) {
    return Column(
      children: [
        // Add button
        GestureDetector(
          onTap: () => _showAddSegmentDialog(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, size: 16, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  'Add Segment',
                  style: TextStyle(color: Colors.green, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Segment list
        Expanded(
          child: segments.isEmpty
              ? _buildEmptyState('No music segments', Icons.music_off)
              : Container(
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.surface.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: FluxForgeTheme.border),
                  ),
                  child: ListView.builder(
                    itemCount: segments.length,
                    itemBuilder: (context, index) {
                      final segment = segments[index];
                      final isSelected = _selectedSegmentId == segment.id;

                      return GestureDetector(
                        onTap: () => setState(() {
                          _selectedSegmentId = isSelected ? null : segment.id;
                        }),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.pink.withValues(alpha: 0.1)
                                : Colors.transparent,
                            border: Border(
                              left: isSelected
                                  ? BorderSide(color: Colors.pink, width: 3)
                                  : BorderSide.none,
                              bottom: BorderSide(
                                color: FluxForgeTheme.border.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.music_note,
                                    size: 14,
                                    color: Colors.pink,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      segment.name,
                                      style: TextStyle(
                                        color: FluxForgeTheme.textPrimary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  _buildInfoChip('${segment.tempo.toStringAsFixed(0)} BPM', Colors.pink),
                                  const SizedBox(width: 6),
                                  _buildInfoChip('${segment.beatsPerBar}/4', Colors.blue),
                                  const SizedBox(width: 6),
                                  _buildInfoChip('${segment.durationBars} bars', Colors.teal),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSegmentEditor(BuildContext context, List<MusicSegment> segments) {
    if (_selectedSegmentId == null) {
      return _buildEmptyState('Select a segment to edit', Icons.touch_app);
    }

    final segment = segments
        .where((s) => s.id == _selectedSegmentId)
        .firstOrNull;

    if (segment == null) return const SizedBox.shrink();

    final provider = context.read<MiddlewareProvider>();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.edit, size: 16, color: Colors.pink),
              const SizedBox(width: 8),
              Text(
                segment.name,
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  provider.removeMusicSegment(segment.id);
                  setState(() => _selectedSegmentId = null);
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(Icons.delete, size: 14, color: Colors.red),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Tempo and time signature
          Row(
            children: [
              Expanded(
                child: _buildNumberInput(
                  label: 'Tempo (BPM)',
                  value: segment.tempo,
                  min: 40,
                  max: 300,
                  color: Colors.pink,
                  onChanged: (v) {
                    provider.updateMusicSegment(segment.copyWith(tempo: v));
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildNumberInput(
                  label: 'Beats/Bar',
                  value: segment.beatsPerBar.toDouble(),
                  min: 2,
                  max: 12,
                  color: Colors.blue,
                  onChanged: (v) {
                    provider.updateMusicSegment(segment.copyWith(beatsPerBar: v.toInt()));
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildNumberInput(
                  label: 'Duration (bars)',
                  value: segment.durationBars.toDouble(),
                  min: 1,
                  max: 64,
                  color: Colors.teal,
                  onChanged: (v) {
                    provider.updateMusicSegment(segment.copyWith(durationBars: v.toInt()));
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Cue points
          Text(
            'Cue Points',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildSliderInput(
                  label: 'Entry Cue',
                  value: segment.entryCueBars,
                  max: segment.durationBars.toDouble(),
                  unit: 'bars',
                  color: Colors.green,
                  onChanged: (v) {
                    provider.updateMusicSegment(segment.copyWith(entryCueBars: v));
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSliderInput(
                  label: 'Exit Cue',
                  value: segment.exitCueBars,
                  max: segment.durationBars.toDouble(),
                  unit: 'bars',
                  color: Colors.red,
                  onChanged: (v) {
                    provider.updateMusicSegment(segment.copyWith(exitCueBars: v));
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Loop region
          Text(
            'Loop Region',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildSliderInput(
                  label: 'Loop Start',
                  value: segment.loopStartBars,
                  max: segment.durationBars.toDouble(),
                  unit: 'bars',
                  color: Colors.orange,
                  onChanged: (v) {
                    provider.updateMusicSegment(segment.copyWith(loopStartBars: v));
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSliderInput(
                  label: 'Loop End',
                  value: segment.loopEndBars,
                  max: segment.durationBars.toDouble(),
                  unit: 'bars',
                  color: Colors.purple,
                  onChanged: (v) {
                    provider.updateMusicSegment(segment.copyWith(loopEndBars: v));
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Markers
          Row(
            children: [
              Text(
                'Markers',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _showAddMarkerDialog(context, segment),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.cyan.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.cyan),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 12, color: Colors.cyan),
                      const SizedBox(width: 4),
                      Text(
                        'Add Marker',
                        style: TextStyle(color: Colors.cyan, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Marker list
          Expanded(
            child: segment.markers.isEmpty
                ? Center(
                    child: Text(
                      'No markers',
                      style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
                    ),
                  )
                : ListView.builder(
                    itemCount: segment.markers.length,
                    itemBuilder: (context, index) {
                      final marker = segment.markers[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.surface.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: FluxForgeTheme.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getMarkerColor(marker.markerType).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                marker.markerType.displayName,
                                style: TextStyle(
                                  color: _getMarkerColor(marker.markerType),
                                  fontSize: 9,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                marker.name,
                                style: TextStyle(
                                  color: FluxForgeTheme.textPrimary,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            Text(
                              '${marker.positionBars.toStringAsFixed(1)} bars',
                              style: TextStyle(
                                color: FluxForgeTheme.textSecondary,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Color _getMarkerColor(MarkerType type) {
    switch (type) {
      case MarkerType.generic:
        return Colors.grey;
      case MarkerType.entry:
        return Colors.green;
      case MarkerType.exit:
        return Colors.red;
      case MarkerType.sync:
        return Colors.cyan;
    }
  }

  Widget _buildStingersTab(BuildContext context, List<Stinger> stingers) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stinger list
        SizedBox(
          width: 250,
          child: _buildStingerList(context, stingers),
        ),
        const SizedBox(width: 16),
        // Stinger editor
        Expanded(
          child: _buildStingerEditor(context, stingers),
        ),
      ],
    );
  }

  Widget _buildStingerList(BuildContext context, List<Stinger> stingers) {
    return Column(
      children: [
        // Add button
        GestureDetector(
          onTap: () => _showAddStingerDialog(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, size: 16, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  'Add Stinger',
                  style: TextStyle(color: Colors.green, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Stinger list
        Expanded(
          child: stingers.isEmpty
              ? _buildEmptyState('No stingers', Icons.flash_off)
              : Container(
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.surface.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: FluxForgeTheme.border),
                  ),
                  child: ListView.builder(
                    itemCount: stingers.length,
                    itemBuilder: (context, index) {
                      final stinger = stingers[index];
                      final isSelected = _selectedStingerId == stinger.id;

                      return GestureDetector(
                        onTap: () => setState(() {
                          _selectedStingerId = isSelected ? null : stinger.id;
                        }),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.orange.withValues(alpha: 0.1)
                                : Colors.transparent,
                            border: Border(
                              left: isSelected
                                  ? BorderSide(color: Colors.orange, width: 3)
                                  : BorderSide.none,
                              bottom: BorderSide(
                                color: FluxForgeTheme.border.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.flash_on,
                                    size: 14,
                                    color: Colors.orange,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      stinger.name,
                                      style: TextStyle(
                                        color: FluxForgeTheme.textPrimary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  _buildInfoChip(stinger.syncPoint.displayName, Colors.cyan),
                                  const SizedBox(width: 6),
                                  _buildInfoChip('Pri: ${stinger.priority}', Colors.purple),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildStingerEditor(BuildContext context, List<Stinger> stingers) {
    if (_selectedStingerId == null) {
      return _buildEmptyState('Select a stinger to edit', Icons.touch_app);
    }

    final stinger = stingers
        .where((s) => s.id == _selectedStingerId)
        .firstOrNull;

    if (stinger == null) return const SizedBox.shrink();

    final provider = context.read<MiddlewareProvider>();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.flash_on, size: 16, color: Colors.orange),
              const SizedBox(width: 8),
              Text(
                stinger.name,
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  provider.removeStinger(stinger.id);
                  setState(() => _selectedStingerId = null);
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(Icons.delete, size: 14, color: Colors.red),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Sync point selector
          Text(
            'Sync Point',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: MusicSyncPoint.values.map((syncPoint) {
              final isActive = stinger.syncPoint == syncPoint;
              return GestureDetector(
                onTap: () {
                  provider.updateStinger(stinger.copyWith(syncPoint: syncPoint));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.cyan.withValues(alpha: 0.2)
                        : FluxForgeTheme.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isActive ? Colors.cyan : FluxForgeTheme.border,
                    ),
                  ),
                  child: Text(
                    syncPoint.displayName,
                    style: TextStyle(
                      color: isActive ? Colors.cyan : FluxForgeTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          // Custom grid (if applicable)
          if (stinger.syncPoint == MusicSyncPoint.customGrid)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSliderInput(
                  label: 'Custom Grid',
                  value: stinger.customGridBeats,
                  max: 16,
                  unit: 'beats',
                  color: Colors.cyan,
                  onChanged: (v) {
                    provider.updateStinger(stinger.copyWith(customGridBeats: v));
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          // Ducking settings
          Text(
            'Music Ducking',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildSliderInput(
                  label: 'Duck Amount',
                  value: stinger.musicDuckDb.abs(),
                  max: 24,
                  unit: 'dB',
                  color: Colors.orange,
                  onChanged: (v) {
                    provider.updateStinger(stinger.copyWith(musicDuckDb: -v));
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSliderInput(
                  label: 'Attack',
                  value: stinger.duckAttackMs,
                  max: 100,
                  unit: 'ms',
                  color: Colors.green,
                  onChanged: (v) {
                    provider.updateStinger(stinger.copyWith(duckAttackMs: v));
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSliderInput(
                  label: 'Release',
                  value: stinger.duckReleaseMs,
                  max: 500,
                  unit: 'ms',
                  color: Colors.red,
                  onChanged: (v) {
                    provider.updateStinger(stinger.copyWith(duckReleaseMs: v));
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Priority and interrupt
          Row(
            children: [
              Expanded(
                child: _buildNumberInput(
                  label: 'Priority',
                  value: stinger.priority.toDouble(),
                  min: 0,
                  max: 100,
                  color: Colors.purple,
                  onChanged: (v) {
                    provider.updateStinger(stinger.copyWith(priority: v.toInt()));
                  },
                ),
              ),
              const SizedBox(width: 16),
              // Can interrupt toggle
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Can Interrupt',
                    style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 10),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      provider.updateStinger(
                        stinger.copyWith(canInterrupt: !stinger.canInterrupt),
                      );
                    },
                    child: Container(
                      width: 48,
                      height: 24,
                      decoration: BoxDecoration(
                        color: stinger.canInterrupt
                            ? Colors.green.withValues(alpha: 0.3)
                            : FluxForgeTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: stinger.canInterrupt ? Colors.green : FluxForgeTheme.border,
                        ),
                      ),
                      child: AnimatedAlign(
                        duration: const Duration(milliseconds: 150),
                        alignment: stinger.canInterrupt
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          width: 20,
                          height: 20,
                          margin: const EdgeInsets.all(1),
                          decoration: BoxDecoration(
                            color: stinger.canInterrupt
                                ? Colors.green
                                : FluxForgeTheme.textSecondary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: FluxForgeTheme.textSecondary),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(color: FluxForgeTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberInput({
    required String label,
    required double value,
    required double min,
    required double max,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 10),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  activeTrackColor: color,
                  inactiveTrackColor: FluxForgeTheme.surface,
                  thumbColor: color,
                ),
                child: Slider(
                  value: value,
                  min: min,
                  max: max,
                  onChanged: onChanged,
                ),
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                value.toStringAsFixed(0),
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSliderInput({
    required String label,
    required double value,
    required double max,
    required String unit,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 10),
            ),
            Text(
              '${value.toStringAsFixed(1)} $unit',
              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            activeTrackColor: color,
            inactiveTrackColor: FluxForgeTheme.surface,
            thumbColor: color,
          ),
          child: Slider(
            value: value / max,
            onChanged: (v) => onChanged(v * max),
          ),
        ),
      ],
    );
  }

  void _showAddSegmentDialog(BuildContext context) {
    final controller = TextEditingController();
    final provider = context.read<MiddlewareProvider>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxForgeTheme.surfaceDark,
        title: Text('Add Segment', style: TextStyle(color: FluxForgeTheme.textPrimary)),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Segment Name',
            labelStyle: TextStyle(color: FluxForgeTheme.textSecondary),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: FluxForgeTheme.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.pink),
            ),
          ),
          style: TextStyle(color: FluxForgeTheme.textPrimary),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: FluxForgeTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                provider.addMusicSegment(name: controller.text, soundId: 0);
                Navigator.pop(ctx);
              }
            },
            child: Text('Add', style: TextStyle(color: Colors.pink)),
          ),
        ],
      ),
    );
  }

  void _showAddStingerDialog(BuildContext context) {
    final controller = TextEditingController();
    final provider = context.read<MiddlewareProvider>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxForgeTheme.surfaceDark,
        title: Text('Add Stinger', style: TextStyle(color: FluxForgeTheme.textPrimary)),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Stinger Name',
            labelStyle: TextStyle(color: FluxForgeTheme.textSecondary),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: FluxForgeTheme.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.orange),
            ),
          ),
          style: TextStyle(color: FluxForgeTheme.textPrimary),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: FluxForgeTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                provider.addStinger(name: controller.text, soundId: 0);
                Navigator.pop(ctx);
              }
            },
            child: Text('Add', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
  }

  void _showAddMarkerDialog(BuildContext context, MusicSegment segment) {
    final controller = TextEditingController();
    final provider = context.read<MiddlewareProvider>();
    MarkerType selectedType = MarkerType.generic;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: FluxForgeTheme.surfaceDark,
          title: Text('Add Marker', style: TextStyle(color: FluxForgeTheme.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: 'Marker Name',
                  labelStyle: TextStyle(color: FluxForgeTheme.textSecondary),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: FluxForgeTheme.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.cyan),
                  ),
                ),
                style: TextStyle(color: FluxForgeTheme.textPrimary),
              ),
              const SizedBox(height: 16),
              Row(
                children: MarkerType.values.map((type) {
                  final isActive = selectedType == type;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => selectedType = type),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: isActive
                              ? _getMarkerColor(type).withValues(alpha: 0.2)
                              : FluxForgeTheme.surface,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isActive
                                ? _getMarkerColor(type)
                                : FluxForgeTheme.border,
                          ),
                        ),
                        child: Text(
                          type.displayName,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isActive
                                ? _getMarkerColor(type)
                                : FluxForgeTheme.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: FluxForgeTheme.textSecondary)),
            ),
            TextButton(
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  provider.addMusicMarker(
                    segment.id,
                    name: controller.text,
                    positionBars: 0.0,
                    markerType: selectedType,
                  );
                  Navigator.pop(ctx);
                }
              },
              child: Text('Add', style: TextStyle(color: Colors.cyan)),
            ),
          ],
        ),
      ),
    );
  }
}
