/// Audio Preview Queue Widget (P12.1.13)
///
/// Queue multiple audio files for sequential preview.
/// Features:
/// - Add files to queue
/// - Auto-play queue
/// - Reorder items via drag-drop
/// - Remove items
/// - Progress indicator
library;

import 'dart:async';
import 'package:flutter/material.dart';

// =============================================================================
// QUEUE ITEM MODEL
// =============================================================================

/// A single item in the audio preview queue
class AudioQueueItem {
  final String id;
  final String audioPath;
  final String displayName;
  final Duration? duration;
  final DateTime addedAt;

  AudioQueueItem({
    required this.id,
    required this.audioPath,
    required this.displayName,
    this.duration,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  String get fileName {
    final parts = audioPath.split('/');
    return parts.isNotEmpty ? parts.last : audioPath;
  }
}

/// Queue playback state
enum QueuePlaybackState {
  stopped,
  playing,
  paused,
}

// =============================================================================
// AUDIO PREVIEW QUEUE WIDGET
// =============================================================================

class AudioPreviewQueue extends StatefulWidget {
  final Future<void> Function(String audioPath)? onPlayAudio;
  final Future<void> Function()? onStopAudio;
  final Future<Duration?> Function(String audioPath)? getDuration;

  const AudioPreviewQueue({
    super.key,
    this.onPlayAudio,
    this.onStopAudio,
    this.getDuration,
  });

  @override
  State<AudioPreviewQueue> createState() => AudioPreviewQueueState();
}

class AudioPreviewQueueState extends State<AudioPreviewQueue> {
  final List<AudioQueueItem> _queue = [];
  int _currentIndex = -1;
  QueuePlaybackState _playbackState = QueuePlaybackState.stopped;
  Timer? _playbackTimer;
  double _progress = 0.0;

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Add audio file to queue
  Future<void> addToQueue(String audioPath, {String? displayName}) async {
    final id = '${DateTime.now().millisecondsSinceEpoch}_${_queue.length}';
    final name = displayName ?? _extractFileName(audioPath);

    Duration? duration;
    if (widget.getDuration != null) {
      duration = await widget.getDuration!(audioPath);
    }

    setState(() {
      _queue.add(AudioQueueItem(
        id: id,
        audioPath: audioPath,
        displayName: name,
        duration: duration,
      ));
    });
  }

  /// Remove item from queue
  void removeFromQueue(String itemId) {
    final index = _queue.indexWhere((item) => item.id == itemId);
    if (index < 0) return;

    // If removing currently playing item, stop playback
    if (index == _currentIndex && _playbackState == QueuePlaybackState.playing) {
      _stopPlayback();
    }

    setState(() {
      _queue.removeAt(index);
      if (_currentIndex >= _queue.length) {
        _currentIndex = _queue.length - 1;
      }
    });
  }

  /// Clear entire queue
  void clearQueue() {
    _stopPlayback();
    setState(() {
      _queue.clear();
      _currentIndex = -1;
    });
  }

  /// Reorder items in queue
  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex--;
    setState(() {
      final item = _queue.removeAt(oldIndex);
      _queue.insert(newIndex, item);
      // Update current index if needed
      if (_currentIndex == oldIndex) {
        _currentIndex = newIndex;
      } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
        _currentIndex--;
      } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
        _currentIndex++;
      }
    });
  }

  /// Start playing queue from beginning or current position
  Future<void> playQueue() async {
    if (_queue.isEmpty) return;

    if (_currentIndex < 0) _currentIndex = 0;
    setState(() => _playbackState = QueuePlaybackState.playing);
    await _playCurrentItem();
  }

  /// Pause playback
  void pauseQueue() {
    _playbackTimer?.cancel();
    widget.onStopAudio?.call();
    setState(() => _playbackState = QueuePlaybackState.paused);
  }

  /// Stop playback and reset to beginning
  void stopQueue() {
    _stopPlayback();
    setState(() {
      _currentIndex = -1;
      _progress = 0.0;
    });
  }

  /// Skip to next item
  Future<void> skipNext() async {
    if (_currentIndex < _queue.length - 1) {
      _playbackTimer?.cancel();
      widget.onStopAudio?.call();
      setState(() {
        _currentIndex++;
        _progress = 0.0;
      });
      if (_playbackState == QueuePlaybackState.playing) {
        await _playCurrentItem();
      }
    }
  }

  /// Skip to previous item
  Future<void> skipPrevious() async {
    if (_currentIndex > 0) {
      _playbackTimer?.cancel();
      widget.onStopAudio?.call();
      setState(() {
        _currentIndex--;
        _progress = 0.0;
      });
      if (_playbackState == QueuePlaybackState.playing) {
        await _playCurrentItem();
      }
    }
  }

  // ─── Getters ────────────────────────────────────────────────────────────────

  List<AudioQueueItem> get queue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  QueuePlaybackState get playbackState => _playbackState;
  double get progress => _progress;
  bool get isPlaying => _playbackState == QueuePlaybackState.playing;
  bool get isEmpty => _queue.isEmpty;
  int get length => _queue.length;

  // ─── Private Methods ────────────────────────────────────────────────────────

  void _stopPlayback() {
    _playbackTimer?.cancel();
    widget.onStopAudio?.call();
    setState(() => _playbackState = QueuePlaybackState.stopped);
  }

  Future<void> _playCurrentItem() async {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) {
      _stopPlayback();
      return;
    }

    final item = _queue[_currentIndex];
    setState(() => _progress = 0.0);

    await widget.onPlayAudio?.call(item.audioPath);

    // Simulate playback progress
    final duration = item.duration ?? const Duration(seconds: 3);
    const tickInterval = Duration(milliseconds: 100);
    final totalTicks = duration.inMilliseconds / tickInterval.inMilliseconds;
    var currentTick = 0;

    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(tickInterval, (timer) {
      currentTick++;
      setState(() => _progress = currentTick / totalTicks);

      if (currentTick >= totalTicks) {
        timer.cancel();
        _onItemComplete();
      }
    });
  }

  void _onItemComplete() {
    if (_currentIndex < _queue.length - 1) {
      setState(() => _currentIndex++);
      _playCurrentItem();
    } else {
      _stopPlayback();
      setState(() {
        _currentIndex = -1;
        _progress = 0.0;
      });
    }
  }

  String _extractFileName(String path) {
    final parts = path.split('/');
    final fileName = parts.isNotEmpty ? parts.last : path;
    // Remove extension
    final dotIndex = fileName.lastIndexOf('.');
    return dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        const Divider(height: 1),
        Expanded(child: _buildQueueList()),
        const Divider(height: 1),
        _buildControls(),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF1a1a20),
      child: Row(
        children: [
          const Icon(Icons.queue_music, size: 18, color: Color(0xFF4A9EFF)),
          const SizedBox(width: 8),
          const Text(
            'Preview Queue',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Text(
            '${_queue.length} items',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
          const SizedBox(width: 8),
          if (_queue.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all, size: 16),
              onPressed: clearQueue,
              tooltip: 'Clear queue',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
        ],
      ),
    );
  }

  Widget _buildQueueList() {
    if (_queue.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.playlist_add, size: 40, color: Colors.grey[700]),
            const SizedBox(height: 8),
            Text(
              'Queue is empty',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 4),
            Text(
              'Add audio files to preview',
              style: TextStyle(fontSize: 10, color: Colors.grey[700]),
            ),
          ],
        ),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _queue.length,
      onReorder: reorderQueue,
      itemBuilder: (context, index) => _buildQueueItem(_queue[index], index),
    );
  }

  Widget _buildQueueItem(AudioQueueItem item, int index) {
    final isCurrent = index == _currentIndex;
    final isPlaying = isCurrent && _playbackState == QueuePlaybackState.playing;

    return Container(
      key: ValueKey(item.id),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isCurrent ? const Color(0xFF2a2a35) : const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isCurrent ? const Color(0xFF4A9EFF) : const Color(0xFF333340),
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: isCurrent ? const Color(0xFF4A9EFF) : Colors.grey[800],
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: isPlaying
                ? const Icon(Icons.play_arrow, size: 14, color: Colors.white)
                : Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isCurrent ? Colors.white : Colors.grey[500],
                    ),
                  ),
          ),
        ),
        title: Text(
          item.displayName,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: item.duration != null
            ? Text(
                _formatDuration(item.duration!),
                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isCurrent && isPlaying)
              SizedBox(
                width: 40,
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.grey[800],
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF4A9EFF)),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.close, size: 14),
              onPressed: () => removeFromQueue(item.id),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: const Color(0xFF1a1a20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.skip_previous, size: 20),
            onPressed: _currentIndex > 0 ? skipPrevious : null,
            color: const Color(0xFF4A9EFF),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF4A9EFF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: IconButton(
              icon: Icon(
                _playbackState == QueuePlaybackState.playing
                    ? Icons.pause
                    : Icons.play_arrow,
                size: 24,
              ),
              onPressed: _queue.isEmpty
                  ? null
                  : () {
                      if (_playbackState == QueuePlaybackState.playing) {
                        pauseQueue();
                      } else {
                        playQueue();
                      }
                    },
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.stop, size: 20),
            onPressed: _playbackState != QueuePlaybackState.stopped ? stopQueue : null,
            color: const Color(0xFFFF6B6B),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.skip_next, size: 20),
            onPressed: _currentIndex < _queue.length - 1 ? skipNext : null,
            color: const Color(0xFF4A9EFF),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
