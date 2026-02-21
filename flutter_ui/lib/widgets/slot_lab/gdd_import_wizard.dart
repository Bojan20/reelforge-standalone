/// GDD Import Wizard V2
///
/// Multi-step wizard for importing Game Design Documents:
/// 1. Input (paste JSON or load file)
/// 2. Preview (show parsed GDD summary with tabbed details)
/// 3. Stages (show generated stages grouped by category)
/// 4. Confirm (apply to SlotLab)
///
/// V2 Changes:
/// - Responsive sizing (90% screen, min 1100x850)
/// - Better step indicator with labels
/// - Tabbed preview with detailed views
/// - Stages grouped by category with expansion tiles
/// - ClipRRect for overflow prevention
///
/// Part of P3.4: GDD import wizard
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/safe_file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../services/gdd_import_service.dart';
import '../../services/stage_configuration_service.dart';
import '../../services/service_locator.dart';
import '../../providers/slot_lab_project_provider.dart';

/// GDD Import Wizard Dialog
class GddImportWizard extends StatefulWidget {
  const GddImportWizard({super.key});

  /// Show the wizard as a dialog
  static Future<GddImportResult?> show(BuildContext context) {
    return showDialog<GddImportResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const GddImportWizard(),
    );
  }

  @override
  State<GddImportWizard> createState() => _GddImportWizardState();
}

class _GddImportWizardState extends State<GddImportWizard>
    with SingleTickerProviderStateMixin {
  int _currentStep = 0;
  final _jsonController = TextEditingController();
  GddImportResult? _importResult;
  bool _isLoading = false;
  String? _error;
  bool _isPdfImport = false;

  // Preview tab controller
  late TabController _previewTabController;

  // Step configuration
  static const _steps = [
    _StepConfig('Input', Icons.input, 'Paste JSON or load file'),
    _StepConfig('Preview', Icons.preview, 'Review GDD details'),
    _StepConfig('Stages', Icons.layers, 'View generated stages'),
    _StepConfig('Import', Icons.check_circle, 'Confirm and import'),
  ];

  // Stage category expansion state
  final Map<String, bool> _expandedCategories = {};

  @override
  void initState() {
    super.initState();
    _previewTabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _jsonController.dispose();
    _previewTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.of(context).size;

    // Responsive sizing
    final dialogWidth = (screenSize.width * 0.9).clamp(1100.0, 1500.0);
    final dialogHeight = (screenSize.height * 0.9).clamp(850.0, 1000.0);

    return Dialog(
      backgroundColor: const Color(0xFF1a1a20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: dialogWidth,
          height: dialogHeight,
          child: Column(
            children: [
              // Header
              _buildHeader(theme),

              // Step indicator
              _buildStepIndicator(),

              // Content area
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Color(0xFF4A9EFF)),
                            SizedBox(height: 16),
                            Text(
                              'Processing...',
                              style: TextStyle(color: Colors.white54),
                            ),
                          ],
                        ),
                      )
                    : ClipRect(
                        child: _buildStepContent(),
                      ),
              ),

              // Navigation
              _buildNavigation(),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF121216),
        border: Border(
          bottom: BorderSide(color: Color(0xFF2a2a30), width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF4A9EFF).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.upload_file, color: Color(0xFF4A9EFF), size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Import Game Design Document',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _steps[_currentStep].subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          ),
          // Quick stats when GDD is loaded
          if (_importResult case GddImportResult(:final gdd, :final generatedStages)) ...[
            _buildQuickBadge(
              '${gdd.symbols.length}',
              'Symbols',
              const Color(0xFF9370DB),
            ),
            const SizedBox(width: 8),
            _buildQuickBadge(
              '${gdd.features.length}',
              'Features',
              const Color(0xFF40FF90),
            ),
            const SizedBox(width: 8),
            _buildQuickBadge(
              '${generatedStages.length}',
              'Stages',
              const Color(0xFF4A9EFF),
            ),
            const SizedBox(width: 16),
          ],
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Cancel',
          ),
        ],
      ),
    );
  }

  Widget _buildQuickBadge(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: color.withOpacity(0.7),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP INDICATOR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStepIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      child: Row(
        children: List.generate(_steps.length * 2 - 1, (index) {
          if (index.isOdd) {
            // Connector line
            final stepIndex = index ~/ 2;
            final isComplete = _currentStep > stepIndex;
            return Expanded(
              child: Container(
                height: 3,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: isComplete ? const Color(0xFF4A9EFF) : const Color(0xFF2a2a30),
                ),
              ),
            );
          } else {
            // Step indicator
            final stepIndex = index ~/ 2;
            final step = _steps[stepIndex];
            final isActive = stepIndex == _currentStep;
            final isComplete = stepIndex < _currentStep;

            return _buildStepIndicatorItem(step, stepIndex, isActive, isComplete);
          }
        }),
      ),
    );
  }

  Widget _buildStepIndicatorItem(
    _StepConfig step,
    int index,
    bool isActive,
    bool isComplete,
  ) {
    final color = isComplete
        ? const Color(0xFF4A9EFF)
        : isActive
            ? const Color(0xFF4A9EFF)
            : Colors.white24;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: isActive ? 48 : 40,
          height: isActive ? 48 : 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isComplete
                ? const Color(0xFF4A9EFF)
                : isActive
                    ? const Color(0xFF4A9EFF).withOpacity(0.2)
                    : const Color(0xFF2a2a30),
            border: Border.all(
              color: color,
              width: isActive ? 3 : 2,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: const Color(0xFF4A9EFF).withOpacity(0.3),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: isComplete
                ? const Icon(Icons.check, size: 20, color: Colors.white)
                : Icon(
                    step.icon,
                    size: isActive ? 22 : 18,
                    color: isActive ? const Color(0xFF4A9EFF) : Colors.white38,
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          step.name,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.white54,
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP CONTENT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildInputStep();
      case 1:
        return _buildPreviewStep();
      case 2:
        return _buildStagesStep();
      case 3:
        return _buildConfirmStep();
      default:
        return const SizedBox();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 1: INPUT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildInputStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Instructions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF4A9EFF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF4A9EFF).withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Color(0xFF4A9EFF), size: 24),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Import your Game Design Document',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Paste JSON directly, load from a .json file, or extract from a PDF document. '
                        'The wizard will auto-detect symbols, features, and generate audio stages.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Action buttons
          Row(
            children: [
              _buildActionButton(
                icon: Icons.folder_open,
                label: 'Load File',
                subtitle: 'JSON or PDF',
                onTap: _loadFromFile,
              ),
              const SizedBox(width: 12),
              _buildActionButton(
                icon: Icons.paste,
                label: 'Paste',
                subtitle: 'From clipboard',
                onTap: _pasteFromClipboard,
              ),
              const SizedBox(width: 12),
              _buildActionButton(
                icon: Icons.science,
                label: 'Sample',
                subtitle: 'Test GDD',
                onTap: _loadSampleGdd,
                color: const Color(0xFF40FF90),
              ),
              const Spacer(),
              if (_jsonController.text.isNotEmpty)
                TextButton.icon(
                  onPressed: () {
                    _jsonController.clear();
                    setState(() {
                      _error = null;
                      _importResult = null;
                    });
                  },
                  icon: const Icon(Icons.clear, size: 18),
                  label: const Text('Clear'),
                  style: TextButton.styleFrom(foregroundColor: Colors.white54),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // JSON input
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF121216),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _error != null
                      ? Colors.red.withOpacity(0.5)
                      : const Color(0xFF2a2a30),
                ),
              ),
              child: Column(
                children: [
                  // Input header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFF2a2a30)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isPdfImport ? Icons.picture_as_pdf : Icons.code,
                          size: 16,
                          color: _isPdfImport ? Colors.red : const Color(0xFF4A9EFF),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isPdfImport ? 'Extracted PDF Text' : 'JSON Input',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        if (_jsonController.text.isNotEmpty)
                          Text(
                            '${_jsonController.text.length} chars',
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Text field
                  Expanded(
                    child: TextField(
                      controller: _jsonController,
                      maxLines: null,
                      expands: true,
                      style: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 13,
                        color: Colors.white,
                        height: 1.5,
                      ),
                      decoration: InputDecoration(
                        hintText: '''{
  "name": "My Slot Game",
  "version": "1.0",
  "grid": {
    "rows": 3,
    "columns": 5,
    "mechanic": "ways"
  },
  "symbols": [...],
  "features": [...],
  "math": {...}
}''',
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.2),
                          fontFamily: 'JetBrains Mono',
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Error display
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Colors.red),
                    onPressed: () => setState(() => _error = null),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    Color color = const Color(0xFF4A9EFF),
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: color.withOpacity(0.7),
                      fontSize: 11,
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

  Future<void> _loadFromFile() async {
    final result = await SafeFilePicker.pickFiles(context,
      type: FileType.custom,
      allowedExtensions: ['json', 'pdf'],
    );

    if (result != null && result.files.single.path != null) {
      setState(() => _isLoading = true);
      try {
        final filePath = result.files.single.path!;
        final extension = filePath.toLowerCase().split('.').last;

        if (extension == 'pdf') {
          final file = File(filePath);
          final bytes = await file.readAsBytes();
          final document = PdfDocument(inputBytes: bytes);

          final textExtractor = PdfTextExtractor(document);
          final extractedText = textExtractor.extractText();
          document.dispose();

          _jsonController.text = extractedText;
          setState(() {
            _error = null;
            _isPdfImport = true;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      'PDF extracted: ${extractedText.length} characters. Click NEXT to parse.',
                    ),
                  ],
                ),
                backgroundColor: const Color(0xFF40FF90),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        } else {
          final bytes = result.files.single.bytes ?? await File(filePath).readAsBytes();
          _jsonController.text = utf8.decode(bytes);
          setState(() {
            _error = null;
            _isPdfImport = false;
          });
        }
      } catch (e) {
        setState(() => _error = 'Failed to read file: $e');
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _jsonController.text = data!.text!;
      setState(() {
        _error = null;
        _isPdfImport = false;
      });
    }
  }

  void _loadSampleGdd() {
    _jsonController.text = GddImportService.instance.createSampleGddJson();
    setState(() {
      _error = null;
      _isPdfImport = false;
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 2: PREVIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPreviewStep() {
    final gdd = _importResult?.gdd;
    if (gdd == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber, size: 48, color: Colors.orange),
            SizedBox(height: 16),
            Text('No GDD loaded', style: TextStyle(color: Colors.white54, fontSize: 16)),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Tab bar
        Container(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFF2a2a30)),
            ),
          ),
          child: TabBar(
            controller: _previewTabController,
            indicatorColor: const Color(0xFF4A9EFF),
            indicatorWeight: 3,
            labelColor: const Color(0xFF4A9EFF),
            unselectedLabelColor: Colors.white54,
            tabs: const [
              Tab(icon: Icon(Icons.dashboard, size: 20), text: 'Overview'),
              Tab(icon: Icon(Icons.casino, size: 20), text: 'Symbols'),
              Tab(icon: Icon(Icons.extension, size: 20), text: 'Features'),
              Tab(icon: Icon(Icons.calculate, size: 20), text: 'Math'),
            ],
          ),
        ),
        // Tab content
        Expanded(
          child: TabBarView(
            controller: _previewTabController,
            children: [
              _buildOverviewTab(gdd),
              _buildSymbolsTab(gdd),
              _buildFeaturesTab(gdd),
              _buildMathTab(gdd),
            ],
          ),
        ),
        // Warnings
        if (_importResult?.hasWarnings ?? false)
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Warnings',
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...(_importResult!.warnings.map((w) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '• $w',
                        style: const TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ))),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildOverviewTab(GameDesignDocument gdd) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Top row: Game info + Grid
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Game info
              Expanded(
                child: _buildInfoCard(
                  'Game Information',
                  Icons.games,
                  const Color(0xFF4A9EFF),
                  [
                    _buildInfoRow('Name', gdd.name),
                    _buildInfoRow('Version', gdd.version),
                    if (gdd.description != null) _buildInfoRow('Description', gdd.description!),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Grid visualization
              _buildGridVisualization(gdd),
            ],
          ),
          const SizedBox(height: 16),
          // Bottom row: Math + Summary
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Math summary
              Expanded(
                child: _buildInfoCard(
                  'Math Model',
                  Icons.calculate,
                  const Color(0xFF40FF90),
                  [
                    _buildInfoRow('RTP', '${(gdd.math.rtp * 100).toStringAsFixed(2)}%'),
                    _buildInfoRow('Volatility', gdd.math.volatility),
                    _buildInfoRow('Hit Frequency', '${(gdd.math.hitFrequency * 100).toStringAsFixed(1)}%'),
                    _buildInfoRow('Max Win', '${_computeMaxWin(gdd.math.winTiers).toStringAsFixed(0)}x'),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Content summary
              Expanded(
                child: _buildInfoCard(
                  'Content Summary',
                  Icons.summarize,
                  const Color(0xFFFF9040),
                  [
                    _buildInfoRow('Symbols', '${gdd.symbols.length}'),
                    _buildInfoRow('Features', '${gdd.features.length}'),
                    _buildInfoRow('Win Tiers', '${gdd.math.winTiers.length}'),
                    _buildInfoRow('Stages', '${_importResult?.generatedStages.length ?? 0}'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, IconData icon, Color color, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121216),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridVisualization(GameDesignDocument gdd) {
    final rows = gdd.grid.rows;
    final cols = gdd.grid.columns;

    return Container(
      width: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121216),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF9370DB).withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.grid_3x3, size: 18, color: Color(0xFF9370DB)),
              const SizedBox(width: 8),
              Text(
                'Grid: $cols x $rows (${gdd.grid.mechanic})',
                style: const TextStyle(
                  color: Color(0xFF9370DB),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Grid preview
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0a0a0c),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: List.generate(
                rows,
                (row) => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    cols,
                    (col) => Container(
                      width: 36,
                      height: 36,
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1a1a20),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: const Color(0xFF9370DB).withOpacity(0.3),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          _getPreviewEmoji(gdd, row, col),
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (gdd.grid.paylines != null) ...[
            const SizedBox(height: 12),
            Text(
              '${gdd.grid.paylines} Paylines',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
          if (gdd.grid.ways != null) ...[
            const SizedBox(height: 12),
            Text(
              '${gdd.grid.ways} Ways',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  String _getPreviewEmoji(GameDesignDocument gdd, int row, int col) {
    final symbolIndex = (row * gdd.grid.columns + col) % gdd.symbols.length;
    final symbol = gdd.symbols[symbolIndex];
    return _getEmojiForSymbol(symbol.name, symbol.tier);
  }

  Widget _buildSymbolsTab(GameDesignDocument gdd) {
    final groupedSymbols = <SymbolTier, List<GddSymbol>>{};
    for (final tier in SymbolTier.values) {
      final symbols = gdd.symbolsByTier(tier);
      if (symbols.isNotEmpty) {
        groupedSymbols[tier] = symbols;
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: groupedSymbols.length,
      itemBuilder: (context, index) {
        final tier = groupedSymbols.keys.elementAt(index);
        final symbols = groupedSymbols[tier]!;
        final tierColor = _getTierColor(tier);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF121216),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tierColor.withOpacity(0.3)),
          ),
          child: ExpansionTile(
            initiallyExpanded: tier == SymbolTier.premium || tier == SymbolTier.high,
            leading: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: tierColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '${symbols.length}',
                  style: TextStyle(
                    color: tierColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            title: Text(
              tier.label,
              style: TextStyle(
                color: tierColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            iconColor: tierColor,
            collapsedIconColor: tierColor.withOpacity(0.5),
            children: [
              const Divider(color: Color(0xFF2a2a30), height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: symbols.map((symbol) => _buildSymbolRow(symbol)).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSymbolRow(GddSymbol symbol) {
    final tierColor = _getTierColor(symbol.tier);
    final emoji = _getEmojiForSymbol(symbol.name, symbol.tier);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0a0a0c),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Emoji
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tierColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(width: 12),
          // Name & ID
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  symbol.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  symbol.id,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          // Tags
          if (symbol.isWild)
            _buildSymbolTag('WILD', Colors.yellow),
          if (symbol.isScatter)
            _buildSymbolTag('SCATTER', Colors.purple),
          if (symbol.isBonus)
            _buildSymbolTag('BONUS', Colors.green),
          // Payout preview
          if (symbol.payouts.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1a1a20),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${symbol.payouts.entries.first.key}x → ${symbol.payouts.entries.first.value}',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSymbolTag(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildFeaturesTab(GameDesignDocument gdd) {
    if (gdd.features.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.extension_off, size: 48, color: Colors.white24),
            SizedBox(height: 16),
            Text('No features defined', style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 350,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.4,
      ),
      itemCount: gdd.features.length,
      itemBuilder: (context, index) {
        final feature = gdd.features[index];
        final color = _getFeatureColor(feature.type);
        final icon = _getFeatureIcon(feature.type);

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF121216),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          feature.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          feature.type.label,
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (feature.triggerCondition != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Trigger: ${feature.triggerCondition}',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const Spacer(),
              // Feature stats from actual fields
              if (feature.initialSpins != null || feature.retriggerable != null || feature.stages.isNotEmpty) ...[
                const Divider(color: Color(0xFF2a2a30)),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (feature.initialSpins != null)
                      _buildFeatureParam('Spins', '${feature.initialSpins}'),
                    if (feature.retriggerable != null)
                      _buildFeatureParam('Retrigger', '${feature.retriggerable}x'),
                    if (feature.stages.isNotEmpty)
                      _buildFeatureParam('Stages', '${feature.stages.length}'),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildMathTab(GameDesignDocument gdd) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Core stats
          Row(
            children: [
              Expanded(
                child: _buildMathStatCard(
                  'RTP',
                  '${(gdd.math.rtp * 100).toStringAsFixed(2)}%',
                  Icons.percent,
                  const Color(0xFF4A9EFF),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMathStatCard(
                  'Volatility',
                  gdd.math.volatility,
                  Icons.trending_up,
                  _getVolatilityColor(gdd.math.volatility),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMathStatCard(
                  'Hit Frequency',
                  '${(gdd.math.hitFrequency * 100).toStringAsFixed(1)}%',
                  Icons.casino,
                  const Color(0xFF40FF90),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMathStatCard(
                  'Max Win',
                  '${_computeMaxWin(gdd.math.winTiers).toStringAsFixed(0)}x',
                  Icons.emoji_events,
                  const Color(0xFFFFD700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Win tiers
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF121216),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.leaderboard, size: 18, color: Color(0xFFFFD700)),
                    SizedBox(width: 8),
                    Text(
                      'Win Tiers',
                      style: TextStyle(
                        color: Color(0xFFFFD700),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...gdd.math.winTiers.map((tier) => _buildWinTierRow(tier)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMathStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121216),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWinTierRow(GddWinTier tier) {
    final color = _getWinTierColor(tier.name);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tier.name,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '${tier.minMultiplier.toStringAsFixed(1)}x - ${tier.maxMultiplier.toStringAsFixed(1)}x',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 3: STAGES
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStagesStep() {
    final stages = _importResult?.generatedStages ?? [];
    if (stages.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.layers, size: 48, color: Colors.white24),
            SizedBox(height: 16),
            Text('No stages generated', style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    // Group stages by category
    final groupedStages = <String, List<String>>{};
    for (final stage in stages) {
      final category = _getCategoryForStage(stage);
      groupedStages.putIfAbsent(category, () => []).add(stage);
    }

    return Column(
      children: [
        // Summary bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          color: const Color(0xFF121216),
          child: Row(
            children: [
              const Icon(Icons.layers, color: Color(0xFF40FF90), size: 22),
              const SizedBox(width: 12),
              Text(
                '${stages.length} stages in ${groupedStages.length} categories',
                style: const TextStyle(
                  color: Color(0xFF40FF90),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    for (final cat in groupedStages.keys) {
                      _expandedCategories[cat] = true;
                    }
                  });
                },
                icon: const Icon(Icons.unfold_more, size: 18),
                label: const Text('Expand All'),
                style: TextButton.styleFrom(foregroundColor: Colors.white54),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _expandedCategories.clear();
                  });
                },
                icon: const Icon(Icons.unfold_less, size: 18),
                label: const Text('Collapse All'),
                style: TextButton.styleFrom(foregroundColor: Colors.white54),
              ),
            ],
          ),
        ),
        // Stage list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: groupedStages.length,
            itemBuilder: (context, index) {
              final category = groupedStages.keys.elementAt(index);
              final categoryStages = groupedStages[category]!;
              final color = _getColorForCategory(category);
              final isExpanded = _expandedCategories[category] ?? (index < 3);

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF121216),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: ExpansionTile(
                  key: Key('stage_cat_$category'),
                  initiallyExpanded: isExpanded,
                  onExpansionChanged: (expanded) {
                    setState(() => _expandedCategories[category] = expanded);
                  },
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '${categoryStages.length}',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  title: Text(
                    category,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  iconColor: color,
                  collapsedIconColor: color.withOpacity(0.5),
                  children: [
                    const Divider(color: Color(0xFF2a2a30), height: 1),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: categoryStages.map((stage) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: color.withOpacity(0.2)),
                            ),
                            child: Text(
                              stage,
                              style: const TextStyle(
                                fontFamily: 'JetBrains Mono',
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 4: CONFIRM
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildConfirmStep() {
    final gdd = _importResult?.gdd;
    final stages = _importResult?.generatedStages ?? [];
    final symbols = _importResult?.generatedSymbols ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Success icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF40FF90).withOpacity(0.15),
            ),
            child: const Icon(
              Icons.check_circle,
              size: 48,
              color: Color(0xFF40FF90),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Ready to Import',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Review the summary below and click Import to apply',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 32),

          // Summary cards
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Game config
              Expanded(
                child: _buildConfirmCard(
                  'Game Configuration',
                  Icons.games,
                  const Color(0xFF4A9EFF),
                  [
                    _buildConfirmRow('Game Name', gdd?.name ?? 'Unknown'),
                    _buildConfirmRow('Grid Size', '${gdd?.grid.columns ?? 5} x ${gdd?.grid.rows ?? 3}'),
                    _buildConfirmRow('Mechanic', gdd?.grid.mechanic ?? 'ways'),
                    _buildConfirmRow('RTP', '${((gdd?.math.rtp ?? 0.96) * 100).toStringAsFixed(2)}%'),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Content
              Expanded(
                child: _buildConfirmCard(
                  'Content to Import',
                  Icons.inventory_2,
                  const Color(0xFF40FF90),
                  [
                    _buildConfirmRow('GDD Symbols', '${gdd?.symbols.length ?? 0}'),
                    _buildConfirmRow('Audio Symbols', '${symbols.length} (auto-generated)'),
                    _buildConfirmRow('Features', '${gdd?.features.length ?? 0}'),
                    _buildConfirmRow('Audio Stages', '${stages.length}'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Info box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF4A9EFF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF4A9EFF).withOpacity(0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: Color(0xFF4A9EFF), size: 24),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'What will happen:',
                        style: TextStyle(
                          color: Color(0xFF4A9EFF),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildCheckItem('Symbols will be added to your SlotLab project'),
                      _buildCheckItem('Audio stages will be registered with StageConfigurationService'),
                      _buildCheckItem('You can then create audio events for each stage'),
                      _buildCheckItem('GDD data will be stored for reference'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmCard(
    String title,
    IconData icon,
    Color color,
    List<Widget> children,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF121216),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildConfirmRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.check, size: 16, color: Color(0xFF40FF90)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•', style: TextStyle(color: Color(0xFF4A9EFF))),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NAVIGATION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildNavigation() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF121216),
        border: Border(
          top: BorderSide(color: Color(0xFF2a2a30), width: 1),
        ),
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            OutlinedButton.icon(
              onPressed: () => setState(() => _currentStep--),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Color(0xFF2a2a30)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
            ),
          const Spacer(),
          // Step dots
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(_steps.length, (index) {
              final isActive = index == _currentStep;
              return Container(
                width: isActive ? 24 : 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: isActive
                      ? const Color(0xFF4A9EFF)
                      : index < _currentStep
                          ? const Color(0xFF4A9EFF).withOpacity(0.5)
                          : const Color(0xFF2a2a30),
                ),
              );
            }),
          ),
          const Spacer(),
          if (_currentStep < _steps.length - 1)
            ElevatedButton.icon(
              onPressed: _canProceed ? _nextStep : null,
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text('Next'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A9EFF),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF2a2a30),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: _finishImport,
              icon: const Icon(Icons.check_circle, size: 18),
              label: const Text('Import'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF40FF90),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              ),
            ),
        ],
      ),
    );
  }

  bool get _canProceed {
    switch (_currentStep) {
      case 0:
        return _jsonController.text.trim().isNotEmpty;
      case 1:
      case 2:
        return _importResult != null && !_importResult!.hasErrors;
      default:
        return true;
    }
  }

  void _nextStep() {
    if (_currentStep == 0) {
      setState(() => _isLoading = true);
      // Parse JSON
      final result = GddImportService.instance.importFromJson(_jsonController.text);
      setState(() => _isLoading = false);

      if (result == null || result.hasErrors) {
        setState(() {
          _error = result?.errors.join('\n') ?? 'Failed to parse GDD';
        });
        return;
      }
      setState(() {
        _importResult = result;
        _error = null;
      });
    }

    setState(() => _currentStep++);
  }

  void _finishImport() {
    if (_importResult == null) return;

    setState(() => _isLoading = true);

    // Import symbols into SlotLabProjectProvider
    if (_importResult!.generatedSymbols.isNotEmpty) {
      try {
        final projectProvider = sl<SlotLabProjectProvider>();
        projectProvider.replaceSymbols(_importResult!.generatedSymbols);
      } catch (e) { /* ignored */ }
    }

    // Register custom stages with StageConfigurationService
    final service = StageConfigurationService.instance;
    for (final stageName in _importResult!.generatedStages) {
      if (service.getStage(stageName) != null) continue;

      final category = _inferCategory(stageName);
      final priority = service.getPriority(stageName);
      final bus = service.getBus(stageName);

      service.registerCustomStage(StageDefinition(
        name: stageName,
        category: category,
        priority: priority,
        bus: bus,
        spatialIntent: service.getSpatialIntent(stageName),
      ));
    }

    setState(() => _isLoading = false);
    Navigator.of(context).pop(_importResult);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  double _computeMaxWin(List<GddWinTier> winTiers) {
    if (winTiers.isEmpty) return 0.0;
    return winTiers.map((t) => t.maxMultiplier).reduce((a, b) => a > b ? a : b);
  }

  Widget _buildFeatureParam(String key, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF0a0a0c),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$key: $value',
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 10,
        ),
      ),
    );
  }

  String _getCategoryForStage(String stage) {
    if (stage.startsWith('SPIN_') || stage.startsWith('REEL_')) return 'Spin & Reels';
    if (stage.startsWith('WIN_') || stage.startsWith('ROLLUP_')) return 'Wins';
    if (stage.startsWith('FS_') || stage.startsWith('FREESPIN_')) return 'Free Spins';
    if (stage.startsWith('BONUS_')) return 'Bonus';
    if (stage.startsWith('HOLD_') || stage.startsWith('RESPIN_')) return 'Hold & Respin';
    if (stage.startsWith('CASCADE_') || stage.startsWith('TUMBLE_')) return 'Cascade';
    if (stage.startsWith('JACKPOT_')) return 'Jackpot';
    if (stage.startsWith('GAMBLE_')) return 'Gamble';
    if (stage.startsWith('WILD_')) return 'Wild';
    if (stage.startsWith('SCATTER_') || stage.startsWith('ANTICIPATION_')) return 'Scatter';
    if (stage.startsWith('SYMBOL_')) return 'Symbol';
    if (stage.startsWith('MULT_')) return 'Multiplier';
    if (stage.startsWith('MUSIC_') || stage.startsWith('AMBIENT_')) return 'Music';
    if (stage.startsWith('UI_')) return 'UI';
    return 'Custom';
  }

  Color _getColorForCategory(String category) {
    return switch (category) {
      'Spin & Reels' => const Color(0xFF4A9EFF),
      'Wins' => const Color(0xFFFFD700),
      'Free Spins' => const Color(0xFF40FF90),
      'Bonus' => const Color(0xFF9370DB),
      'Hold & Respin' => const Color(0xFFFF9040),
      'Cascade' => const Color(0xFF40C8FF),
      'Jackpot' => const Color(0xFFFF4040),
      'Gamble' => const Color(0xFFE040FB),
      'Wild' => const Color(0xFFFFB6C1),
      'Scatter' => const Color(0xFFFFB6C1),
      'Symbol' => const Color(0xFF888888),
      'Multiplier' => const Color(0xFFFF9040),
      'Music' => const Color(0xFF40C8FF),
      'UI' => const Color(0xFF808080),
      _ => Colors.white54,
    };
  }

  Color _getTierColor(SymbolTier tier) {
    return switch (tier) {
      SymbolTier.premium => const Color(0xFFFFD700),
      SymbolTier.high => const Color(0xFFFF69B4),
      SymbolTier.mid => const Color(0xFF40FF90),
      SymbolTier.low => const Color(0xFF4A9EFF),
      SymbolTier.special => const Color(0xFFE040FB),
      SymbolTier.wild => const Color(0xFFE040FB),
      SymbolTier.scatter => const Color(0xFFFF9040),
      SymbolTier.bonus => const Color(0xFF40C8FF),
    };
  }

  Color _getFeatureColor(GddFeatureType type) {
    return switch (type) {
      GddFeatureType.freeSpins => const Color(0xFF40FF90),
      GddFeatureType.bonus => const Color(0xFF9370DB),
      GddFeatureType.multiplier => const Color(0xFFFF9040),
      GddFeatureType.expanding => const Color(0xFFE040FB),
      GddFeatureType.sticky => const Color(0xFFFFB6C1),
      GddFeatureType.cascade => const Color(0xFF40C8FF),
      GddFeatureType.holdAndSpin => const Color(0xFFFF9040),
      GddFeatureType.jackpot => const Color(0xFFFFD700),
      GddFeatureType.gamble => const Color(0xFFE040FB),
      GddFeatureType.random => Colors.white54,
    };
  }

  IconData _getFeatureIcon(GddFeatureType type) {
    return switch (type) {
      GddFeatureType.freeSpins => Icons.autorenew,
      GddFeatureType.bonus => Icons.card_giftcard,
      GddFeatureType.multiplier => Icons.close,
      GddFeatureType.expanding => Icons.star,
      GddFeatureType.sticky => Icons.push_pin,
      GddFeatureType.cascade => Icons.waterfall_chart,
      GddFeatureType.holdAndSpin => Icons.replay,
      GddFeatureType.jackpot => Icons.emoji_events,
      GddFeatureType.gamble => Icons.casino,
      GddFeatureType.random => Icons.shuffle,
    };
  }

  Color _getVolatilityColor(String volatility) {
    final lower = volatility.toLowerCase();
    if (lower.contains('extreme') || lower.contains('very high')) {
      return const Color(0xFFFF4040);
    } else if (lower.contains('high')) {
      return const Color(0xFFFF9040);
    } else if (lower.contains('medium') || lower.contains('med')) {
      return const Color(0xFFFFD700);
    } else {
      return const Color(0xFF40FF90);
    }
  }

  Color _getWinTierColor(String tierName) {
    final lower = tierName.toLowerCase();
    if (lower.contains('ultra') || lower.contains('jackpot')) {
      return const Color(0xFFFFD700);
    } else if (lower.contains('epic') || lower.contains('mega')) {
      return const Color(0xFFFF4040);
    } else if (lower.contains('super') || lower.contains('big')) {
      return const Color(0xFFFF9040);
    } else if (lower.contains('medium') || lower.contains('nice')) {
      return const Color(0xFF40FF90);
    } else {
      return const Color(0xFF4A9EFF);
    }
  }

  String _getEmojiForSymbol(String name, SymbolTier tier) {
    final lower = name.toLowerCase();

    // Theme-specific
    if (lower.contains('zeus')) return '⚡';
    if (lower.contains('hades')) return '💀';
    if (lower.contains('poseidon')) return '🔱';
    if (lower.contains('athena')) return '🦉';
    if (lower.contains('medusa')) return '🐍';
    if (lower.contains('dragon')) return '🐉';
    if (lower.contains('tiger')) return '🐅';
    if (lower.contains('phoenix')) return '🦅';
    if (lower.contains('lion')) return '🦁';
    if (lower.contains('wolf')) return '🐺';
    if (lower.contains('eagle')) return '🦅';
    if (lower.contains('ra') || lower.contains('sun')) return '☀️';
    if (lower.contains('anubis')) return '🐕';
    if (lower.contains('horus')) return '🦅';
    if (lower.contains('scarab')) return '🪲';
    if (lower.contains('cleopatra')) return '👑';
    if (lower.contains('pharaoh')) return '🤴';
    if (lower.contains('pyramid')) return '📐';

    // Standard symbols
    if (lower.contains('wild')) return '⭐';
    if (lower.contains('scatter')) return '💎';
    if (lower.contains('bonus')) return '🎁';
    if (lower.contains('free') || lower.contains('spin')) return '🎰';
    if (lower.contains('gold') || lower.contains('coin')) return '🪙';
    if (lower.contains('diamond')) return '💎';
    if (lower.contains('crown')) return '👑';
    if (lower.contains('chest') || lower.contains('treasure')) return '📦';
    if (lower.contains('book')) return '📕';
    if (lower.contains('bell')) return '🔔';
    if (lower.contains('seven') || lower.contains('7')) return '7️⃣';
    if (lower.contains('bar')) return '🍫';
    if (lower.contains('cherry')) return '🍒';
    if (lower.contains('lemon')) return '🍋';
    if (lower.contains('orange')) return '🍊';
    if (lower.contains('plum') || lower.contains('grape')) return '🍇';
    if (lower.contains('watermelon') || lower.contains('melon')) return '🍉';
    if (lower.contains('apple')) return '🍎';
    if (lower.contains('banana')) return '🍌';
    if (lower.contains('strawberry')) return '🍓';

    // Card symbols
    if (lower.contains('ace') || lower == 'a') return '🂡';
    if (lower.contains('king') || lower == 'k') return '🂮';
    if (lower.contains('queen') || lower == 'q') return '🂭';
    if (lower.contains('jack') || lower == 'j') return '🂫';
    if (lower.contains('10') || lower.contains('ten')) return '🔟';
    if (lower.contains('9') || lower.contains('nine')) return '9️⃣';

    // Default by tier
    return switch (tier) {
      SymbolTier.premium => '💎',
      SymbolTier.high => '👑',
      SymbolTier.mid => '🎯',
      SymbolTier.low => '🃏',
      SymbolTier.special => '✨',
      SymbolTier.wild => '⭐',
      SymbolTier.scatter => '💠',
      SymbolTier.bonus => '🎁',
    };
  }

  StageCategory _inferCategory(String stage) {
    if (stage.startsWith('SPIN_') || stage.startsWith('REEL_')) return StageCategory.spin;
    if (stage.startsWith('WIN_') || stage.startsWith('ROLLUP_')) return StageCategory.win;
    if (stage.startsWith('FS_') || stage.startsWith('FREESPIN_')) return StageCategory.feature;
    if (stage.startsWith('BONUS_')) return StageCategory.feature;
    if (stage.startsWith('HOLD_') || stage.startsWith('RESPIN_')) return StageCategory.hold;
    if (stage.startsWith('CASCADE_') || stage.startsWith('TUMBLE_')) return StageCategory.cascade;
    if (stage.startsWith('JACKPOT_')) return StageCategory.jackpot;
    if (stage.startsWith('GAMBLE_')) return StageCategory.gamble;
    if (stage.startsWith('WILD_') || stage.startsWith('SCATTER_') || stage.startsWith('SYMBOL_')) {
      return StageCategory.symbol;
    }
    if (stage.startsWith('MUSIC_') || stage.startsWith('AMBIENT_')) return StageCategory.music;
    if (stage.startsWith('UI_')) return StageCategory.ui;
    return StageCategory.custom;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STEP CONFIG
// ═══════════════════════════════════════════════════════════════════════════

class _StepConfig {
  final String name;
  final IconData icon;
  final String subtitle;

  const _StepConfig(this.name, this.icon, this.subtitle);
}

// Extensions SymbolTierExtension and GddFeatureTypeExtension are defined in gdd_import_service.dart
