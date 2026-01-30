/// Voice Steal Statistics Panel
///
/// P1-09: Voice Steal Statistics UI
///
/// Shows which events get stolen most frequently, helping identify:
/// - Voice pool sizing issues
/// - Priority conflicts
/// - Events that need dedicated voice slots

import 'package:flutter/material.dart';
import '../../services/voice_steal_profiler.dart';

class VoiceStealPanel extends StatefulWidget {
  const VoiceStealPanel({super.key});

  @override
  State<VoiceStealPanel> createState() => _VoiceStealPanelState();
}

class _VoiceStealPanelState extends State<VoiceStealPanel> {
  /// Selected tab
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final profiler = VoiceStealProfiler.instance;

    return Column(
      children: [
        // Header
        _buildHeader(profiler),
        const Divider(height: 1),

        // Stats summary
        _buildStatsSummary(profiler),
        const Divider(height: 1),

        // Tabs
        _buildTabBar(),
        const Divider(height: 1),

        // Content
        Expanded(
          child: _buildTabContent(profiler),
        ),
      ],
    );
  }

  Widget _buildHeader(VoiceStealProfiler profiler) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.grey[900],
      child: Row(
        children: [
          const Icon(Icons.swap_horiz, size: 20, color: Colors.orange),
          const SizedBox(width: 8),
          const Text(
            'Voice Steal Statistics',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const Spacer(),

          // Enable/Disable
          Switch(
            value: profiler.enabled,
            onChanged: (value) {
              if (value) {
                profiler.enable();
              } else {
                profiler.disable();
              }
              setState(() {});
            },
            activeColor: Colors.green,
          ),
          const SizedBox(width: 8),
          Text(
            profiler.enabled ? 'Enabled' : 'Disabled',
            style: TextStyle(
              color: profiler.enabled ? Colors.green : Colors.grey,
              fontSize: 12,
            ),
          ),

          const SizedBox(width: 16),

          // Clear
          IconButton(
            icon: const Icon(Icons.clear_all, size: 20),
            onPressed: () {
              profiler.clear();
              setState(() {});
            },
            tooltip: 'Clear statistics',
          ),

          // Export
          PopupMenuButton<String>(
            icon: const Icon(Icons.download, size: 20),
            tooltip: 'Export',
            onSelected: (value) {
              if (value == 'json') {
                final json = profiler.exportToJson();
                debugPrint('[VoiceStealPanel] Exported JSON: $json');
              } else if (value == 'csv') {
                final csv = profiler.exportToCsv();
                debugPrint('[VoiceStealPanel] Exported CSV:\n$csv');
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'json', child: Text('Export JSON')),
              const PopupMenuItem(value: 'csv', child: Text('Export CSV')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSummary(VoiceStealProfiler profiler) {
    final topStolen = profiler.getTopStolenSources(1);
    final abnormal = profiler.getAbnormalStealSources();

    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.grey[850],
      child: Row(
        children: [
          _buildStatCard(
            'Total Steals',
            '${profiler.totalSteals}',
            Icons.swap_horiz,
            Colors.orange,
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            'Unique Sources',
            '${profiler.sourceStats.length}',
            Icons.category,
            Colors.blue,
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            'Most Stolen',
            topStolen.isNotEmpty ? topStolen.first.source : 'N/A',
            Icons.warning,
            Colors.red,
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            'Abnormal Steals',
            '${abnormal.fold<int>(0, (sum, s) => sum + s.abnormalSteals)}',
            Icons.error,
            abnormal.isNotEmpty ? Colors.red : Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.grey[850],
      child: Row(
        children: [
          _buildTab('Top Stolen', 0),
          _buildTab('Recent Steals', 1),
          _buildTab('Abnormal', 2),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int index) {
    final isSelected = _selectedTab == index;

    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedTab = index;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? Colors.blue : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.blue : Colors.grey[400],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent(VoiceStealProfiler profiler) {
    switch (_selectedTab) {
      case 0:
        return _buildTopStolenTab(profiler);
      case 1:
        return _buildRecentStealsTab(profiler);
      case 2:
        return _buildAbnormalTab(profiler);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTopStolenTab(VoiceStealProfiler profiler) {
    final topSources = profiler.getTopStolenSources(50);

    if (topSources.isEmpty) {
      return _buildEmptyState('No steal data yet');
    }

    return ListView.builder(
      itemCount: topSources.length,
      itemBuilder: (context, index) {
        final stats = topSources[index];
        return _buildSourceStatsItem(stats, index + 1);
      },
    );
  }

  Widget _buildSourceStatsItem(SourceStealStats stats, int rank) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey[800]!),
        ),
      ),
      child: Row(
        children: [
          // Rank
          SizedBox(
            width: 40,
            child: Text(
              '#$rank',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // Source name
          Expanded(
            flex: 3,
            child: Text(
              stats.source,
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Stolen count
          Expanded(
            child: Row(
              children: [
                const Icon(Icons.swap_horiz, size: 14, color: Colors.orange),
                const SizedBox(width: 4),
                Text(
                  '${stats.stolenCount}',
                  style: const TextStyle(fontSize: 13, color: Colors.orange),
                ),
              ],
            ),
          ),

          // Stealer count
          Expanded(
            child: Row(
              children: [
                const Icon(Icons.arrow_forward, size: 14, color: Colors.blue),
                const SizedBox(width: 4),
                Text(
                  '${stats.stealerCount}',
                  style: const TextStyle(fontSize: 13, color: Colors.blue),
                ),
              ],
            ),
          ),

          // Avg duration
          Expanded(
            child: Text(
              '${stats.avgPlayDurationMs.toStringAsFixed(1)}ms',
              style: const TextStyle(fontSize: 13),
            ),
          ),

          // Abnormal count
          if (stats.abnormalSteals > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '⚠️ ${stats.abnormalSteals}',
                style: const TextStyle(fontSize: 11, color: Colors.red),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecentStealsTab(VoiceStealProfiler profiler) {
    final recentSteals = profiler.getRecentSteals(100);

    if (recentSteals.isEmpty) {
      return _buildEmptyState('No steal events yet');
    }

    return ListView.builder(
      itemCount: recentSteals.length,
      itemBuilder: (context, index) {
        final event = recentSteals[index];
        return _buildStealEventItem(event);
      },
    );
  }

  Widget _buildStealEventItem(VoiceStealEvent event) {
    final isAbnormal = event.isAbnormal;
    final color = isAbnormal ? Colors.red : Colors.orange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: color, width: 3),
          bottom: BorderSide(color: Colors.grey[800]!),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Icon
              Icon(
                isAbnormal ? Icons.error : Icons.swap_horiz,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 8),

              // Stealer → Stolen
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 13),
                    children: [
                      TextSpan(
                        text: event.stealerSource,
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                      ),
                      const TextSpan(text: ' → ', style: TextStyle(color: Colors.grey)),
                      TextSpan(
                        text: event.stolenSource,
                        style: TextStyle(color: color),
                      ),
                    ],
                  ),
                ),
              ),

              // Play duration
              Text(
                '${event.playDurationMs.toStringAsFixed(1)}ms',
                style: TextStyle(fontSize: 12, color: Colors.grey[400]),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const SizedBox(width: 24),
              Text(
                'Priority: ${event.stealerPriority} → ${event.stolenPriority}',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              const Spacer(),
              Text(
                'Voice ${event.stolenVoiceId}',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAbnormalTab(VoiceStealProfiler profiler) {
    final abnormalSources = profiler.getAbnormalStealSources();

    if (abnormalSources.isEmpty) {
      return _buildEmptyState('No abnormal steals', subtitle: 'All steals respect priority order');
    }

    return ListView.builder(
      itemCount: abnormalSources.length,
      itemBuilder: (context, index) {
        final stats = abnormalSources[index];
        return _buildAbnormalSourceItem(stats);
      },
    );
  }

  Widget _buildAbnormalSourceItem(SourceStealStats stats) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          left: const BorderSide(color: Colors.red, width: 3),
          bottom: BorderSide(color: Colors.grey[800]!),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.error, size: 16, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              stats.source,
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${stats.abnormalSteals} abnormal steals',
              style: const TextStyle(fontSize: 12, color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message, {String? subtitle}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.hourglass_empty, size: 48, color: Colors.grey[600]),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: Colors.grey[500]),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ],
      ),
    );
  }
}
