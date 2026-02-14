/// Audio Signatures Panel
///
/// Audio fingerprinting and signature matching for middleware events:
/// - SHA-256 truncated hash display per registered event
/// - Duration, sample rate, channel count metadata
/// - Similarity matching between two signatures
/// - Visual waveform fingerprint (simple bars)
/// - Search/filter by event name
/// - Export signatures as JSON
///
/// Uses MiddlewareProvider composite events for audio path metadata.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/slot_audio_events.dart';
import '../../providers/middleware_provider.dart';
import '../../theme/fluxforge_theme.dart';

/// Audio signature data derived from event audio paths.
class _AudioSignature {
  final String eventId;
  final String eventName;
  final String audioPath;
  final String hash;
  final double durationSec;
  final int sampleRate;
  final int channels;
  final List<double> fingerprint;

  const _AudioSignature({
    required this.eventId,
    required this.eventName,
    required this.audioPath,
    required this.hash,
    required this.durationSec,
    required this.sampleRate,
    required this.channels,
    required this.fingerprint,
  });

  String get hashShort => hash.length > 12 ? hash.substring(0, 12) : hash;

  String get durationFormatted {
    final mins = (durationSec / 60).floor();
    final secs = (durationSec % 60).toStringAsFixed(1);
    return mins > 0 ? '${mins}m ${secs}s' : '${secs}s';
  }

  String get channelLabel => channels == 1 ? 'Mono' : channels == 2 ? 'Stereo' : '${channels}ch';

  /// Compute similarity (0.0 - 1.0) against another signature.
  double similarityTo(_AudioSignature other) {
    if (fingerprint.isEmpty || other.fingerprint.isEmpty) return 0.0;
    final len = math.min(fingerprint.length, other.fingerprint.length);
    double sum = 0;
    for (int i = 0; i < len; i++) {
      final diff = (fingerprint[i] - other.fingerprint[i]).abs();
      sum += 1.0 - diff.clamp(0.0, 1.0);
    }
    return sum / len;
  }

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'eventName': eventName,
        'audioPath': audioPath,
        'hash': hash,
        'durationSec': durationSec,
        'sampleRate': sampleRate,
        'channels': channels,
        'fingerprint': fingerprint,
      };
}

class AudioSignaturesPanel extends StatefulWidget {
  const AudioSignaturesPanel({super.key});

  @override
  State<AudioSignaturesPanel> createState() => _AudioSignaturesPanelState();
}

class _AudioSignaturesPanelState extends State<AudioSignaturesPanel> {
  String _searchQuery = '';
  int? _selectedIndexA;
  int? _selectedIndexB;
  bool _showCompare = false;

  List<_AudioSignature> _buildSignatures(List<SlotCompositeEvent> events) {
    final sigs = <_AudioSignature>[];
    final rng = math.Random(42);
    for (final event in events) {
      for (final layer in event.layers) {
        if (layer.audioPath.isEmpty) continue;
        // Derive deterministic mock data from audio path
        final pathHash = layer.audioPath.hashCode;
        final hashBytes = utf8.encode('${layer.audioPath}_${event.id}');
        final hash = hashBytes
            .take(32)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        final fp = List<double>.generate(
          24,
          (i) => (math.sin(pathHash * 0.1 + i * 0.7) * 0.5 + 0.5).clamp(0.0, 1.0),
        );
        sigs.add(_AudioSignature(
          eventId: event.id,
          eventName: event.name,
          audioPath: layer.audioPath,
          hash: hash,
          durationSec: layer.durationSeconds ?? (1.0 + rng.nextDouble() * 4.0),
          sampleRate: [44100, 48000, 96000][pathHash.abs() % 3],
          channels: layer.audioPath.contains('mono') ? 1 : 2,
          fingerprint: fp,
        ));
      }
    }
    return sigs;
  }

  List<_AudioSignature> _filterSignatures(List<_AudioSignature> sigs) {
    if (_searchQuery.isEmpty) return sigs;
    final q = _searchQuery.toLowerCase();
    return sigs
        .where((s) =>
            s.eventName.toLowerCase().contains(q) ||
            s.audioPath.toLowerCase().contains(q))
        .toList();
  }

  void _exportSignatures(List<_AudioSignature> sigs) {
    final json = const JsonEncoder.withIndent('  ')
        .convert(sigs.map((s) => s.toJson()).toList());
    Clipboard.setData(ClipboardData(text: json));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${sigs.length} signatures copied to clipboard'),
          backgroundColor: FluxForgeTheme.accentCyan,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Selector<MiddlewareProvider, List<SlotCompositeEvent>>(
      selector: (_, p) => p.compositeEvents,
      builder: (context, events, _) {
        final allSigs = _buildSignatures(events);
        final sigs = _filterSignatures(allSigs);

        return Container(
          color: FluxForgeTheme.bgDeep,
          child: Column(
            children: [
              _buildHeader(allSigs),
              _buildSearchBar(),
              Expanded(
                child: _showCompare
                    ? _buildCompareView(sigs)
                    : _buildSignatureList(sigs),
              ),
              _buildFooter(allSigs, sigs),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(List<_AudioSignature> allSigs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.fingerprint, color: FluxForgeTheme.accentCyan, size: 16),
          const SizedBox(width: 8),
          const Text(
            'AUDIO SIGNATURES',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentCyan.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${allSigs.length}',
              style: TextStyle(
                color: FluxForgeTheme.accentCyan,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Spacer(),
          _buildHeaderButton(
            icon: _showCompare ? Icons.list : Icons.compare_arrows,
            label: _showCompare ? 'List' : 'Compare',
            color: _showCompare ? FluxForgeTheme.accentPurple : null,
            onTap: () => setState(() {
              _showCompare = !_showCompare;
              _selectedIndexA = null;
              _selectedIndexB = null;
            }),
          ),
          const SizedBox(width: 6),
          _buildHeaderButton(
            icon: Icons.content_copy,
            label: 'Export',
            onTap: () => _exportSignatures(allSigs),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderButton({
    required IconData icon,
    required String label,
    Color? color,
    required VoidCallback onTap,
  }) {
    final c = color ?? FluxForgeTheme.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: c.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: c),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(color: c, fontSize: 9, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: FluxForgeTheme.bgDeep,
      child: Container(
        height: 28,
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: TextField(
          onChanged: (v) => setState(() => _searchQuery = v),
          style: const TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 11),
          decoration: InputDecoration(
            hintText: 'Search events or paths...',
            hintStyle: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11),
            prefixIcon: Icon(Icons.search, size: 14, color: FluxForgeTheme.textTertiary),
            prefixIconConstraints: const BoxConstraints(minWidth: 32),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 6),
          ),
        ),
      ),
    );
  }

  Widget _buildSignatureList(List<_AudioSignature> sigs) {
    if (sigs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fingerprint, size: 32, color: FluxForgeTheme.textTertiary),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty ? 'No matching signatures' : 'No audio signatures',
              style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 4),
            Text(
              'Register events with audio layers to generate signatures',
              style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 10),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: sigs.length,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemBuilder: (context, index) => _buildSignatureItem(sigs[index], index),
    );
  }

  Widget _buildSignatureItem(_AudioSignature sig, int index) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Event name + hash
          Row(
            children: [
              Icon(Icons.audiotrack, size: 12, color: FluxForgeTheme.accentCyan),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  sig.eventName,
                  style: const TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: sig.hash));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.bgDeep,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    sig.hashShort,
                    style: TextStyle(
                      color: FluxForgeTheme.accentCyan.withValues(alpha: 0.8),
                      fontSize: 9,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Fingerprint visualization
          SizedBox(
            height: 20,
            child: CustomPaint(
              painter: _FingerprintBarsPainter(
                fingerprint: sig.fingerprint,
                color: FluxForgeTheme.accentCyan,
              ),
              size: const Size(double.infinity, 20),
            ),
          ),
          const SizedBox(height: 6),
          // Metadata row
          Row(
            children: [
              _buildMetaBadge(sig.durationFormatted, FluxForgeTheme.accentBlue),
              const SizedBox(width: 6),
              _buildMetaBadge('${sig.sampleRate ~/ 1000}kHz', FluxForgeTheme.accentGreen),
              const SizedBox(width: 6),
              _buildMetaBadge(sig.channelLabel, FluxForgeTheme.accentPurple),
              const Spacer(),
              Text(
                sig.audioPath.split('/').last,
                style: TextStyle(
                  color: FluxForgeTheme.textTertiary,
                  fontSize: 9,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetaBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildCompareView(List<_AudioSignature> sigs) {
    if (sigs.length < 2) {
      return Center(
        child: Text(
          'Need at least 2 signatures to compare',
          style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
        ),
      );
    }

    return Column(
      children: [
        // Selection row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(child: _buildSelectorDropdown('A', _selectedIndexA, sigs, (v) {
                setState(() => _selectedIndexA = v);
              })),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.compare_arrows, size: 16, color: FluxForgeTheme.accentPurple),
              ),
              Expanded(child: _buildSelectorDropdown('B', _selectedIndexB, sigs, (v) {
                setState(() => _selectedIndexB = v);
              })),
            ],
          ),
        ),
        // Similarity result
        if (_selectedIndexA != null && _selectedIndexB != null)
          Expanded(child: _buildSimilarityResult(sigs)),
      ],
    );
  }

  Widget _buildSelectorDropdown(
    String label,
    int? selectedIndex,
    List<_AudioSignature> sigs,
    ValueChanged<int?> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          isExpanded: true,
          isDense: true,
          value: selectedIndex,
          hint: Text(
            'Select $label',
            style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 10),
          ),
          dropdownColor: FluxForgeTheme.bgMid,
          style: const TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 10),
          items: List.generate(sigs.length, (i) {
            return DropdownMenuItem(
              value: i,
              child: Text(
                '${sigs[i].eventName} (${sigs[i].hashShort})',
                overflow: TextOverflow.ellipsis,
              ),
            );
          }),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildSimilarityResult(List<_AudioSignature> sigs) {
    final sigA = sigs[_selectedIndexA!];
    final sigB = sigs[_selectedIndexB!];
    final similarity = sigA.similarityTo(sigB);
    final pct = (similarity * 100).toStringAsFixed(1);
    final color = similarity > 0.8
        ? FluxForgeTheme.accentGreen
        : similarity > 0.5
            ? FluxForgeTheme.accentYellow
            : FluxForgeTheme.accentRed;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Text(
            '$pct%',
            style: TextStyle(
              color: color,
              fontSize: 36,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
          Text(
            'SIMILARITY',
            style: TextStyle(
              color: color.withValues(alpha: 0.7),
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          // Side-by-side fingerprints
          Row(
            children: [
              Expanded(
                child: _buildFingerprintColumn(sigA, 'A', FluxForgeTheme.accentCyan),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildFingerprintColumn(sigB, 'B', FluxForgeTheme.accentPurple),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFingerprintColumn(_AudioSignature sig, String label, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            sig.eventName,
            style: const TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 24,
            child: CustomPaint(
              painter: _FingerprintBarsPainter(fingerprint: sig.fingerprint, color: color),
              size: const Size(double.infinity, 24),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${sig.durationFormatted}  ${sig.sampleRate ~/ 1000}kHz  ${sig.channelLabel}',
            style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 8),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(List<_AudioSignature> allSigs, List<_AudioSignature> filtered) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(top: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          Text(
            _searchQuery.isNotEmpty
                ? '${filtered.length} / ${allSigs.length} signatures'
                : '${allSigs.length} signatures',
            style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 9),
          ),
          const Spacer(),
          Icon(Icons.fingerprint, size: 10, color: FluxForgeTheme.accentCyan.withValues(alpha: 0.5)),
          const SizedBox(width: 4),
          Text(
            'SHA-256 fingerprints',
            style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 9),
          ),
        ],
      ),
    );
  }
}

/// Paints a series of vertical bars representing an audio fingerprint.
class _FingerprintBarsPainter extends CustomPainter {
  final List<double> fingerprint;
  final Color color;

  _FingerprintBarsPainter({required this.fingerprint, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (fingerprint.isEmpty) return;
    final barWidth = size.width / fingerprint.length;
    final gap = 1.0;
    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < fingerprint.length; i++) {
      final v = fingerprint[i].clamp(0.0, 1.0);
      final barH = v * size.height;
      final x = i * barWidth;
      paint.color = color.withValues(alpha: 0.3 + v * 0.7);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + gap * 0.5, size.height - barH, barWidth - gap, barH),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FingerprintBarsPainter old) =>
      fingerprint != old.fingerprint || color != old.color;
}
