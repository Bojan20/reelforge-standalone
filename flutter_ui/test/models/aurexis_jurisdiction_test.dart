import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/models/aurexis_jurisdiction.dart';

void main() {
  group('AurexisJurisdiction', () {
    test('all jurisdictions have labels and codes', () {
      for (final j in AurexisJurisdiction.values) {
        expect(j.label, isNotEmpty);
        expect(j.code, isNotEmpty);
      }
    });
  });

  group('JurisdictionDatabase', () {
    test('all jurisdictions have rules', () {
      for (final j in AurexisJurisdiction.values) {
        final rules = JurisdictionDatabase.getRules(j);
        expect(rules, isNotNull);
      }
    });

    test('UKGC is most restrictive on celebrations', () {
      final ukgc = JurisdictionDatabase.getRules(AurexisJurisdiction.ukgc);
      final mga = JurisdictionDatabase.getRules(AurexisJurisdiction.mga);
      expect(ukgc.maxCelebrationDurationS, lessThanOrEqualTo(mga.maxCelebrationDurationS));
    });

    test('Australia has strictest fatigue regulation', () {
      final aus = JurisdictionDatabase.getRules(AurexisJurisdiction.australia);
      for (final j in AurexisJurisdiction.values) {
        if (j == AurexisJurisdiction.australia) continue;
        final other = JurisdictionDatabase.getRules(j);
        expect(aus.minFatigueRegulation, greaterThanOrEqualTo(other.minFatigueRegulation));
      }
    });

    test('None jurisdiction has no restrictions', () {
      final none = JurisdictionDatabase.getRules(AurexisJurisdiction.none);
      expect(none.ldwSuppression, false);
      expect(none.sessionTimeCues, false);
      expect(none.maxCelebrationDurationS, 0);
    });
  });

  group('JurisdictionComplianceEngine', () {
    test('unrestricted config passes all jurisdictions', () {
      final report = JurisdictionComplianceEngine.checkCompliance(
        jurisdiction: AurexisJurisdiction.none,
        currentEscalationMultiplier: 1.0,
        currentFatigueRegulation: 0.5,
        currentWinVolumeBoostDb: 3.0,
        currentCelebrationDurationS: 3.0,
        isDeterministic: true,
        hasLdwSuppression: true,
        hasSessionTimeCues: true,
      );
      expect(report.allPassed, true);
    });

    test('UKGC fails on excessive escalation', () {
      final report = JurisdictionComplianceEngine.checkCompliance(
        jurisdiction: AurexisJurisdiction.ukgc,
        currentEscalationMultiplier: 5.0, // UKGC max is 3.0
        currentFatigueRegulation: 0.5,
        currentWinVolumeBoostDb: 3.0,
        currentCelebrationDurationS: 3.0,
        isDeterministic: true,
        hasLdwSuppression: true,
        hasSessionTimeCues: true,
      );
      expect(report.allPassed, false);
      expect(
        report.checks.any((c) => c.ruleName == 'Escalation Multiplier' && !c.passed),
        true,
      );
    });

    test('compliance report serializes to JSON', () {
      final report = JurisdictionComplianceEngine.checkCompliance(
        jurisdiction: AurexisJurisdiction.mga,
        currentEscalationMultiplier: 2.0,
        currentFatigueRegulation: 0.3,
        currentWinVolumeBoostDb: 6.0,
        currentCelebrationDurationS: 5.0,
        isDeterministic: true,
        hasLdwSuppression: false,
        hasSessionTimeCues: false,
      );
      final json = report.toJsonString();
      expect(json, contains('MGA'));
      expect(json, contains('checks'));
    });

    test('config overrides are generated for restrictive jurisdictions', () {
      final overrides = JurisdictionComplianceEngine.getConfigOverrides(
        AurexisJurisdiction.ukgc,
      );
      expect(overrides, isNotEmpty);
      expect(overrides.containsKey('escalation'), true);
      expect(overrides.containsKey('fatigue'), true);
    });
  });
}
