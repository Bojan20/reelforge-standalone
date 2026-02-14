// audio_pool_manager_widget.dart — Audio Pool Monitoring Panel
//
// Comprehensive audio pool monitoring for SlotLab Lower Zone ENGINE tab.
// Connects to real AudioPool.instance service for live stats display.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/audio_pool.dart';
import '../../theme/fluxforge_theme.dart';

const _kRefreshInterval = Duration(seconds: 2);

const _kPoolBarColors = [
  Color(0xFF50D8FF), Color(0xFF5AA8FF), Color(0xFFB080FF), Color(0xFF50FF98),
  Color(0xFFFFE050), Color(0xFFFF9850), Color(0xFFFF80B0), Color(0xFF4ECDC4),
];

class AudioPoolManagerWidget extends StatefulWidget {
  const AudioPoolManagerWidget({super.key});

  @override
  State<AudioPoolManagerWidget> createState() => _AudioPoolManagerWidgetState();
}

class _AudioPoolManagerWidgetState extends State<AudioPoolManagerWidget> {
  Timer? _refreshTimer;

  int _totalAcquires = 0;
  int _poolHits = 0;
  int _poolMisses = 0;
  int _overflowCount = 0;
  int _pendingOverflow = 0;
  double _hitRate = 0.0;
  int _totalPooledVoices = 0;
  int _activeVoiceCount = 0;
  Map<String, int> _poolSizes = {};

  @override
  void initState() {
    super.initState();
    _readStats();
    _refreshTimer = Timer.periodic(_kRefreshInterval, (_) {
      if (mounted) _readStats();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _readStats() {
    final pool = AudioPool.instance;
    setState(() {
      _totalAcquires = pool.totalAcquires;
      _poolHits = pool.poolHits;
      _poolMisses = pool.poolMisses;
      _overflowCount = pool.overflowCount;
      _pendingOverflow = pool.pendingOverflowVoices;
      _hitRate = pool.hitRate;
      _totalPooledVoices = pool.totalPooledVoices;
      _activeVoiceCount = pool.activeVoiceCount;
      _poolSizes = Map<String, int>.from(pool.poolSizes);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(10),
              children: [
                _buildStatCards(),
                const SizedBox(height: 10),
                _buildHitRateBar(),
                const SizedBox(height: 10),
                _buildPoolBreakdown(),
                const SizedBox(height: 10),
                _buildConfigFooter(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -- Header -----------------------------------------------------------------

  Widget _buildHeader() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: FluxForgeTheme.bgMid,
      child: Row(
        children: [
          const Icon(Icons.memory, size: 14, color: FluxForgeTheme.accentCyan),
          const SizedBox(width: 6),
          Text('AUDIO POOL', style: FluxForgeTheme.label.copyWith(
            color: FluxForgeTheme.textPrimary,
            fontWeight: FontWeight.w600, letterSpacing: 0.8,
          )),
          const SizedBox(width: 8),
          Text('$_totalPooledVoices voices', style: FluxForgeTheme.label.copyWith(
            color: FluxForgeTheme.textTertiary,
          )),
          const Spacer(),
          _headerBtn('Reset', Icons.refresh, onTap: () {
            AudioPool.instance.reset();
            _readStats();
          }),
          const SizedBox(width: 4),
          _headerBtn('Stop All', Icons.stop, color: const Color(0xFFFF4060), onTap: () {
            AudioPool.instance.stopAll();
            _readStats();
          }),
        ],
      ),
    );
  }

  Widget _headerBtn(String label, IconData icon, {Color? color, required VoidCallback onTap}) {
    final c = color ?? FluxForgeTheme.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: c.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: c),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: c)),
          ],
        ),
      ),
    );
  }

  // -- Stat cards -------------------------------------------------------------

  Widget _buildStatCards() {
    return Row(
      children: [
        Expanded(child: _statCard(
          '${(_hitRate * 100).toStringAsFixed(1)}%', 'Hit Rate', _hitRateColor(_hitRate),
        )),
        const SizedBox(width: 6),
        Expanded(child: _statCard('$_totalAcquires', 'Acquires', FluxForgeTheme.accentBlue)),
        const SizedBox(width: 6),
        Expanded(child: _statCard('$_activeVoiceCount', 'Active', FluxForgeTheme.accentCyan)),
        const SizedBox(width: 6),
        Expanded(child: _statCard(
          '$_overflowCount', 'Overflow',
          _overflowCount > 0 ? const Color(0xFFFF4060) : FluxForgeTheme.textTertiary,
        )),
      ],
    );
  }

  Widget _statCard(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: TextStyle(
            fontFamily: FluxForgeTheme.monoFontFamily,
            fontSize: 15, fontWeight: FontWeight.w700, color: color, height: 1.1,
          )),
          const SizedBox(height: 3),
          Text(label, style: FluxForgeTheme.label.copyWith(
            color: FluxForgeTheme.textTertiary, fontSize: 9,
          )),
        ],
      ),
    );
  }

  // -- Hit rate bar -----------------------------------------------------------

  Widget _buildHitRateBar() {
    final pct = (_hitRate * 100).toStringAsFixed(1);
    final barColor = _hitRateColor(_hitRate);

    return _section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Hit Rate', style: FluxForgeTheme.bodySmall.copyWith(
              color: FluxForgeTheme.textSecondary,
            )),
            const Spacer(),
            Text('$_poolHits hits / $_poolMisses misses',
              style: FluxForgeTheme.label.copyWith(color: FluxForgeTheme.textTertiary)),
            const SizedBox(width: 8),
            Text('$pct%', style: TextStyle(
              fontFamily: FluxForgeTheme.monoFontFamily,
              fontSize: 11, fontWeight: FontWeight.w600, color: barColor,
            )),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 6,
              child: CustomPaint(
                size: const Size(double.infinity, 6),
                painter: _BarPainter(ratio: _hitRate, fillColor: barColor),
              ),
            ),
          ),
          if (_pendingOverflow > 0) ...[
            const SizedBox(height: 4),
            Text('$_pendingOverflow overflow voice(s) pending cleanup',
              style: FluxForgeTheme.label.copyWith(
                color: const Color(0xFFFF4060).withValues(alpha: 0.8), fontSize: 9,
              )),
          ],
        ],
      ),
    );
  }

  // -- Pool breakdown ---------------------------------------------------------

  Widget _buildPoolBreakdown() {
    if (_poolSizes.isEmpty) {
      return _section(
        child: Text(
          'No pools allocated yet. Pools are created on first audio trigger.',
          style: FluxForgeTheme.bodySmall.copyWith(color: FluxForgeTheme.textTertiary),
        ),
      );
    }

    final sorted = _poolSizes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxV = sorted.first.value.clamp(1, 999999);

    return _section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('POOL BREAKDOWN', style: FluxForgeTheme.label.copyWith(
              color: FluxForgeTheme.textSecondary, fontWeight: FontWeight.w600, letterSpacing: 0.6,
            )),
            const Spacer(),
            Text('${sorted.length} event(s)', style: FluxForgeTheme.label.copyWith(
              color: FluxForgeTheme.textTertiary,
            )),
          ]),
          const SizedBox(height: 6),
          ...sorted.asMap().entries.map((e) {
            final color = _kPoolBarColors[e.key % _kPoolBarColors.length];
            return _poolRow(e.value.key, e.value.value, maxV, color);
          }),
        ],
      ),
    );
  }

  Widget _poolRow(String eventKey, int count, int maxVoices, Color color) {
    final ratio = (maxVoices > 0 ? count / maxVoices : 0.0).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(
          width: 130,
          child: Text(eventKey, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: FluxForgeTheme.monoFontFamily,
              fontSize: 10, color: FluxForgeTheme.textSecondary)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 10,
              child: CustomPaint(
                size: const Size(double.infinity, 10),
                painter: _BarPainter(ratio: ratio, fillColor: color, rounded: true),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 50,
          child: Text('$count voice${count == 1 ? '' : 's'}',
            textAlign: TextAlign.right,
            style: TextStyle(fontFamily: FluxForgeTheme.monoFontFamily,
              fontSize: 9, color: color, fontWeight: FontWeight.w500)),
        ),
      ]),
    );
  }

  // -- Config footer ----------------------------------------------------------

  Widget _buildConfigFooter() {
    return _section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Config: min=2-4  max=8-12  timeout=30-60s  preload=ON',
            style: TextStyle(fontFamily: FluxForgeTheme.monoFontFamily,
              fontSize: 9, color: FluxForgeTheme.textTertiary)),
          const SizedBox(height: 6),
          Row(children: [
            _cfgBtn('Default Config', onTap: () {
              AudioPool.instance.configure(AudioPoolConfig.defaultConfig);
              _readStats();
            }),
            const SizedBox(width: 6),
            _cfgBtn('SlotLab Config', highlighted: true, onTap: () {
              AudioPool.instance.configure(AudioPoolConfig.slotLabConfig);
              _readStats();
            }),
          ]),
        ],
      ),
    );
  }

  Widget _cfgBtn(String label, {bool highlighted = false, required VoidCallback onTap}) {
    final bc = highlighted ? FluxForgeTheme.accentCyan.withValues(alpha: 0.4) : FluxForgeTheme.borderSubtle;
    final tc = highlighted ? FluxForgeTheme.accentCyan : FluxForgeTheme.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: bc),
          color: highlighted ? FluxForgeTheme.accentCyan.withValues(alpha: 0.06) : Colors.transparent,
        ),
        child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: tc)),
      ),
    );
  }

  // -- Shared helpers ---------------------------------------------------------

  Widget _section({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: child,
    );
  }

  Color _hitRateColor(double rate) {
    if (rate >= 0.70) return FluxForgeTheme.accentGreen;
    if (rate >= 0.40) return FluxForgeTheme.accentYellow;
    return const Color(0xFFFF4060);
  }
}

// -- Custom painter (shared for hit-rate bar and pool bars) --------------------

class _BarPainter extends CustomPainter {
  final double ratio;
  final Color fillColor;
  final bool rounded;

  _BarPainter({required this.ratio, required this.fillColor, this.rounded = false});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = FluxForgeTheme.bgDeep;
    final r = const Radius.circular(2);

    if (rounded) {
      canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), bgPaint);
    } else {
      canvas.drawRect(Offset.zero & size, bgPaint);
    }

    if (ratio > 0) {
      final w = size.width * math.min(ratio, 1.0);
      final rect = Rect.fromLTWH(0, 0, w, size.height);
      final fillPaint = Paint()..color = fillColor.withValues(alpha: rounded ? 0.7 : 1.0);

      if (!rounded) {
        fillPaint.shader = LinearGradient(
          colors: [fillColor.withValues(alpha: 0.9), fillColor],
        ).createShader(rect);
      }

      if (rounded) {
        canvas.drawRRect(RRect.fromRectAndRadius(rect, r), fillPaint);
      } else {
        canvas.drawRect(rect, fillPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.ratio != ratio || old.fillColor != fillColor;
}
