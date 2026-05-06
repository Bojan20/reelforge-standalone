// AI Provider Settings dialog — choose Local / Anthropic / Azure + credentials.

import 'package:flutter/material.dart';

import '../../models/ai_composer.dart';
import '../../services/ai_composer_service.dart';

class AiProviderSettingsDialog extends StatefulWidget {
  const AiProviderSettingsDialog({super.key, required this.service});

  final AiComposerService service;

  @override
  State<AiProviderSettingsDialog> createState() => _AiProviderSettingsDialogState();
}

class _AiProviderSettingsDialogState extends State<AiProviderSettingsDialog> {
  late ProviderSelection _draft;

  late final TextEditingController _ollamaEndpointCtrl;
  late final TextEditingController _ollamaModelCtrl;
  late final TextEditingController _anthropicEndpointCtrl;
  late final TextEditingController _anthropicModelCtrl;
  late final TextEditingController _anthropicKeyCtrl;
  late final TextEditingController _azureEndpointCtrl;
  late final TextEditingController _azureDeploymentCtrl;
  late final TextEditingController _azureApiVersionCtrl;
  late final TextEditingController _azureKeyCtrl;

  bool _obscureAnthropic = true;
  bool _obscureAzure = true;
  String? _statusMsg;
  Color _statusColor = Colors.white60;

  @override
  void initState() {
    super.initState();
    _draft = widget.service.selection;
    _ollamaEndpointCtrl = TextEditingController(text: _draft.ollama.endpoint);
    _ollamaModelCtrl = TextEditingController(text: _draft.ollama.model);
    _anthropicEndpointCtrl = TextEditingController(text: _draft.anthropic.endpoint);
    _anthropicModelCtrl = TextEditingController(text: _draft.anthropic.model);
    _anthropicKeyCtrl = TextEditingController();
    _azureEndpointCtrl = TextEditingController(text: _draft.azure.endpoint);
    _azureDeploymentCtrl = TextEditingController(text: _draft.azure.deployment);
    _azureApiVersionCtrl = TextEditingController(text: _draft.azure.apiVersion);
    _azureKeyCtrl = TextEditingController();
    widget.service.refreshCredentialsPresence();
  }

  @override
  void dispose() {
    _ollamaEndpointCtrl.dispose();
    _ollamaModelCtrl.dispose();
    _anthropicEndpointCtrl.dispose();
    _anthropicModelCtrl.dispose();
    _anthropicKeyCtrl.dispose();
    _azureEndpointCtrl.dispose();
    _azureDeploymentCtrl.dispose();
    _azureApiVersionCtrl.dispose();
    _azureKeyCtrl.dispose();
    super.dispose();
  }

  void _setStatus(String msg, {bool ok = true}) {
    setState(() {
      _statusMsg = msg;
      _statusColor = ok ? const Color(0xFF44DD66) : const Color(0xFFFF6666);
    });
  }

  ProviderSelection _collect() => ProviderSelection(
        provider: _draft.provider,
        ollama: OllamaConfig(
            endpoint: _ollamaEndpointCtrl.text.trim(),
            model: _ollamaModelCtrl.text.trim()),
        anthropic: AnthropicConfig(
            endpoint: _anthropicEndpointCtrl.text.trim(),
            model: _anthropicModelCtrl.text.trim()),
        azure: AzureConfig(
            endpoint: _azureEndpointCtrl.text.trim(),
            deployment: _azureDeploymentCtrl.text.trim(),
            apiVersion: _azureApiVersionCtrl.text.trim()),
      );

  Future<void> _save() async {
    final next = _collect();
    final ok = await widget.service.setSelection(next);
    if (!ok) {
      _setStatus('Failed to save selection', ok: false);
      return;
    }
    // Push API keys if user typed any.
    if (_anthropicKeyCtrl.text.trim().isNotEmpty) {
      await widget.service.putAnthropicKey(_anthropicKeyCtrl.text.trim());
      _anthropicKeyCtrl.clear();
    }
    if (_azureKeyCtrl.text.trim().isNotEmpty) {
      await widget.service.putAzureKey(_azureKeyCtrl.text.trim());
      _azureKeyCtrl.clear();
    }
    _setStatus('Saved.');
  }

  Future<void> _testConnection() async {
    _setStatus('Testing…');
    await widget.service.refreshActiveInfo();
    final info = widget.service.activeInfo;
    if (info == null) {
      _setStatus('No info returned', ok: false);
      return;
    }
    _setStatus(
      info.healthy
          ? 'OK — ${info.id.displayLabel}: ${info.model}'
          : 'Health check failed — check endpoint / key',
      ok: info.healthy,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF06060A),
      child: Container(
        width: 640,
        constraints: const BoxConstraints(maxHeight: 720),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('AI Provider · Multi-provider Composer',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6)),
            const SizedBox(height: 4),
            const Text(
              'Choose which AI backend FluxForge uses to compose audio designs.',
              style: TextStyle(color: Colors.white60, fontSize: 11),
            ),
            const SizedBox(height: 16),
            _buildProviderSelector(),
            const SizedBox(height: 16),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 12),
            Expanded(child: SingleChildScrollView(child: _buildActiveConfig())),
            const SizedBox(height: 12),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderSelector() {
    return Wrap(
      spacing: 8,
      children: AiProviderId.values.map((id) {
        final selected = _draft.provider == id;
        return ChoiceChip(
          label: Text(id.displayLabel,
              style: TextStyle(
                color: selected ? Colors.black : Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              )),
          selected: selected,
          onSelected: (_) => setState(() {
            _draft = _draft.copyWith(provider: id);
          }),
          selectedColor: const Color(0xFF44DD66),
          backgroundColor: const Color(0xFF1A1A28),
          showCheckmark: false,
        );
      }).toList(),
    );
  }

  Widget _buildActiveConfig() {
    return switch (_draft.provider) {
      AiProviderId.ollama => _ollamaConfig(),
      AiProviderId.anthropic => _anthropicConfig(),
      AiProviderId.azureOpenai => _azureConfig(),
    };
  }

  Widget _ollamaConfig() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _infoBox(
            'Local LLM via Ollama. Air-gapped — no data leaves this machine.\n'
            'Customer must run `ollama serve` and `ollama pull <model>` first.'),
        const SizedBox(height: 12),
        _textField('Endpoint', _ollamaEndpointCtrl,
            hint: 'http://127.0.0.1:11434'),
        const SizedBox(height: 8),
        _textField('Model', _ollamaModelCtrl,
            hint: 'llama3.1:70b · qwen2.5:32b · mistral-nemo'),
      ],
    );
  }

  Widget _anthropicConfig() {
    final hasKey = widget.service.anthropicKeyPresent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _infoBox(
            'Anthropic Claude — bring your own API key. Stored securely in OS keychain. '
            'Inference happens at api.anthropic.com.'),
        const SizedBox(height: 12),
        _textField('Endpoint', _anthropicEndpointCtrl,
            hint: 'https://api.anthropic.com'),
        const SizedBox(height: 8),
        _textField('Model', _anthropicModelCtrl,
            hint: 'claude-sonnet-4-5 · claude-opus-4'),
        const SizedBox(height: 12),
        _credentialField(
          label: 'API Key',
          hint: hasKey ? '•••• stored in keychain' : 'sk-ant-…',
          controller: _anthropicKeyCtrl,
          obscure: _obscureAnthropic,
          onToggle: () =>
              setState(() => _obscureAnthropic = !_obscureAnthropic),
          onDelete: hasKey
              ? () async {
                  await widget.service.deleteAnthropicKey();
                  _setStatus('Anthropic key deleted from keychain.');
                }
              : null,
        ),
      ],
    );
  }

  Widget _azureConfig() {
    final hasKey = widget.service.azureKeyPresent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _infoBox(
            'Azure OpenAI — your enterprise tenant. Data stays in your Azure region. '
            'Configure resource endpoint + deployment ID + key.'),
        const SizedBox(height: 12),
        _textField('Resource endpoint', _azureEndpointCtrl,
            hint: 'https://my-tenant.openai.azure.com'),
        const SizedBox(height: 8),
        _textField('Deployment', _azureDeploymentCtrl,
            hint: 'gpt-4o-eu (the Azure deployment ID)'),
        const SizedBox(height: 8),
        _textField('API Version', _azureApiVersionCtrl,
            hint: '2024-08-01-preview'),
        const SizedBox(height: 12),
        _credentialField(
          label: 'API Key',
          hint: hasKey ? '•••• stored in keychain' : '<azure key>',
          controller: _azureKeyCtrl,
          obscure: _obscureAzure,
          onToggle: () => setState(() => _obscureAzure = !_obscureAzure),
          onDelete: hasKey
              ? () async {
                  await widget.service.deleteAzureKey();
                  _setStatus('Azure key deleted from keychain.');
                }
              : null,
        ),
      ],
    );
  }

  Widget _textField(String label, TextEditingController ctrl,
      {String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.white60, fontSize: 11, letterSpacing: 0.4)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
            isDense: true,
            border: const OutlineInputBorder(),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
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
    VoidCallback? onDelete,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.white60, fontSize: 11, letterSpacing: 0.4)),
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
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                obscure ? Icons.visibility_off : Icons.visibility,
                size: 18,
                color: Colors.white60,
              ),
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

  Widget _infoBox(String text) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A28),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Colors.white60, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 11, height: 1.4)),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Row(
      children: [
        if (_statusMsg != null)
          Expanded(
            child: Text(_statusMsg!,
                style: TextStyle(color: _statusColor, fontSize: 11)),
          )
        else
          const Spacer(),
        TextButton(
          onPressed: _testConnection,
          child: const Text('Test Connection'),
        ),
        const SizedBox(width: 4),
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
    );
  }
}
