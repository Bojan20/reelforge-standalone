/// Audio Hover Preview Widget
///
/// Quick audio preview on hover in the browser:
/// - Mini waveform display
/// - Play on hover (with delay)
/// - Quick play/stop controls
/// - Duration display
/// - Format/sample rate info
/// - Drag to timeline support
///
/// INTEGRATION: Uses AudioPlaybackService.previewFile() for playback
library;

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';
import '../../services/audio_playback_service.dart';
import '../../services/waveform_thumbnail_cache.dart';

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO FILE INFO MODEL
// ═══════════════════════════════════════════════════════════════════════════

class AudioFileInfo {
  final String id;
  final String name;
  final String path;
  final Duration duration;
  final int sampleRate;
  final int channels;
  final String format;
  final int bitDepth;
  final List<double>? waveformData;
  final List<String> tags;

  const AudioFileInfo({
    required this.id,
    required this.name,
    required this.path,
    required this.duration,
    this.sampleRate = 48000,
    this.channels = 2,
    this.format = 'WAV',
    this.bitDepth = 24,
    this.waveformData,
    this.tags = const [],
  });

  String get durationFormatted {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    final millis = duration.inMilliseconds % 1000;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}.'
        '${(millis ~/ 10).toString().padLeft(2, '0')}';
  }

  String get channelLabel => channels == 1 ? 'Mono' : 'Stereo';

  String get qualityLabel => '$sampleRate Hz / $bitDepth bit';
}

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO BROWSER ITEM WITH HOVER PREVIEW
// ═══════════════════════════════════════════════════════════════════════════

class AudioBrowserItem extends StatefulWidget {
  final AudioFileInfo audioInfo;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final Function(AudioFileInfo)? onDragStart;
  final VoidCallback? onPlay;
  final VoidCallback? onStop;
  final bool isPlaying;

  const AudioBrowserItem({
    super.key,
    required this.audioInfo,
    this.isSelected = false,
    this.onTap,
    this.onDoubleTap,
    this.onDragStart,
    this.onPlay,
    this.onStop,
    this.isPlaying = false,
  });

  @override
  State<AudioBrowserItem> createState() => _AudioBrowserItemState();
}

class _AudioBrowserItemState extends State<AudioBrowserItem>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  Timer? _hoverPreviewTimer;
  Timer? _progressTimer;
  bool _showPreview = false;
  late AnimationController _playbackController;
  double _playbackProgress = 0.0;
  int _currentVoiceId = -1;
  DateTime? _playbackStartTime;
  WaveformThumbnailData? _cachedWaveform;

  @override
  void initState() {
    super.initState();
    _playbackController = AnimationController(
      vsync: this,
      duration: widget.audioInfo.duration,
    );
    _playbackController.addListener(() {
      setState(() => _playbackProgress = _playbackController.value);
    });
    _loadWaveform();
  }

  void _loadWaveform() {
    final cache = WaveformThumbnailCache.instance;

    // Check cache first (sync)
    final cached = cache.get(widget.audioInfo.path);
    if (cached != null) {
      setState(() => _cachedWaveform = cached);
      return;
    }

    // Generate in background
    Future.microtask(() {
      if (!mounted) return;
      final data = cache.generate(widget.audioInfo.path);
      if (mounted && data != null) {
        setState(() => _cachedWaveform = data);
      }
    });
  }

  @override
  void dispose() {
    _hoverPreviewTimer?.cancel();
    _progressTimer?.cancel();
    _playbackController.dispose();
    _stopPlayback();
    super.dispose();
  }

  void _onHoverStart() {
    setState(() => _isHovered = true);

    // Start preview timer (play after 500ms hover)
    _hoverPreviewTimer = Timer(const Duration(milliseconds: 500), () {
      if (_isHovered && mounted) {
        setState(() => _showPreview = true);
        _startPlayback();
      }
    });
  }

  void _onHoverEnd() {
    setState(() {
      _isHovered = false;
      _showPreview = false;
    });
    _hoverPreviewTimer?.cancel();
    _stopPlayback();
  }

  /// Start playback via AudioPlaybackService
  void _startPlayback() {
    // Use AudioPlaybackService for actual audio playback
    _currentVoiceId = AudioPlaybackService.instance.previewFile(
      widget.audioInfo.path,
      source: PlaybackSource.browser,
    );

    if (_currentVoiceId >= 0) {
      _playbackStartTime = DateTime.now();
      _playbackController.forward(from: 0);

      // Start progress tracking timer (syncs with audio)
      _progressTimer?.cancel();
      _progressTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (!mounted || _playbackStartTime == null) return;

        final elapsed = DateTime.now().difference(_playbackStartTime!);
        final progress = elapsed.inMilliseconds / widget.audioInfo.duration.inMilliseconds;

        if (progress >= 1.0) {
          _stopPlayback();
        }
      });

      widget.onPlay?.call();
    }
  }

  /// Stop playback via AudioPlaybackService
  void _stopPlayback() {
    _progressTimer?.cancel();
    _progressTimer = null;
    _playbackStartTime = null;

    if (_currentVoiceId >= 0) {
      AudioPlaybackService.instance.stopSource(PlaybackSource.browser);
      _currentVoiceId = -1;
    }

    _playbackController.stop();
    _playbackController.reset();
    widget.onStop?.call();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _onHoverStart(),
      onExit: (_) => _onHoverEnd(),
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: Draggable<AudioFileInfo>(
          data: widget.audioInfo,
          onDragStarted: () => widget.onDragStart?.call(widget.audioInfo),
          feedback: _buildDragFeedback(),
          childWhenDragging: Opacity(
            opacity: 0.5,
            child: _buildContent(),
          ),
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: widget.isSelected
            ? FluxForgeTheme.accentBlue.withOpacity(0.2)
            : _isHovered
                ? Colors.white.withOpacity(0.05)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: widget.isSelected
              ? FluxForgeTheme.accentBlue
              : _isHovered
                  ? FluxForgeTheme.borderSubtle
                  : Colors.transparent,
          width: widget.isSelected ? 1 : 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: Icon, Name, Duration
          Row(
            children: [
              // File type icon
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _getFormatColor().withOpacity(0.3),
                      _getFormatColor().withOpacity(0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(
                  Icons.audiotrack,
                  size: 14,
                  color: _getFormatColor(),
                ),
              ),
              const SizedBox(width: 8),

              // Name and format
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.audioInfo.name,
                      style: TextStyle(
                        color: widget.isSelected
                            ? FluxForgeTheme.accentBlue
                            : Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        Text(
                          widget.audioInfo.format,
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 9,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '·',
                          style: TextStyle(color: Colors.white24),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.audioInfo.channelLabel,
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Duration
              Text(
                widget.audioInfo.durationFormatted,
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),

              // Play button on hover
              if (_isHovered) ...[
                const SizedBox(width: 8),
                _buildPlayButton(),
              ],
            ],
          ),

          // Preview section (shows on hover)
          if (_showPreview || widget.isPlaying) ...[
            const SizedBox(height: 8),
            _buildHoverPreview(),
          ],

          // Tags
          if (widget.audioInfo.tags.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 2,
              children: widget.audioInfo.tags.map((tag) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentOrange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      color: FluxForgeTheme.accentOrange,
                      fontSize: 8,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlayButton() {
    final isActuallyPlaying = _currentVoiceId >= 0 || widget.isPlaying;

    return InkWell(
      onTap: () {
        if (isActuallyPlaying) {
          _stopPlayback();
        } else {
          _startPlayback();
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: isActuallyPlaying
              ? FluxForgeTheme.accentGreen.withOpacity(0.2)
              : FluxForgeTheme.accentBlue.withOpacity(0.2),
          shape: BoxShape.circle,
          border: Border.all(
            color: isActuallyPlaying
                ? FluxForgeTheme.accentGreen
                : FluxForgeTheme.accentBlue,
            width: 1,
          ),
        ),
        child: Icon(
          isActuallyPlaying ? Icons.stop : Icons.play_arrow,
          size: 14,
          color: isActuallyPlaying
              ? FluxForgeTheme.accentGreen
              : FluxForgeTheme.accentBlue,
        ),
      ),
    );
  }

  Widget _buildHoverPreview() {
    final isActuallyPlaying = _currentVoiceId >= 0 || widget.isPlaying;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle, width: 0.5),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // Waveform
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: CustomPaint(
                  size: Size(constraints.maxWidth, 40),
                  painter: _MiniWaveformPainter(
                    waveformData: widget.audioInfo.waveformData,
                    cachedData: _cachedWaveform,
                    progress: _playbackProgress,
                    isPlaying: isActuallyPlaying,
                  ),
                ),
              ),

              // Playback progress overlay
              if (isActuallyPlaying)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 50),
                    width: _playbackProgress * constraints.maxWidth,
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.accentGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),

              // Info overlay
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    widget.audioInfo.qualityLabel,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 8,
                    ),
                  ),
                ),
              ),

              // Playing indicator
              if (isActuallyPlaying)
                Positioned(
                  left: 4,
                  top: 4,
                  child: Row(
                    children: [
                      _PlayingIndicator(),
                      const SizedBox(width: 4),
                      Text(
                        'PLAYING',
                        style: TextStyle(
                          color: FluxForgeTheme.accentGreen,
                          fontSize: 7,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDragFeedback() {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: FluxForgeTheme.accentBlue, width: 2),
          boxShadow: [
            BoxShadow(
              color: FluxForgeTheme.accentBlue.withOpacity(0.3),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.audiotrack, color: FluxForgeTheme.accentBlue, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.audioInfo.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getFormatColor() {
    switch (widget.audioInfo.format.toUpperCase()) {
      case 'WAV':
        return FluxForgeTheme.accentBlue;
      case 'FLAC':
        return FluxForgeTheme.accentGreen;
      case 'MP3':
        return FluxForgeTheme.accentOrange;
      case 'OGG':
        return const Color(0xFFE040FB);
      case 'AIFF':
        return const Color(0xFF40C8FF);
      default:
        return Colors.grey;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MINI WAVEFORM PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _MiniWaveformPainter extends CustomPainter {
  final List<double>? waveformData;
  final WaveformThumbnailData? cachedData;
  final double progress;
  final bool isPlaying;

  _MiniWaveformPainter({
    this.waveformData,
    this.cachedData,
    this.progress = 0,
    this.isPlaying = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final halfHeight = size.height * 0.4;

    // Use cached FFI data if available
    if (cachedData != null) {
      _paintFromCache(canvas, size, centerY, halfHeight);
      return;
    }

    // Fall back to legacy data or fake waveform
    final data = waveformData ?? _generateFakeWaveform(64);
    final barWidth = size.width / data.length;

    for (int i = 0; i < data.length; i++) {
      final x = i * barWidth;
      final amplitude = data[i] * halfHeight;
      final isPastProgress = i / data.length < progress;

      final paint = Paint()
        ..color = isPastProgress && isPlaying
            ? FluxForgeTheme.accentGreen.withOpacity(0.8)
            : Colors.white.withOpacity(0.3)
        ..strokeWidth = barWidth * 0.7
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(x + barWidth / 2, centerY - amplitude),
        Offset(x + barWidth / 2, centerY + amplitude),
        paint,
      );
    }
  }

  void _paintFromCache(Canvas canvas, Size size, double centerY, double halfHeight) {
    final path = Path();
    bool first = true;

    // Top edge (max peaks)
    for (int i = 0; i < kThumbnailWidth; i++) {
      final x = (i / kThumbnailWidth) * size.width;
      final (_, maxVal) = cachedData!.getPeakAt(i);
      final y = centerY - (maxVal * halfHeight);
      final isPastProgress = i / kThumbnailWidth < progress;

      if (first) {
        path.moveTo(x, y);
        first = false;
      } else {
        path.lineTo(x, y);
      }
    }

    // Bottom edge (min peaks, reversed)
    for (int i = kThumbnailWidth - 1; i >= 0; i--) {
      final x = (i / kThumbnailWidth) * size.width;
      final (minVal, _) = cachedData!.getPeakAt(i);
      final y = centerY - (minVal * halfHeight);
      path.lineTo(x, y);
    }

    path.close();

    // Fill waveform (base color)
    final basePaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, basePaint);

    // Draw progress overlay if playing
    if (isPlaying && progress > 0) {
      final progressWidth = progress * size.width;
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, progressWidth, size.height));
      final progressPaint = Paint()
        ..color = FluxForgeTheme.accentGreen.withOpacity(0.8)
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, progressPaint);
      canvas.restore();
    }

    // Draw center line
    final centerPaint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      centerPaint,
    );
  }

  List<double> _generateFakeWaveform(int samples) {
    final random = math.Random(42);
    return List.generate(samples, (i) {
      final envelope = math.sin(i / samples * math.pi);
      return (random.nextDouble() * 0.5 + 0.3) * envelope;
    });
  }

  @override
  bool shouldRepaint(covariant _MiniWaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.cachedData != cachedData;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PLAYING INDICATOR
// ═══════════════════════════════════════════════════════════════════════════

class _PlayingIndicator extends StatefulWidget {
  @override
  State<_PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<_PlayingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.2;
            final progress = (_controller.value + delay) % 1.0;
            final height = 4 + 4 * math.sin(progress * math.pi);

            return Container(
              width: 2,
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentGreen,
                borderRadius: BorderRadius.circular(1),
              ),
            );
          }),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO BROWSER PANEL
// ═══════════════════════════════════════════════════════════════════════════

/// Full audio browser panel with search, filter, and preview
class AudioBrowserPanel extends StatefulWidget {
  final List<AudioFileInfo> audioFiles;
  final Function(AudioFileInfo)? onSelect;
  final Function(AudioFileInfo)? onPlay;
  final Function(AudioFileInfo)? onDrop;
  final double height;

  const AudioBrowserPanel({
    super.key,
    required this.audioFiles,
    this.onSelect,
    this.onPlay,
    this.onDrop,
    this.height = 400,
  });

  @override
  State<AudioBrowserPanel> createState() => _AudioBrowserPanelState();
}

class _AudioBrowserPanelState extends State<AudioBrowserPanel> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFormat = 'All';
  AudioFileInfo? _selectedFile;
  String? _playingFileId;

  static const List<String> _formatFilters = [
    'All',
    'WAV',
    'FLAC',
    'MP3',
    'OGG',
    'AIFF',
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AudioFileInfo> get _filteredFiles {
    return widget.audioFiles.where((file) {
      // Format filter
      if (_selectedFormat != 'All' && file.format != _selectedFormat) {
        return false;
      }

      // Search filter
      if (_searchQuery.isNotEmpty) {
        final matchesName = file.name.toLowerCase().contains(_searchQuery);
        final matchesTags =
            file.tags.any((tag) => tag.toLowerCase().contains(_searchQuery));
        if (!matchesName && !matchesTags) return false;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        children: [
          _buildHeader(),
          _buildFilters(),
          Expanded(child: _buildFileList()),
          _buildStatusBar(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_open, size: 16, color: FluxForgeTheme.accentBlue),
          const SizedBox(width: 8),
          Text(
            'AUDIO BROWSER',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),

          // Search
          SizedBox(
            width: 180,
            height: 24,
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white, fontSize: 11),
              decoration: InputDecoration(
                hintText: 'Search files...',
                hintStyle: TextStyle(color: Colors.white38, fontSize: 11),
                prefixIcon: Icon(Icons.search, size: 14, color: Colors.white38),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, size: 12, color: Colors.white38),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: FluxForgeTheme.accentBlue),
                ),
                filled: true,
                fillColor: FluxForgeTheme.bgDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Text(
            'Format:',
            style: TextStyle(color: Colors.white38, fontSize: 10),
          ),
          const SizedBox(width: 8),
          ..._formatFilters.map((format) {
            final isActive = _selectedFormat == format;

            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: InkWell(
                onTap: () => setState(() => _selectedFormat = format),
                borderRadius: BorderRadius.circular(3),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isActive
                        ? FluxForgeTheme.accentBlue.withOpacity(0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: isActive
                          ? FluxForgeTheme.accentBlue
                          : FluxForgeTheme.borderSubtle,
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    format,
                    style: TextStyle(
                      color: isActive
                          ? FluxForgeTheme.accentBlue
                          : Colors.white54,
                      fontSize: 9,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFileList() {
    final files = _filteredFiles;

    if (files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _searchQuery.isNotEmpty ? Icons.search_off : Icons.folder_off,
              size: 40,
              color: Colors.white24,
            ),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No files match your search'
                  : 'No audio files',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];

        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: AudioBrowserItem(
            audioInfo: file,
            isSelected: _selectedFile?.id == file.id,
            isPlaying: _playingFileId == file.id,
            onTap: () {
              setState(() => _selectedFile = file);
              widget.onSelect?.call(file);
            },
            onDoubleTap: () => widget.onPlay?.call(file),
            onPlay: () {
              setState(() => _playingFileId = file.id);
              widget.onPlay?.call(file);
            },
            onStop: () => setState(() => _playingFileId = null),
            onDragStart: (info) => widget.onDrop?.call(info),
          ),
        );
      },
    );
  }

  Widget _buildStatusBar() {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(7)),
      ),
      child: Row(
        children: [
          Text(
            '${_filteredFiles.length} files',
            style: TextStyle(color: Colors.white38, fontSize: 9),
          ),
          if (_selectedFormat != 'All') ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentBlue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                _selectedFormat,
                style: TextStyle(
                  color: FluxForgeTheme.accentBlue,
                  fontSize: 8,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (_playingFileId != null)
            Row(
              children: [
                _PlayingIndicator(),
                const SizedBox(width: 4),
                Text(
                  'Playing',
                  style: TextStyle(
                    color: FluxForgeTheme.accentGreen,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
