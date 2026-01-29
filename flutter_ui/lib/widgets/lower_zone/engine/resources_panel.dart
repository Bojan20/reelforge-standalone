/// Engine Resources Panel
///
/// Real-time monitoring of engine resources via FFI.
/// SL-LZ-P1.3: Engine Resources Panel
///
/// Displays:
/// - Voice pool statistics (active/idle voices)
/// - Memory usage
/// - CPU load (if FFI available)

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/service_locator.dart';
import '../../../src/rust/native_ffi.dart';
import '../../../theme/fluxforge_theme.dart';

class EngineResourcesPanel extends StatefulWidget {
  const EngineResourcesPanel({super.key});

  @override
  State<EngineResourcesPanel> createState() => _EngineResourcesPanelState();
}

class _EngineResourcesPanelState extends State<EngineResourcesPanel> {
  Timer? _updateTimer;
  NativeVoicePoolStats? _voiceStats;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _updateStats();
    _updateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) _updateStats();
    });
  }

  void _updateStats() {
    try {
      final ffi = sl<NativeFFI>();
      final stats = ffi.getVoicePoolStats();
      setState(() {
        _voiceStats = stats;
        _errorMessage = '';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'FFI Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF0D0D10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.analytics_outlined, size: 16, color: FluxForgeTheme.accentBlue),
              const SizedBox(width: 8),
              const Text(
                'ENGINE RESOURCES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              // Refresh button
              IconButton(
                icon: const Icon(Icons.refresh, size: 16, color: Colors.white38),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: _updateStats,
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Error message
          if (_errorMessage.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, size: 14, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage,
                      style: const TextStyle(fontSize: 10, color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          // Stats cards
          Expanded(
            child: _voiceStats != null
                ? _buildStatsView(_voiceStats!)
                : _buildLoadingState(),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(strokeWidth: 2),
          SizedBox(height: 12),
          Text(
            'Loading engine stats...',
            style: TextStyle(fontSize: 10, color: Colors.white38),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsView(NativeVoicePoolStats stats) {
    final idleVoices = stats.maxVoices - stats.activeCount;
    return ListView(
      children: [
        // Voice Pool Statistics
        _buildStatCard(
          title: 'VOICE POOL',
          icon: Icons.graphic_eq,
          color: FluxForgeTheme.accentBlue,
          children: [
            _buildStatRow('Active Voices', '${stats.activeCount}', stats.activeCount / stats.maxVoices),
            _buildStatRow('Idle Voices', '$idleVoices', null),
            _buildStatRow('Pool Size', '${stats.maxVoices}', null),
            _buildStatRow('Utilization', '${stats.utilizationPercent.toStringAsFixed(1)}%', stats.utilizationPercent / 100),
          ],
        ),
        const SizedBox(height: 8),
        // Per-Bus Voice Count
        _buildStatCard(
          title: 'VOICES PER BUS',
          icon: Icons.route,
          color: FluxForgeTheme.accentGreen,
          children: [
            if (stats.sfxVoices > 0) _buildStatRow('SFX', '${stats.sfxVoices}', stats.sfxVoices / stats.maxVoices),
            if (stats.musicVoices > 0) _buildStatRow('Music', '${stats.musicVoices}', stats.musicVoices / stats.maxVoices),
            if (stats.voiceVoices > 0) _buildStatRow('Voice', '${stats.voiceVoices}', stats.voiceVoices / stats.maxVoices),
            if (stats.ambienceVoices > 0) _buildStatRow('Ambience', '${stats.ambienceVoices}', stats.ambienceVoices / stats.maxVoices),
            if (stats.auxVoices > 0) _buildStatRow('Aux', '${stats.auxVoices}', stats.auxVoices / stats.maxVoices),
            if (stats.masterVoices > 0) _buildStatRow('Master', '${stats.masterVoices}', stats.masterVoices / stats.maxVoices),
          ],
        ),
        const SizedBox(height: 8),
        // Per-Source Voice Count
        _buildStatCard(
          title: 'VOICES PER SOURCE',
          icon: Icons.speed,
          color: FluxForgeTheme.accentOrange,
          children: [
            if (stats.dawVoices > 0) _buildStatRow('DAW', '${stats.dawVoices}', stats.dawVoices / stats.maxVoices),
            if (stats.slotLabVoices > 0) _buildStatRow('SlotLab', '${stats.slotLabVoices}', stats.slotLabVoices / stats.maxVoices),
            if (stats.middlewareVoices > 0) _buildStatRow('Middleware', '${stats.middlewareVoices}', stats.middlewareVoices / stats.maxVoices),
            if (stats.browserVoices > 0) _buildStatRow('Browser', '${stats.browserVoices}', stats.browserVoices / stats.maxVoices),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF16161C),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Card header
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Stats rows
          ...children,
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, double? fraction) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 10, color: Colors.white54),
            ),
          ),
          if (fraction != null)
            Container(
              width: 60,
              height: 12,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(6),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: fraction.clamp(0.0, 1.0),
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _getFractionColor(fraction),
                  ),
                  minHeight: 12,
                ),
              ),
            ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Color _getFractionColor(double fraction) {
    if (fraction < 0.5) return FluxForgeTheme.accentGreen;
    if (fraction < 0.8) return FluxForgeTheme.accentOrange;
    return Colors.red;
  }

  String _busIdToName(int busId) {
    switch (busId) {
      case 0:
        return 'Master';
      case 1:
        return 'Music';
      case 2:
        return 'SFX';
      case 3:
        return 'Voice';
      case 4:
        return 'UI';
      case 5:
        return 'Ambience';
      case 6:
        return 'Reels';
      case 7:
        return 'Wins';
      default:
        return 'Bus $busId';
    }
  }
}
