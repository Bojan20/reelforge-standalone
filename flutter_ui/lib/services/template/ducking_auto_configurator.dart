/// Ducking Auto Configurator
///
/// Sets up ducking rules based on template configuration.
/// Ducking automatically reduces bus volumes when other buses are active.
///
/// P3-12: Template Gallery
library;

import 'package:flutter/foundation.dart';

import '../../models/middleware_models.dart';
import '../../models/template_models.dart';
import '../../providers/subsystems/ducking_system_provider.dart';
import '../service_locator.dart';

/// Configures ducking rules from template
class DuckingAutoConfigurator {
  /// Configure all ducking rules from template
  ///
  /// Returns the number of rules configured
  int configureAll(BuiltTemplate template) {
    final duckingProvider = sl<DuckingSystemProvider>();
    int count = 0;

    // Clear existing rules first
    duckingProvider.clear();

    // Add template-defined rules
    for (final rule in template.source.duckingRules) {
      try {
        duckingProvider.addRule(
          sourceBus: rule.sourceBus.displayName,
          sourceBusId: rule.sourceBus.engineId,
          targetBus: rule.targetBus.displayName,
          targetBusId: rule.targetBus.engineId,
          duckAmountDb: rule.duckAmountDb,
          attackMs: rule.attackMs,
          releaseMs: rule.releaseMs,
          curve: DuckingCurve.linear,
        );
        count++;
      } catch (e) {
        debugPrint('[DuckingAutoConfigurator] ⚠️ Failed to add rule: $e');
      }
    }

    // Add default rules if template doesn't define any
    if (template.source.duckingRules.isEmpty) {
      count += _addDefaultRules(duckingProvider);
    }

    debugPrint('[DuckingAutoConfigurator] Configured $count ducking rules');
    return count;
  }

  /// Add default ducking rules
  int _addDefaultRules(DuckingSystemProvider provider) {
    int count = 0;

    // Default rules for slot audio:

    // 1. Wins duck music (prominent win sounds)
    try {
      provider.addRule(
        sourceBus: 'Wins',
        sourceBusId: TemplateBus.wins.engineId,
        targetBus: 'Music',
        targetBusId: TemplateBus.music.engineId,
        duckAmountDb: -12.0, // Strong duck for big wins
        attackMs: 30.0,
        releaseMs: 800.0,
        curve: DuckingCurve.exponential,
      );
      count++;
    } catch (e) {
      debugPrint('[DuckingAutoConfigurator] ⚠️ Failed to add wins→music rule: $e');
    }

    // 2. Voice ducks music (dialog clarity)
    try {
      provider.addRule(
        sourceBus: 'Voice',
        sourceBusId: TemplateBus.vo.engineId,
        targetBus: 'Music',
        targetBusId: TemplateBus.music.engineId,
        duckAmountDb: -10.0,
        attackMs: 20.0,
        releaseMs: 500.0,
        curve: DuckingCurve.linear,
      );
      count++;
    } catch (e) {
      debugPrint('[DuckingAutoConfigurator] ⚠️ Failed to add voice→music rule: $e');
    }

    // 3. Voice ducks SFX (dialog priority)
    try {
      provider.addRule(
        sourceBus: 'Voice',
        sourceBusId: TemplateBus.vo.engineId,
        targetBus: 'SFX',
        targetBusId: TemplateBus.sfx.engineId,
        duckAmountDb: -6.0,
        attackMs: 30.0,
        releaseMs: 400.0,
        curve: DuckingCurve.linear,
      );
      count++;
    } catch (e) {
      debugPrint('[DuckingAutoConfigurator] ⚠️ Failed to add voice→sfx rule: $e');
    }

    // 4. Wins duck ambience (focus on wins)
    try {
      provider.addRule(
        sourceBus: 'Wins',
        sourceBusId: TemplateBus.wins.engineId,
        targetBus: 'Ambience',
        targetBusId: TemplateBus.ambience.engineId,
        duckAmountDb: -18.0, // Heavy duck
        attackMs: 50.0,
        releaseMs: 1000.0,
        curve: DuckingCurve.exponential,
      );
      count++;
    } catch (e) {
      debugPrint('[DuckingAutoConfigurator] ⚠️ Failed to add wins→ambience rule: $e');
    }

    // 5. Reels duck ambience (subtle)
    try {
      provider.addRule(
        sourceBus: 'Reels',
        sourceBusId: TemplateBus.reels.engineId,
        targetBus: 'Ambience',
        targetBusId: TemplateBus.ambience.engineId,
        duckAmountDb: -6.0,
        attackMs: 100.0,
        releaseMs: 500.0,
        curve: DuckingCurve.linear,
      );
      count++;
    } catch (e) {
      debugPrint('[DuckingAutoConfigurator] ⚠️ Failed to add reels→ambience rule: $e');
    }

    return count;
  }
}
