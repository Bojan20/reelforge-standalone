/// FluxMacro Live Progress Monitor — FM-39
///
/// Displays real-time macro execution progress:
/// - Circular progress indicator with percentage
/// - Current step name and ETA
/// - Monospace log stream with color-coded entries (green/yellow/red)
/// - Cancel button
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../../providers/fluxmacro_provider.dart';
import '../../../../theme/fluxforge_theme.dart';

class MacroMonitor extends StatefulWidget {
  const MacroMonitor({super.key});

  @override
  State<MacroMonitor> createState() => _MacroMonitorState();
}

class _MacroMonitorState extends State<MacroMonitor> {
  final _provider = GetIt.instance<FluxMacroProvider>();
  final _scrollController = ScrollController();
  final List<_LogEntry> _logEntries = [];
  bool _autoScroll = true;
  Timer? _logPollTimer;

  @override
  void initState() {
    super.initState();
    _provider.addListener(_onProviderChanged);
    _startLogPolling();
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderChanged);
    _logPollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onProviderChanged() {
    if (mounted) setState(() {});
  }

  void _startLogPolling() {
    _logPollTimer?.cancel();
    _logPollTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _pollLogs(),
    );
  }

  void _pollLogs() {
    if (!_provider.initialized) return;

    final logs = _provider.getLogs();
    if (logs == null) return;

    final entries = logs['entries'] as List<dynamic>?;
    if (entries == null) return;

    final newEntries = entries.skip(_logEntries.length).map((e) {
      final map = e as Map<String, dynamic>;
      return _LogEntry(
        timestamp: map['timestamp'] as String? ?? '',
        level: map['level'] as String? ?? 'info',
        source: map['source'] as String? ?? '',
        message: map['message'] as String? ?? '',
      );
    }).toList();

    if (newEntries.isNotEmpty) {
      setState(() {
        _logEntries.addAll(newEntries);
      });
      if (_autoScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
            );
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        children: [
          _buildHeader(),
          const Divider(height: 1, color: FluxForgeTheme.bgHover),
          // Progress section
          if (_provider.isRunning) _buildProgressSection(),
          // Log stream
          Expanded(child: _buildLogStream()),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: FluxForgeTheme.bgMid,
      child: Row(
        children: [
          Icon(
            _provider.isRunning ? Icons.play_circle_fill : Icons.monitor,
            size: 14,
            color: _provider.isRunning
                ? FluxForgeTheme.accentGreen
                : FluxForgeTheme.textTertiary,
          ),
          const SizedBox(width: 6),
          const Text(
            'MONITOR',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          // Auto-scroll toggle
          GestureDetector(
            onTap: () => setState(() => _autoScroll = !_autoScroll),
            child: Icon(
              Icons.vertical_align_bottom,
              size: 14,
              color: _autoScroll
                  ? FluxForgeTheme.accentBlue
                  : FluxForgeTheme.textTertiary,
            ),
          ),
          const SizedBox(width: 8),
          // Clear logs
          GestureDetector(
            onTap: () => setState(() => _logEntries.clear()),
            child: const Icon(
              Icons.delete_sweep,
              size: 14,
              color: FluxForgeTheme.textTertiary,
            ),
          ),
          if (_provider.isRunning) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _provider.cancel,
              child: const Icon(
                Icons.stop_circle,
                size: 14,
                color: FluxForgeTheme.accentRed,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PROGRESS SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildProgressSection() {
    final progress = _provider.progress;
    final percent = (progress * 100).toInt();
    final currentStep = _provider.currentStep ?? 'Initializing...';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: FluxForgeTheme.bgMid.withValues(alpha: 0.5),
      child: Row(
        children: [
          // Circular progress
          SizedBox(
            width: 32,
            height: 32,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2.5,
                  backgroundColor: FluxForgeTheme.bgSurface,
                  valueColor: const AlwaysStoppedAnimation(FluxForgeTheme.accentYellow),
                ),
                Text(
                  '$percent',
                  style: const TextStyle(
                    color: FluxForgeTheme.accentYellow,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Step info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currentStep,
                  style: const TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(1),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 2,
                    backgroundColor: FluxForgeTheme.bgSurface,
                    valueColor: const AlwaysStoppedAnimation(FluxForgeTheme.accentYellow),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LOG STREAM
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLogStream() {
    if (_logEntries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.terminal,
              size: 32,
              color: FluxForgeTheme.textTertiary.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 8),
            const Text(
              'No log output',
              style: TextStyle(
                color: FluxForgeTheme.textTertiary,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Run a macro to see log stream',
              style: TextStyle(
                color: FluxForgeTheme.textTertiary.withValues(alpha: 0.6),
                fontSize: 10,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      color: const Color(0xFF0A0A10),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(8),
        itemCount: _logEntries.length,
        itemExtent: 18,
        itemBuilder: (context, index) {
          final entry = _logEntries[index];
          return _buildLogLine(entry);
        },
      ),
    );
  }

  Widget _buildLogLine(_LogEntry entry) {
    final color = switch (entry.level) {
      'error' => FluxForgeTheme.accentRed,
      'warn' || 'warning' => FluxForgeTheme.accentOrange,
      'debug' => FluxForgeTheme.textTertiary,
      _ => FluxForgeTheme.accentGreen,
    };

    final levelTag = switch (entry.level) {
      'error' => 'ERR',
      'warn' || 'warning' => 'WRN',
      'debug' => 'DBG',
      _ => 'INF',
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timestamp
        if (entry.timestamp.isNotEmpty)
          SizedBox(
            width: 70,
            child: Text(
              entry.timestamp.length > 8
                  ? entry.timestamp.substring(entry.timestamp.length - 8)
                  : entry.timestamp,
              style: TextStyle(
                color: FluxForgeTheme.textTertiary.withValues(alpha: 0.4),
                fontSize: 10,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ),
        // Level
        SizedBox(
          width: 28,
          child: Text(
            levelTag,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              fontFamily: 'JetBrains Mono',
            ),
          ),
        ),
        // Source
        if (entry.source.isNotEmpty)
          SizedBox(
            width: 100,
            child: Text(
              entry.source,
              style: TextStyle(
                color: FluxForgeTheme.accentCyan.withValues(alpha: 0.6),
                fontSize: 10,
                fontFamily: 'JetBrains Mono',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        // Message
        Expanded(
          child: Text(
            entry.message,
            style: TextStyle(
              color: color.withValues(alpha: 0.8),
              fontSize: 10,
              fontFamily: 'JetBrains Mono',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _LogEntry {
  final String timestamp;
  final String level;
  final String source;
  final String message;

  const _LogEntry({
    required this.timestamp,
    required this.level,
    required this.source,
    required this.message,
  });
}
