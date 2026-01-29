/// Batch Distribution Results Dialog
///
/// Shows results after folder drop with auto-matching:
/// - Summary: Total files, Matched, Unmatched, Success rate
/// - Matched tab: file → stage mappings with confidence scores
/// - Unmatched tab: files with reasons why they didn't match
/// - Manual assign option for unmatched files
///
/// Task: SL-LP-P0.3
library;

import 'package:flutter/material.dart';
import '../../services/stage_group_service.dart';
import '../../theme/fluxforge_theme.dart';

/// Batch Distribution Results Dialog
class BatchDistributionDialog extends StatelessWidget {
  final List<StageMatch> matched;
  final List<UnmatchedFile> unmatched;

  const BatchDistributionDialog({
    super.key,
    required this.matched,
    required this.unmatched,
  });

  /// Show dialog with batch import results
  static Future<void> show(
    BuildContext context, {
    required List<StageMatch> matched,
    required List<UnmatchedFile> unmatched,
  }) {
    return showDialog(
      context: context,
      builder: (_) => BatchDistributionDialog(
        matched: matched,
        unmatched: unmatched,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = matched.length + unmatched.length;
    final successRate = total > 0 ? ((matched.length / total) * 100).toInt() : 0;

    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A22),
      title: Row(
        children: [
          Icon(Icons.folder_open, color: FluxForgeTheme.accentBlue, size: 20),
          const SizedBox(width: 8),
          const Text(
            'Batch Import Results',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Summary section
            _buildSummary(total, successRate),
            const SizedBox(height: 16),
            // Tabs: Matched | Unmatched
            Expanded(
              child: DefaultTabController(
                length: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TabBar(
                      indicatorColor: FluxForgeTheme.accentBlue,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white54,
                      tabs: [
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle, size: 16, color: FluxForgeTheme.accentGreen),
                              const SizedBox(width: 6),
                              Text('Matched (${matched.length})'),
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.warning, size: 16, color: FluxForgeTheme.accentOrange),
                              const SizedBox(width: 6),
                              Text('Unmatched (${unmatched.length})'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildMatchedTab(),
                          _buildUnmatchedTab(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (unmatched.isNotEmpty)
          TextButton.icon(
            icon: Icon(Icons.edit, size: 16, color: FluxForgeTheme.accentOrange),
            label: const Text('Manual Assign Unmatched'),
            onPressed: () {
              // TODO: Open manual assignment dialog
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Manual assignment: ${unmatched.length} files'),
                  backgroundColor: FluxForgeTheme.accentOrange,
                ),
              );
            },
          ),
        TextButton(
          child: const Text('Close'),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _buildSummary(int total, int successRate) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.accentBlue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: FluxForgeTheme.accentBlue.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStat('Total Files', total.toString(), Colors.white),
          _buildStat('Matched', matched.length.toString(), FluxForgeTheme.accentGreen),
          _buildStat('Unmatched', unmatched.length.toString(), FluxForgeTheme.accentOrange),
          _buildStat(
            'Success Rate',
            '$successRate%',
            successRate == 100 ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentOrange,
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Colors.white54,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildMatchedTab() {
    if (matched.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 48, color: Colors.white24),
            const SizedBox(height: 12),
            Text(
              'No files matched',
              style: TextStyle(fontSize: 14, color: Colors.white54),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: matched.length,
      itemBuilder: (context, index) {
        final match = matched[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF16161C),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: FluxForgeTheme.accentGreen.withOpacity(0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle, size: 16, color: FluxForgeTheme.accentGreen),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      match.audioPath.split('/').last,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.arrow_forward, size: 10, color: Colors.white38),
                        const SizedBox(width: 4),
                        Text(
                          match.stage,
                          style: TextStyle(
                            fontSize: 10,
                            color: FluxForgeTheme.accentGreen,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Confidence score
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentGreen.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${match.confidence}%',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: FluxForgeTheme.accentGreen,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUnmatchedTab() {
    if (unmatched.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.celebration, size: 48, color: FluxForgeTheme.accentGreen.withOpacity(0.5)),
            const SizedBox(height: 12),
            Text(
              'All files matched!',
              style: TextStyle(
                fontSize: 14,
                color: FluxForgeTheme.accentGreen,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '100% success rate',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: unmatched.length,
      itemBuilder: (context, index) {
        final file = unmatched[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF16161C),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: FluxForgeTheme.accentOrange.withOpacity(0.3),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning, size: 16, color: FluxForgeTheme.accentOrange),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.audioPath.split('/').last,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      file.suggestions.isEmpty
                          ? 'No keywords matched'
                          : 'Suggestions: ${file.suggestions.take(2).map((s) => s.stage).join(', ')}',
                      style: TextStyle(
                        fontSize: 9,
                        color: FluxForgeTheme.accentOrange.withOpacity(0.8),
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
