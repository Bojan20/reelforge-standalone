/// GDD Import Panel
///
/// Game Design Document import and validation:
/// - File picker for JSON files
/// - Real-time validation feedback
/// - Preview parsed GameModel
/// - One-click import to engine
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../theme/fluxforge_theme.dart';
import '../../src/rust/native_ffi.dart';
import '../../src/rust/slot_lab_v2_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// GDD IMPORT PANEL
// ═══════════════════════════════════════════════════════════════════════════════

class GddImportPanel extends StatefulWidget {
  final VoidCallback? onClose;
  final ValueChanged<Map<String, dynamic>>? onModelImported;

  const GddImportPanel({
    super.key,
    this.onClose,
    this.onModelImported,
  });

  @override
  State<GddImportPanel> createState() => _GddImportPanelState();
}

class _GddImportPanelState extends State<GddImportPanel> {
  // State
  String? _filePath;
  String? _gddJson;
  GddValidationResult? _validationResult;
  Map<String, dynamic>? _parsedModel;
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Select GDD JSON File',
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        await _loadFile(path);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to pick file: $e';
      });
    }
  }

  Future<void> _loadFile(String path) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _validationResult = null;
      _parsedModel = null;
    });

    try {
      final file = File(path);
      final content = await file.readAsString();

      // Validate JSON syntax
      try {
        jsonDecode(content);
      } catch (e) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Invalid JSON syntax: $e';
        });
        return;
      }

      setState(() {
        _filePath = path;
        _gddJson = content;
      });

      // Validate via FFI
      _validateGdd(content);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to read file: $e';
      });
    }
  }

  void _validateGdd(String json) {
    try {
      final result = NativeFFI.instance.slotLabGddValidate(json);
      setState(() {
        _validationResult = result;
        _isLoading = false;
      });

      // If valid, also parse to model
      if (result.valid) {
        _parseToModel(json);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Validation error: $e';
      });
    }
  }

  void _parseToModel(String json) {
    try {
      final result = NativeFFI.instance.slotLabGddToModel(json);
      if (result.isSuccess) {
        setState(() {
          _parsedModel = result.model;
        });
      } else {
        setState(() {
          _errorMessage = result.errorMessage;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Parse error: $e';
      });
    }
  }

  void _importToEngine() {
    if (_gddJson == null || _validationResult?.valid != true) return;

    try {
      final success = NativeFFI.instance.slotLabV2InitFromGdd(_gddJson!);
      if (success) {
        widget.onModelImported?.call(_parsedModel ?? {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GDD imported successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to import GDD to engine'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Import error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _clear() {
    setState(() {
      _filePath = null;
      _gddJson = null;
      _validationResult = null;
      _parsedModel = null;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(),
          // Content
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.upload_file, size: 18, color: FluxForgeTheme.accent),
          const SizedBox(width: 8),
          const Text(
            'GDD Import',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          if (widget.onClose != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: widget.onClose,
              color: FluxForgeTheme.textMuted,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Validating GDD...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    if (_filePath == null) {
      return _buildDropZone();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // File info
          _buildFileInfo(),
          const SizedBox(height: 16),

          // Validation result
          _buildValidationResult(),
          const SizedBox(height: 16),

          // Error message
          if (_errorMessage != null) ...[
            _buildErrorMessage(),
            const SizedBox(height: 16),
          ],

          // Parsed model preview
          if (_parsedModel != null) ...[
            _buildModelPreview(),
            const SizedBox(height: 16),
          ],

          // Actions
          _buildActions(),
        ],
      ),
    );
  }

  Widget _buildDropZone() {
    return Center(
      child: InkWell(
        onTap: _pickFile,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 300,
          height: 200,
          decoration: BoxDecoration(
            color: FluxForgeTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: FluxForgeTheme.accent.withValues(alpha: 0.5),
              style: BorderStyle.solid,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_upload_outlined,
                size: 64,
                color: FluxForgeTheme.accent.withValues(alpha: 0.7),
              ),
              const SizedBox(height: 16),
              const Text(
                'Click to select GDD file',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'or drag & drop a .json file',
                style: TextStyle(
                  color: FluxForgeTheme.textMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Browse Files',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileInfo() {
    final fileName = _filePath?.split('/').last ?? 'Unknown';
    final fileSize = _gddJson?.length ?? 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: FluxForgeTheme.accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.description, color: Colors.white70, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${(fileSize / 1024).toStringAsFixed(1)} KB',
                  style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: _clear,
            color: FluxForgeTheme.textMuted,
          ),
        ],
      ),
    );
  }

  Widget _buildValidationResult() {
    if (_validationResult == null) return const SizedBox.shrink();

    final isValid = _validationResult!.valid;
    final errors = _validationResult!.errors;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isValid
            ? FluxForgeTheme.accentGreen.withValues(alpha: 0.1)
            : FluxForgeTheme.accentRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isValid
              ? FluxForgeTheme.accentGreen.withValues(alpha: 0.5)
              : FluxForgeTheme.accentRed.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isValid ? Icons.check_circle : Icons.error,
                color: isValid ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                isValid ? 'Validation Passed' : 'Validation Failed',
                style: TextStyle(
                  color: isValid ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (!isValid && errors.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...errors.map((error) => Padding(
              padding: const EdgeInsets.only(left: 28, top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: TextStyle(color: FluxForgeTheme.accentRed)),
                  Expanded(
                    child: Text(
                      error,
                      style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 12),
                    ),
                  ),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.accentRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.accentRed.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning, color: FluxForgeTheme.accentRed, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelPreview() {
    if (_parsedModel == null) return const SizedBox.shrink();

    final info = _parsedModel!['info'] as Map<String, dynamic>? ?? {};
    final grid = _parsedModel!['grid'] as Map<String, dynamic>? ?? {};
    final symbols = _parsedModel!['symbols'] as List? ?? [];
    final features = _parsedModel!['features'] as List? ?? [];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Model Preview',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          // Game info
          _buildPreviewRow('Name', info['name'] as String? ?? 'Unknown'),
          _buildPreviewRow('ID', info['id'] as String? ?? 'unknown'),
          _buildPreviewRow('Provider', info['provider'] as String? ?? '-'),
          _buildPreviewRow('Volatility', info['volatility'] as String? ?? 'medium'),
          _buildPreviewRow('Target RTP', '${((info['target_rtp'] as num? ?? 0.965) * 100).toStringAsFixed(2)}%'),
          const Divider(color: Colors.white24, height: 24),
          // Grid
          _buildPreviewRow('Grid', '${grid['reels'] ?? 5}x${grid['rows'] ?? 3}'),
          _buildPreviewRow('Symbols', '${symbols.length}'),
          _buildPreviewRow('Features', '${features.length}'),
        ],
      ),
    );
  }

  Widget _buildPreviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    final canImport = _validationResult?.valid == true;

    return Row(
      children: [
        // Pick another file
        OutlinedButton.icon(
          icon: const Icon(Icons.folder_open, size: 16),
          label: const Text('Choose Another'),
          onPressed: _pickFile,
          style: OutlinedButton.styleFrom(
            foregroundColor: FluxForgeTheme.textMuted,
          ),
        ),
        const Spacer(),
        // Import button
        ElevatedButton.icon(
          icon: const Icon(Icons.download, size: 16),
          label: const Text('Import to Engine'),
          onPressed: canImport ? _importToEngine : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: FluxForgeTheme.accent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: FluxForgeTheme.border,
            padding: const EdgeInsets.symmetric(horizontal: 20),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SAMPLE GDD TEMPLATE GENERATOR
// ═══════════════════════════════════════════════════════════════════════════════

class GddTemplateGenerator {
  /// Generate a sample GDD JSON template
  static String generateTemplate() {
    final template = {
      'game': {
        'name': 'Example Slot Game',
        'id': 'example_slot',
        'version': '1.0.0',
        'provider': 'Studio Name',
      },
      'math': {
        'volatility': 'medium',
        'target_rtp': 0.965,
        'hit_frequency': 0.33,
      },
      'grid': {
        'reels': 5,
        'rows': 3,
        'paylines': 20,
      },
      'symbols': [
        {'id': 0, 'name': 'Wild', 'type': 'wild', 'multiplier': 2},
        {'id': 1, 'name': 'Scatter', 'type': 'scatter'},
        {'id': 2, 'name': 'Premium 1', 'type': 'paying', 'pays': {'3': 100, '4': 250, '5': 500}},
        {'id': 3, 'name': 'Premium 2', 'type': 'paying', 'pays': {'3': 75, '4': 200, '5': 400}},
        {'id': 4, 'name': 'Low 1', 'type': 'paying', 'pays': {'3': 25, '4': 50, '5': 100}},
        {'id': 5, 'name': 'Low 2', 'type': 'paying', 'pays': {'3': 20, '4': 40, '5': 80}},
      ],
      'features': {
        'free_spins': {
          'enabled': true,
          'trigger': {'symbol': 1, 'count': 3},
          'base_spins': 10,
          'multiplier': 3,
        },
        'cascades': {
          'enabled': false,
        },
      },
      'audio_events': [
        'SPIN_START',
        'REEL_SPIN',
        'REEL_STOP',
        'ANTICIPATION',
        'WIN_SMALL',
        'WIN_BIG',
        'FREE_SPINS_TRIGGER',
      ],
    };

    return const JsonEncoder.withIndent('  ').convert(template);
  }
}
