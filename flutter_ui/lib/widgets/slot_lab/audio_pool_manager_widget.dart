// audio_pool_manager_widget.dart — Advanced Audio Pool Management
import 'package:flutter/material.dart';

class AudioPoolStats {
  final int totalFiles;
  final int activePreviews;
  final int cacheHits;
  final int cacheMisses;
  const AudioPoolStats({required this.totalFiles, required this.activePreviews, required this.cacheHits, required this.cacheMisses});
  double get hitRate => (cacheHits + cacheMisses) > 0 ? cacheHits / (cacheHits + cacheMisses) : 0.0;
}

class AudioPoolManagerWidget extends StatelessWidget {
  final AudioPoolStats stats;
  final VoidCallback? onClearCache;
  const AudioPoolManagerWidget({super.key, required this.stats, this.onClearCache});
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Audio Pool Statistics', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          _buildStatRow('Total Files', '${stats.totalFiles}'),
          _buildStatRow('Active Previews', '${stats.activePreviews}'),
          _buildStatRow('Cache Hit Rate', '${(stats.hitRate * 100).toStringAsFixed(1)}%'),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onClearCache, child: const Text('Clear Cache')),
        ],
      ),
    );
  }
  
  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Text(value, style: const TextStyle(color: Color(0xFF40FF90), fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
