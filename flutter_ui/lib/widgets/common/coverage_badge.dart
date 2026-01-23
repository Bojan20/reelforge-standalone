/// Coverage Badge Widget
///
/// Displays test coverage percentage in a compact badge format.
/// Can read coverage from:
/// - Local coverage file (development)
/// - CI/CD artifact cache
/// - Remote API (optional)
///
/// Used in status bars and panel footers to show project health.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

/// Coverage data model
class CoverageData {
  final double linePercent;
  final double branchPercent;
  final int coveredLines;
  final int totalLines;
  final DateTime? lastUpdated;
  final String? source;

  const CoverageData({
    required this.linePercent,
    this.branchPercent = 0.0,
    this.coveredLines = 0,
    this.totalLines = 0,
    this.lastUpdated,
    this.source,
  });

  factory CoverageData.empty() => const CoverageData(linePercent: 0.0);

  factory CoverageData.fromLcov(String lcovContent) {
    int totalLines = 0;
    int coveredLines = 0;
    int totalBranches = 0;
    int coveredBranches = 0;

    for (final line in lcovContent.split('\n')) {
      if (line.startsWith('LF:')) {
        totalLines += int.tryParse(line.substring(3)) ?? 0;
      } else if (line.startsWith('LH:')) {
        coveredLines += int.tryParse(line.substring(3)) ?? 0;
      } else if (line.startsWith('BRF:')) {
        totalBranches += int.tryParse(line.substring(4)) ?? 0;
      } else if (line.startsWith('BRH:')) {
        coveredBranches += int.tryParse(line.substring(4)) ?? 0;
      }
    }

    return CoverageData(
      linePercent: totalLines > 0 ? (coveredLines / totalLines * 100) : 0.0,
      branchPercent: totalBranches > 0 ? (coveredBranches / totalBranches * 100) : 0.0,
      coveredLines: coveredLines,
      totalLines: totalLines,
      lastUpdated: DateTime.now(),
      source: 'lcov',
    );
  }

  factory CoverageData.fromJson(Map<String, dynamic> json) {
    return CoverageData(
      linePercent: (json['line_percent'] as num?)?.toDouble() ?? 0.0,
      branchPercent: (json['branch_percent'] as num?)?.toDouble() ?? 0.0,
      coveredLines: (json['covered_lines'] as num?)?.toInt() ?? 0,
      totalLines: (json['total_lines'] as num?)?.toInt() ?? 0,
      lastUpdated: json['last_updated'] != null
          ? DateTime.tryParse(json['last_updated'] as String)
          : null,
      source: json['source'] as String?,
    );
  }

  /// Get health status based on coverage
  String get healthStatus {
    if (linePercent >= 80) return 'excellent';
    if (linePercent >= 60) return 'good';
    if (linePercent >= 40) return 'fair';
    return 'poor';
  }

  /// Get color for coverage level
  Color get healthColor {
    if (linePercent >= 80) return FluxForgeTheme.accentGreen;
    if (linePercent >= 60) return FluxForgeTheme.accentCyan;
    if (linePercent >= 40) return FluxForgeTheme.accentYellow;
    return FluxForgeTheme.accentRed;
  }
}

/// Service for loading coverage data
class CoverageService {
  static final CoverageService instance = CoverageService._();
  CoverageService._();

  CoverageData? _cachedData;
  DateTime? _lastFetch;

  /// Load coverage from local lcov.info file
  Future<CoverageData?> loadFromLcov(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        final content = await file.readAsString();
        _cachedData = CoverageData.fromLcov(content);
        _lastFetch = DateTime.now();
        return _cachedData;
      }
    } catch (e) {
      // Ignore errors
    }
    return null;
  }

  /// Load coverage from local JSON cache
  Future<CoverageData?> loadFromCache(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        _cachedData = CoverageData.fromJson(json);
        _lastFetch = DateTime.now();
        return _cachedData;
      }
    } catch (e) {
      // Ignore errors
    }
    return null;
  }

  /// Get cached data
  CoverageData? get cached => _cachedData;

  /// Save coverage to local cache
  Future<void> saveToCache(String path, CoverageData data) async {
    try {
      final file = File(path);
      await file.writeAsString(jsonEncode({
        'line_percent': data.linePercent,
        'branch_percent': data.branchPercent,
        'covered_lines': data.coveredLines,
        'total_lines': data.totalLines,
        'last_updated': data.lastUpdated?.toIso8601String(),
        'source': data.source,
      }));
    } catch (e) {
      // Ignore errors
    }
  }
}

/// Compact coverage badge for status bars
class CoverageBadge extends StatefulWidget {
  final String? lcovPath;
  final String? cachePath;
  final Duration refreshInterval;
  final bool showBranchCoverage;

  const CoverageBadge({
    super.key,
    this.lcovPath,
    this.cachePath,
    this.refreshInterval = const Duration(minutes: 5),
    this.showBranchCoverage = false,
  });

  @override
  State<CoverageBadge> createState() => _CoverageBadgeState();
}

class _CoverageBadgeState extends State<CoverageBadge> {
  CoverageData _data = CoverageData.empty();
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadCoverage();
    _refreshTimer = Timer.periodic(widget.refreshInterval, (_) => _loadCoverage());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCoverage() async {
    final service = CoverageService.instance;

    // Try lcov first
    if (widget.lcovPath != null) {
      final data = await service.loadFromLcov(widget.lcovPath!);
      if (data != null && mounted) {
        setState(() {
          _data = data;
          _isLoading = false;
        });
        return;
      }
    }

    // Try cache
    if (widget.cachePath != null) {
      final data = await service.loadFromCache(widget.cachePath!);
      if (data != null && mounted) {
        setState(() {
          _data = data;
          _isLoading = false;
        });
        return;
      }
    }

    // Use cached data from service
    if (service.cached != null && mounted) {
      setState(() {
        _data = service.cached!;
        _isLoading = false;
      });
      return;
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.5),
        ),
      );
    }

    if (_data.totalLines == 0) {
      return Tooltip(
        message: 'No coverage data available',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: FluxForgeTheme.borderSubtle, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield_outlined, size: 12, color: Colors.white24),
              const SizedBox(width: 4),
              Text(
                'N/A',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      );
    }

    final color = _data.healthColor;

    return Tooltip(
      message: _buildTooltipText(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _data.linePercent >= 80
                  ? Icons.shield
                  : _data.linePercent >= 60
                      ? Icons.shield_outlined
                      : Icons.warning_amber,
              size: 12,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              '${_data.linePercent.toStringAsFixed(0)}%',
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
            if (widget.showBranchCoverage && _data.branchPercent > 0) ...[
              Text(
                ' / ',
                style: TextStyle(color: Colors.white24, fontSize: 10),
              ),
              Text(
                '${_data.branchPercent.toStringAsFixed(0)}%',
                style: TextStyle(
                  color: color.withValues(alpha: 0.7),
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _buildTooltipText() {
    final lines = <String>[
      'Line Coverage: ${_data.linePercent.toStringAsFixed(1)}%',
      'Lines: ${_data.coveredLines}/${_data.totalLines}',
    ];

    if (_data.branchPercent > 0) {
      lines.add('Branch Coverage: ${_data.branchPercent.toStringAsFixed(1)}%');
    }

    if (_data.lastUpdated != null) {
      lines.add('Updated: ${_formatDate(_data.lastUpdated!)}');
    }

    if (_data.source != null) {
      lines.add('Source: ${_data.source}');
    }

    return lines.join('\n');
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

/// Detailed coverage panel for expanded view
class CoverageDetailPanel extends StatefulWidget {
  final String? lcovPath;
  final String? cachePath;

  const CoverageDetailPanel({
    super.key,
    this.lcovPath,
    this.cachePath,
  });

  @override
  State<CoverageDetailPanel> createState() => _CoverageDetailPanelState();
}

class _CoverageDetailPanelState extends State<CoverageDetailPanel> {
  CoverageData _data = CoverageData.empty();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCoverage();
  }

  Future<void> _loadCoverage() async {
    final service = CoverageService.instance;

    if (widget.lcovPath != null) {
      final data = await service.loadFromLcov(widget.lcovPath!);
      if (data != null && mounted) {
        setState(() {
          _data = data;
          _isLoading = false;
        });
        return;
      }
    }

    if (widget.cachePath != null) {
      final data = await service.loadFromCache(widget.cachePath!);
      if (data != null && mounted) {
        setState(() {
          _data = data;
          _isLoading = false;
        });
        return;
      }
    }

    if (service.cached != null && mounted) {
      setState(() {
        _data = service.cached!;
        _isLoading = false;
      });
      return;
    }

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.shield, size: 20, color: _data.healthColor),
              const SizedBox(width: 8),
              Text(
                'TEST COVERAGE',
                style: TextStyle(
                  color: _data.healthColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 16),
                onPressed: () {
                  setState(() => _isLoading = true);
                  _loadCoverage();
                },
                splashRadius: 14,
                color: Colors.white38,
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Main percentage display
          Row(
            children: [
              Expanded(
                child: _buildMetricBox(
                  'Lines',
                  '${_data.linePercent.toStringAsFixed(1)}%',
                  '${_data.coveredLines}/${_data.totalLines}',
                  _data.healthColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricBox(
                  'Branches',
                  _data.branchPercent > 0
                      ? '${_data.branchPercent.toStringAsFixed(1)}%'
                      : 'N/A',
                  null,
                  _data.branchPercent > 0 ? _data.healthColor : Colors.white24,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Progress bar
          _buildProgressBar(),

          // Metadata
          if (_data.lastUpdated != null) ...[
            const SizedBox(height: 12),
            Text(
              'Last updated: ${_formatDate(_data.lastUpdated!)}',
              style: TextStyle(color: Colors.white24, fontSize: 10),
            ),
          ],
          if (_data.source != null) ...[
            const SizedBox(height: 4),
            Text(
              'Source: ${_data.source}',
              style: TextStyle(color: Colors.white24, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricBox(String label, String value, String? subValue, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
          if (subValue != null) ...[
            const SizedBox(height: 2),
            Text(
              subValue,
              style: TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Coverage', style: TextStyle(color: Colors.white54, fontSize: 10)),
            Text(
              _data.healthStatus.toUpperCase(),
              style: TextStyle(
                color: _data.healthColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(4),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  // Threshold markers
                  _buildMarker(constraints.maxWidth * 0.4, FluxForgeTheme.accentYellow),
                  _buildMarker(constraints.maxWidth * 0.6, FluxForgeTheme.accentCyan),
                  _buildMarker(constraints.maxWidth * 0.8, FluxForgeTheme.accentGreen),
                  // Fill
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: constraints.maxWidth * (_data.linePercent / 100).clamp(0.0, 1.0),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _data.healthColor.withValues(alpha: 0.7),
                          _data.healthColor,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMarker(double left, Color color) {
    return Positioned(
      left: left,
      top: 0,
      bottom: 0,
      child: Container(width: 1, color: color.withValues(alpha: 0.3)),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
