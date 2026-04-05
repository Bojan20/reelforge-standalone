/// RNG Seed Control Panel (P4.10)
///
/// Debug panel for controlling and monitoring RNG state in slot simulations:
/// - View current RNG seed state
/// - Enable/disable seed logging
/// - View seed log history
/// - Replay specific seeds for deterministic testing
/// - Export seed log for QA
///
/// Created: 2026-01-30

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/fluxforge_theme.dart';
import '../../src/rust/native_ffi.dart';

/// RNG Seed Control Panel Widget
class RngSeedPanel extends StatefulWidget {
  final VoidCallback? onClose;

  const RngSeedPanel({
    super.key,
    this.onClose,
  });

  @override
  State<RngSeedPanel> createState() => _RngSeedPanelState();
}

class _RngSeedPanelState extends State<RngSeedPanel> {
  bool _isLoggingEnabled = false;
  List<SeedLogEntry> _logEntries = [];
  Timer? _refreshTimer;
  final TextEditingController _seedInputController = TextEditingController();
  final TextEditingController _containerIdController = TextEditingController();
  int? _selectedContainerId;
  String? _currentRngState;

  @override
  void initState() {
    super.initState();
    _loadState();
    _startRefreshTimer();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _seedInputController.dispose();
    _containerIdController.dispose();
    super.dispose();
  }

  void _loadState() {
    try {
      _isLoggingEnabled = NativeFFI.instance.seedLogIsEnabled();
      _logEntries = NativeFFI.instance.seedLogGetLastN(20);
      if (_selectedContainerId != null) {
        final state = NativeFFI.instance.seedLogGetRngState(_selectedContainerId!);
        _currentRngState = state.toRadixString(16).padLeft(16, '0').toUpperCase();
      }
    } catch (e) { /* ignored */ }
  }

  void _startRefreshTimer() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isLoggingEnabled) {
        setState(() {
          _loadState();
        });
      }
    });
  }

  void _toggleLogging() {
    setState(() {
      _isLoggingEnabled = !_isLoggingEnabled;
      NativeFFI.instance.seedLogEnable(_isLoggingEnabled);
    });
  }

  void _clearLog() {
    NativeFFI.instance.seedLogClear();
    setState(() {
      _logEntries = [];
    });
  }

  void _replaySeed(SeedLogEntry entry) {
    final seed = int.tryParse(entry.seedBefore, radix: 16);
    if (seed != null) {
      final success = NativeFFI.instance.seedLogReplaySeed(entry.containerId, seed);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Replayed seed ${entry.seedBefore} on container ${entry.containerId}'),
            backgroundColor: FluxForgeTheme.accentGreen,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _applySeedFromInput() {
    final containerId = int.tryParse(_containerIdController.text);
    final seed = int.tryParse(_seedInputController.text, radix: 16);

    if (containerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Invalid container ID'),
          backgroundColor: FluxForgeTheme.accentOrange,
        ),
      );
      return;
    }

    if (seed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Invalid seed (must be hex)'),
          backgroundColor: FluxForgeTheme.accentOrange,
        ),
      );
      return;
    }

    final success = NativeFFI.instance.seedLogReplaySeed(containerId, seed);
    if (success) {
      setState(() {
        _selectedContainerId = containerId;
        _loadState();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Applied seed to container $containerId'),
          backgroundColor: FluxForgeTheme.accentGreen,
        ),
      );
    }
  }

  void _copyLogToClipboard() {
    final allEntries = NativeFFI.instance.seedLogGetAll();
    final buffer = StringBuffer();
    buffer.writeln('tick,containerId,seedBefore,seedAfter,selectedId,pitchOffset,volumeOffset');
    for (final entry in allEntries) {
      buffer.writeln(
        '${entry.tick},${entry.containerId},${entry.seedBefore},${entry.seedAfter},'
        '${entry.selectedId},${entry.pitchOffset},${entry.volumeOffset}',
      );
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied ${allEntries.length} entries to clipboard'),
        backgroundColor: FluxForgeTheme.accentBlue,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep.withAlpha(240),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          const Divider(height: 1, color: Color(0xFF2A2A35)),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildControls(),
                const SizedBox(height: 8),
                _buildSeedInput(),
                const SizedBox(height: 8),
                _buildLogHeader(),
                const SizedBox(height: 4),
                _buildLogList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                Icons.casino,
                size: 14,
                color: _isLoggingEnabled
                    ? FluxForgeTheme.accentGreen
                    : FluxForgeTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                'RNG Seed Control',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: FluxForgeTheme.textPrimary,
                ),
              ),
            ],
          ),
          Row(
            children: [
              GestureDetector(
                onTap: _copyLogToClipboard,
                child: Tooltip(
                  message: 'Export CSV',
                  child: Icon(
                    Icons.download,
                    size: 14,
                    color: FluxForgeTheme.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _clearLog,
                child: Icon(
                  Icons.delete_outline,
                  size: 14,
                  color: FluxForgeTheme.textSecondary,
                ),
              ),
              if (widget.onClose != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: widget.onClose,
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: FluxForgeTheme.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    final count = NativeFFI.instance.seedLogGetCount();

    return Row(
      children: [
        // Logging toggle
        GestureDetector(
          onTap: _toggleLogging,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _isLoggingEnabled
                  ? FluxForgeTheme.accentGreen.withAlpha(30)
                  : FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _isLoggingEnabled
                    ? FluxForgeTheme.accentGreen.withAlpha(100)
                    : FluxForgeTheme.borderSubtle,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isLoggingEnabled ? Icons.fiber_manual_record : Icons.circle_outlined,
                  size: 10,
                  color: _isLoggingEnabled
                      ? FluxForgeTheme.accentGreen
                      : FluxForgeTheme.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  _isLoggingEnabled ? 'Recording' : 'Paused',
                  style: TextStyle(
                    fontSize: 10,
                    color: _isLoggingEnabled
                        ? FluxForgeTheme.accentGreen
                        : FluxForgeTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Entry count
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '$count entries',
            style: TextStyle(
              fontSize: 10,
              color: FluxForgeTheme.textSecondary,
              fontFamily: 'monospace',
            ),
          ),
        ),
        const Spacer(),
        // Current RNG state
        if (_currentRngState != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentBlue.withAlpha(20),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _currentRngState!.substring(0, 8),
              style: TextStyle(
                fontSize: 10,
                color: FluxForgeTheme.accentBlue,
                fontFamily: 'monospace',
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSeedInput() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MANUAL SEED INJECTION',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: FluxForgeTheme.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              // Container ID
              SizedBox(
                width: 60,
                child: TextField(
                  controller: _containerIdController,
                  style: TextStyle(
                    fontSize: 10,
                    color: FluxForgeTheme.textPrimary,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    hintText: 'ID',
                    hintStyle: TextStyle(
                      fontSize: 10,
                      color: FluxForgeTheme.textSecondary,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(3),
                      borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(3),
                      borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(3),
                      borderSide: BorderSide(color: FluxForgeTheme.accentBlue),
                    ),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 4),
              // Seed hex
              Expanded(
                child: TextField(
                  controller: _seedInputController,
                  style: TextStyle(
                    fontSize: 10,
                    color: FluxForgeTheme.textPrimary,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    hintText: 'Seed (hex)',
                    hintStyle: TextStyle(
                      fontSize: 10,
                      color: FluxForgeTheme.textSecondary,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(3),
                      borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(3),
                      borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(3),
                      borderSide: BorderSide(color: FluxForgeTheme.accentBlue),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Apply button
              GestureDetector(
                onTap: _applySeedFromInput,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentBlue.withAlpha(30),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: FluxForgeTheme.accentBlue.withAlpha(80)),
                  ),
                  child: Text(
                    'Apply',
                    style: TextStyle(
                      fontSize: 10,
                      color: FluxForgeTheme.accentBlue,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogHeader() {
    return Row(
      children: [
        SizedBox(width: 45, child: _buildGridHeader('Tick')),
        SizedBox(width: 30, child: _buildGridHeader('ID')),
        Expanded(child: _buildGridHeader('Seed Before')),
        SizedBox(width: 30, child: _buildGridHeader('Sel')),
        SizedBox(width: 40, child: _buildGridHeader('Action')),
      ],
    );
  }

  Widget _buildGridHeader(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        color: FluxForgeTheme.textSecondary,
      ),
    );
  }

  Widget _buildLogList() {
    if (_logEntries.isEmpty) {
      return Container(
        height: 80,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          _isLoggingEnabled ? 'Waiting for RNG events...' : 'Enable logging to capture seeds',
          style: TextStyle(
            fontSize: 10,
            color: FluxForgeTheme.textSecondary,
          ),
        ),
      );
    }

    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.all(4),
        itemCount: _logEntries.length,
        itemBuilder: (context, index) {
          final entry = _logEntries[_logEntries.length - 1 - index];
          return _buildLogRow(entry);
        },
      ),
    );
  }

  Widget _buildLogRow(SeedLogEntry entry) {
    final shortSeed = entry.seedBefore.length > 8
        ? entry.seedBefore.substring(0, 8)
        : entry.seedBefore;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          // Tick
          SizedBox(
            width: 45,
            child: Text(
              '${entry.tick}',
              style: TextStyle(
                fontSize: 9,
                color: FluxForgeTheme.textSecondary,
                fontFamily: 'monospace',
              ),
            ),
          ),
          // Container ID
          SizedBox(
            width: 30,
            child: Text(
              '${entry.containerId}',
              style: TextStyle(
                fontSize: 9,
                color: FluxForgeTheme.textPrimary,
                fontFamily: 'monospace',
              ),
            ),
          ),
          // Seed
          Expanded(
            child: GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: entry.seedBefore));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Seed copied'),
                    duration: const Duration(seconds: 1),
                    backgroundColor: FluxForgeTheme.accentBlue,
                  ),
                );
              },
              child: Text(
                shortSeed,
                style: TextStyle(
                  fontSize: 9,
                  color: FluxForgeTheme.accentBlue,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          // Selected ID
          SizedBox(
            width: 30,
            child: Text(
              '${entry.selectedId}',
              style: TextStyle(
                fontSize: 9,
                color: FluxForgeTheme.accentOrange,
                fontFamily: 'monospace',
              ),
            ),
          ),
          // Replay button
          SizedBox(
            width: 40,
            child: GestureDetector(
              onTap: () => _replaySeed(entry),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentGreen.withAlpha(20),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  'Replay',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 8,
                    color: FluxForgeTheme.accentGreen,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact RNG status badge for status bars
class RngStatusBadge extends StatefulWidget {
  final VoidCallback? onTap;

  const RngStatusBadge({super.key, this.onTap});

  @override
  State<RngStatusBadge> createState() => _RngStatusBadgeState();
}

class _RngStatusBadgeState extends State<RngStatusBadge> {
  bool _isLogging = false;
  int _entryCount = 0;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) {
        _loadState();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _loadState() {
    try {
      setState(() {
        _isLogging = NativeFFI.instance.seedLogIsEnabled();
        _entryCount = NativeFFI.instance.seedLogGetCount();
      });
    } catch (_) { /* ignored */ }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: _isLogging
              ? FluxForgeTheme.accentGreen.withAlpha(20)
              : FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _isLogging
                ? FluxForgeTheme.accentGreen.withAlpha(80)
                : FluxForgeTheme.borderSubtle,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isLogging ? Icons.casino : Icons.casino_outlined,
              size: 12,
              color: _isLogging
                  ? FluxForgeTheme.accentGreen
                  : FluxForgeTheme.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              '$_entryCount',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: _isLogging
                    ? FluxForgeTheme.accentGreen
                    : FluxForgeTheme.textSecondary,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
