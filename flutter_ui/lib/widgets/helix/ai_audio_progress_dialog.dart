// AI Audio Progress dialog — live polling of batch generation.

import 'package:flutter/material.dart';

import '../../models/ai_composer.dart';
import '../../services/ai_composer_service.dart';

class AiAudioProgressDialog extends StatefulWidget {
  const AiAudioProgressDialog({super.key, required this.service});
  final AiComposerService service;

  @override
  State<AiAudioProgressDialog> createState() => _AiAudioProgressDialogState();
}

class _AiAudioProgressDialogState extends State<AiAudioProgressDialog> {
  @override
  void initState() {
    super.initState();
    widget.service.addListener(_onTick);
  }

  @override
  void dispose() {
    widget.service.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    setState(() {});
    final p = widget.service.audioProgress;
    if (!p.active && p.total > 0) {
      // Auto-close 1.2s after completion so user can read the final state.
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.service.audioProgress;
    final pct = p.total == 0 ? 0.0 : p.completed / p.total;

    return Dialog(
      backgroundColor: const Color(0xFF06060A),
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  p.active
                      ? Icons.audiotrack
                      : (p.failed > 0 ? Icons.warning : Icons.check_circle),
                  color: p.active
                      ? const Color(0xFFFFAA33)
                      : (p.failed > 0
                          ? const Color(0xFFFF6666)
                          : const Color(0xFF44DD66)),
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    p.active
                        ? 'Generating audio…'
                        : (p.total == 0
                            ? 'Starting…'
                            : 'Done — ${p.succeeded} ok / ${p.failed} failed'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6),
                  ),
                ),
                if (p.active)
                  TextButton.icon(
                    icon: const Icon(Icons.cancel, size: 14),
                    label: const Text('Cancel'),
                    onPressed: p.cancelRequested
                        ? null
                        : () => widget.service.cancelAudioBatch(),
                    style:
                        TextButton.styleFrom(foregroundColor: const Color(0xFFFF6666)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: p.active && p.total > 0 ? pct : (p.total > 0 ? 1.0 : null),
                minHeight: 8,
                backgroundColor: const Color(0xFF1A1A28),
                valueColor: AlwaysStoppedAnimation<Color>(p.failed > 0
                    ? const Color(0xFFFFAA33)
                    : const Color(0xFF44DD66)),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${p.completed} / ${p.total}'
              '${p.current != null ? "  ·  ${p.current}" : ""}',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
            const SizedBox(height: 12),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: p.partialResults.length,
                itemBuilder: (_, i) => _resultRow(p.partialResults[i]),
              ),
            ),
            if (!p.active && p.total > 0) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _resultRow(AudioAssetResult r) {
    final ok = r.ok;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(ok ? Icons.check : Icons.close,
              size: 14,
              color: ok ? const Color(0xFF44DD66) : const Color(0xFFFF6666)),
          const SizedBox(width: 6),
          SizedBox(
            width: 110,
            child: Text(r.stageId,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(r.assetName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 11)),
          ),
          Text(r.backend.displayLabel,
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
          if (ok) ...[
            const SizedBox(width: 8),
            Text(_formatBytes(r.bytes),
                style:
                    const TextStyle(color: Color(0xFF44DD66), fontSize: 10)),
          ],
        ],
      ),
    );
  }

  String _formatBytes(int b) {
    if (b < 1024) return '${b}B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)}K';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)}M';
  }
}
