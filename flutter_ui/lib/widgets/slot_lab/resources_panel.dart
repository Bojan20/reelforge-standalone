/// Resources Panel for Slot Lab
///
/// Audio asset management with:
/// - Full asset list with metadata
/// - Waveform thumbnails
/// - Duration, sample rate, channels info
/// - Memory footprint per asset
/// - Load/Unload controls
/// - Search and filtering

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';
import '../../widgets/browser/audio_pool_panel.dart';
import '../../services/waveform_cache_service.dart';

/// Resources Panel Widget
class ResourcesPanel extends StatefulWidget {
  final double height;
  final List<Map<String, dynamic>>? audioPool;

  const ResourcesPanel({
    super.key,
    this.height = 250,
    this.audioPool,
  });

  @override
  State<ResourcesPanel> createState() => _ResourcesPanelState();
}

class _ResourcesPanelState extends State<ResourcesPanel> {
  List<AudioFileInfo> _resources = [];
  String _searchQuery = '';
  String _selectedCategory = 'All';
  String? _selectedResourceId;

  // Waveform cache stats
  Map<String, dynamic> _cacheStats = {};
  int _diskCacheSize = 0;
  int _diskCacheCount = 0;

  final _categories = ['All', 'SFX', 'Music', 'Voice', 'UI', 'Ambience'];

  @override
  void initState() {
    super.initState();
    _loadResources();
    _loadCacheStats();
  }

  Future<void> _loadCacheStats() async {
    final stats = WaveformCacheService.instance.getStats();
    final size = await WaveformCacheService.instance.getDiskCacheSize();
    final count = await WaveformCacheService.instance.getDiskCacheCount();
    if (mounted) {
      setState(() {
        _cacheStats = stats;
        _diskCacheSize = size;
        _diskCacheCount = count;
      });
    }
  }

  @override
  void didUpdateWidget(covariant ResourcesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.audioPool != oldWidget.audioPool) {
      _loadResources();
    }
  }

  void _loadResources() {
    // Use audio pool from parent if available
    if (widget.audioPool != null && widget.audioPool!.isNotEmpty) {
      setState(() {
        _resources = widget.audioPool!.asMap().entries.map((entry) {
          final item = entry.value;
          final path = item['path'] as String? ?? '';
          final name = item['name'] as String? ?? path.split('/').last;
          final duration = (item['duration'] as num?)?.toDouble() ?? 1.0;
          final sampleRate = (item['sampleRate'] as num?)?.toInt() ??
                             (item['sample_rate'] as num?)?.toInt() ?? 48000;
          final channels = (item['channels'] as num?)?.toInt() ?? 2;
          // Estimate file size from duration and sample rate
          final fileSize = (duration * sampleRate * channels * 2).toInt(); // 16-bit

          return AudioFileInfo(
            id: '${entry.key}',
            name: name,
            path: path,
            duration: duration,
            sampleRate: sampleRate,
            channels: channels,
            fileSize: fileSize,
          );
        }).toList();
      });
      debugPrint('[ResourcesPanel] Loaded ${_resources.length} resources from parent');
      return;
    }

    // No audio pool - show empty state
    setState(() {
      _resources = [];
    });
  }

  List<AudioFileInfo> get _filteredResources {
    var result = _resources;

    // Filter by category
    if (_selectedCategory != 'All') {
      result = result.where((r) {
        final folder = r.path.split('/').first.toLowerCase();
        return folder == _selectedCategory.toLowerCase();
      }).toList();
    }

    // Filter by search
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result.where((r) =>
        r.name.toLowerCase().contains(query) ||
        r.path.toLowerCase().contains(query)
      ).toList();
    }

    return result;
  }

  int get _totalMemory {
    return _resources.fold(0, (sum, r) => sum + r.fileSize);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      color: FluxForgeTheme.bgDeep,
      child: Row(
        children: [
          // Left: Resource list
          Expanded(
            flex: 3,
            child: _buildResourceList(),
          ),
          // Divider
          Container(width: 1, color: FluxForgeTheme.borderSubtle),
          // Right: Details
          Expanded(
            flex: 2,
            child: _buildResourceDetails(),
          ),
        ],
      ),
    );
  }

  Widget _buildResourceList() {
    return Column(
      children: [
        // Header with search
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: FluxForgeTheme.bgMid,
          child: Row(
            children: [
              const Icon(Icons.storage, size: 14, color: FluxForgeTheme.accentBlue),
              const SizedBox(width: 8),
              const Text(
                'RESOURCES',
                style: TextStyle(
                  color: FluxForgeTheme.accentBlue,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              // Stats
              Text(
                '${_resources.length} files • ${_formatBytes(_totalMemory)}',
                style: const TextStyle(color: Colors.white38, fontSize: 9),
              ),
            ],
          ),
        ),
        // Search and filters
        Container(
          padding: const EdgeInsets.all(8),
          color: FluxForgeTheme.bgMid.withOpacity(0.5),
          child: Row(
            children: [
              // Search
              Expanded(
                child: Container(
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.bgDeep,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 12, color: Colors.white38),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                          decoration: const InputDecoration(
                            hintText: 'Search...',
                            hintStyle: TextStyle(color: Colors.white24),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (value) => setState(() => _searchQuery = value),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Category filter
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgDeep,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCategory,
                    dropdownColor: FluxForgeTheme.bgMid,
                    isDense: true,
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                    items: _categories.map((c) =>
                      DropdownMenuItem(value: c, child: Text(c))
                    ).toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _selectedCategory = value);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        // Resource list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _filteredResources.length,
            itemBuilder: (context, index) {
              final resource = _filteredResources[index];
              final isSelected = _selectedResourceId == resource.id;
              return _buildResourceItem(resource, isSelected);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResourceItem(AudioFileInfo resource, bool isSelected) {
    return GestureDetector(
      onTap: () => setState(() => _selectedResourceId = resource.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected
              ? FluxForgeTheme.accentBlue.withOpacity(0.15)
              : FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? FluxForgeTheme.accentBlue : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Row(
          children: [
            // Icon based on type
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _getCategoryColor(resource.path).withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                _getCategoryIcon(resource.path),
                size: 14,
                color: _getCategoryColor(resource.path),
              ),
            ),
            const SizedBox(width: 10),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    resource.name,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        resource.formattedDuration,
                        style: const TextStyle(color: Colors.white38, fontSize: 9),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        resource.channelsLabel,
                        style: const TextStyle(color: Colors.white38, fontSize: 9),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        resource.formattedSize,
                        style: const TextStyle(color: Colors.white38, fontSize: 9),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Usage indicator
            if (resource.usedInClips.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentGreen.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '${resource.usedInClips.length}',
                  style: const TextStyle(
                    color: FluxForgeTheme.accentGreen,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResourceDetails() {
    final selectedResource = _selectedResourceId != null
        ? _resources.firstWhere(
            (r) => r.id == _selectedResourceId,
            orElse: () => _resources.first,
          )
        : null;

    if (selectedResource == null) {
      // Show cache stats when no resource selected
      return Column(
        children: [
          // Header
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: FluxForgeTheme.bgMid,
            child: const Row(
              children: [
                Icon(Icons.cached, size: 14, color: FluxForgeTheme.accentCyan),
                SizedBox(width: 8),
                Text(
                  'WAVEFORM CACHE',
                  style: TextStyle(
                    color: FluxForgeTheme.accentCyan,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cache stats
                  _buildDetailRow('Memory Cache', '${_cacheStats['memorySize'] ?? 0} waveforms'),
                  _buildDetailRow('Disk Cache', '$_diskCacheCount files'),
                  _buildDetailRow('Disk Size', _formatBytes(_diskCacheSize)),
                  const SizedBox(height: 8),
                  _buildDetailRow('Memory Hits', '${_cacheStats['memoryHits'] ?? 0}'),
                  _buildDetailRow('Disk Hits', '${_cacheStats['diskHits'] ?? 0}'),
                  _buildDetailRow('Disk Misses', '${_cacheStats['diskMisses'] ?? 0}'),
                  _buildDetailRow('Hit Rate', '${_cacheStats['hitRate'] ?? '0.0'}%'),
                  const SizedBox(height: 16),
                  // Clear cache button
                  GestureDetector(
                    onTap: () async {
                      await WaveformCacheService.instance.clearAll();
                      _loadCacheStats();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF4040).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFFF4040).withOpacity(0.5)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.delete_outline, size: 14, color: Color(0xFFFF4040)),
                          SizedBox(width: 6),
                          Text(
                            'Clear Cache',
                            style: TextStyle(
                              color: Color(0xFFFF4040),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Refresh stats
                  GestureDetector(
                    onTap: _loadCacheStats,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentBlue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: FluxForgeTheme.accentBlue.withOpacity(0.5)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.refresh, size: 14, color: FluxForgeTheme.accentBlue),
                          SizedBox(width: 6),
                          Text(
                            'Refresh Stats',
                            style: TextStyle(
                              color: FluxForgeTheme.accentBlue,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Select a resource for details',
                    style: TextStyle(color: Colors.white38, fontSize: 10),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        // Header
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: FluxForgeTheme.bgMid,
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 14, color: FluxForgeTheme.accentCyan),
              const SizedBox(width: 8),
              const Text(
                'DETAILS',
                style: TextStyle(
                  color: FluxForgeTheme.accentCyan,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
        // Details
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name
                Text(
                  selectedResource.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
                const SizedBox(height: 4),
                Text(
                  selectedResource.path,
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
                const SizedBox(height: 16),

                // Mini waveform preview
                Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.bgDeep,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: FluxForgeTheme.borderSubtle),
                  ),
                  child: CustomPaint(
                    painter: _MiniWaveformPainter(
                      color: _getCategoryColor(selectedResource.path),
                    ),
                    size: Size.infinite,
                  ),
                ),
                const SizedBox(height: 16),

                // Metadata grid
                _buildDetailRow('Duration', selectedResource.formattedDuration),
                _buildDetailRow('Sample Rate', '${selectedResource.sampleRate} Hz'),
                _buildDetailRow('Channels', selectedResource.channelsLabel),
                _buildDetailRow('Bit Depth', '${selectedResource.bitDepth} bit'),
                _buildDetailRow('File Size', selectedResource.formattedSize),

                const SizedBox(height: 16),

                // Actions
                Row(
                  children: [
                    Expanded(
                      child: _buildActionButton(
                        'Preview',
                        Icons.play_arrow,
                        FluxForgeTheme.accentGreen,
                        () {
                          // Play preview
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildActionButton(
                        'Unload',
                        Icons.remove_circle_outline,
                        const Color(0xFFFF4040),
                        () {
                          // Unload from memory
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getCategoryColor(String path) {
    final folder = path.split('/').first.toLowerCase();
    return switch (folder) {
      'sfx' => FluxForgeTheme.accentGreen,
      'music' => FluxForgeTheme.accentBlue,
      'voice' || 'vo' => FluxForgeTheme.accentOrange,
      'ui' => const Color(0xFFF1C40F),
      'ambience' => FluxForgeTheme.accentCyan,
      _ => Colors.white54,
    };
  }

  IconData _getCategoryIcon(String path) {
    final folder = path.split('/').first.toLowerCase();
    return switch (folder) {
      'sfx' => Icons.volume_up,
      'music' => Icons.music_note,
      'voice' || 'vo' => Icons.record_voice_over,
      'ui' => Icons.touch_app,
      'ambience' => Icons.landscape,
      _ => Icons.audio_file,
    };
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Mini waveform painter
class _MiniWaveformPainter extends CustomPainter {
  final Color color;

  _MiniWaveformPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.5)
      ..strokeWidth = 1;

    final midY = size.height / 2;
    final random = DateTime.now().millisecondsSinceEpoch;

    for (int i = 0; i < size.width.toInt(); i += 2) {
      final amplitude = ((((random + i * 7) % 100) / 100) * 0.8 + 0.1) * midY * 0.9;
      canvas.drawLine(
        Offset(i.toDouble(), midY - amplitude),
        Offset(i.toDouble(), midY + amplitude),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
