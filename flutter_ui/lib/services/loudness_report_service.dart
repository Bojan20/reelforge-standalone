/// Loudness Report Service — HTML Interactive Report Generator
///
/// #22: Generates HTML reports with:
/// - Integrated LUFS, Short-term graph, True Peak, LRA
/// - Clipping detection with timestamps
/// - Dry run (analysis without rendering)
/// - Multiple target compliance checks
library;

import 'dart:math' as math;
import 'package:flutter/foundation.dart';

import 'loudness_analysis_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// REPORT DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════════

/// A single short-term LUFS reading with timestamp
class ShortTermReading {
  final double timeSec;
  final double lufs;

  const ShortTermReading(this.timeSec, this.lufs);
}

/// A detected clipping event
class ClipEvent {
  final double timeSec;
  final double peakDb;
  final String channel; // 'L', 'R', 'Both'

  const ClipEvent(this.timeSec, this.peakDb, this.channel);
}

/// Complete report data
class LoudnessReportData {
  final String projectName;
  final DateTime timestamp;
  final Duration duration;
  final LoudnessResult analysis;
  final List<ShortTermReading> shortTermHistory;
  final List<ClipEvent> clipEvents;
  final Map<LoudnessTarget, LoudnessCompliance> complianceMap;
  final int sampleRate;
  final int channels;
  final int totalSamples;

  const LoudnessReportData({
    required this.projectName,
    required this.timestamp,
    required this.duration,
    required this.analysis,
    required this.shortTermHistory,
    required this.clipEvents,
    required this.complianceMap,
    required this.sampleRate,
    required this.channels,
    required this.totalSamples,
  });

  bool get hasClipping => clipEvents.isNotEmpty;
  int get clipCount => clipEvents.length;

  String get durationFormatted {
    final m = duration.inMinutes;
    final s = duration.inSeconds % 60;
    final ms = duration.inMilliseconds % 1000;
    return '$m:${s.toString().padLeft(2, '0')}.${(ms ~/ 10).toString().padLeft(2, '0')}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LOUDNESS REPORT SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

/// Service that performs dry-run analysis and generates HTML reports
class LoudnessReportService extends ChangeNotifier {
  LoudnessReportService._();
  static final LoudnessReportService instance = LoudnessReportService._();

  // State
  bool _isAnalyzing = false;
  double _progress = 0.0;
  LoudnessReportData? _lastReport;
  String? _lastHtml;

  bool get isAnalyzing => _isAnalyzing;
  double get progress => _progress;
  LoudnessReportData? get lastReport => _lastReport;
  String? get lastHtml => _lastHtml;

  /// Perform dry-run analysis (no rendering) and generate report data
  Future<LoudnessReportData?> analyzeDryRun({
    required List<double> samples,
    required int sampleRate,
    int channels = 2,
    String projectName = 'Untitled',
  }) async {
    if (_isAnalyzing || samples.isEmpty) return null;

    _isAnalyzing = true;
    _progress = 0.0;
    notifyListeners();

    try {
      final shortTermHistory = <ShortTermReading>[];
      final clipEvents = <ClipEvent>[];

      // K-weighting filter states
      final kWeightL = [_BiquadState(), _BiquadState()];
      final kWeightR = [_BiquadState(), _BiquadState()];

      // Integration state
      final momentaryBuffer = <double>[];
      final shortTermBuffer = <double>[];
      final integratedBuffer = <double>[];
      double maxSamplePeak = 0.0;
      double maxTruePeak = 0.0;
      double maxShortTerm = -70.0;
      double minShortTerm = 0.0;
      double lastSampleL = 0.0;
      double lastSampleR = 0.0;

      final totalSamples = samples.length;
      final samplesPerFrame = channels;
      final momentarySamples = (sampleRate * 0.4).round();
      int sampleIndex = 0;

      // Process all samples (check _isAnalyzing for cancellation)
      for (int i = 0; i < totalSamples && _isAnalyzing; i += samplesPerFrame) {
        final l = samples[i];
        final r = (i + 1 < totalSamples && channels == 2) ? samples[i + 1] : l;

        // Track sample peak
        final absL = l.abs();
        final absR = r.abs();
        maxSamplePeak = math.max(maxSamplePeak, math.max(absL, absR));

        // Clipping detection (> -0.1 dBFS ≈ 0.9886)
        if (absL > 0.9886 || absR > 0.9886) {
          final timeSec = sampleIndex / sampleRate;
          final peakLin = math.max(absL, absR);
          final peakDb = 20.0 * math.log(peakLin) / math.ln10;
          final channel = (absL > 0.9886 && absR > 0.9886)
              ? 'Both'
              : absL > 0.9886
                  ? 'L'
                  : 'R';
          // Deduplicate: only add if >50ms from last clip
          if (clipEvents.isEmpty || (timeSec - clipEvents.last.timeSec) > 0.05) {
            clipEvents.add(ClipEvent(timeSec, peakDb, channel));
          }
        }

        // True peak (2x oversampling)
        final truePeakL = math.max(absL, ((l + lastSampleL) / 2.0).abs());
        final truePeakR = math.max(absR, ((r + lastSampleR) / 2.0).abs());
        maxTruePeak = math.max(maxTruePeak, math.max(truePeakL, truePeakR));
        lastSampleL = l;
        lastSampleR = r;

        // K-weighting
        final lFiltered = _applyKWeighting(l, kWeightL, sampleRate);
        final rFiltered = _applyKWeighting(r, kWeightR, sampleRate);
        final ms = (lFiltered * lFiltered + rFiltered * rFiltered) / 2.0;
        momentaryBuffer.add(ms);

        sampleIndex++;

        // Momentary window (400ms)
        if (momentaryBuffer.length >= momentarySamples) {
          final momentaryMs = momentaryBuffer
              .skip(momentaryBuffer.length - momentarySamples)
              .fold(0.0, (a, b) => a + b) / momentarySamples;

          shortTermBuffer.add(momentaryMs);

          if (momentaryBuffer.length > momentarySamples * 2) {
            momentaryBuffer.removeRange(0, momentaryBuffer.length - momentarySamples);
          }
        }

        // Short-term window (3s ≈ 8 momentary windows)
        if (shortTermBuffer.length >= 8) {
          final stMs = shortTermBuffer
              .skip(shortTermBuffer.length - 8)
              .fold(0.0, (a, b) => a + b) / 8;
          final stLufs = _msToLufs(stMs);

          if (stLufs > -70.0) {
            maxShortTerm = math.max(maxShortTerm, stLufs);
            if (minShortTerm == 0.0) {
              minShortTerm = stLufs;
            } else {
              minShortTerm = math.min(minShortTerm, stLufs);
            }
          }

          // Record for graph
          final timeSec = sampleIndex / sampleRate;
          shortTermHistory.add(ShortTermReading(timeSec, stLufs));

          if (stMs > 0.0) {
            integratedBuffer.add(stMs);
          }

          if (shortTermBuffer.length > 16) {
            shortTermBuffer.removeRange(0, shortTermBuffer.length - 8);
          }
        }

        // Progress update
        if (i % (sampleRate * channels) == 0) {
          _progress = i / totalSamples;
          notifyListeners();
          await Future<void>.delayed(Duration.zero);
        }
      }

      // Check if cancelled
      if (!_isAnalyzing) {
        _progress = 0.0;
        notifyListeners();
        return null;
      }

      // Calculate integrated LUFS with gating
      final integrated = _calculateIntegratedLufs(integratedBuffer);

      // Calculate LRA
      double lra = 0.0;
      if (shortTermBuffer.length > 10) {
        final sorted = shortTermBuffer.map(_msToLufs).where((l) => l > -70.0).toList()..sort();
        if (sorted.length > 10) {
          final p10 = sorted[(sorted.length * 0.1).floor()];
          final p95 = sorted[(sorted.length * 0.95).floor()];
          lra = p95 - p10;
        }
      }

      final duration = Duration(
        milliseconds: (totalSamples / channels / sampleRate * 1000).round(),
      );

      final analysisResult = LoudnessResult(
        integratedLufs: integrated,
        shortTermLufs: shortTermHistory.isNotEmpty ? shortTermHistory.last.lufs : -70.0,
        momentaryLufs: -70.0,
        truePeak: _linearToDb(maxTruePeak),
        samplePeak: _linearToDb(maxSamplePeak),
        loudnessRange: lra,
        maxShortTerm: maxShortTerm,
        minShortTerm: minShortTerm,
        duration: duration,
        isValid: true,
      );

      // Build compliance map for all targets
      final complianceMap = <LoudnessTarget, LoudnessCompliance>{};
      for (final target in LoudnessTarget.values) {
        if (target == LoudnessTarget.custom) continue;
        complianceMap[target] = target.checkCompliance(analysisResult);
      }

      final report = LoudnessReportData(
        projectName: projectName,
        timestamp: DateTime.now(),
        duration: duration,
        analysis: analysisResult,
        shortTermHistory: shortTermHistory,
        clipEvents: clipEvents,
        complianceMap: complianceMap,
        sampleRate: sampleRate,
        channels: channels,
        totalSamples: totalSamples,
      );

      _lastReport = report;
      _lastHtml = generateHtml(report);
      _isAnalyzing = false;
      _progress = 1.0;
      notifyListeners();

      return report;
    } catch (e) {
      _isAnalyzing = false;
      _progress = 0.0;
      notifyListeners();
      return null;
    }
  }

  /// Cancel running analysis
  void cancelAnalysis() {
    _isAnalyzing = false;
    _progress = 0.0;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HTML REPORT GENERATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Generate interactive HTML report
  String generateHtml(LoudnessReportData data) {
    final buf = StringBuffer();

    buf.writeln('<!DOCTYPE html>');
    buf.writeln('<html lang="en">');
    buf.writeln('<head>');
    buf.writeln('<meta charset="UTF-8">');
    buf.writeln('<meta name="viewport" content="width=device-width, initial-scale=1.0">');
    buf.writeln('<title>Loudness Report — ${_escapeHtml(data.projectName)}</title>');
    buf.writeln('<style>');
    buf.writeln(_cssStyles());
    buf.writeln('</style>');
    buf.writeln('</head>');
    buf.writeln('<body>');

    // Header
    buf.writeln('<div class="header">');
    buf.writeln('<h1>LOUDNESS REPORT</h1>');
    buf.writeln('<div class="subtitle">${_escapeHtml(data.projectName)}</div>');
    buf.writeln('<div class="timestamp">${data.timestamp.toIso8601String().substring(0, 19)}</div>');
    buf.writeln('</div>');

    // Summary cards
    buf.writeln('<div class="summary-grid">');
    _writeCard(buf, 'Integrated LUFS', LoudnessResult.formatLufs(data.analysis.integratedLufs),
        _lufsClass(data.analysis.integratedLufs));
    _writeCard(buf, 'True Peak', LoudnessResult.formatPeak(data.analysis.truePeak),
        data.analysis.truePeak > -1.0 ? 'warn' : 'ok');
    _writeCard(buf, 'Loudness Range', LoudnessResult.formatLra(data.analysis.loudnessRange), 'neutral');
    _writeCard(buf, 'Sample Peak', '${data.analysis.samplePeak.toStringAsFixed(1)} dBFS',
        data.analysis.samplePeak > -0.1 ? 'clip' : 'ok');
    _writeCard(buf, 'Duration', data.durationFormatted, 'neutral');
    _writeCard(buf, 'Clipping', data.hasClipping ? '${data.clipCount} events' : 'None',
        data.hasClipping ? 'clip' : 'ok');
    buf.writeln('</div>');

    // Short-term LUFS graph
    buf.writeln('<div class="section">');
    buf.writeln('<h2>Short-term LUFS Over Time</h2>');
    buf.writeln('<div class="graph-container">');
    buf.writeln('<canvas id="stGraph" width="900" height="250"></canvas>');
    buf.writeln('</div>');
    buf.writeln('</div>');

    // Compliance table
    buf.writeln('<div class="section">');
    buf.writeln('<h2>Target Compliance</h2>');
    buf.writeln('<table class="compliance-table">');
    buf.writeln('<tr><th>Target</th><th>LUFS</th><th>Peak Limit</th><th>LUFS Status</th><th>Peak Status</th><th>Result</th></tr>');
    for (final entry in data.complianceMap.entries) {
      final t = entry.key;
      final c = entry.value;
      buf.writeln('<tr class="${c.isCompliant ? 'row-ok' : 'row-fail'}">');
      buf.writeln('<td>${t.name}</td>');
      buf.writeln('<td>${t.targetLufs.toStringAsFixed(1)} LUFS</td>');
      buf.writeln('<td>${t.truePeakLimit.toStringAsFixed(1)} dBTP</td>');
      buf.writeln('<td>${c.lufsStatus}</td>');
      buf.writeln('<td>${c.peakStatus}</td>');
      buf.writeln('<td class="${c.isCompliant ? 'pass' : 'fail'}">${c.isCompliant ? 'PASS' : 'FAIL'}</td>');
      buf.writeln('</tr>');
    }
    buf.writeln('</table>');
    buf.writeln('</div>');

    // Clipping events
    if (data.hasClipping) {
      buf.writeln('<div class="section">');
      buf.writeln('<h2>Clipping Events (${data.clipCount})</h2>');
      buf.writeln('<table class="clip-table">');
      buf.writeln('<tr><th>#</th><th>Time</th><th>Peak</th><th>Channel</th></tr>');
      final maxShow = math.min(data.clipCount, 100);
      for (int i = 0; i < maxShow; i++) {
        final e = data.clipEvents[i];
        buf.writeln('<tr>');
        buf.writeln('<td>${i + 1}</td>');
        buf.writeln('<td>${_formatTime(e.timeSec)}</td>');
        buf.writeln('<td>${e.peakDb.toStringAsFixed(1)} dB</td>');
        buf.writeln('<td>${e.channel}</td>');
        buf.writeln('</tr>');
      }
      if (data.clipCount > 100) {
        buf.writeln('<tr><td colspan="4" class="more">... and ${data.clipCount - 100} more events</td></tr>');
      }
      buf.writeln('</table>');
      buf.writeln('</div>');
    }

    // Technical details
    buf.writeln('<div class="section">');
    buf.writeln('<h2>Technical Details</h2>');
    buf.writeln('<div class="details-grid">');
    _writeDetail(buf, 'Sample Rate', '${data.sampleRate} Hz');
    _writeDetail(buf, 'Channels', '${data.channels}');
    _writeDetail(buf, 'Total Samples', '${data.totalSamples}');
    _writeDetail(buf, 'Max Short-term', LoudnessResult.formatLufs(data.analysis.maxShortTerm));
    _writeDetail(buf, 'Min Short-term', LoudnessResult.formatLufs(data.analysis.minShortTerm));
    _writeDetail(buf, 'Algorithm', 'ITU-R BS.1770-4');
    buf.writeln('</div>');
    buf.writeln('</div>');

    // Footer
    buf.writeln('<div class="footer">');
    buf.writeln('Generated by FluxForge Studio');
    buf.writeln('</div>');

    // JavaScript for interactive graph
    buf.writeln('<script>');
    buf.writeln(_graphScript(data));
    buf.writeln('</script>');

    buf.writeln('</body>');
    buf.writeln('</html>');

    return buf.toString();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CSS
  // ═══════════════════════════════════════════════════════════════════════════

  String _cssStyles() {
    return '''
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: -apple-system, BlinkMacSystemFont, 'SF Pro', sans-serif; background: #1a1a2e; color: #e0e0e0; padding: 24px; }
.header { text-align: center; margin-bottom: 32px; padding: 24px; background: linear-gradient(135deg, #16213e, #0f3460); border-radius: 12px; }
.header h1 { font-size: 28px; letter-spacing: 4px; color: #00d2ff; margin-bottom: 8px; }
.subtitle { font-size: 16px; color: #a0c4ff; }
.timestamp { font-size: 12px; color: #607080; margin-top: 8px; }
.summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 12px; margin-bottom: 24px; }
.card { padding: 16px; border-radius: 8px; background: #16213e; border: 1px solid #1a3a5c; text-align: center; }
.card .label { font-size: 10px; text-transform: uppercase; letter-spacing: 1px; color: #607080; margin-bottom: 8px; }
.card .value { font-size: 22px; font-weight: 700; font-family: 'SF Mono', monospace; }
.card.ok .value { color: #4ade80; }
.card.warn .value { color: #fbbf24; }
.card.clip .value { color: #f87171; }
.card.neutral .value { color: #60a5fa; }
.section { background: #16213e; border-radius: 8px; padding: 20px; margin-bottom: 16px; border: 1px solid #1a3a5c; }
.section h2 { font-size: 14px; letter-spacing: 2px; color: #00d2ff; margin-bottom: 16px; text-transform: uppercase; }
.graph-container { position: relative; width: 100%; overflow-x: auto; }
canvas { background: #0f1629; border-radius: 4px; width: 100%; }
table { width: 100%; border-collapse: collapse; font-size: 12px; }
th { text-align: left; padding: 8px 12px; background: #0f1629; color: #60a5fa; font-weight: 600; border-bottom: 2px solid #1a3a5c; }
td { padding: 6px 12px; border-bottom: 1px solid #1a2a3c; }
.row-ok td { color: #e0e0e0; }
.row-fail td { color: #fca5a5; }
.pass { color: #4ade80; font-weight: 700; }
.fail { color: #f87171; font-weight: 700; }
.more { text-align: center; color: #607080; font-style: italic; }
.details-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 8px; }
.detail { display: flex; justify-content: space-between; padding: 6px 0; border-bottom: 1px solid #1a2a3c; }
.detail .key { color: #607080; }
.detail .val { color: #e0e0e0; font-family: 'SF Mono', monospace; }
.footer { text-align: center; color: #404060; font-size: 11px; margin-top: 32px; padding: 16px; }
.tooltip { position: absolute; background: #0f1629; border: 1px solid #00d2ff; border-radius: 4px; padding: 8px; font-size: 11px; pointer-events: none; display: none; z-index: 10; color: #e0e0e0; }
''';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // JAVASCRIPT GRAPH
  // ═══════════════════════════════════════════════════════════════════════════

  String _graphScript(LoudnessReportData data) {
    // Serialize short-term data as JSON arrays
    final times = data.shortTermHistory.map((r) => r.timeSec.toStringAsFixed(2)).join(',');
    final values = data.shortTermHistory.map((r) => r.lufs.toStringAsFixed(1)).join(',');

    return '''
(function() {
  const times = [$times];
  const values = [$values];
  const canvas = document.getElementById('stGraph');
  if (!canvas || times.length === 0) return;
  const ctx = canvas.getContext('2d');
  const dpr = window.devicePixelRatio || 1;
  const rect = canvas.getBoundingClientRect();
  canvas.width = rect.width * dpr;
  canvas.height = rect.height * dpr;
  ctx.scale(dpr, dpr);
  const W = rect.width, H = rect.height;
  const pad = { l: 50, r: 20, t: 10, b: 30 };
  const gW = W - pad.l - pad.r;
  const gH = H - pad.t - pad.b;
  const maxT = times[times.length - 1];
  const minL = -50, maxL = 0;

  function tX(t) { return pad.l + (t / maxT) * gW; }
  function lY(l) { return pad.t + ((maxL - l) / (maxL - minL)) * gH; }

  // Grid
  ctx.strokeStyle = '#1a3a5c';
  ctx.lineWidth = 0.5;
  for (let l = minL; l <= maxL; l += 10) {
    const y = lY(l);
    ctx.beginPath(); ctx.moveTo(pad.l, y); ctx.lineTo(W - pad.r, y); ctx.stroke();
    ctx.fillStyle = '#607080'; ctx.font = '10px monospace';
    ctx.textAlign = 'right'; ctx.fillText(l + ' LUFS', pad.l - 4, y + 3);
  }
  // Time axis
  const step = maxT > 60 ? 30 : maxT > 10 ? 5 : 1;
  for (let t = 0; t <= maxT; t += step) {
    const x = tX(t);
    ctx.beginPath(); ctx.moveTo(x, pad.t); ctx.lineTo(x, H - pad.b); ctx.stroke();
    ctx.fillStyle = '#607080'; ctx.textAlign = 'center';
    ctx.fillText(t >= 60 ? Math.floor(t/60)+'m'+(t%60>0?(t%60)+'s':'') : t+'s', x, H - pad.b + 14);
  }

  // Short-term line
  ctx.beginPath();
  ctx.strokeStyle = '#00d2ff';
  ctx.lineWidth = 1.5;
  for (let i = 0; i < times.length; i++) {
    const x = tX(times[i]), y = lY(Math.max(values[i], minL));
    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
  }
  ctx.stroke();

  // Fill under curve
  ctx.lineTo(tX(times[times.length-1]), lY(minL));
  ctx.lineTo(tX(times[0]), lY(minL));
  ctx.closePath();
  const grad = ctx.createLinearGradient(0, pad.t, 0, H - pad.b);
  grad.addColorStop(0, 'rgba(0,210,255,0.3)');
  grad.addColorStop(1, 'rgba(0,210,255,0.02)');
  ctx.fillStyle = grad;
  ctx.fill();

  // Integrated LUFS line
  const intLufs = ${data.analysis.integratedLufs.toStringAsFixed(1)};
  if (intLufs > minL) {
    const iy = lY(intLufs);
    ctx.setLineDash([6, 4]);
    ctx.strokeStyle = '#4ade80';
    ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(pad.l, iy); ctx.lineTo(W - pad.r, iy); ctx.stroke();
    ctx.setLineDash([]);
    ctx.fillStyle = '#4ade80'; ctx.font = '10px monospace'; ctx.textAlign = 'left';
    ctx.fillText('INT: ' + intLufs.toFixed(1) + ' LUFS', pad.l + 4, iy - 4);
  }

  // Hover tooltip
  const tooltip = document.createElement('div');
  tooltip.className = 'tooltip';
  canvas.parentElement.appendChild(tooltip);

  canvas.addEventListener('mousemove', function(e) {
    const br = canvas.getBoundingClientRect();
    const mx = e.clientX - br.left;
    const mt = (mx - pad.l) / gW * maxT;
    let closest = 0, minDist = Infinity;
    for (let i = 0; i < times.length; i++) {
      const d = Math.abs(times[i] - mt);
      if (d < minDist) { minDist = d; closest = i; }
    }
    if (minDist < maxT * 0.02) {
      tooltip.style.display = 'block';
      tooltip.style.left = (tX(times[closest]) + 10) + 'px';
      tooltip.style.top = (lY(values[closest]) - 30) + 'px';
      const ts = times[closest];
      const m = Math.floor(ts/60), s = Math.floor(ts%60);
      tooltip.innerHTML = '<b>' + m + ':' + String(s).padStart(2,'0') + '</b><br>' + values[closest].toFixed(1) + ' LUFS';
    } else {
      tooltip.style.display = 'none';
    }
  });
  canvas.addEventListener('mouseleave', function() { tooltip.style.display = 'none'; });
})();
''';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  void _writeCard(StringBuffer buf, String label, String value, String cls) {
    buf.writeln('<div class="card $cls">');
    buf.writeln('<div class="label">$label</div>');
    buf.writeln('<div class="value">$value</div>');
    buf.writeln('</div>');
  }

  void _writeDetail(StringBuffer buf, String key, String value) {
    buf.writeln('<div class="detail"><span class="key">$key</span><span class="val">$value</span></div>');
  }

  String _lufsClass(double lufs) {
    if (lufs > -8.0) return 'clip';
    if (lufs > -14.0) return 'warn';
    return 'ok';
  }

  String _formatTime(double sec) {
    final m = (sec / 60).floor();
    final s = (sec % 60).floor();
    final ms = ((sec % 1) * 100).round();
    return '$m:${s.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}';
  }

  String _escapeHtml(String text) {
    return text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DSP (duplicated from LoudnessAnalysisService for dry-run isolation)
  // ═══════════════════════════════════════════════════════════════════════════

  double _applyKWeighting(double input, List<_BiquadState> states, int sampleRate) {
    // Stage 1: High shelf (+4dB at high frequencies)
    const b0Hs = 1.53512485958697;
    const b1Hs = -2.69169618940638;
    const b2Hs = 1.19839281085285;
    const a1Hs = -1.69065929318241;
    const a2Hs = 0.73248077421585;
    var output = states[0].process(input, b0Hs, b1Hs, b2Hs, a1Hs, a2Hs);

    // Stage 2: High-pass filter
    const b0Hp = 1.0;
    const b1Hp = -2.0;
    const b2Hp = 1.0;
    const a1Hp = -1.99004745483398;
    const a2Hp = 0.99007225036621;
    output = states[1].process(output, b0Hp, b1Hp, b2Hp, a1Hp, a2Hp);

    return output;
  }

  double _msToLufs(double ms) {
    if (ms <= 0.0) return -70.0;
    return -0.691 + 10.0 * math.log(ms) / math.ln10;
  }

  double _linearToDb(double linear) {
    if (linear <= 0.0) return -70.0;
    return 20.0 * math.log(linear) / math.ln10;
  }

  double _calculateIntegratedLufs(List<double> buffer) {
    if (buffer.isEmpty) return -70.0;

    final gated1 = buffer.where((ms) => _msToLufs(ms) > -70.0).toList();
    if (gated1.isEmpty) return -70.0;

    final ungatedMean = gated1.fold(0.0, (a, b) => a + b) / gated1.length;
    final relativeThreshold = _msToLufs(ungatedMean) - 10.0;

    final gated2 = gated1.where((ms) => _msToLufs(ms) > relativeThreshold).toList();
    if (gated2.isEmpty) return -70.0;

    final gatedMean = gated2.fold(0.0, (a, b) => a + b) / gated2.length;
    return _msToLufs(gatedMean);
  }
}

/// Biquad state for K-weighting
class _BiquadState {
  double z1 = 0.0;
  double z2 = 0.0;

  double process(double input, double b0, double b1, double b2, double a1, double a2) {
    final output = b0 * input + z1;
    z1 = b1 * input - a1 * output + z2;
    z2 = b2 * input - a2 * output;
    return output;
  }
}
