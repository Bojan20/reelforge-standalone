/// Video Export Panel
///
/// UI for video recording and export:
/// - Recording controls (start/stop/pause)
/// - Format and quality selection
/// - Export history
/// - FFmpeg status indicator
///
/// Created: 2026-01-30 (P4.15)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../services/video_export_service.dart';

/// Video export panel widget
class VideoExportPanel extends StatefulWidget {
  final RenderRepaintBoundary? boundary;
  final VoidCallback? onRecordingStarted;
  final VoidCallback? onRecordingEnded;

  const VideoExportPanel({
    super.key,
    this.boundary,
    this.onRecordingStarted,
    this.onRecordingEnded,
  });

  @override
  State<VideoExportPanel> createState() => _VideoExportPanelState();
}

class _VideoExportPanelState extends State<VideoExportPanel> {
  final _service = VideoExportService.instance;
  bool _ffmpegAvailable = false;
  String? _ffmpegVersion;
  Timer? _refreshTimer;
  double _exportProgress = 0;
  String _exportStatus = '';

  @override
  void initState() {
    super.initState();
    _initService();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  Future<void> _initService() async {
    await _service.init();
    _ffmpegAvailable = await _service.isFFmpegAvailable();
    _ffmpegVersion = await _service.getFFmpegVersion();
    if (mounted) setState(() {});
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(VideoExportPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.boundary != oldWidget.boundary) {
      _service.setBoundary(widget.boundary);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          if (!_ffmpegAvailable) _buildFFmpegWarning(),
          if (_ffmpegAvailable) ...[
            _buildRecordingControls(),
            const SizedBox(height: 16),
            _buildConfigSection(),
            const SizedBox(height: 16),
            Expanded(child: _buildHistorySection()),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(
          Icons.videocam,
          color: _service.isRecording ? Colors.red : Colors.white70,
          size: 24,
        ),
        const SizedBox(width: 8),
        const Text(
          'Video Export',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const Spacer(),
        if (_service.isRecording) ...[
          _buildRecordingIndicator(),
          const SizedBox(width: 12),
        ],
        _buildFFmpegStatus(),
      ],
    );
  }

  Widget _buildRecordingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.red.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'REC ${_formatDuration(_service.recordingDuration)}',
            style: const TextStyle(
              color: Colors.red,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFFmpegStatus() {
    return Tooltip(
      message: _ffmpegAvailable
          ? _ffmpegVersion ?? 'FFmpeg available'
          : 'FFmpeg not found in PATH',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _ffmpegAvailable
              ? Colors.green.withOpacity(0.2)
              : Colors.orange.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _ffmpegAvailable ? Icons.check_circle : Icons.warning,
              color: _ffmpegAvailable ? Colors.green : Colors.orange,
              size: 14,
            ),
            const SizedBox(width: 4),
            Text(
              'FFmpeg',
              style: TextStyle(
                color: _ffmpegAvailable ? Colors.green : Colors.orange,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFFmpegWarning() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange, size: 20),
              SizedBox(width: 8),
              Text(
                'FFmpeg Required',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Video export requires FFmpeg to be installed and available in PATH.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _openFFmpegDownload(),
                icon: const Icon(Icons.download, size: 16),
                label: const Text('Download FFmpeg'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.orange,
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => _initService(),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Check Again'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white70,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_service.isIdle) _buildStartButton(),
              if (_service.isRecording) ...[
                _buildPauseButton(),
                const SizedBox(width: 16),
                _buildStopButton(),
              ],
              if (_service.isPaused) ...[
                _buildResumeButton(),
                const SizedBox(width: 16),
                _buildStopButton(),
              ],
              if (_service.isEncoding) _buildEncodingIndicator(),
            ],
          ),
          if (_service.isRecording || _service.isPaused) ...[
            const SizedBox(height: 12),
            _buildRecordingStats(),
          ],
          if (_service.isEncoding) ...[
            const SizedBox(height: 12),
            _buildProgressBar(),
          ],
        ],
      ),
    );
  }

  Widget _buildStartButton() {
    return ElevatedButton.icon(
      onPressed: widget.boundary != null ? _startRecording : null,
      icon: const Icon(Icons.fiber_manual_record, color: Colors.red),
      label: const Text('Start Recording'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.red.withOpacity(0.2),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    );
  }

  Widget _buildPauseButton() {
    return IconButton(
      onPressed: _service.pauseRecording,
      icon: const Icon(Icons.pause, color: Colors.white),
      tooltip: 'Pause',
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withOpacity(0.1),
      ),
    );
  }

  Widget _buildResumeButton() {
    return IconButton(
      onPressed: _service.resumeRecording,
      icon: const Icon(Icons.play_arrow, color: Colors.green),
      tooltip: 'Resume',
      style: IconButton.styleFrom(
        backgroundColor: Colors.green.withOpacity(0.2),
      ),
    );
  }

  Widget _buildStopButton() {
    return ElevatedButton.icon(
      onPressed: _stopRecording,
      icon: const Icon(Icons.stop),
      label: const Text('Stop & Export'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue.withOpacity(0.3),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    );
  }

  Widget _buildEncodingIndicator() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          _exportStatus.isNotEmpty ? _exportStatus : 'Encoding...',
          style: const TextStyle(color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildRecordingStats() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildStat('Frames', '${_service.frameCount}'),
        const SizedBox(width: 24),
        _buildStat('Duration', _formatDuration(_service.recordingDuration)),
        const SizedBox(width: 24),
        _buildStat('Format', _service.config.format.displayName),
      ],
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
            fontFamily: 'monospace',
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBar() {
    return Column(
      children: [
        LinearProgressIndicator(
          value: _exportProgress,
          backgroundColor: Colors.white.withOpacity(0.1),
          color: Colors.blue,
        ),
        const SizedBox(height: 8),
        Text(
          '${(_exportProgress * 100).toInt()}% - $_exportStatus',
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildConfigSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Export Settings',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildFormatSelector()),
              const SizedBox(width: 12),
              Expanded(child: _buildQualitySelector()),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildMaxDurationSelector()),
              const SizedBox(width: 12),
              _buildAudioToggle(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFormatSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Format',
          style: TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<VideoExportFormat>(
          value: _service.config.format,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide.none,
            ),
          ),
          dropdownColor: const Color(0xFF2A2A30),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          items: VideoExportFormat.values.map((format) {
            return DropdownMenuItem(
              value: format,
              child: Text(format.displayName),
            );
          }).toList(),
          onChanged: _service.isIdle
              ? (format) {
                  if (format != null) {
                    _service.setConfig(_service.config.copyWith(format: format));
                  }
                }
              : null,
        ),
      ],
    );
  }

  Widget _buildQualitySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quality',
          style: TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<VideoExportQuality>(
          value: _service.config.quality,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide.none,
            ),
          ),
          dropdownColor: const Color(0xFF2A2A30),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          items: VideoExportQuality.values.map((quality) {
            return DropdownMenuItem(
              value: quality,
              child: Text(quality.displayName),
            );
          }).toList(),
          onChanged: _service.isIdle
              ? (quality) {
                  if (quality != null) {
                    _service.setConfig(_service.config.copyWith(quality: quality));
                  }
                }
              : null,
        ),
      ],
    );
  }

  Widget _buildMaxDurationSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Max Duration',
          style: TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<int>(
          value: _service.config.maxDurationSeconds,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide.none,
            ),
          ),
          dropdownColor: const Color(0xFF2A2A30),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          items: const [
            DropdownMenuItem(value: 30, child: Text('30 seconds')),
            DropdownMenuItem(value: 60, child: Text('1 minute')),
            DropdownMenuItem(value: 120, child: Text('2 minutes')),
            DropdownMenuItem(value: 300, child: Text('5 minutes')),
            DropdownMenuItem(value: 600, child: Text('10 minutes')),
          ],
          onChanged: _service.isIdle
              ? (duration) {
                  if (duration != null) {
                    _service.setConfig(
                      _service.config.copyWith(maxDurationSeconds: duration),
                    );
                  }
                }
              : null,
        ),
      ],
    );
  }

  Widget _buildAudioToggle() {
    return Tooltip(
      message: 'Include audio in export (requires system audio capture)',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: _service.config.includeAudio,
            onChanged: _service.isIdle
                ? (value) {
                    _service.setConfig(
                      _service.config.copyWith(includeAudio: value ?? false),
                    );
                  }
                : null,
            fillColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return Colors.blue;
              }
              return Colors.white24;
            }),
          ),
          const Text(
            'Audio',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection() {
    final history = _service.history;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Export History',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const Spacer(),
            if (history.isNotEmpty)
              TextButton(
                onPressed: () => _showClearHistoryDialog(),
                child: const Text(
                  'Clear All',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: history.isEmpty
              ? _buildEmptyHistory()
              : ListView.builder(
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    return _buildHistoryItem(history[index], index);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyHistory() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.video_library_outlined,
            size: 48,
            color: Colors.white.withOpacity(0.2),
          ),
          const SizedBox(height: 12),
          Text(
            'No exports yet',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Start recording to create your first video',
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(VideoExportResult result, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: result.success
              ? Colors.green.withOpacity(0.2)
              : Colors.red.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            result.success ? Icons.check_circle : Icons.error,
            color: result.success ? Colors.green : Colors.red,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.success) ...[
                  Text(
                    result.filePath?.split('/').last ?? 'Unknown',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${result.durationFormatted} • ${result.frameCount} frames • ${result.fileSizeFormatted}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 11,
                    ),
                  ),
                ] else ...[
                  const Text(
                    'Export failed',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    result.error ?? 'Unknown error',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (result.success) ...[
            IconButton(
              icon: const Icon(Icons.folder_open, size: 18),
              color: Colors.white54,
              tooltip: 'Open in Finder',
              onPressed: () => _service.openInFileManager(result.filePath!),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: Colors.white38,
            tooltip: 'Remove from history',
            onPressed: () => _service.removeFromHistory(index),
          ),
        ],
      ),
    );
  }

  // Actions

  Future<void> _startRecording() async {
    if (widget.boundary == null) {
      _showError('No capture boundary set');
      return;
    }

    // Start refresh timer for UI updates
    _refreshTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => setState(() {}),
    );

    final success = await _service.startRecording(boundary: widget.boundary);
    if (success) {
      widget.onRecordingStarted?.call();
    } else {
      _refreshTimer?.cancel();
      _showError('Failed to start recording');
    }
  }

  Future<void> _stopRecording() async {
    _refreshTimer?.cancel();

    final result = await _service.stopRecording(
      onProgress: (progress, status) {
        setState(() {
          _exportProgress = progress;
          _exportStatus = status;
        });
      },
    );

    widget.onRecordingEnded?.call();

    if (result.success) {
      _showSuccess('Video exported: ${result.filePath?.split('/').last}');
    } else {
      _showError('Export failed: ${result.error}');
    }
  }

  void _showClearHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A30),
        title: const Text('Clear History', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to clear all export history?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _service.clearHistory();
              Navigator.pop(context);
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _openFFmpegDownload() {
    // In real implementation, open URL
    debugPrint('Open https://ffmpeg.org/download.html');
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

/// Compact recording button for toolbar integration
class VideoRecordButton extends StatelessWidget {
  final RenderRepaintBoundary? boundary;
  final double size;

  const VideoRecordButton({
    super.key,
    this.boundary,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: VideoExportService.instance,
      builder: (context, _) {
        final service = VideoExportService.instance;

        return Tooltip(
          message: service.isRecording
              ? 'Stop Recording'
              : service.isEncoding
                  ? 'Encoding...'
                  : 'Start Recording',
          child: IconButton(
            onPressed: service.isEncoding ? null : () => _toggle(service),
            icon: Icon(
              service.isRecording
                  ? Icons.stop
                  : service.isEncoding
                      ? Icons.hourglass_top
                      : Icons.fiber_manual_record,
              color: service.isRecording ? Colors.red : Colors.white70,
              size: size * 0.6,
            ),
            style: IconButton.styleFrom(
              backgroundColor: service.isRecording
                  ? Colors.red.withOpacity(0.2)
                  : Colors.white.withOpacity(0.1),
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggle(VideoExportService service) async {
    if (service.isRecording) {
      await service.stopRecording();
    } else {
      await service.startRecording(boundary: boundary);
    }
  }
}

/// Recording time indicator for status bar
class RecordingTimeIndicator extends StatefulWidget {
  const RecordingTimeIndicator({super.key});

  @override
  State<RecordingTimeIndicator> createState() => _RecordingTimeIndicatorState();
}

class _RecordingTimeIndicatorState extends State<RecordingTimeIndicator> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = VideoExportService.instance;

    if (!service.isRecording) {
      return const SizedBox.shrink();
    }

    final duration = service.recordingDuration;
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$minutes:$seconds',
            style: const TextStyle(
              color: Colors.red,
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
