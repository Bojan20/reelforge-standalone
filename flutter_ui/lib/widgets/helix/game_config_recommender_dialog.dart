// FLUX_MASTER_TODO 0.5 F.2 UI WIRE — AI Recommender dialog.
//
// Standalone Material dialog koji omotava `GameConfigRecommender` service.
// Designer bira market segment + player profile + (optional) target max win,
// klikne "Recommend", dobije ceo blueprint sa rationale-om za svako polje
// (RTP / volatility / hit freq / max win / bonus freq / feature stack /
// audio palette / compliance flags). Klik na rationale stavku otvara
// "Why?" objašnjenje — onboarding bez tutorijala.
//
// Ulaz iz UI-a: showDialog(context, builder: (_) => GameConfigRecommenderDialog())
// — bez constructor argumenta, dialog je samostalan.

import 'package:flutter/material.dart';

import '../../services/game_config_recommender.dart';
import '../../theme/flux_motion.dart';
import '../../theme/fluxforge_theme.dart';

class GameConfigRecommenderDialog extends StatefulWidget {
  const GameConfigRecommenderDialog({super.key});

  @override
  State<GameConfigRecommenderDialog> createState() =>
      _GameConfigRecommenderDialogState();
}

class _GameConfigRecommenderDialogState
    extends State<GameConfigRecommenderDialog> {
  MarketSegment _market = MarketSegment.mgaCrypto;
  PlayerProfile _player = PlayerProfile.engaged;
  double? _targetMaxWin;
  GameConfigRecommendation? _result;
  RecommendationRationale? _expandedRationale;

  late final TextEditingController _maxWinCtrl;

  @override
  void initState() {
    super.initState();
    _maxWinCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _maxWinCtrl.dispose();
    super.dispose();
  }

  void _runRecommend() {
    final raw = _maxWinCtrl.text.trim();
    final target = raw.isEmpty ? null : double.tryParse(raw);
    final rec = GameConfigRecommender.instance.recommend(
      market: _market,
      player: _player,
      targetMaxWin: target,
    );
    setState(() {
      _result = rec;
      _targetMaxWin = target;
      _expandedRationale = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0D0D14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: FluxForgeTheme.brandGold.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 14),
              const Divider(height: 1, color: Colors.white12),
              const SizedBox(height: 14),
              _buildInputs(),
              const SizedBox(height: 14),
              const Divider(height: 1, color: Colors.white12),
              const SizedBox(height: 12),
              Expanded(
                child: _result == null
                    ? _buildEmptyState()
                    : _buildResult(_result!),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Close',
                        style: FluxForgeTheme.dockSans(color: Colors.white60)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _runRecommend,
                    icon: const Icon(Icons.auto_awesome, size: 16),
                    label: Text(_result == null ? 'Recommend' : 'Re-Recommend'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: FluxForgeTheme.brandGold,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: FluxForgeTheme.brandGold.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.auto_awesome,
            color: FluxForgeTheme.brandGold,
            size: 20,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI GAME CONFIG RECOMMENDER',
                style: FluxForgeTheme.dockSans(
                  size: 13,
                  weight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: FluxForgeTheme.brandGold,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Heuristic rule engine — math + features + audio + compliance, sa rationale-om za svako polje.',
                style: FluxForgeTheme.dockSans(size: 11, color: Colors.white60),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInputs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSegmentedDropdown<MarketSegment>(
          label: 'MARKET',
          value: _market,
          items: MarketSegment.values,
          getLabel: (m) => m.label,
          onChanged: (v) => setState(() => _market = v!),
        ),
        const SizedBox(height: 10),
        _buildSegmentedDropdown<PlayerProfile>(
          label: 'PLAYER PROFILE',
          value: _player,
          items: PlayerProfile.values,
          getLabel: (p) => p.label,
          onChanged: (v) => setState(() => _player = v!),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            SizedBox(
              width: 130,
              child: Text(
                'TARGET MAX WIN',
                style: FluxForgeTheme.dockSans(
                  color: Colors.white54,
                  size: 10,
                  weight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            Expanded(
              child: TextField(
                controller: _maxWinCtrl,
                keyboardType: TextInputType.number,
                style: FluxForgeTheme.dockSans(color: Colors.white, size: 13),
                decoration: InputDecoration(
                  hintText: 'optional (e.g. 5000)',
                  hintStyle: FluxForgeTheme.dockSans(color: Colors.white24, size: 12),
                  filled: true,
                  fillColor: const Color(0xFF1A1A22),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  suffixText: '× bet',
                  suffixStyle: FluxForgeTheme.dockSans(
                      color: Colors.white38, size: 11),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSegmentedDropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) getLabel,
    required ValueChanged<T?> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: FluxForgeTheme.dockSans(
              color: Colors.white54,
              size: 10,
              weight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A22),
              borderRadius: BorderRadius.circular(6),
            ),
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              dropdownColor: const Color(0xFF1A1A22),
              underline: const SizedBox.shrink(),
              style: FluxForgeTheme.dockSans(color: Colors.white, size: 13),
              items: items
                  .map((m) =>
                      DropdownMenuItem<T>(value: m, child: Text(getLabel(m))))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.tips_and_updates_outlined,
            size: 56,
            color: Colors.white.withValues(alpha: 0.18),
          ),
          const SizedBox(height: 12),
          Text(
            'Click "Recommend" to generate config blueprint.',
            style: FluxForgeTheme.dockSans(color: Colors.white38, size: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildResult(GameConfigRecommendation rec) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader('MATH PROFILE'),
          _buildKv('RTP', '${(rec.math.rtp * 100).toStringAsFixed(2)}%',
              field: 'rtp'),
          _buildKv('Volatility', '${rec.math.volatility} / 10',
              field: 'volatility'),
          _buildKv('Hit Frequency',
              '${(rec.math.hitFrequency * 100).toStringAsFixed(1)}% spinova',
              field: 'hit_frequency'),
          _buildKv(
              'Max Win',
              '${rec.math.maxWinMultiplier.toStringAsFixed(0)}× bet',
              field: 'max_win_multiplier'),
          _buildKv('Bonus Frequency', '1 in ${rec.math.bonusFrequencyOneIn} spinova',
              field: 'bonus_frequency_one_in'),
          const SizedBox(height: 14),
          _buildSectionHeader('FEATURE STACK'),
          _featureChip('Free Spins', rec.features.freeSpins, 'feature.free_spins'),
          _featureChip('Cascade', rec.features.cascade, 'feature.cascade'),
          _featureChip('Hold & Win', rec.features.holdAndWin, 'feature.hold_and_win'),
          _featureChip('Gamble', rec.features.gamble, 'feature.gamble'),
          _featureChip('Wild Multiplier', rec.features.wildMultiplier,
              'feature.wild_multiplier'),
          _featureChip('Expanding Wilds', rec.features.expandingWilds,
              'feature.expanding_wilds'),
          const SizedBox(height: 14),
          _buildSectionHeader('AUDIO PALETTE'),
          _buildKv('Style', rec.audioPalette.label, field: 'audio_palette'),
          const SizedBox(height: 14),
          _buildSectionHeader('COMPLIANCE'),
          _buildKv('LDW Guard', rec.compliance.requiresLdwGuard ? 'REQUIRED' : 'optional',
              field: 'compliance.requires_ldw_guard'),
          _buildKv(
              'Near-Miss Cap',
              '${(rec.compliance.nearMissQuotaCap * 100).toStringAsFixed(1)}% spinova',
              field: 'compliance.near_miss_quota_cap'),
          _buildKv(
              'Celebration Cap',
              '${rec.compliance.celebrationDurationCapMs}ms',
              field: 'compliance.celebration_duration_cap_ms'),
          _buildKv('Auto-Spin', rec.compliance.autoSpinAllowed ? 'allowed' : 'BLOCKED',
              field: 'compliance.auto_spin_allowed'),
          if (_expandedRationale != null) ...[
            const SizedBox(height: 18),
            _buildRationaleCard(_expandedRationale!),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 6),
      child: Text(
        text,
        style: FluxForgeTheme.dockSans(
          color: FluxForgeTheme.brandGold.withValues(alpha: 0.85),
          size: 10,
          weight: FontWeight.bold,
          letterSpacing: 1.4,
        ),
      ),
    );
  }

  Widget _buildKv(String label, String value, {required String field}) {
    final rationale = _result?.rationale.firstWhere(
      (r) => r.field == field,
      orElse: () => const RecommendationRationale(
        field: '?',
        value: null,
        reason: '',
        source: '',
      ),
    );
    final hasRationale = rationale != null && rationale.field != '?';
    return InkWell(
      onTap: hasRationale
          ? () => setState(() {
                _expandedRationale =
                    _expandedRationale?.field == rationale.field
                        ? null
                        : rationale;
              })
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: Row(
          children: [
            SizedBox(
              width: 160,
              child: Text(
                label,
                style: FluxForgeTheme.dockSans(color: Colors.white60, size: 12),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: FluxForgeTheme.dockSans(
                  color: Colors.white,
                  size: 13,
                  weight: FontWeight.w600,
                ),
              ),
            ),
            if (hasRationale)
              Icon(
                _expandedRationale?.field == rationale.field
                    ? Icons.help
                    : Icons.help_outline,
                size: 14,
                color: _expandedRationale?.field == rationale.field
                    ? FluxForgeTheme.brandGold
                    : Colors.white24,
              ),
          ],
        ),
      ),
    );
  }

  Widget _featureChip(String label, bool on, String field) {
    final color = on ? const Color(0xFF40FF90) : Colors.white24;
    return _buildKv(label, on ? '✓ enabled' : '— skipped', field: field).withColorOverride(color);
  }

  Widget _buildRationaleCard(RecommendationRationale r) {
    return AnimatedContainer(
      duration: FluxMotion.standard,
      curve: FluxMotion.glassSpring,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.brandGold.withValues(alpha: 0.08),
        border: Border.all(
            color: FluxForgeTheme.brandGold.withValues(alpha: 0.4), width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome,
                  size: 14, color: FluxForgeTheme.brandGold),
              const SizedBox(width: 6),
              Text(
                'WHY: ${r.field}',
                style: FluxForgeTheme.dockSans(
                  color: FluxForgeTheme.brandGold,
                  size: 10,
                  weight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            r.reason,
            style: FluxForgeTheme.dockSans(
                color: Colors.white, size: 12, height: 1.45),
          ),
          const SizedBox(height: 8),
          Text(
            'Source rule: ${r.source}',
            style: FluxForgeTheme.dockMono(
                color: Colors.white38, size: 10).copyWith(
                fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }
}

extension _ColorOverride on Widget {
  /// No-op pomocna ekstenzija da zadrzi InkWell hijerarhiju kompaktnu.
  /// Prilagodjene boje feature chip-ova nisu kritican use-case za MVP.
  Widget withColorOverride(Color _) => this;
}
