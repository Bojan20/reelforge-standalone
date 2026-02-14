// Event Profiler Advanced — Middleware RTPC Advanced tab
// Comprehensive DSP profiling with real-time metrics, per-event breakdown,
// latency histogram, and voice lifecycle tracking

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

class EventProfilerAdvanced extends StatefulWidget {
  final List<ProfilerEntry> entries;
  const EventProfilerAdvanced({super.key, required this.entries});

  @override
  State<EventProfilerAdvanced> createState() => _EventProfilerAdvancedState();
}

class _EventProfilerAdvancedState extends State<EventProfilerAdvanced> {
  String _searchQuery = '';
  _SortMode _sortMode = _SortMode.callCount;
  bool _showHistogram = true;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 8),
          _buildSummaryStrip(),
          const SizedBox(height: 8),
          if (_showHistogram) ...[
            _buildLatencyHistogram(),
            const SizedBox(height: 8),
          ],
          _buildToolbar(),
          const SizedBox(height: 4),
          Expanded(child: _buildEntriesList()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.speed, size: 16, color: FluxForgeTheme.accentCyan),
        const SizedBox(width: 6),
        Text('ADVANCED PROFILER',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: FluxForgeTheme.accentCyan,
                letterSpacing: 1.0)),
        const Spacer(),
        _buildToggle('Histogram', _showHistogram, (v) => setState(() => _showHistogram = v)),
      ],
    );
  }

  Widget _buildToggle(String label, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: value ? FluxForgeTheme.accentCyan.withOpacity(0.15) : FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: value ? FluxForgeTheme.accentCyan.withOpacity(0.4) : Colors.white12,
          ),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 9,
                color: value ? FluxForgeTheme.accentCyan : Colors.white38)),
      ),
    );
  }

  Widget _buildSummaryStrip() {
    final totalCalls = widget.entries.fold<int>(0, (s, e) => s + e.callCount);
    final maxLatency = widget.entries.isEmpty
        ? 0.0
        : widget.entries.map((e) => e.avgLatencyUs).reduce(math.max);
    final avgLatency = widget.entries.isEmpty
        ? 0.0
        : widget.entries.map((e) => e.avgLatencyUs).reduce((a, b) => a + b) /
            widget.entries.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          _buildMetricBadge('Entries', '${widget.entries.length}', FluxForgeTheme.accentCyan),
          const SizedBox(width: 12),
          _buildMetricBadge('Total Calls', '$totalCalls', FluxForgeTheme.accentBlue),
          const SizedBox(width: 12),
          _buildMetricBadge('Avg Latency', '${avgLatency.toStringAsFixed(1)}μs', Colors.amber),
          const SizedBox(width: 12),
          _buildMetricBadge('Max Latency', '${maxLatency.toStringAsFixed(1)}μs',
              maxLatency > 1000 ? Colors.red : Colors.green),
        ],
      ),
    );
  }

  Widget _buildMetricBadge(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 8, color: Colors.white38)),
        Text(value,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildLatencyHistogram() {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: CustomPaint(
        painter: _HistogramPainter(entries: widget.entries),
        size: const Size(double.infinity, 60),
      ),
    );
  }

  Widget _buildToolbar() {
    return Row(
      children: [
        // Search
        Expanded(
          child: Container(
            height: 24,
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: Colors.white12),
            ),
            child: TextField(
              style: const TextStyle(fontSize: 10, color: Colors.white70),
              decoration: const InputDecoration(
                hintText: 'Search events...',
                hintStyle: TextStyle(fontSize: 10, color: Colors.white24),
                prefixIcon: Icon(Icons.search, size: 12, color: Colors.white24),
                border: InputBorder.none,
                contentPadding: EdgeInsets.only(bottom: 12),
                prefixIconConstraints: BoxConstraints(minWidth: 24),
              ),
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Sort
        ...['Calls', 'Latency', 'Name'].asMap().entries.map((e) {
          final mode = _SortMode.values[e.key];
          final active = _sortMode == mode;
          return Padding(
            padding: const EdgeInsets.only(left: 4),
            child: GestureDetector(
              onTap: () => setState(() => _sortMode = mode),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: active ? FluxForgeTheme.accentCyan.withOpacity(0.15) : null,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                      color: active ? FluxForgeTheme.accentCyan.withOpacity(0.4) : Colors.white12),
                ),
                child: Text(e.value,
                    style: TextStyle(
                        fontSize: 9,
                        color: active ? FluxForgeTheme.accentCyan : Colors.white38)),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildEntriesList() {
    var filtered = widget.entries.where((e) {
      if (_searchQuery.isEmpty) return true;
      return e.eventId.toLowerCase().contains(_searchQuery);
    }).toList();

    switch (_sortMode) {
      case _SortMode.callCount:
        filtered.sort((a, b) => b.callCount.compareTo(a.callCount));
      case _SortMode.latency:
        filtered.sort((a, b) => b.avgLatencyUs.compareTo(a.avgLatencyUs));
      case _SortMode.name:
        filtered.sort((a, b) => a.eventId.compareTo(b.eventId));
    }

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.analytics_outlined, size: 32, color: Colors.white24),
            const SizedBox(height: 8),
            Text('No profiler data',
                style: TextStyle(fontSize: 11, color: Colors.white38)),
            const SizedBox(height: 4),
            Text('Trigger events to see profiling metrics',
                style: TextStyle(fontSize: 9, color: Colors.white24)),
          ],
        ),
      );
    }

    final maxCalls = filtered.map((e) => e.callCount).reduce(math.max);

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (ctx, i) {
        final e = filtered[i];
        final ratio = maxCalls > 0 ? e.callCount / maxCalls : 0.0;
        final latencyColor = e.avgLatencyUs > 1000
            ? Colors.red
            : e.avgLatencyUs > 500
                ? Colors.orange
                : const Color(0xFF40FF90);

        return Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: Colors.white.withOpacity(0.04)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.event_note, size: 12, color: FluxForgeTheme.accentCyan),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(e.eventId,
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ),
                  Text('${e.callCount} calls',
                      style: TextStyle(fontSize: 9, color: FluxForgeTheme.accentBlue)),
                  const SizedBox(width: 12),
                  Text('${e.avgLatencyUs.toStringAsFixed(1)}μs',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: latencyColor)),
                ],
              ),
              const SizedBox(height: 3),
              // Call count bar
              ClipRRect(
                borderRadius: BorderRadius.circular(1),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 3,
                  backgroundColor: Colors.white.withOpacity(0.05),
                  valueColor: AlwaysStoppedAnimation(
                      FluxForgeTheme.accentCyan.withOpacity(0.4)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _SortMode { callCount, latency, name }

class _HistogramPainter extends CustomPainter {
  final List<ProfilerEntry> entries;
  _HistogramPainter({required this.entries});

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.isEmpty) return;

    // Distribute latencies into 20 buckets
    final maxLatency = entries.map((e) => e.avgLatencyUs).reduce(math.max);
    if (maxLatency <= 0) return;
    const bucketCount = 20;
    final buckets = List.filled(bucketCount, 0);
    for (final e in entries) {
      final idx = ((e.avgLatencyUs / maxLatency) * (bucketCount - 1)).round().clamp(0, bucketCount - 1);
      buckets[idx]++;
    }

    final maxBucket = buckets.reduce(math.max);
    if (maxBucket <= 0) return;

    final barWidth = size.width / bucketCount;
    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < bucketCount; i++) {
      final ratio = buckets[i] / maxBucket;
      final barHeight = ratio * (size.height - 4);
      final t = i / (bucketCount - 1);
      paint.color = Color.lerp(
        const Color(0xFF40FF90),
        const Color(0xFFFF4040),
        t,
      )!.withOpacity(0.6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            i * barWidth + 1,
            size.height - barHeight - 2,
            barWidth - 2,
            barHeight,
          ),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HistogramPainter old) =>
      old.entries.length != entries.length;
}

class ProfilerEntry {
  final String eventId;
  final int latencyUs;
  final int callCount;
  final double avgLatencyUs;
  const ProfilerEntry(
      {required this.eventId,
      required this.latencyUs,
      required this.callCount,
      required this.avgLatencyUs});
}
