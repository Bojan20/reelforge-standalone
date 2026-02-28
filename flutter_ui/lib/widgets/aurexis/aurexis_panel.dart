import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../providers/aurexis_provider.dart';
import '../../providers/aurexis_profile_provider.dart';
import '../../models/aurexis_jurisdiction.dart';
import '../../models/aurexis_cabinet.dart';
import 'aurexis_theme.dart';
import 'audit_trail_widget.dart';
import 'aurexis_behavior_slider.dart';
import 'cabinet_simulator_widget.dart';
import 'compliance_report_widget.dart';
import 'memory_budget_bar.dart';
import 'qa_framework_widget.dart';
import 'retheme_wizard_widget.dart';
import 'visualizers/fatigue_meter_viz.dart';
import 'visualizers/voice_cluster_viz.dart';
import 'visualizers/energy_density_viz.dart';
import 'visualizers/attention_field_viz.dart';
import 'visualizers/rtp_emotion_curve_viz.dart';
import 'visualizers/win_escalation_viz.dart';

/// AUREXIS™ Intelligence Panel — Left-side panel (280px).
///
/// 7 collapsible sections:
/// 1. PROFILE — Profile selection, intensity, quick dials
/// 2. BEHAVIOR — Meta-controls (Spatial, Dynamics, Music, Variation)
/// 3. TWEAK — Per-system compact editors
/// 4. CABINET — Speaker simulation + ambient noise (monitoring-only)
/// 5. COMPLIANCE — Jurisdiction compliance report
/// 6. AUDIT — Session operation audit trail
/// 7. SCOPE — Real-time visualizers (fatigue, collision, escalation)
class AurexisPanel extends StatefulWidget {
  const AurexisPanel({super.key});

  @override
  State<AurexisPanel> createState() => _AurexisPanelState();
}

class _AurexisPanelState extends State<AurexisPanel> {
  late final AurexisProvider _engine;
  late final AurexisProfileProvider _profile;

  bool _sectionProfile = true;
  bool _sectionBehavior = true;
  bool _sectionTweak = false;
  bool _sectionCabinet = false;
  bool _sectionCompliance = false;
  bool _sectionAudit = false;
  bool _sectionScope = true;

  CabinetSimulatorState _cabinetState = const CabinetSimulatorState();
  String? _tweakSubView; // 'qa', 'retheme', or null (default chips)

  @override
  void initState() {
    super.initState();
    _engine = GetIt.instance<AurexisProvider>();
    _profile = GetIt.instance<AurexisProfileProvider>();
    _engine.addListener(_onEngineUpdate);
    _profile.addListener(_onProfileUpdate);
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngineUpdate);
    _profile.removeListener(_onProfileUpdate);
    super.dispose();
  }

  void _onEngineUpdate() {
    if (mounted) setState(() {});
  }

  void _onProfileUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AurexisDimens.panelWidth,
      color: AurexisColors.bgPanel,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                _buildSection(
                  title: 'PROFILE',
                  expanded: _sectionProfile,
                  onToggle: () => setState(() => _sectionProfile = !_sectionProfile),
                  trailing: _profile.modified
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: AurexisColors.modified.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text('MOD', style: AurexisTextStyles.badge.copyWith(color: AurexisColors.modified)),
                        )
                      : null,
                  child: _buildProfileSection(),
                ),
                _buildSection(
                  title: 'BEHAVIOR',
                  expanded: _sectionBehavior,
                  onToggle: () => setState(() => _sectionBehavior = !_sectionBehavior),
                  child: _buildBehaviorSection(),
                ),
                _buildSection(
                  title: 'TWEAK',
                  expanded: _sectionTweak,
                  onToggle: () => setState(() => _sectionTweak = !_sectionTweak),
                  child: _buildTweakSection(),
                ),
                _buildSection(
                  title: 'CABINET',
                  expanded: _sectionCabinet,
                  onToggle: () => setState(() => _sectionCabinet = !_sectionCabinet),
                  trailing: _cabinetState.enabled
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: AurexisColors.accent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text('ON', style: AurexisTextStyles.badge.copyWith(color: AurexisColors.accent)),
                        )
                      : null,
                  child: CabinetSimulatorWidget(
                    state: _cabinetState,
                    onStateChanged: (s) => setState(() => _cabinetState = s),
                  ),
                ),
                _buildSection(
                  title: 'COMPLIANCE',
                  expanded: _sectionCompliance,
                  onToggle: () => setState(() => _sectionCompliance = !_sectionCompliance),
                  trailing: _profile.jurisdiction != AurexisJurisdiction.none
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: AurexisColors.spatial.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(
                            _profile.jurisdiction.code,
                            style: AurexisTextStyles.badge.copyWith(color: AurexisColors.spatial),
                          ),
                        )
                      : null,
                  child: const ComplianceReportWidget(),
                ),
                _buildSection(
                  title: 'AUDIT',
                  expanded: _sectionAudit,
                  onToggle: () => setState(() => _sectionAudit = !_sectionAudit),
                  child: const AuditTrailWidget(),
                ),
                _buildSection(
                  title: 'SCOPE',
                  expanded: _sectionScope,
                  onToggle: () => setState(() => _sectionScope = !_sectionScope),
                  child: _buildScopeSection(),
                ),
              ],
            ),
          ),
          // Memory budget bar (always visible at bottom)
          const AurexisMemoryBudgetWidget(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: AurexisColors.bgSectionHeader,
        border: Border(bottom: BorderSide(color: AurexisColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Text(
            'AUREXIS',
            style: AurexisTextStyles.sectionTitle.copyWith(
              color: AurexisColors.accent,
              fontSize: 11,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(width: 4),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _engine.initialized ? AurexisColors.active : AurexisColors.inactive,
            ),
          ),
          const Spacer(),
          // A/B toggle
          if (_profile.abActive)
            _buildMiniButton(
              label: _profile.showingB ? 'B' : 'A',
              active: true,
              onTap: _profile.toggleAB,
            ),
          const SizedBox(width: 4),
          _buildMiniButton(
            label: 'A/B',
            active: _profile.abActive,
            onTap: () {
              if (!_profile.abActive) {
                _profile.captureA();
                _profile.captureB();
              } else {
                _profile.deactivateAB();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMiniButton({required String label, bool active = false, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: active ? AurexisColors.accent.withValues(alpha: 0.15) : Colors.transparent,
          border: Border.all(
            color: active ? AurexisColors.accent : AurexisColors.borderSubtle,
            width: 0.5,
          ),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          style: AurexisTextStyles.badge.copyWith(
            color: active ? AurexisColors.accent : AurexisColors.textSecondary,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SECTION WRAPPER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSection({
    required String title,
    required bool expanded,
    required VoidCallback onToggle,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: AurexisDimens.sectionGap),
      decoration: const BoxDecoration(
        color: AurexisColors.bgSection,
        border: Border(
          top: BorderSide(color: AurexisColors.borderSubtle, width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          GestureDetector(
            onTap: onToggle,
            child: Container(
              height: AurexisDimens.sectionHeaderHeight,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              color: AurexisColors.bgSectionHeader,
              child: Row(
                children: [
                  Icon(
                    expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 14,
                    color: AurexisColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(title, style: AurexisTextStyles.sectionTitle),
                  const Spacer(),
                  if (trailing != null) trailing,
                ],
              ),
            ),
          ),
          // Content
          if (expanded)
            Padding(
              padding: const EdgeInsets.all(AurexisDimens.sectionPadding),
              child: child,
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. PROFILE SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildProfileSection() {
    final profile = _profile.activeProfile;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Profile dropdown
        Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: AurexisColors.bgInput,
            borderRadius: BorderRadius.circular(AurexisDimens.borderRadius),
            border: Border.all(color: AurexisColors.borderSubtle, width: 0.5),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: profile.id,
              isExpanded: true,
              isDense: true,
              dropdownColor: AurexisColors.bgSection,
              style: AurexisTextStyles.profileName,
              icon: const Icon(Icons.unfold_more, size: 14, color: AurexisColors.textSecondary),
              items: _profile.allProfiles.map((p) {
                return DropdownMenuItem(
                  value: p.id,
                  child: Text(
                    p.name,
                    style: AurexisTextStyles.profileName.copyWith(
                      color: p.builtIn ? AurexisColors.textPrimary : AurexisColors.variation,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (id) {
                if (id != null) _profile.selectProfile(id);
              },
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Jurisdiction dropdown
        Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: AurexisColors.bgInput,
            borderRadius: BorderRadius.circular(AurexisDimens.borderRadius),
            border: Border.all(color: AurexisColors.borderSubtle, width: 0.5),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<AurexisJurisdiction>(
              value: _profile.jurisdiction,
              isExpanded: true,
              isDense: true,
              dropdownColor: AurexisColors.bgSection,
              style: AurexisTextStyles.paramLabel.copyWith(fontSize: 9),
              icon: const Icon(Icons.unfold_more, size: 12, color: AurexisColors.textSecondary),
              items: AurexisJurisdiction.values.map((j) {
                return DropdownMenuItem(
                  value: j,
                  child: Text(j.label, style: AurexisTextStyles.paramLabel.copyWith(fontSize: 9)),
                );
              }).toList(),
              onChanged: (j) {
                if (j != null) _profile.setJurisdiction(j);
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        // Intensity slider
        AurexisBehaviorSlider(
          label: 'Intensity',
          value: profile.intensity,
          onChanged: _profile.setIntensity,
          onReset: _profile.resetToDefault,
          color: AurexisColors.accent,
        ),
        const SizedBox(height: 4),
        // Quick actions row
        Row(
          children: [
            _buildMiniButton(
              label: 'Save As',
              onTap: () => _showSaveDialog(context),
            ),
            const SizedBox(width: 4),
            _buildMiniButton(
              label: 'Reset',
              onTap: _profile.resetToDefault,
            ),
            const Spacer(),
            // Platform indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AurexisColors.bgInput,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                _engine.platform.label,
                style: AurexisTextStyles.badge.copyWith(color: AurexisColors.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showSaveDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AurexisColors.bgSection,
        title: const Text('Save Profile', style: TextStyle(color: AurexisColors.textPrimary, fontSize: 14)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AurexisColors.textPrimary, fontSize: 12),
          decoration: const InputDecoration(
            hintText: 'Profile name',
            hintStyle: TextStyle(color: AurexisColors.textLabel),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                _profile.saveAsCustom(controller.text);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // controller is disposed when dialog closes
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. BEHAVIOR SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBehaviorSection() {
    final b = _profile.activeProfile.behavior;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // SPATIAL group
        _buildBehaviorGroup(
          title: 'SPATIAL',
          color: AurexisColors.spatial,
          locked: _profile.lockSpatial,
          onLockToggle: _profile.toggleLockSpatial,
          sliders: [
            AurexisBehaviorSlider(
              label: 'Width',
              value: b.spatial.width,
              onChanged: _profile.setSpatialWidth,
              onReset: () => _profile.resetBehaviorParam('spatial', 'width'),
              color: AurexisColors.spatial,
            ),
            AurexisBehaviorSlider(
              label: 'Depth',
              value: b.spatial.depth,
              onChanged: _profile.setSpatialDepth,
              onReset: () => _profile.resetBehaviorParam('spatial', 'depth'),
              color: AurexisColors.spatial,
            ),
            AurexisBehaviorSlider(
              label: 'Movement',
              value: b.spatial.movement,
              onChanged: _profile.setSpatialMovement,
              onReset: () => _profile.resetBehaviorParam('spatial', 'movement'),
              color: AurexisColors.spatial,
            ),
          ],
        ),
        const SizedBox(height: 4),
        // DYNAMICS group
        _buildBehaviorGroup(
          title: 'DYNAMICS',
          color: AurexisColors.dynamics,
          locked: _profile.lockDynamics,
          onLockToggle: _profile.toggleLockDynamics,
          sliders: [
            AurexisBehaviorSlider(
              label: 'Escalation',
              value: b.dynamics.escalation,
              onChanged: _profile.setDynamicsEscalation,
              onReset: () => _profile.resetBehaviorParam('dynamics', 'escalation'),
              color: AurexisColors.dynamics,
            ),
            AurexisBehaviorSlider(
              label: 'Ducking',
              value: b.dynamics.ducking,
              onChanged: _profile.setDynamicsDucking,
              onReset: () => _profile.resetBehaviorParam('dynamics', 'ducking'),
              color: AurexisColors.dynamics,
            ),
            AurexisBehaviorSlider(
              label: 'Fatigue',
              value: b.dynamics.fatigue,
              onChanged: _profile.setDynamicsFatigue,
              onReset: () => _profile.resetBehaviorParam('dynamics', 'fatigue'),
              color: AurexisColors.dynamics,
            ),
          ],
        ),
        const SizedBox(height: 4),
        // MUSIC group
        _buildBehaviorGroup(
          title: 'MUSIC',
          color: AurexisColors.music,
          locked: _profile.lockMusic,
          onLockToggle: _profile.toggleLockMusic,
          sliders: [
            AurexisBehaviorSlider(
              label: 'Reactivity',
              value: b.music.reactivity,
              onChanged: _profile.setMusicReactivity,
              onReset: () => _profile.resetBehaviorParam('music', 'reactivity'),
              color: AurexisColors.music,
            ),
            AurexisBehaviorSlider(
              label: 'Layer Bias',
              value: b.music.layerBias,
              onChanged: _profile.setMusicLayerBias,
              onReset: () => _profile.resetBehaviorParam('music', 'layerBias'),
              color: AurexisColors.music,
            ),
            AurexisBehaviorSlider(
              label: 'Transition',
              value: b.music.transition,
              onChanged: _profile.setMusicTransition,
              onReset: () => _profile.resetBehaviorParam('music', 'transition'),
              color: AurexisColors.music,
            ),
          ],
        ),
        const SizedBox(height: 4),
        // VARIATION group
        _buildBehaviorGroup(
          title: 'VARIATION',
          color: AurexisColors.variation,
          locked: _profile.lockVariation,
          onLockToggle: _profile.toggleLockVariation,
          sliders: [
            AurexisBehaviorSlider(
              label: 'Pan Drift',
              value: b.variation.panDrift,
              onChanged: _profile.setVariationPanDrift,
              onReset: () => _profile.resetBehaviorParam('variation', 'panDrift'),
              color: AurexisColors.variation,
            ),
            AurexisBehaviorSlider(
              label: 'Width Var',
              value: b.variation.widthVar,
              onChanged: _profile.setVariationWidthVar,
              onReset: () => _profile.resetBehaviorParam('variation', 'widthVar'),
              color: AurexisColors.variation,
            ),
            AurexisBehaviorSlider(
              label: 'Timing Var',
              value: b.variation.timingVar,
              onChanged: _profile.setVariationTimingVar,
              onReset: () => _profile.resetBehaviorParam('variation', 'timingVar'),
              color: AurexisColors.variation,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBehaviorGroup({
    required String title,
    required Color color,
    required bool locked,
    required VoidCallback onLockToggle,
    required List<Widget> sliders,
  }) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AurexisColors.bgInput,
        borderRadius: BorderRadius.circular(AurexisDimens.borderRadius),
        border: Border.all(
          color: locked ? AurexisColors.locked.withValues(alpha: 0.4) : AurexisColors.borderSubtle,
          width: 0.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Group header
          Row(
            children: [
              Container(
                width: 3,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                title,
                style: AurexisTextStyles.sectionTitle.copyWith(
                  color: color,
                  fontSize: 9,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onLockToggle,
                child: Icon(
                  locked ? Icons.lock : Icons.lock_open,
                  size: 11,
                  color: locked ? AurexisColors.locked : AurexisColors.textLabel,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          ...sliders,
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. TWEAK SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTweakSection() {
    // Sub-view mode
    if (_tweakSubView == 'qa') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSubViewHeader('QA Framework'),
          const QaFrameworkWidget(),
        ],
      );
    }
    if (_tweakSubView == 'retheme') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSubViewHeader('Re-Theme Wizard'),
          ReThemeWizardWidget(
            onApply: (_) => setState(() => _tweakSubView = null),
            onCancel: () => setState(() => _tweakSubView = null),
          ),
        ],
      );
    }

    // Default: System chips + tools
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // System selector chips
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            _buildSystemChip('VOL', AurexisColors.spatial),
            _buildSystemChip('RTP', AurexisColors.dynamics),
            _buildSystemChip('FAT', AurexisColors.music),
            _buildSystemChip('COL', AurexisColors.variation),
            _buildSystemChip('ESC', AurexisColors.dynamics),
            _buildSystemChip('VAR', AurexisColors.variation),
            _buildSystemChip('PLT', AurexisColors.spatial),
            _buildSystemChip('ATT', AurexisColors.music),
          ],
        ),
        const SizedBox(height: 8),
        // Tools row
        Row(
          children: [
            Expanded(
              child: _buildToolButton(
                icon: Icons.science_outlined,
                label: 'QA Suite',
                color: AurexisColors.fatigueFresh,
                onTap: () => setState(() => _tweakSubView = 'qa'),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _buildToolButton(
                icon: Icons.swap_horiz,
                label: 'Re-Theme',
                color: AurexisColors.variation,
                onTap: () => setState(() => _tweakSubView = 'retheme'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSubViewHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => setState(() => _tweakSubView = null),
            child: Icon(Icons.arrow_back, size: 14, color: AurexisColors.accent),
          ),
          const SizedBox(width: 4),
          Text(
            title,
            style: AurexisTextStyles.sectionTitle.copyWith(
              color: AurexisColors.accent,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.2), width: 0.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: AurexisTextStyles.badge.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Text(
        label,
        style: AurexisTextStyles.badge.copyWith(color: color),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. SCOPE SECTION (Live visualizers)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildScopeSection() {
    final params = _engine.parameters;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Fatigue meter with sparkline
        FatigueMeterViz(
          fatigueIndex: params.fatigueIndex,
          sessionDurationS: params.sessionDurationS,
          rmsAvgDb: params.rmsExposureAvgDb,
          hfCumulative: params.hfExposureCumulative,
          height: 90,
        ),
        const SizedBox(height: 6),
        // Voice cluster / collision map
        VoiceClusterViz(
          centerOccupancy: params.centerOccupancy,
          voicesRedistributed: params.voicesRedistributed,
          duckingBiasDb: params.duckingBiasDb,
          stereoWidth: params.stereoWidth,
          panDrift: params.panDrift,
          height: 70,
        ),
        const SizedBox(height: 6),
        // Energy density sparkline
        EnergyDensityViz(
          energyDensity: params.energyDensity,
          escalationMultiplier: params.escalationMultiplier,
          height: 55,
        ),
        const SizedBox(height: 6),
        // Win escalation stack
        WinEscalationViz(
          stereoWidth: params.stereoWidth,
          harmonicExcitation: params.harmonicExcitation,
          reverbTailExtensionMs: params.reverbTailExtensionMs,
          subReinforcementDb: params.subReinforcementDb,
          transientSharpness: params.transientSharpness,
          escalationMultiplier: params.escalationMultiplier,
          height: 95,
        ),
        const SizedBox(height: 6),
        // RTP pacing curve
        RtpEmotionCurveViz(
          rtp: _engine.rtp,
          reverbSendBias: params.reverbSendBias,
          reverbTailExtensionMs: params.reverbTailExtensionMs,
          height: 65,
        ),
        const SizedBox(height: 6),
        // Attention field
        AttentionFieldViz(
          attentionX: params.attentionX,
          attentionY: params.attentionY,
          attentionWeight: params.attentionWeight,
          height: 70,
        ),
      ],
    );
  }

}
