/// CORTEX Vision Dashboard — The Eyes of the Organism, Visualized
///
/// Lower Zone tab that shows what CORTEX sees:
/// - Live region snapshots (timeline, mixer, slot_lab, lower_zone, transport)
/// - Vision event timeline with anomaly detection
/// - Visual diff indicators (what changed between captures)
/// - Per-region health scoring (freshness, responsiveness)
/// - Observation controls (start/stop, manual capture, cleanup)
///
/// This is the UI where the organism's vision becomes visible to the user.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/cortex_vision_service.dart';
import '../../services/vision_diff_engine.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// VISION DASHBOARD — Full lower zone panel
// ═══════════════════════════════════════════════════════════════════════════

class VisionDashboard extends StatefulWidget {
  const VisionDashboard({super.key});

  @override
  State<VisionDashboard> createState() => _VisionDashboardState();
}

class _VisionDashboardState extends State<VisionDashboard> {
  final CortexVisionService _vision = CortexVisionService.instance;
  final VisionDiffEngine _diffEngine = VisionDiffEngine.instance;
  Timer? _refreshTimer;
  String? _selectedRegion;
  bool _showEvents = false;

  @override
  void initState() {
    super.initState();
    _vision.addListener(_onVisionUpdate);
    // Refresh UI every 2s to show latest snapshots
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _vision.removeListener(_onVisionUpdate);
    super.dispose();
  }

  void _onVisionUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        children: [
          // ─── Header bar ────────────────────────────────────────────
          _buildHeader(),
          // ─── Content ───────────────────────────────────────────────
          Expanded(
            child: _showEvents ? _buildEventTimeline() : _buildRegionGrid(),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HEADER — controls and status
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    final isObserving = _vision.isObserving;
    final snapshotCount = _vision.snapshots.length;
    final eventCount = _vision.events.length;
    final regionCount = _vision.regions.length;

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          // Eye icon + title
          Icon(
            isObserving ? Icons.visibility : Icons.visibility_off,
            size: 14,
            color: isObserving ? FluxForgeTheme.accentCyan : FluxForgeTheme.textTertiary,
          ),
          const SizedBox(width: 6),
          Text(
            'CORTEX VISION',
            style: TextStyle(
              color: FluxForgeTheme.accentCyan,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 12),

          // Stats
          _buildStatChip('$regionCount regions', FluxForgeTheme.textSecondary),
          const SizedBox(width: 8),
          _buildStatChip('$snapshotCount captures', FluxForgeTheme.textSecondary),
          const SizedBox(width: 8),
          _buildStatChip('$eventCount events', FluxForgeTheme.textSecondary),

          const Spacer(),

          // Toggle: Regions / Events
          _buildToggle('Regions', !_showEvents, () => setState(() => _showEvents = false)),
          const SizedBox(width: 4),
          _buildToggle('Events', _showEvents, () => setState(() => _showEvents = true)),
          const SizedBox(width: 12),

          // Observe toggle
          _buildActionButton(
            isObserving ? 'Stop' : 'Observe',
            isObserving ? Icons.pause : Icons.play_arrow,
            isObserving ? FluxForgeTheme.warningOrange : FluxForgeTheme.accentGreen,
            () {
              if (isObserving) {
                _vision.stopObserving();
              } else {
                _vision.startObserving();
              }
              setState(() {});
            },
          ),
          const SizedBox(width: 4),

          // Manual capture
          _buildActionButton(
            'Capture',
            Icons.camera_alt,
            FluxForgeTheme.accentBlue,
            () async {
              await _vision.captureAll(metadata: {'type': 'manual'});
              _vision.recordEvent(
                type: VisionEventType.manualCapture,
                description: 'Manual capture all regions',
              );
            },
          ),
          const SizedBox(width: 4),

          // Cleanup
          _buildActionButton(
            'Clean',
            Icons.cleaning_services,
            FluxForgeTheme.textTertiary,
            () async {
              final deleted = await _vision.cleanupOldSnapshots(keepLast: 20);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Cleaned up $deleted old snapshots'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // REGION GRID — visual snapshot grid for all regions
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildRegionGrid() {
    final regions = _vision.regions;
    if (regions.isEmpty) {
      return Center(
        child: Text(
          'No vision regions registered',
          style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 13),
        ),
      );
    }

    return Row(
      children: [
        // Region grid (left side)
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final names = [...regions.keys, 'full_window'];
                final crossAxisCount = constraints.maxWidth > 900 ? 3 : 2;
                return GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    childAspectRatio: 16 / 10,
                  ),
                  itemCount: names.length,
                  itemBuilder: (context, index) {
                    final name = names[index];
                    return _buildRegionCard(name);
                  },
                );
              },
            ),
          ),
        ),

        // Detail panel (right side) — when a region is selected
        if (_selectedRegion != null)
          SizedBox(
            width: 280,
            child: _buildRegionDetail(_selectedRegion!),
          ),
      ],
    );
  }

  Widget _buildRegionCard(String regionName) {
    final snapshot = _vision.latestFor(regionName);
    final isSelected = _selectedRegion == regionName;
    final diff = _diffEngine.latestDiffFor(regionName);
    final freshness = _getRegionFreshness(snapshot);

    return GestureDetector(
      onTap: () => setState(() {
        _selectedRegion = _selectedRegion == regionName ? null : regionName;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isSelected ? FluxForgeTheme.bgElevated : FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? FluxForgeTheme.accentCyan
                : freshness == _RegionFreshness.stale
                    ? FluxForgeTheme.warningOrange.withValues(alpha: 0.5)
                    : FluxForgeTheme.borderSubtle,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Snapshot preview
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                child: snapshot != null
                    ? _buildSnapshotPreview(snapshot)
                    : Container(
                        color: FluxForgeTheme.bgDeepest,
                        child: Center(
                          child: Icon(
                            Icons.visibility_off,
                            color: FluxForgeTheme.textTertiary.withValues(alpha: 0.3),
                            size: 28,
                          ),
                        ),
                      ),
              ),
            ),

            // Info bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgSurface,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(5)),
              ),
              child: Row(
                children: [
                  // Freshness indicator dot
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _freshnessColor(freshness),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Region name
                  Expanded(
                    child: Text(
                      regionName.replaceAll('_', ' ').toUpperCase(),
                      style: TextStyle(
                        color: FluxForgeTheme.textPrimary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Diff change indicator
                  if (diff != null && diff.changePercent > 0.01)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: _diffColor(diff.changePercent).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        '${(diff.changePercent * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: _diffColor(diff.changePercent),
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  // Resolution + size
                  if (snapshot != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      snapshot.sizeKB,
                      style: TextStyle(
                        color: FluxForgeTheme.textTertiary,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSnapshotPreview(VisionSnapshot snapshot) {
    final file = File(snapshot.filePath);
    if (!file.existsSync()) {
      return Container(
        color: FluxForgeTheme.bgDeepest,
        child: Center(
          child: Text(
            'File removed',
            style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 10),
          ),
        ),
      );
    }

    return Image.file(
      file,
      fit: BoxFit.cover,
      cacheWidth: 400, // Limit decoded image size for performance
      errorBuilder: (context, error, stackTrace) => Container(
        color: FluxForgeTheme.bgDeepest,
        child: Center(
          child: Icon(Icons.broken_image, color: FluxForgeTheme.textTertiary, size: 20),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // REGION DETAIL PANEL
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildRegionDetail(String regionName) {
    final region = _vision.getRegion(regionName);
    final snapshot = _vision.latestFor(regionName);
    final diff = _diffEngine.latestDiffFor(regionName);
    final regionSnapshots = _vision.snapshots
        .where((s) => s.regionName == regionName)
        .take(10)
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          left: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Region header
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgSurface,
              border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  regionName.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(
                    color: FluxForgeTheme.accentCyan,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
                if (region != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      region.description,
                      style: TextStyle(
                        color: FluxForgeTheme.textTertiary,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Snapshot info
          if (snapshot != null)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow('Resolution', snapshot.resolution),
                  _buildInfoRow('Size', snapshot.sizeKB),
                  _buildInfoRow('Captured', _formatTimestamp(snapshot.capturedAt)),
                  _buildInfoRow('Freshness', _freshnessDuration(snapshot)),
                  if (diff != null) ...[
                    const SizedBox(height: 6),
                    _buildInfoRow('Change', '${(diff.changePercent * 100).toStringAsFixed(2)}%'),
                    _buildInfoRow('Changed px', '${diff.changedPixels}'),
                    _buildInfoRow('Diff time', '${diff.computeTimeMs}ms'),
                  ],
                ],
              ),
            ),

          // Capture button for this region
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: SizedBox(
              height: 28,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await _vision.capture(regionName, metadata: {'type': 'manual_single'});
                  if (regionName != 'full_window') {
                    _diffEngine.computeDiff(regionName);
                  }
                },
                icon: Icon(Icons.camera_alt, size: 14, color: FluxForgeTheme.textPrimary),
                label: Text(
                  'Capture Now',
                  style: TextStyle(fontSize: 11, color: FluxForgeTheme.textPrimary),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: FluxForgeTheme.accentBlue.withValues(alpha: 0.2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Recent snapshots for this region
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: regionSnapshots.length,
              itemBuilder: (context, index) {
                final s = regionSnapshots[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.bgSurface,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Row(
                      children: [
                        Text(
                          _formatTimestamp(s.capturedAt),
                          style: TextStyle(
                            color: FluxForgeTheme.textSecondary,
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const Spacer(),
                        Text(
                          s.sizeKB,
                          style: TextStyle(
                            color: FluxForgeTheme.textTertiary,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // EVENT TIMELINE — chronological vision events
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildEventTimeline() {
    final events = _vision.events;
    if (events.isEmpty) {
      return Center(
        child: Text(
          'No vision events recorded yet',
          style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 13),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        return _buildEventRow(event);
      },
    );
  }

  Widget _buildEventRow(VisionEvent event) {
    final icon = _eventIcon(event.type);
    final color = _eventColor(event.type);

    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border(
          left: BorderSide(color: color, width: 3),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.description,
                  style: TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontSize: 11,
                  ),
                ),
                if (event.snapshot != null)
                  Text(
                    '${event.snapshot!.regionName} — ${event.snapshot!.resolution} — ${event.snapshot!.sizeKB}',
                    style: TextStyle(
                      color: FluxForgeTheme.textTertiary,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            _formatTimestamp(event.timestamp),
            style: TextStyle(
              color: FluxForgeTheme.textTertiary,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildStatChip(String text, Color color) {
    return Text(
      text,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w500),
    );
  }

  Widget _buildToggle(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? FluxForgeTheme.accentCyan.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: active ? FluxForgeTheme.accentCyan.withValues(alpha: 0.4) : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? FluxForgeTheme.accentCyan : FluxForgeTheme.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 10),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: FluxForgeTheme.textPrimary,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Freshness scoring ──────────────────────────────────────────────

  _RegionFreshness _getRegionFreshness(VisionSnapshot? snapshot) {
    if (snapshot == null) return _RegionFreshness.dead;
    final age = DateTime.now().difference(snapshot.capturedAt);
    if (age.inSeconds < 15) return _RegionFreshness.fresh;
    if (age.inSeconds < 60) return _RegionFreshness.recent;
    return _RegionFreshness.stale;
  }

  Color _freshnessColor(_RegionFreshness freshness) => switch (freshness) {
    _RegionFreshness.fresh => FluxForgeTheme.accentGreen,
    _RegionFreshness.recent => FluxForgeTheme.accentCyan,
    _RegionFreshness.stale => FluxForgeTheme.warningOrange,
    _RegionFreshness.dead => FluxForgeTheme.textTertiary.withValues(alpha: 0.3),
  };

  String _freshnessDuration(VisionSnapshot snapshot) {
    final age = DateTime.now().difference(snapshot.capturedAt);
    if (age.inSeconds < 5) return 'just now';
    if (age.inSeconds < 60) return '${age.inSeconds}s ago';
    if (age.inMinutes < 60) return '${age.inMinutes}m ago';
    return '${age.inHours}h ago';
  }

  // ─── Diff scoring ──────────────────────────────────────────────────

  Color _diffColor(double changePercent) {
    if (changePercent < 0.05) return FluxForgeTheme.accentGreen;
    if (changePercent < 0.20) return FluxForgeTheme.accentCyan;
    if (changePercent < 0.50) return FluxForgeTheme.warningOrange;
    return FluxForgeTheme.accentRed;
  }

  // ─── Event styling ─────────────────────────────────────────────────

  IconData _eventIcon(VisionEventType type) => switch (type) {
    VisionEventType.stateChange => Icons.swap_horiz,
    VisionEventType.animationComplete => Icons.animation,
    VisionEventType.userInteraction => Icons.touch_app,
    VisionEventType.errorVisible => Icons.error_outline,
    VisionEventType.healthCheck => Icons.favorite,
    VisionEventType.manualCapture => Icons.camera_alt,
  };

  Color _eventColor(VisionEventType type) => switch (type) {
    VisionEventType.stateChange => FluxForgeTheme.accentBlue,
    VisionEventType.animationComplete => FluxForgeTheme.accentPurple,
    VisionEventType.userInteraction => FluxForgeTheme.accentCyan,
    VisionEventType.errorVisible => FluxForgeTheme.errorRed,
    VisionEventType.healthCheck => FluxForgeTheme.accentGreen,
    VisionEventType.manualCapture => FluxForgeTheme.accentYellow,
  };

  String _formatTimestamp(DateTime ts) {
    return '${_pad(ts.hour)}:${_pad(ts.minute)}:${_pad(ts.second)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}

enum _RegionFreshness { fresh, recent, stale, dead }
