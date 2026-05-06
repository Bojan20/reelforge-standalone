// AI Audio Settings dialog — choose backend per kind + manage credentials.

import 'package:flutter/material.dart';

import '../../models/ai_composer.dart';
import '../../services/ai_composer_service.dart';

class AiAudioSettingsDialog extends StatefulWidget {
  const AiAudioSettingsDialog({super.key, required this.service});

  final AiComposerService service;

  @override
  State<AiAudioSettingsDialog> createState() => _AiAudioSettingsDialogState();
}

class _AiAudioSettingsDialogState extends State<AiAudioSettingsDialog> {
  late AudioRoutingTable _routing;

  late final TextEditingController _elKeyCtrl;
  late final TextEditingController _sunoKeyCtrl;
  bool _obscureEl = true;
  bool _obscureSuno = true;

  String? _statusMsg;
  Color _statusColor = Colors.white60;

  @override
  void initState() {
    super.initState();
    _routing = widget.service.routing;
    _elKeyCtrl = TextEditingController();
    _sunoKeyCtrl = TextEditingController();
    widget.service.refreshRouting();
    widget.service.refreshAudioCredentialsPresence();
  }

  @override
  void dispose() {
    _elKeyCtrl.dispose();
    _sunoKeyCtrl.dispose();
    super.dispose();
  }

  void _setStatus(String msg, {bool ok = true}) {
    setState(() {
      _statusMsg = msg;
      _statusColor = ok ? const Color(0xFF44DD66) : const Color(0xFFFF6666);
    });
  }

  Future<void> _save() async {
    final ok = await widget.service.setRouting(_routing);
    if (!ok) {
      _setStatus('Failed to save routing', ok: false);
      return;
    }
    if (_elKeyCtrl.text.trim().isNotEmpty) {
      await widget.service.putElevenlabsKey(_elKeyCtrl.text.trim());
      _elKeyCtrl.clear();
    }
    if (_sunoKeyCtrl.text.trim().isNotEmpty) {
      await widget.service.putSunoKey(_sunoKeyCtrl.text.trim());
      _sunoKeyCtrl.clear();
    }
    _setStatus('Saved.');
  }

  Future<void> _switchAirGapped() async {
    final ok = await widget.service.switchToAirGapped();
    if (ok) {
      setState(() => _routing = widget.service.routing);
      _setStatus('Switched to air-gapped routing (all Local).');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF06060A),
      child: Container(
        width: 620,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Audio Backends · Routing & Credentials',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6)),
            const SizedBox(height: 4),
            const Text(
              'Choose which backend produces SFX, voice, and music. Keys are stored in the OS keychain.',
              style: TextStyle(color: Colors.white60, fontSize: 11),
            ),
            const SizedBox(height: 16),
            _buildRoutingRow('SFX', AudioKind.sfx),
            const SizedBox(height: 6),
            _buildRoutingRow('Voice', AudioKind.tts),
            const SizedBox(height: 6),
            _buildRoutingRow('Music', AudioKind.music),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.security, size: 14),
                label: const Text('Switch to Air-Gapped (all Local)',
                    style: TextStyle(fontSize: 11)),
                onPressed: _switchAirGapped,
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
              ),
            ),
            const Divider(color: Colors.white12, height: 24),
            _credentialField(
              label: 'ElevenLabs API Key',
              hint: widget.service.elevenlabsKeyPresent
                  ? '•••• stored in keychain'
                  : 'sk_…',
              controller: _elKeyCtrl,
              obscure: _obscureEl,
              onToggle: () => setState(() => _obscureEl = !_obscureEl),
              hasKey: widget.service.elevenlabsKeyPresent,
              onDelete: widget.service.elevenlabsKeyPresent
                  ? () async {
                      await widget.service.deleteElevenlabsKey();
                      _setStatus('ElevenLabs key removed.');
                    }
                  : null,
            ),
            const SizedBox(height: 12),
            _credentialField(
              label: 'Suno API Key',
              hint: widget.service.sunoKeyPresent
                  ? '•••• stored in keychain'
                  : 'bearer …',
              controller: _sunoKeyCtrl,
              obscure: _obscureSuno,
              onToggle: () => setState(() => _obscureSuno = !_obscureSuno),
              hasKey: widget.service.sunoKeyPresent,
              onDelete: widget.service.sunoKeyPresent
                  ? () async {
                      await widget.service.deleteSunoKey();
                      _setStatus('Suno key removed.');
                    }
                  : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (_statusMsg != null)
                  Expanded(
                    child: Text(_statusMsg!,
                        style:
                            TextStyle(color: _statusColor, fontSize: 11)),
                  )
                else
                  const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
                const SizedBox(width: 4),
                ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF44DD66),
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoutingRow(String label, AudioKind kind) {
    final current = _routing.map[kind] ?? AudioBackendId.local;
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 6,
            children: AudioBackendId.values.map((b) {
              final selected = current == b;
              return ChoiceChip(
                label: Text(b.displayLabel,
                    style: TextStyle(
                        fontSize: 11,
                        color: selected ? Colors.black : Colors.white70,
                        fontWeight: FontWeight.w600)),
                selected: selected,
                onSelected: (_) =>
                    setState(() => _routing = _routing.copyWithKind(kind, b)),
                selectedColor: const Color(0xFF44DD66),
                backgroundColor: const Color(0xFF1A1A28),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _credentialField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggle,
    required bool hasKey,
    VoidCallback? onDelete,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                    letterSpacing: 0.4)),
            const SizedBox(width: 8),
            if (hasKey)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF44DD66).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('IN KEYCHAIN',
                    style: TextStyle(
                        color: Color(0xFF44DD66),
                        fontSize: 9,
                        fontWeight: FontWeight.w700)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                obscureText: obscure,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle:
                      const TextStyle(color: Colors.white38, fontSize: 11),
                  isDense: true,
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 10),
                ),
              ),
            ),
            IconButton(
              icon: Icon(obscure ? Icons.visibility_off : Icons.visibility,
                  size: 18, color: Colors.white60),
              onPressed: onToggle,
            ),
            if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: Color(0xFFFF6666)),
                onPressed: onDelete,
                tooltip: 'Delete from keychain',
              ),
          ],
        ),
      ],
    );
  }
}
