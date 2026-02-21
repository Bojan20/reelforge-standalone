/// Session Replay Panel
///
/// UI panel for recording and replaying SlotLab sessions.
/// Provides controls for recording, playback, seeking, and session management.
///
/// Created: 2026-01-30 (P4.9)

import 'dart:async';

import '../../utils/safe_file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/session_replay_models.dart';
import '../../services/session_replay_service.dart';

/// Main session replay panel widget
class SessionReplayPanel extends StatefulWidget {
  final String gameId;
  final String gameName;
  final VoidCallback? onRecordingStarted;
  final VoidCallback? onRecordingStopped;
  final void Function(RecordedSpin spin)? onSpinReplay;

  const SessionReplayPanel({
    super.key,
    required this.gameId,
    this.gameName = '',
    this.onRecordingStarted,
    this.onRecordingStopped,
    this.onSpinReplay,
  });

  @override
  State<SessionReplayPanel> createState() => _SessionReplayPanelState();
}

class _SessionReplayPanelState extends State<SessionReplayPanel> {
  final _recorder = SessionRecorder.instance;
  final _replay = SessionReplayEngine.instance;
  final _storage = SessionStorage.instance;

  List<SessionSummary> _savedSessions = [];
  bool _isLoadingSessions = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _recorder.init(gameId: widget.gameId, gameName: widget.gameName);
    _recorder.addListener(_onStateChange);
    _replay.addListener(_onStateChange);
    _loadSavedSessions();

    // Set up replay callbacks
    _replay.onSpinStart = (spin) {
      widget.onSpinReplay?.call(spin);
    };
  }

  @override
  void dispose() {
    _recorder.removeListener(_onStateChange);
    _replay.removeListener(_onStateChange);
    super.dispose();
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSavedSessions() async {
    setState(() => _isLoadingSessions = true);
    try {
      _savedSessions = await _storage.listSessions();
    } catch (e) {
      _errorMessage = 'Failed to load sessions: $e';
    }
    setState(() => _isLoadingSessions = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A20),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _replay.hasSession
                ? _buildReplayView()
                : _buildRecordingView(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF242430),
        border: Border(bottom: BorderSide(color: Color(0xFF3A3A4A))),
      ),
      child: Row(
        children: [
          const Icon(Icons.videocam, color: Color(0xFF4A9EFF), size: 20),
          const SizedBox(width: 8),
          const Text(
            'SESSION REPLAY',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (_recorder.isRecording)
            _RecordingIndicator(spinCount: _recorder.spinCount),
          if (_replay.isPlaying)
            _PlaybackIndicator(position: _replay.position),
        ],
      ),
    );
  }

  Widget _buildRecordingView() {
    return Row(
      children: [
        // Left: Controls
        SizedBox(
          width: 280,
          child: _buildControlsPanel(),
        ),
        const VerticalDivider(width: 1, color: Color(0xFF3A3A4A)),
        // Right: Session list
        Expanded(
          child: _buildSessionList(),
        ),
      ],
    );
  }

  Widget _buildControlsPanel() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('RECORDING', Icons.fiber_manual_record),
          const SizedBox(height: 12),
          _buildRecordingControls(),
          const SizedBox(height: 24),
          _buildSectionHeader('QUICK ACTIONS', Icons.flash_on),
          const SizedBox(height: 12),
          _buildQuickActions(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white54, size: 14),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }

  Widget _buildRecordingControls() {
    final state = _recorder.state;

    return Column(
      children: [
        // Main record button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: state.canRecord
                ? _startRecording
                : (state.canStop ? _stopRecording : null),
            icon: Icon(
              state.isActive ? Icons.stop : Icons.fiber_manual_record,
              size: 18,
            ),
            label: Text(state.isActive ? 'STOP RECORDING' : 'START RECORDING'),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  state.isActive ? const Color(0xFFFF4060) : const Color(0xFF4A9EFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Pause/Resume
        if (state.isActive || state == RecordingState.paused)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed:
                  state.canPause ? _pauseRecording : (state.canResume ? _resumeRecording : null),
              icon: Icon(
                state == RecordingState.paused ? Icons.play_arrow : Icons.pause,
                size: 18,
              ),
              label: Text(state == RecordingState.paused ? 'RESUME' : 'PAUSE'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Color(0xFF3A3A4A)),
              ),
            ),
          ),
        const SizedBox(height: 16),
        // Recording stats
        if (_recorder.isRecording) _buildRecordingStats(),
      ],
    );
  }

  Widget _buildRecordingStats() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E26),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3A3A4A)),
      ),
      child: Column(
        children: [
          _buildStatRow('Spins Recorded', _recorder.spinCount.toString()),
          const SizedBox(height: 4),
          _buildStatRow('Session ID', _recorder.sessionId?.substring(0, 16) ?? '-'),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        Text(value,
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontFamily: 'monospace')),
      ],
    );
  }

  Widget _buildQuickActions() {
    return Column(
      children: [
        _QuickActionButton(
          icon: Icons.folder_open,
          label: 'Import Session',
          onTap: _importSession,
        ),
        const SizedBox(height: 8),
        _QuickActionButton(
          icon: Icons.refresh,
          label: 'Refresh List',
          onTap: _loadSavedSessions,
        ),
      ],
    );
  }

  Widget _buildSessionList() {
    if (_isLoadingSessions) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFFF4060), size: 48),
            const SizedBox(height: 12),
            Text(_errorMessage!, style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                setState(() => _errorMessage = null);
                _loadSavedSessions();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_savedSessions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off, color: Colors.white24, size: 48),
            SizedBox(height: 12),
            Text('No recorded sessions',
                style: TextStyle(color: Colors.white54)),
            SizedBox(height: 4),
            Text('Start recording to capture sessions',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _savedSessions.length,
      itemBuilder: (context, index) {
        final session = _savedSessions[index];
        return _SessionCard(
          summary: session,
          onPlay: () => _loadAndPlaySession(session.sessionId),
          onExport: () => _exportSession(session.sessionId),
          onDelete: () => _deleteSession(session.sessionId),
        );
      },
    );
  }

  Widget _buildReplayView() {
    final session = _replay.session!;
    final position = _replay.position;

    return Column(
      children: [
        // Session info bar
        _buildSessionInfoBar(session),
        // Timeline
        Expanded(
          child: _buildReplayTimeline(session, position),
        ),
        // Controls
        _buildReplayControls(),
      ],
    );
  }

  Widget _buildSessionInfoBar(RecordedSession session) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF242430),
        border: Border(bottom: BorderSide(color: Color(0xFF3A3A4A))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.gameName.isNotEmpty ? session.gameName : session.gameId,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${session.spinCount} spins • ${_formatDuration(session.duration)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          // Stats badges
          _StatBadge(label: 'RTP', value: '${session.rtp.toStringAsFixed(1)}%'),
          const SizedBox(width: 8),
          _StatBadge(
              label: 'Total Win', value: session.totalWin.toStringAsFixed(2)),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54),
            onPressed: _closeReplay,
            tooltip: 'Close replay',
          ),
        ],
      ),
    );
  }

  Widget _buildReplayTimeline(RecordedSession session, ReplayPosition position) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Progress bar
          _buildProgressBar(position),
          const SizedBox(height: 16),
          // Spin list
          Expanded(
            child: _buildSpinList(session, position),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(ReplayPosition position) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Spin ${position.spinIndex + 1} / ${_replay.totalSpins}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            Text(
              '${(position.progress * 100).toStringAsFixed(1)}%',
              style: const TextStyle(
                  color: Color(0xFF4A9EFF), fontSize: 12, fontFamily: 'monospace'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: position.progress,
            backgroundColor: const Color(0xFF3A3A4A),
            valueColor: const AlwaysStoppedAnimation(Color(0xFF4A9EFF)),
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildSpinList(RecordedSession session, ReplayPosition position) {
    return ListView.builder(
      itemCount: session.spins.length,
      itemBuilder: (context, index) {
        final spin = session.spins[index];
        final isActive = index == position.spinIndex;
        final isPast = index < position.spinIndex;

        return _SpinListItem(
          spin: spin,
          isActive: isActive,
          isPast: isPast,
          onTap: () => _replay.seekToSpin(index),
        );
      },
    );
  }

  Widget _buildReplayControls() {
    final state = _replay.state;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF242430),
        border: Border(top: BorderSide(color: Color(0xFF3A3A4A))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Rewind
          IconButton(
            icon: const Icon(Icons.skip_previous),
            color: Colors.white70,
            onPressed: () => _replay.seekToSpin(0),
            tooltip: 'Go to start',
          ),
          const SizedBox(width: 8),
          // Previous spin
          IconButton(
            icon: const Icon(Icons.fast_rewind),
            color: Colors.white70,
            onPressed: _replay.position.spinIndex > 0
                ? () => _replay.seekToSpin(_replay.position.spinIndex - 1)
                : null,
            tooltip: 'Previous spin',
          ),
          const SizedBox(width: 16),
          // Play/Pause
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF4A9EFF),
              borderRadius: BorderRadius.circular(24),
            ),
            child: IconButton(
              icon: Icon(state.isActive ? Icons.pause : Icons.play_arrow),
              color: Colors.white,
              iconSize: 32,
              onPressed: state.isActive ? _replay.pause : _replay.play,
              tooltip: state.isActive ? 'Pause' : 'Play',
            ),
          ),
          const SizedBox(width: 16),
          // Next spin
          IconButton(
            icon: const Icon(Icons.fast_forward),
            color: Colors.white70,
            onPressed: _replay.position.spinIndex < _replay.totalSpins - 1
                ? () => _replay.seekToSpin(_replay.position.spinIndex + 1)
                : null,
            tooltip: 'Next spin',
          ),
          const SizedBox(width: 8),
          // Stop
          IconButton(
            icon: const Icon(Icons.stop),
            color: Colors.white70,
            onPressed: state.canStop ? _replay.stop : null,
            tooltip: 'Stop',
          ),
          const Spacer(),
          // Speed selector
          _SpeedSelector(
            speed: _replay.speed,
            onChanged: _replay.setSpeed,
          ),
        ],
      ),
    );
  }

  // Actions
  void _startRecording() {
    _recorder.startRecording();
    widget.onRecordingStarted?.call();
  }

  void _pauseRecording() => _recorder.pauseRecording();

  void _resumeRecording() => _recorder.resumeRecording();

  void _stopRecording() {
    final session = _recorder.stopRecording();
    if (session != null) {
      _storage.saveSession(session).then((_) => _loadSavedSessions());
    }
    widget.onRecordingStopped?.call();
  }

  Future<void> _loadAndPlaySession(String sessionId) async {
    final session = await _storage.loadSession(
      '${_getSessionPath()}/$sessionId.ffsession',
    );

    if (session != null) {
      await _replay.loadSession(session);
      _replay.play();
    }
  }

  String _getSessionPath() {
    return _storage.storagePath;
  }

  Future<void> _importSession() async {
    final result = await SafeFilePicker.pickFiles(context,
      type: FileType.custom,
      allowedExtensions: ['ffsession', 'json'],
    );

    if (result != null && result.files.single.path != null) {
      final session = await _storage.importSession(result.files.single.path!);
      if (session != null) {
        await _storage.saveSession(session);
        _loadSavedSessions();
      }
    }
  }

  Future<void> _exportSession(String sessionId) async {
    final session = await _storage.loadSession(
      '${_getSessionPath()}/$sessionId.ffsession',
    );

    if (session != null) {
      final outputPath = await SafeFilePicker.saveFile(context,
        dialogTitle: 'Export Session',
        fileName: '$sessionId.ffsession',
        allowedExtensions: ['ffsession'],
      );

      if (outputPath != null) {
        await _storage.exportSession(session, outputPath);
      }
    }
  }

  Future<void> _deleteSession(String sessionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Session?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF4060)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _storage.deleteSession(sessionId);
      _loadSavedSessions();
    }
  }

  void _closeReplay() {
    _replay.unloadSession();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes}m ${seconds}s';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _RecordingIndicator extends StatefulWidget {
  final int spinCount;

  const _RecordingIndicator({required this.spinCount});

  @override
  State<_RecordingIndicator> createState() => _RecordingIndicatorState();
}

class _RecordingIndicatorState extends State<_RecordingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color.lerp(
                const Color(0xFFFF4060),
                const Color(0xFFFF4060).withOpacity(0.3),
                _controller.value,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'REC • ${widget.spinCount} spins',
          style: const TextStyle(
            color: Color(0xFFFF4060),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _PlaybackIndicator extends StatelessWidget {
  final ReplayPosition position;

  const _PlaybackIndicator({required this.position});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.play_arrow, color: Color(0xFF40FF90), size: 16),
        const SizedBox(width: 4),
        Text(
          'PLAYING • Spin ${position.spinIndex + 1}',
          style: const TextStyle(
            color: Color(0xFF40FF90),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1E1E26),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: Colors.white54, size: 18),
              const SizedBox(width: 10),
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final SessionSummary summary;
  final VoidCallback onPlay;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  const _SessionCard({
    required this.summary,
    required this.onPlay,
    required this.onExport,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF242430),
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onPlay,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF4A9EFF).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.videocam, color: Color(0xFF4A9EFF), size: 20),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.gameName.isNotEmpty ? summary.gameName : summary.gameId,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '${summary.spinCount} spins',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        const Text(' • ', style: TextStyle(color: Colors.white38)),
                        Text(
                          _formatDate(summary.startedAt),
                          style: const TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Badges
              if (summary.hasFeature)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF40FF90).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('FS',
                      style: TextStyle(color: Color(0xFF40FF90), fontSize: 10)),
                ),
              if (summary.hasJackpot)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('JP',
                      style: TextStyle(color: Color(0xFFFFD700), fontSize: 10)),
                ),
              // Actions
              IconButton(
                icon: const Icon(Icons.file_download, size: 18),
                color: Colors.white54,
                onPressed: onExport,
                tooltip: 'Export',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: Colors.white54,
                onPressed: onDelete,
                tooltip: 'Delete',
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Today ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.month}/${date.day}/${date.year}';
    }
  }
}

class _SpinListItem extends StatelessWidget {
  final RecordedSpin spin;
  final bool isActive;
  final bool isPast;
  final VoidCallback onTap;

  const _SpinListItem({
    required this.spin,
    required this.isActive,
    required this.isPast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive
          ? const Color(0xFF4A9EFF).withOpacity(0.2)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: isActive
                    ? const Color(0xFF4A9EFF)
                    : (isPast ? const Color(0xFF40FF90) : Colors.transparent),
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              // Spin number
              SizedBox(
                width: 40,
                child: Text(
                  '#${spin.spinIndex + 1}',
                  style: TextStyle(
                    color: isPast ? Colors.white54 : Colors.white70,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
              // Win amount
              Expanded(
                child: Text(
                  spin.isWin
                      ? '+${spin.winAmount.toStringAsFixed(2)}'
                      : 'No win',
                  style: TextStyle(
                    color: spin.isWin ? const Color(0xFF40FF90) : Colors.white38,
                    fontWeight: spin.isWin ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              // Win ratio
              if (spin.isWin)
                Text(
                  '${spin.winRatio.toStringAsFixed(1)}x',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              // Feature/Jackpot badges
              if (spin.hasFeature)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  margin: const EdgeInsets.only(left: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF40FF90).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text('FS',
                      style: TextStyle(color: Color(0xFF40FF90), fontSize: 9)),
                ),
              if (spin.hasJackpot)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  margin: const EdgeInsets.only(left: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text('JP',
                      style: TextStyle(color: Color(0xFFFFD700), fontSize: 9)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final String value;

  const _StatBadge({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E26),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 9)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _SpeedSelector extends StatelessWidget {
  final ReplaySpeed speed;
  final ValueChanged<ReplaySpeed> onChanged;

  const _SpeedSelector({required this.speed, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ReplaySpeed>(
      initialValue: speed,
      onSelected: onChanged,
      tooltip: 'Playback speed',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E26),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.speed, color: Colors.white54, size: 16),
            const SizedBox(width: 6),
            Text(speed.label,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const Icon(Icons.arrow_drop_down, color: Colors.white54, size: 18),
          ],
        ),
      ),
      itemBuilder: (context) => ReplaySpeed.values
          .map((s) => PopupMenuItem(
                value: s,
                child: Text(s.label),
              ))
          .toList(),
    );
  }
}
