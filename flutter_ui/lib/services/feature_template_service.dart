/// Feature Template Service
///
/// Manages pre-built slot game feature templates with complete
/// stage sequences, audio mappings, and instantiation.
///
/// Part of P1-12: Feature Template Library
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/feature_template.dart';

// =============================================================================
// FEATURE TEMPLATE SERVICE (Singleton)
// =============================================================================

class FeatureTemplateService extends ChangeNotifier {
  static final FeatureTemplateService _instance = FeatureTemplateService._();
  static FeatureTemplateService get instance => _instance;

  FeatureTemplateService._() {
    _loadBuiltInTemplates();
  }

  // State
  final Map<String, FeatureTemplate> _templates = {};
  final Map<String, FeatureTemplateInstance> _instances = {};

  // Getters
  List<FeatureTemplate> get templates => _templates.values.toList();
  List<FeatureTemplate> get builtInTemplates =>
      templates.where((t) => t.isBuiltIn).toList();
  List<FeatureTemplate> get customTemplates =>
      templates.where((t) => !t.isBuiltIn).toList();
  List<FeatureTemplateInstance> get instances => _instances.values.toList();

  // ==========================================================================
  // TEMPLATE MANAGEMENT
  // ==========================================================================

  /// Register a template
  void registerTemplate(FeatureTemplate template) {
    _templates[template.id] = template;
    notifyListeners();
  }

  /// Get template by id
  FeatureTemplate? getTemplate(String id) => _templates[id];

  /// Get templates by type
  List<FeatureTemplate> getTemplatesByType(FeatureType type) {
    return templates.where((t) => t.type == type).toList();
  }

  /// Remove template (only custom, not built-in)
  bool removeTemplate(String id) {
    final template = _templates[id];
    if (template == null || template.isBuiltIn) return false;

    _templates.remove(id);
    notifyListeners();
    return true;
  }

  // ==========================================================================
  // INSTANCE MANAGEMENT
  // ==========================================================================

  /// Create instance from template
  FeatureTemplateInstance createInstance({
    required String templateId,
    required String name,
    Map<String, dynamic>? parameterValues,
    Map<String, String>? audioAssignments,
  }) {
    final template = getTemplate(templateId);
    if (template == null) {
      throw Exception('Template not found: $templateId');
    }

    // Fill default parameter values
    final params = <String, dynamic>{};
    for (final param in template.parameters) {
      params[param.id] = parameterValues?[param.id] ?? param.defaultValue;
    }

    final instance = FeatureTemplateInstance(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      templateId: templateId,
      name: name,
      parameterValues: params,
      audioAssignments: audioAssignments ?? {},
      createdAt: DateTime.now(),
    );

    _instances[instance.id] = instance;
    notifyListeners();
    return instance;
  }

  /// Update instance
  void updateInstance(FeatureTemplateInstance instance) {
    _instances[instance.id] = instance.copyWith(
      modifiedAt: DateTime.now(),
    );
    notifyListeners();
  }

  /// Delete instance
  bool deleteInstance(String id) {
    final removed = _instances.remove(id);
    if (removed != null) notifyListeners();
    return removed != null;
  }

  /// Get instance by id
  FeatureTemplateInstance? getInstance(String id) => _instances[id];

  /// Get instances by template
  List<FeatureTemplateInstance> getInstancesByTemplate(String templateId) {
    return instances.where((i) => i.templateId == templateId).toList();
  }

  // ==========================================================================
  // VALIDATION
  // ==========================================================================

  /// Validate instance completeness
  Map<String, List<String>> validateInstance(FeatureTemplateInstance instance) {
    final errors = <String, List<String>>{};
    final template = getTemplate(instance.templateId);
    if (template == null) {
      errors['general'] = ['Template not found'];
      return errors;
    }

    // Check required parameters
    for (final param in template.parameters.where((p) => p.required)) {
      final value = instance.parameterValues[param.id];
      if (value == null) {
        errors['parameters'] ??= [];
        errors['parameters']!.add('Missing required parameter: ${param.label}');
      }
    }

    // Check required audio slots
    for (final slot in template.requiredSlots) {
      if (!instance.audioAssignments.containsKey(slot.stage)) {
        errors['audio'] ??= [];
        errors['audio']!.add('Missing required audio: ${slot.label}');
      }
    }

    return errors;
  }

  /// Check if instance is complete
  bool isInstanceComplete(FeatureTemplateInstance instance) {
    return validateInstance(instance).isEmpty;
  }

  // ==========================================================================
  // EXPORT / IMPORT
  // ==========================================================================

  /// Export instance to JSON
  String exportInstance(String id) {
    final instance = getInstance(id);
    if (instance == null) throw Exception('Instance not found: $id');
    return jsonEncode(instance.toJson());
  }

  /// Import instance from JSON
  FeatureTemplateInstance importInstance(String json) {
    final data = jsonDecode(json) as Map<String, dynamic>;
    final instance = FeatureTemplateInstance.fromJson(data);
    _instances[instance.id] = instance;
    notifyListeners();
    return instance;
  }

  // ==========================================================================
  // BUILT-IN TEMPLATES
  // ==========================================================================

  void _loadBuiltInTemplates() {
    // Free Spins Template
    registerTemplate(_createFreeSpinsTemplate());

    // Bonus Game Template
    registerTemplate(_createBonusGameTemplate());

    // Hold & Win Template
    registerTemplate(_createHoldAndWinTemplate());

    // Cascade Template
    registerTemplate(_createCascadeTemplate());

    // Jackpot Template
    registerTemplate(_createJackpotTemplate());
  }

  // --------------------------------------------------------------------------
  // Free Spins Template
  // --------------------------------------------------------------------------

  FeatureTemplate _createFreeSpinsTemplate() {
    return FeatureTemplate(
      id: 'free_spins_standard',
      name: 'Free Spins (Standard)',
      type: FeatureType.freeSpins,
      description: 'Standard free spins feature with trigger, entry, spins, retrigger, and exit',
      isBuiltIn: true,
      parameters: [
        const ParameterDef(
          id: 'num_spins',
          label: 'Number of Spins',
          type: ParameterType.integer,
          defaultValue: 10,
          minValue: 5,
          maxValue: 50,
          required: true,
        ),
        const ParameterDef(
          id: 'can_retrigger',
          label: 'Can Retrigger',
          type: ParameterType.boolean,
          defaultValue: true,
        ),
        const ParameterDef(
          id: 'retrigger_spins',
          label: 'Retrigger Spins',
          type: ParameterType.integer,
          defaultValue: 5,
          minValue: 1,
          maxValue: 20,
        ),
      ],
      phases: [
        FeaturePhase(
          id: 'trigger',
          name: 'Trigger',
          description: 'Feature trigger sequence',
          order: 0,
          audioSlots: const [
            AudioSlotDef(
              stage: 'FS_TRIGGER',
              label: 'Trigger Sound',
              description: 'Sound when free spins are triggered',
              required: true,
              priority: 90,
              defaultBus: 'SFX',
            ),
          ],
        ),
        FeaturePhase(
          id: 'entry',
          name: 'Entry',
          description: 'Enter free spins mode',
          order: 1,
          audioSlots: const [
            AudioSlotDef(
              stage: 'FS_ENTER',
              label: 'Enter Sound',
              description: 'Transition into free spins',
              required: true,
              priority: 85,
              defaultBus: 'SFX',
            ),
            AudioSlotDef(
              stage: 'FS_MUSIC',
              label: 'Feature Music',
              description: 'Background music during free spins',
              looping: true,
              priority: 40,
              defaultBus: 'Music',
            ),
          ],
        ),
        FeaturePhase(
          id: 'gameplay',
          name: 'Gameplay',
          description: 'Free spins gameplay',
          order: 2,
          audioSlots: const [
            AudioSlotDef(
              stage: 'FS_SPIN',
              label: 'Spin Sound',
              description: 'Each free spin',
              priority: 60,
              defaultBus: 'SFX',
            ),
            AudioSlotDef(
              stage: 'FS_WIN',
              label: 'Win Sound',
              description: 'Win during free spins',
              priority: 70,
              defaultBus: 'Wins',
            ),
          ],
        ),
        FeaturePhase(
          id: 'retrigger',
          name: 'Retrigger',
          description: 'Retrigger free spins',
          order: 3,
          canSkip: true,
          audioSlots: const [
            AudioSlotDef(
              stage: 'FS_RETRIGGER',
              label: 'Retrigger Sound',
              description: 'Additional spins awarded',
              priority: 85,
              defaultBus: 'SFX',
            ),
          ],
        ),
        FeaturePhase(
          id: 'exit',
          name: 'Exit',
          description: 'End free spins mode',
          order: 4,
          audioSlots: const [
            AudioSlotDef(
              stage: 'FS_EXIT',
              label: 'Exit Sound',
              description: 'Return to base game',
              required: true,
              priority: 80,
              defaultBus: 'SFX',
            ),
            AudioSlotDef(
              stage: 'FS_SUMMARY',
              label: 'Summary Sound',
              description: 'Total win summary',
              priority: 75,
              defaultBus: 'Wins',
            ),
          ],
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Bonus Game Template
  // --------------------------------------------------------------------------

  FeatureTemplate _createBonusGameTemplate() {
    return FeatureTemplate(
      id: 'bonus_game_standard',
      name: 'Bonus Game (Pick & Reveal)',
      type: FeatureType.bonusGame,
      description: 'Pick-style bonus game with trigger, entry, picks, reveal, and exit',
      isBuiltIn: true,
      parameters: [
        const ParameterDef(
          id: 'num_picks',
          label: 'Number of Picks',
          type: ParameterType.integer,
          defaultValue: 3,
          minValue: 1,
          maxValue: 12,
          required: true,
        ),
        const ParameterDef(
          id: 'reveal_all',
          label: 'Reveal All After Complete',
          type: ParameterType.boolean,
          defaultValue: true,
        ),
      ],
      phases: [
        FeaturePhase(
          id: 'trigger',
          name: 'Trigger',
          order: 0,
          audioSlots: const [
            AudioSlotDef(
              stage: 'BONUS_TRIGGER',
              label: 'Trigger Sound',
              required: true,
              priority: 90,
              defaultBus: 'SFX',
            ),
          ],
        ),
        FeaturePhase(
          id: 'entry',
          name: 'Entry',
          order: 1,
          audioSlots: const [
            AudioSlotDef(
              stage: 'BONUS_ENTER',
              label: 'Enter Sound',
              required: true,
              priority: 85,
              defaultBus: 'SFX',
            ),
            AudioSlotDef(
              stage: 'BONUS_MUSIC',
              label: 'Bonus Music',
              looping: true,
              priority: 40,
              defaultBus: 'Music',
            ),
          ],
        ),
        FeaturePhase(
          id: 'picks',
          name: 'Picks',
          order: 2,
          audioSlots: const [
            AudioSlotDef(
              stage: 'BONUS_PICK',
              label: 'Pick Sound',
              description: 'Each pick selection',
              priority: 70,
              defaultBus: 'SFX',
            ),
            AudioSlotDef(
              stage: 'BONUS_REVEAL',
              label: 'Reveal Sound',
              description: 'Reveal picked item',
              priority: 75,
              defaultBus: 'SFX',
            ),
            AudioSlotDef(
              stage: 'BONUS_COLLECT',
              label: 'Collect Sound',
              description: 'Collect revealed item',
              priority: 65,
              defaultBus: 'SFX',
            ),
          ],
        ),
        FeaturePhase(
          id: 'exit',
          name: 'Exit',
          order: 3,
          audioSlots: const [
            AudioSlotDef(
              stage: 'BONUS_EXIT',
              label: 'Exit Sound',
              required: true,
              priority: 80,
              defaultBus: 'SFX',
            ),
            AudioSlotDef(
              stage: 'BONUS_AWARD',
              label: 'Award Sound',
              description: 'Total bonus win',
              priority: 85,
              defaultBus: 'Wins',
            ),
          ],
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Hold & Win Template
  // --------------------------------------------------------------------------

  FeatureTemplate _createHoldAndWinTemplate() {
    return FeatureTemplate(
      id: 'hold_and_win_standard',
      name: 'Hold & Win (Respins)',
      type: FeatureType.holdAndWin,
      description: 'Hold & Win feature with trigger, respins, collect, and award',
      isBuiltIn: true,
      parameters: [
        const ParameterDef(
          id: 'num_respins',
          label: 'Starting Respins',
          type: ParameterType.integer,
          defaultValue: 3,
          minValue: 1,
          maxValue: 10,
          required: true,
        ),
        const ParameterDef(
          id: 'reset_on_collect',
          label: 'Reset Spins on Collect',
          type: ParameterType.boolean,
          defaultValue: true,
        ),
      ],
      phases: [
        FeaturePhase(
          id: 'trigger',
          name: 'Trigger',
          order: 0,
          audioSlots: const [
            AudioSlotDef(
              stage: 'HOLD_TRIGGER',
              label: 'Trigger Sound',
              required: true,
              priority: 90,
              defaultBus: 'SFX',
            ),
          ],
        ),
        FeaturePhase(
          id: 'entry',
          name: 'Entry',
          order: 1,
          audioSlots: const [
            AudioSlotDef(
              stage: 'HOLD_ENTER',
              label: 'Enter Sound',
              required: true,
              priority: 85,
              defaultBus: 'SFX',
            ),
            AudioSlotDef(
              stage: 'HOLD_MUSIC',
              label: 'Hold Music',
              looping: true,
              priority: 40,
              defaultBus: 'Music',
            ),
          ],
        ),
        FeaturePhase(
          id: 'respins',
          name: 'Respins',
          order: 2,
          audioSlots: const [
            AudioSlotDef(
              stage: 'HOLD_SPIN',
              label: 'Respin Sound',
              priority: 60,
              defaultBus: 'Reels',
            ),
            AudioSlotDef(
              stage: 'HOLD_COLLECT',
              label: 'Collect Sound',
              description: 'Symbol collected',
              priority: 70,
              defaultBus: 'SFX',
            ),
            AudioSlotDef(
              stage: 'HOLD_RESET',
              label: 'Reset Sound',
              description: 'Respins reset',
              priority: 65,
              defaultBus: 'SFX',
            ),
          ],
        ),
        FeaturePhase(
          id: 'exit',
          name: 'Exit',
          order: 3,
          audioSlots: const [
            AudioSlotDef(
              stage: 'HOLD_EXIT',
              label: 'Exit Sound',
              required: true,
              priority: 80,
              defaultBus: 'SFX',
            ),
            AudioSlotDef(
              stage: 'HOLD_AWARD',
              label: 'Award Sound',
              description: 'Total collected win',
              priority: 85,
              defaultBus: 'Wins',
            ),
          ],
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Cascade Template
  // --------------------------------------------------------------------------

  FeatureTemplate _createCascadeTemplate() {
    return FeatureTemplate(
      id: 'cascade_standard',
      name: 'Cascade (Avalanche)',
      type: FeatureType.cascade,
      description: 'Cascading reels with drop, evaluate, cascade, and settle',
      isBuiltIn: true,
      parameters: [
        const ParameterDef(
          id: 'max_cascades',
          label: 'Max Cascades',
          type: ParameterType.integer,
          defaultValue: 10,
          minValue: 1,
          maxValue: 50,
        ),
        const ParameterDef(
          id: 'escalate_audio',
          label: 'Escalate Audio',
          type: ParameterType.boolean,
          defaultValue: true,
          description: 'Increase pitch/volume on each cascade',
        ),
      ],
      phases: [
        FeaturePhase(
          id: 'start',
          name: 'Start',
          order: 0,
          audioSlots: const [
            AudioSlotDef(
              stage: 'CASCADE_START',
              label: 'Start Sound',
              required: true,
              priority: 70,
              defaultBus: 'SFX',
            ),
          ],
        ),
        FeaturePhase(
          id: 'cascade',
          name: 'Cascade',
          order: 1,
          audioSlots: const [
            AudioSlotDef(
              stage: 'CASCADE_DROP',
              label: 'Drop Sound',
              description: 'Symbols drop down',
              priority: 65,
              defaultBus: 'SFX',
            ),
            AudioSlotDef(
              stage: 'CASCADE_POP',
              label: 'Pop Sound',
              description: 'Winning symbols pop',
              priority: 70,
              defaultBus: 'SFX',
            ),
            AudioSlotDef(
              stage: 'CASCADE_STEP',
              label: 'Step Sound',
              description: 'Each cascade iteration',
              priority: 60,
              defaultBus: 'SFX',
            ),
          ],
        ),
        FeaturePhase(
          id: 'end',
          name: 'End',
          order: 2,
          audioSlots: const [
            AudioSlotDef(
              stage: 'CASCADE_END',
              label: 'End Sound',
              description: 'Cascade complete',
              required: true,
              priority: 70,
              defaultBus: 'SFX',
            ),
          ],
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // Jackpot Template
  // --------------------------------------------------------------------------

  FeatureTemplate _createJackpotTemplate() {
    return FeatureTemplate(
      id: 'jackpot_standard',
      name: 'Jackpot (4-Tier)',
      type: FeatureType.jackpot,
      description: 'Progressive jackpot with trigger, buildup, reveal, celebration, and complete',
      isBuiltIn: true,
      parameters: [
        const ParameterDef(
          id: 'tiers',
          label: 'Jackpot Tiers',
          type: ParameterType.list,
          defaultValue: ['MINI', 'MINOR', 'MAJOR', 'GRAND'],
          allowedValues: ['MINI', 'MINOR', 'MAJOR', 'GRAND', 'MEGA'],
        ),
      ],
      phases: [
        FeaturePhase(
          id: 'trigger',
          name: 'Trigger',
          order: 0,
          audioSlots: const [
            AudioSlotDef(
              stage: 'JACKPOT_TRIGGER',
              label: 'Trigger Sound',
              required: true,
              priority: 95,
              defaultBus: 'SFX',
            ),
          ],
        ),
        FeaturePhase(
          id: 'buildup',
          name: 'Buildup',
          order: 1,
          audioSlots: const [
            AudioSlotDef(
              stage: 'JACKPOT_BUILDUP',
              label: 'Buildup Sound',
              description: 'Rising tension',
              priority: 90,
              defaultBus: 'Music',
            ),
          ],
        ),
        FeaturePhase(
          id: 'reveal',
          name: 'Reveal',
          order: 2,
          audioSlots: const [
            AudioSlotDef(
              stage: 'JACKPOT_REVEAL_MINI',
              label: 'Reveal MINI',
              priority: 85,
              defaultBus: 'SFX',
            ),
            AudioSlotDef(
              stage: 'JACKPOT_REVEAL_MINOR',
              label: 'Reveal MINOR',
              priority: 88,
              defaultBus: 'SFX',
            ),
            AudioSlotDef(
              stage: 'JACKPOT_REVEAL_MAJOR',
              label: 'Reveal MAJOR',
              priority: 92,
              defaultBus: 'SFX',
            ),
            AudioSlotDef(
              stage: 'JACKPOT_REVEAL_GRAND',
              label: 'Reveal GRAND',
              priority: 95,
              defaultBus: 'SFX',
            ),
          ],
        ),
        FeaturePhase(
          id: 'celebration',
          name: 'Celebration',
          order: 3,
          audioSlots: const [
            AudioSlotDef(
              stage: 'JACKPOT_CELEBRATION',
              label: 'Celebration Sound',
              description: 'Looping celebration',
              looping: true,
              priority: 90,
              defaultBus: 'Music',
            ),
          ],
        ),
        FeaturePhase(
          id: 'complete',
          name: 'Complete',
          order: 4,
          audioSlots: const [
            AudioSlotDef(
              stage: 'JACKPOT_COMPLETE',
              label: 'Complete Sound',
              required: true,
              priority: 85,
              defaultBus: 'SFX',
            ),
          ],
        ),
      ],
    );
  }
}
