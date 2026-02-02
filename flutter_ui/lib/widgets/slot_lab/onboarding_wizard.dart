import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Onboarding wizard step definition
class OnboardingStep {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget Function(OnboardingWizardState state) contentBuilder;
  final bool canSkip;

  const OnboardingStep({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.contentBuilder,
    this.canSkip = true,
  });
}

/// Result of completing the onboarding wizard
class OnboardingResult {
  final bool completed;
  final bool usedTemplate;
  final String? templateId;
  final bool importedGdd;
  final int symbolsAssigned;
  final int spinsCompleted;

  const OnboardingResult({
    required this.completed,
    this.usedTemplate = false,
    this.templateId,
    this.importedGdd = false,
    this.symbolsAssigned = 0,
    this.spinsCompleted = 0,
  });
}

/// 5-step onboarding wizard for SlotLab
class OnboardingWizard extends StatefulWidget {
  final VoidCallback? onComplete;
  final VoidCallback? onSkip;
  final void Function(String templateId)? onTemplateSelected;
  final VoidCallback? onImportGdd;
  final void Function(String symbolId, String audioPath)? onSymbolAudioAssigned;
  final VoidCallback? onTestSpin;

  const OnboardingWizard({
    super.key,
    this.onComplete,
    this.onSkip,
    this.onTemplateSelected,
    this.onImportGdd,
    this.onSymbolAudioAssigned,
    this.onTestSpin,
  });

  /// Check if user has completed onboarding
  static Future<bool> hasCompletedOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('slotlab_onboarding_completed') ?? false;
  }

  /// Mark onboarding as completed
  static Future<void> markOnboardingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('slotlab_onboarding_completed', true);
  }

  /// Reset onboarding (for testing)
  static Future<void> resetOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('slotlab_onboarding_completed');
  }

  /// Show onboarding wizard as modal
  static Future<OnboardingResult?> show(
    BuildContext context, {
    VoidCallback? onComplete,
    VoidCallback? onSkip,
    void Function(String templateId)? onTemplateSelected,
    VoidCallback? onImportGdd,
    void Function(String symbolId, String audioPath)? onSymbolAudioAssigned,
    VoidCallback? onTestSpin,
  }) async {
    return showDialog<OnboardingResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: OnboardingWizard(
          onComplete: onComplete,
          onSkip: onSkip,
          onTemplateSelected: onTemplateSelected,
          onImportGdd: onImportGdd,
          onSymbolAudioAssigned: onSymbolAudioAssigned,
          onTestSpin: onTestSpin,
        ),
      ),
    );
  }

  @override
  State<OnboardingWizard> createState() => OnboardingWizardState();
}

class OnboardingWizardState extends State<OnboardingWizard>
    with TickerProviderStateMixin {
  int _currentStep = 0;
  late final AnimationController _slideController;
  late final AnimationController _fadeController;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  // Step completion tracking
  bool _usedTemplate = false;
  String? _selectedTemplateId;
  bool _importedGdd = false;
  int _symbolsAssigned = 0;
  int _spinsCompleted = 0;

  // Demo state
  final List<_DemoAudioFile> _demoAudioFiles = [
    _DemoAudioFile('spin_start.wav', 'Spin Start', Icons.play_circle),
    _DemoAudioFile('reel_stop.wav', 'Reel Stop', Icons.stop_circle),
    _DemoAudioFile('win_small.wav', 'Small Win', Icons.stars),
    _DemoAudioFile('win_big.wav', 'Big Win', Icons.celebration),
    _DemoAudioFile('scatter_land.wav', 'Scatter Land', Icons.auto_awesome),
  ];

  final List<_DemoSymbol> _demoSymbols = [
    _DemoSymbol('HP1', 'High Pay 1', Colors.purple),
    _DemoSymbol('HP2', 'High Pay 2', Colors.blue),
    _DemoSymbol('WILD', 'Wild', Colors.orange),
    _DemoSymbol('SCATTER', 'Scatter', Colors.green),
  ];

  String? _draggedAudio;
  final Map<String, String> _assignedAudio = {};

  late final List<OnboardingStep> _steps;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_fadeController);

    _steps = [
      OnboardingStep(
        title: 'Welcome to SlotLab',
        subtitle: 'Professional slot audio middleware in 5 minutes',
        icon: Icons.waving_hand,
        contentBuilder: _buildWelcomeStep,
        canSkip: false,
      ),
      OnboardingStep(
        title: 'Setup Your Game',
        subtitle: 'Import GDD or choose a template',
        icon: Icons.settings_applications,
        contentBuilder: _buildSetupStep,
      ),
      OnboardingStep(
        title: 'Assign Audio',
        subtitle: 'Drag audio files to symbols',
        icon: Icons.music_note,
        contentBuilder: _buildAudioAssignStep,
      ),
      OnboardingStep(
        title: 'Test Your Work',
        subtitle: 'Run test spins with forced outcomes',
        icon: Icons.play_arrow,
        contentBuilder: _buildTestStep,
      ),
      OnboardingStep(
        title: 'Export & Ship',
        subtitle: 'Deploy to Unity, Unreal, or Web',
        icon: Icons.rocket_launch,
        contentBuilder: _buildExportStep,
      ),
    ];

    _slideController.forward();
    _fadeController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < _steps.length - 1) {
      _slideController.reverse().then((_) {
        setState(() => _currentStep++);
        _slideController.forward();
      });
    } else {
      _completeOnboarding();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _slideController.reverse().then((_) {
        setState(() => _currentStep--);
        _slideController.forward();
      });
    }
  }

  void _skipOnboarding() {
    widget.onSkip?.call();
    Navigator.of(context).pop(const OnboardingResult(completed: false));
  }

  Future<void> _completeOnboarding() async {
    await OnboardingWizard.markOnboardingCompleted();
    widget.onComplete?.call();
    if (mounted) {
      Navigator.of(context).pop(OnboardingResult(
        completed: true,
        usedTemplate: _usedTemplate,
        templateId: _selectedTemplateId,
        importedGdd: _importedGdd,
        symbolsAssigned: _symbolsAssigned,
        spinsCompleted: _spinsCompleted,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_currentStep];

    return Container(
      width: 720,
      height: 560,
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF4a9eff).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(step),

          // Progress indicator
          _buildProgressIndicator(),

          // Content
          Expanded(
            child: SlideTransition(
              position: _slideAnimation,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: step.contentBuilder(this),
                ),
              ),
            ),
          ),

          // Footer
          _buildFooter(step),
        ],
      ),
    );
  }

  Widget _buildHeader(OnboardingStep step) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFF2a2a30)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4a9eff), Color(0xFF40ff90)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(step.icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  step.subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          if (step.canSkip)
            TextButton(
              onPressed: _skipOnboarding,
              child: Text(
                'Skip Tutorial',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: List.generate(_steps.length, (index) {
          final isActive = index == _currentStep;
          final isCompleted = index < _currentStep;

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 4,
                    decoration: BoxDecoration(
                      color: isCompleted || isActive
                          ? const Color(0xFF4a9eff)
                          : const Color(0xFF2a2a30),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                if (index < _steps.length - 1) const SizedBox(width: 8),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildFooter(OnboardingStep step) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFF2a2a30)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_currentStep > 0)
            TextButton.icon(
              onPressed: _previousStep,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white.withValues(alpha: 0.7),
              ),
            )
          else
            const SizedBox(width: 80),
          Text(
            'Step ${_currentStep + 1} of ${_steps.length}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
          ElevatedButton.icon(
            onPressed: _nextStep,
            icon: Icon(
              _currentStep == _steps.length - 1
                  ? Icons.check
                  : Icons.arrow_forward,
              size: 18,
            ),
            label: Text(_currentStep == _steps.length - 1 ? 'Finish' : 'Next'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4a9eff),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  // Step 1: Welcome
  Widget _buildWelcomeStep(OnboardingWizardState state) {
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
        // Video placeholder (would be actual video in production)
        Container(
          width: 400,
          height: 225,
          decoration: BoxDecoration(
            color: const Color(0xFF0a0a0c),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2a2a30)),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Animated gradient background
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF4a9eff).withValues(alpha: 0.1),
                      const Color(0xFF40ff90).withValues(alpha: 0.1),
                    ],
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF4a9eff).withValues(alpha: 0.2),
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Color(0xFF4a9eff),
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Watch 2-minute tour',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        // Feature highlights
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildFeatureChip(Icons.casino, 'Slot Audio'),
            _buildFeatureChip(Icons.music_note, 'Event System'),
            _buildFeatureChip(Icons.rocket_launch, 'One-Click Export'),
          ],
        ),
        ],
      ),
    );
  }

  Widget _buildFeatureChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2a2a30),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF4a9eff), size: 18),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  // Step 2: Setup
  Widget _buildSetupStep(OnboardingWizardState state) {
    return SingleChildScrollView(
      child: Row(
        children: [
        // GDD Import option
        Expanded(
          child: _buildSetupOption(
            icon: Icons.upload_file,
            title: 'Import GDD',
            subtitle: 'Load your Game Design Document',
            color: const Color(0xFF4a9eff),
            isSelected: _importedGdd,
            onTap: () {
              setState(() {
                _importedGdd = true;
                _usedTemplate = false;
                _selectedTemplateId = null;
              });
              widget.onImportGdd?.call();
            },
          ),
        ),
        const SizedBox(width: 16),
        // OR divider
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 1,
              height: 60,
              color: const Color(0xFF2a2a30),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF2a2a30),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'OR',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
            Container(
              width: 1,
              height: 60,
              color: const Color(0xFF2a2a30),
            ),
          ],
        ),
        const SizedBox(width: 16),
        // Template option
        Expanded(
          child: _buildSetupOption(
            icon: Icons.grid_view,
            title: 'Use Template',
            subtitle: 'Start with a pre-built slot config',
            color: const Color(0xFF40ff90),
            isSelected: _usedTemplate,
            onTap: () => _showTemplateSelector(),
          ),
        ),
        ],
      ),
    );
  }

  Widget _buildSetupOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.1) : const Color(0xFF0a0a0c),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : const Color(0xFF2a2a30),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.2),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check, color: color, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'Selected',
                      style: TextStyle(color: color, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showTemplateSelector() {
    final templates = [
      ('classic_5x3', 'Classic 5x3', '10 paylines'),
      ('ways_243', '243 Ways', 'All ways pay'),
      ('megaways', 'Megaways', 'Up to 117,649 ways'),
      ('cluster', 'Cluster Pays', '7x7 grid'),
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a20),
        title: const Text('Choose Template', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: templates.map((t) {
              return ListTile(
                leading: const Icon(Icons.grid_view, color: Color(0xFF40ff90)),
                title: Text(t.$2, style: const TextStyle(color: Colors.white)),
                subtitle: Text(t.$3, style: const TextStyle(color: Colors.white54)),
                selected: _selectedTemplateId == t.$1,
                selectedTileColor: const Color(0xFF40ff90).withValues(alpha: 0.1),
                onTap: () {
                  setState(() {
                    _usedTemplate = true;
                    _selectedTemplateId = t.$1;
                    _importedGdd = false;
                  });
                  widget.onTemplateSelected?.call(t.$1);
                  Navigator.of(context).pop();
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // Step 3: Audio Assignment
  Widget _buildAudioAssignStep(OnboardingWizardState state) {
    return Column(
      children: [
        // Instructions
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF4a9eff).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF4a9eff).withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Color(0xFF4a9eff), size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Drag audio files from the left and drop on symbols on the right',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Row(
            children: [
              // Audio files (draggable)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0a0a0c),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2a2a30)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sample Audio Files',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _demoAudioFiles.length,
                          itemBuilder: (context, index) {
                            final file = _demoAudioFiles[index];
                            return Draggable<String>(
                              data: file.filename,
                              onDragStarted: () {
                                setState(() => _draggedAudio = file.filename);
                                HapticFeedback.lightImpact();
                              },
                              onDragEnd: (_) {
                                setState(() => _draggedAudio = null);
                              },
                              feedback: Material(
                                color: Colors.transparent,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4a9eff),
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF4a9eff).withValues(alpha: 0.4),
                                        blurRadius: 12,
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(file.icon, color: Colors.white, size: 16),
                                      const SizedBox(width: 8),
                                      Text(
                                        file.label,
                                        style: const TextStyle(color: Colors.white),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1a1a20),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _draggedAudio == file.filename
                                        ? const Color(0xFF4a9eff)
                                        : const Color(0xFF2a2a30),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(file.icon, color: const Color(0xFF4a9eff), size: 20),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            file.label,
                                            style: const TextStyle(color: Colors.white),
                                          ),
                                          Text(
                                            file.filename,
                                            style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.drag_indicator, color: Colors.white24),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Symbols (drop targets)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0a0a0c),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2a2a30)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Symbols',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_assignedAudio.length}/${_demoSymbols.length} assigned',
                            style: TextStyle(
                              color: _assignedAudio.length == _demoSymbols.length
                                  ? const Color(0xFF40ff90)
                                  : Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _demoSymbols.length,
                          itemBuilder: (context, index) {
                            final symbol = _demoSymbols[index];
                            final hasAudio = _assignedAudio.containsKey(symbol.id);

                            return DragTarget<String>(
                              onAcceptWithDetails: (details) {
                                setState(() {
                                  _assignedAudio[symbol.id] = details.data;
                                  _symbolsAssigned = _assignedAudio.length;
                                });
                                widget.onSymbolAudioAssigned?.call(symbol.id, details.data);
                                HapticFeedback.mediumImpact();
                              },
                              builder: (context, candidateData, rejectedData) {
                                final isHovering = candidateData.isNotEmpty;

                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isHovering
                                        ? symbol.color.withValues(alpha: 0.2)
                                        : const Color(0xFF1a1a20),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isHovering
                                          ? symbol.color
                                          : hasAudio
                                              ? const Color(0xFF40ff90)
                                              : const Color(0xFF2a2a30),
                                      width: isHovering ? 2 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: symbol.color.withValues(alpha: 0.3),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Center(
                                          child: Text(
                                            symbol.id,
                                            style: TextStyle(
                                              color: symbol.color,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              symbol.label,
                                              style: const TextStyle(color: Colors.white),
                                            ),
                                            Text(
                                              hasAudio
                                                  ? _assignedAudio[symbol.id]!
                                                  : 'Drop audio here',
                                              style: TextStyle(
                                                color: hasAudio
                                                    ? const Color(0xFF40ff90)
                                                    : Colors.white38,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (hasAudio)
                                        const Icon(
                                          Icons.check_circle,
                                          color: Color(0xFF40ff90),
                                          size: 20,
                                        )
                                      else
                                        Icon(
                                          isHovering ? Icons.add_circle : Icons.add_circle_outline,
                                          color: isHovering ? symbol.color : Colors.white24,
                                          size: 20,
                                        ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Step 4: Test
  Widget _buildTestStep(OnboardingWizardState state) {
    final forcedOutcomes = [
      ('Lose', Icons.close, const Color(0xFF666666)),
      ('Small Win', Icons.star_outline, const Color(0xFF4a9eff)),
      ('Big Win', Icons.stars, const Color(0xFFFFD700)),
      ('Free Spins', Icons.replay, const Color(0xFF40ff90)),
    ];

    return Column(
      children: [
        // Mini slot preview
        Container(
          height: 160,
          decoration: BoxDecoration(
            color: const Color(0xFF0a0a0c),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2a2a30)),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.casino, color: Color(0xFF4a9eff), size: 48),
                const SizedBox(height: 8),
                Text(
                  'Spins completed: $_spinsCompleted',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Forced outcome buttons
        const Text(
          'Test with forced outcomes:',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: forcedOutcomes.map((outcome) {
            return ElevatedButton.icon(
              onPressed: () {
                setState(() => _spinsCompleted++);
                widget.onTestSpin?.call();
                HapticFeedback.mediumImpact();
              },
              icon: Icon(outcome.$2, size: 18),
              label: Text(outcome.$1),
              style: ElevatedButton.styleFrom(
                backgroundColor: outcome.$3.withValues(alpha: 0.2),
                foregroundColor: outcome.$3,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        // Tip
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFD700).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.lightbulb_outline, color: Color(0xFFFFD700), size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tip: Use keyboard shortcuts 1-4 to trigger outcomes quickly',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Step 5: Export
  Widget _buildExportStep(OnboardingWizardState state) {
    final platforms = [
      ('Unity', Icons.gamepad, const Color(0xFF4a9eff), 'C# + JSON'),
      ('Unreal', Icons.sports_esports, const Color(0xFF9370DB), 'C++ + Blueprint'),
      ('Web/Howler', Icons.public, const Color(0xFF40ff90), 'TypeScript + JSON'),
    ];

    return Column(
      children: [
        const Text(
          'Export to your game engine',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: platforms.map((platform) {
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0a0a0c),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: platform.$3.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      Icon(platform.$2, color: platform.$3, size: 40),
                      const SizedBox(height: 12),
                      Text(
                        platform.$1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        platform.$4,
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        // Summary
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF40ff90).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF40ff90).withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Color(0xFF40ff90)),
                  SizedBox(width: 12),
                  Text(
                    'You are ready to start!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildSummaryItem('Setup', _usedTemplate || _importedGdd),
                  _buildSummaryItem('Audio', _symbolsAssigned > 0),
                  _buildSummaryItem('Tested', _spinsCompleted > 0),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryItem(String label, bool completed) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          completed ? Icons.check_circle : Icons.radio_button_unchecked,
          color: completed ? const Color(0xFF40ff90) : Colors.white38,
          size: 18,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: completed ? Colors.white : Colors.white54,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _DemoAudioFile {
  final String filename;
  final String label;
  final IconData icon;

  const _DemoAudioFile(this.filename, this.label, this.icon);
}

class _DemoSymbol {
  final String id;
  final String label;
  final Color color;

  const _DemoSymbol(this.id, this.label, this.color);
}
