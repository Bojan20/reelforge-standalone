import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../providers/slot_lab/ail_provider.dart';

/// UCP-6: AIL Panel Integration
///
/// Displays ranked recommendations with impact score and apply/confirm actions.
class AilPanelZone extends StatefulWidget {
  const AilPanelZone({super.key});

  @override
  State<AilPanelZone> createState() => _AilPanelZoneState();
}

class _AilPanelZoneState extends State<AilPanelZone> {
  AilProvider? _provider;

  @override
  void initState() {
    super.initState();
    try {
      _provider = GetIt.instance<AilProvider>();
      _provider?.addListener(_onUpdate);
    } catch (_) {}
  }

  @override
  void dispose() {
    _provider?.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = _provider;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          const SizedBox(height: 4),
          if (p == null || !p.hasResults)
            _buildEmpty()
          else ...[
            _buildScoreRow(),
            const SizedBox(height: 4),
            _buildRecommendations(),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.psychology, size: 12, color: Color(0xFFFFAB40)),
        const SizedBox(width: 4),
        Text(
          'AIL Recommendations',
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        if (_provider != null && !_provider!.isRunning)
          GestureDetector(
            onTap: () => _provider?.runAnalysis(),
            child: Text(
              'Run',
              style: TextStyle(color: const Color(0xFFFFAB40).withOpacity(0.7), fontSize: 8),
            ),
          ),
      ],
    );
  }

  Widget _buildEmpty() {
    return Text(
      'Run AIL analysis to see recommendations',
      style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 8),
    );
  }

  Widget _buildScoreRow() {
    final p = _provider!;
    return Row(
      children: [
        Text(
          '${p.score.toStringAsFixed(0)}',
          style: TextStyle(color: _statusColor(), fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 4),
        Text(
          p.status.displayName,
          style: TextStyle(color: _statusColor(), fontSize: 9, fontWeight: FontWeight.w500),
        ),
        const Spacer(),
        _countChip('${p.criticalCount}C', const Color(0xFFEF5350)),
        const SizedBox(width: 2),
        _countChip('${p.warningCount}W', const Color(0xFFFFB74D)),
        const SizedBox(width: 2),
        _countChip('${p.infoCount}I', const Color(0xFF42A5F5)),
      ],
    );
  }

  Widget _countChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 7, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildRecommendations() {
    final recs = _provider!.recommendations;
    if (recs.isEmpty) {
      return Text(
        'No recommendations',
        style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 8),
      );
    }

    return Column(
      children: [
        for (final rec in recs.take(5))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              children: [
                Container(
                  width: 5, height: 5,
                  decoration: BoxDecoration(
                    color: _recColor(rec.level),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    rec.title,
                    style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 8),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${rec.impactScore.toStringAsFixed(0)}',
                  style: TextStyle(color: _recColor(rec.level), fontSize: 7),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Color _statusColor() {
    final p = _provider;
    if (p == null) return Colors.white.withOpacity(0.3);
    switch (p.status) {
      case AilStatusLevel.excellent: return const Color(0xFF66BB6A);
      case AilStatusLevel.good: return const Color(0xFF42A5F5);
      case AilStatusLevel.fair: return const Color(0xFFFFB74D);
      case AilStatusLevel.poor: return const Color(0xFFFF8A65);
      case AilStatusLevel.critical: return const Color(0xFFEF5350);
    }
  }

  Color _recColor(AilRecommendationLevel level) {
    switch (level) {
      case AilRecommendationLevel.critical: return const Color(0xFFEF5350);
      case AilRecommendationLevel.warning: return const Color(0xFFFFB74D);
      case AilRecommendationLevel.info: return const Color(0xFF42A5F5);
    }
  }
}
