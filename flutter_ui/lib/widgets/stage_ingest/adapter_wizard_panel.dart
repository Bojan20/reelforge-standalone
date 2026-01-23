// ═══════════════════════════════════════════════════════════════════════════════
// ADAPTER WIZARD PANEL — Auto-configure engine adapters from samples
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../providers/stage_ingest_provider.dart';

/// Visual wizard for auto-configuring engine adapters
class AdapterWizardPanel extends StatefulWidget {
  final StageIngestProvider provider;
  final Function(int configId)? onConfigGenerated;

  const AdapterWizardPanel({
    super.key,
    required this.provider,
    this.onConfigGenerated,
  });

  @override
  State<AdapterWizardPanel> createState() => _AdapterWizardPanelState();
}

class _AdapterWizardPanelState extends State<AdapterWizardPanel> {
  int? _wizardId;
  int _sampleCount = 0;
  WizardResult? _result;
  bool _isAnalyzing = false;
  String _pasteError = '';
  final _jsonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _createWizard();
  }

  @override
  void dispose() {
    if (_wizardId != null) {
      widget.provider.destroyWizard(_wizardId!);
    }
    _jsonController.dispose();
    super.dispose();
  }

  void _createWizard() {
    _wizardId = widget.provider.createWizard();
    setState(() {});
  }

  void _addSample() {
    final text = _jsonController.text.trim();
    if (text.isEmpty) {
      setState(() => _pasteError = 'Paste JSON sample first');
      return;
    }

    try {
      final json = jsonDecode(text);
      if (json is List) {
        // Multiple samples
        final samples = json.map((e) => e as Map<String, dynamic>).toList();
        final count = widget.provider.addSamplesToWizard(_wizardId!, samples);
        if (count > 0) {
          _sampleCount += count;
          _jsonController.clear();
          setState(() => _pasteError = '');
        } else {
          setState(() => _pasteError = 'Failed to add samples');
        }
      } else if (json is Map) {
        // Single sample
        if (widget.provider.addSampleToWizard(_wizardId!, json as Map<String, dynamic>)) {
          _sampleCount++;
          _jsonController.clear();
          setState(() => _pasteError = '');
        } else {
          setState(() => _pasteError = 'Failed to add sample');
        }
      } else {
        setState(() => _pasteError = 'Invalid JSON format');
      }
    } catch (e) {
      setState(() => _pasteError = 'Invalid JSON: ${e.toString().split(':').last}');
    }
  }

  Future<void> _analyze() async {
    if (_sampleCount == 0) {
      setState(() => _pasteError = 'Add at least one sample first');
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _pasteError = '';
    });

    // Run analysis (may take a moment)
    await Future.delayed(const Duration(milliseconds: 100));
    final result = widget.provider.analyzeWizard(_wizardId!);

    setState(() {
      _result = result;
      _isAnalyzing = false;
    });

    if (result?.config != null) {
      widget.onConfigGenerated?.call(result!.config!.configId);
    }
  }

  void _clear() {
    widget.provider.clearWizardSamples(_wizardId!);
    setState(() {
      _sampleCount = 0;
      _result = null;
      _pasteError = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3a3a44)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSampleInput(),
                  const SizedBox(height: 12),
                  _buildSampleStatus(),
                  const SizedBox(height: 12),
                  _buildActions(),
                  if (_result != null) ...[
                    const SizedBox(height: 16),
                    Expanded(child: _buildResult()),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF242430),
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_fix_high, color: Color(0xFFff9040), size: 18),
          const SizedBox(width: 8),
          Text(
            'Adapter Wizard',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, size: 16),
            onPressed: _clear,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(maxWidth: 24),
            color: Colors.white.withOpacity(0.5),
            tooltip: 'Clear & restart',
          ),
        ],
      ),
    );
  }

  Widget _buildSampleInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Paste JSON samples from your slot engine:',
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 100,
          decoration: BoxDecoration(
            color: const Color(0xFF121216),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _pasteError.isNotEmpty
                  ? const Color(0xFFff4040)
                  : const Color(0xFF3a3a44),
            ),
          ),
          child: TextField(
            controller: _jsonController,
            maxLines: null,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              hintText: '{"type": "spin_start", "balance": 1000, ...}',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(8),
            ),
          ),
        ),
        if (_pasteError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _pasteError,
              style: const TextStyle(
                color: Color(0xFFff4040),
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSampleStatus() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF242430),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            _sampleCount > 0 ? Icons.check_circle : Icons.info_outline,
            color: _sampleCount > 0
                ? const Color(0xFF40ff90)
                : Colors.white.withOpacity(0.5),
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            _sampleCount > 0
                ? '$_sampleCount sample${_sampleCount > 1 ? 's' : ''} loaded'
                : 'No samples added yet',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
          const Spacer(),
          Text(
            'Tip: Add 3-5 diverse samples for best results',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _addSample,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Sample'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF4a9eff),
              side: const BorderSide(color: Color(0xFF4a9eff)),
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _sampleCount > 0 && !_isAnalyzing ? _analyze : null,
            icon: _isAnalyzing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome, size: 16),
            label: Text(_isAnalyzing ? 'Analyzing...' : 'Analyze'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFff9040),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResult() {
    final result = _result!;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF242430),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: result.config != null
              ? const Color(0xFF40ff90)
              : const Color(0xFFff9040),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.config != null ? Icons.check_circle : Icons.warning,
                color: result.config != null
                    ? const Color(0xFF40ff90)
                    : const Color(0xFFff9040),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                result.config != null
                    ? 'Config Generated Successfully'
                    : 'Analysis Complete',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _getConfidenceColor(result.confidence).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${(result.confidence * 100).toInt()}% confidence',
                  style: TextStyle(
                    color: _getConfidenceColor(result.confidence),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (result.detectedFields.isNotEmpty) ...[
            Text(
              'Detected Fields:',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: result.detectedFields.map((field) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4a9eff).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    field,
                    style: const TextStyle(
                      color: Color(0xFF4a9eff),
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],
          if (result.recommendedLayer != null)
            Text(
              'Recommended layer: ${result.recommendedLayer}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 11,
              ),
            ),
          if (result.config != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _copyConfig(result.config!.configId),
                    icon: const Icon(Icons.copy, size: 14),
                    label: const Text('Copy Config'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white.withOpacity(0.7),
                      side: BorderSide(color: Colors.white.withOpacity(0.3)),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => widget.onConfigGenerated?.call(result.config!.configId),
                    icon: const Icon(Icons.check, size: 14),
                    label: const Text('Use Config'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF40ff90),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) return const Color(0xFF40ff90);
    if (confidence >= 0.5) return const Color(0xFFffff40);
    return const Color(0xFFff9040);
  }

  void _copyConfig(int configId) {
    final json = widget.provider.getConfigJson(configId);
    if (json != null) {
      Clipboard.setData(ClipboardData(text: json));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Config copied to clipboard')),
      );
    }
  }
}
