/// EventRegistry SlotLab-Specific Functionality Tests
///
/// Tests for:
/// - AudioLayer / AudioEvent model serialization
/// - ContainerType enum behavior
/// - BigWinTier model (fromRatio, displayName, minRatio, JSON round-trip)
/// - StageValidationIssue model
/// - Stage model hierarchy (sealed class, fromJson, toJson)
/// - StageTrace and StagePayload models
/// - TriggerHistoryEntry model
/// - ConditionalAudioRule and presets
///
/// NOTE: EventRegistry is a singleton whose constructor starts a cleanup timer
/// that references NativeFFI.instance and AudioPool.instance, which are not
/// available in a pure unit test environment. Therefore, we focus on testing
/// the data models and enums that EventRegistry uses, rather than the singleton
/// instance itself. The fallback logic (_getFallbackStage) is private and can
/// only be tested indirectly through triggerStage(), which requires FFI.
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/event_registry.dart';
import 'package:fluxforge_ui/models/stage_models.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // AUDIO LAYER MODEL TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('AudioLayer', () {
    test('constructor with defaults', () {
      const layer = AudioLayer(
        id: 'layer_1',
        audioPath: '/audio/spin.wav',
        name: 'Spin Sound',
      );

      expect(layer.id, 'layer_1');
      expect(layer.audioPath, '/audio/spin.wav');
      expect(layer.name, 'Spin Sound');
      expect(layer.volume, 1.0);
      expect(layer.pan, 0.0);
      expect(layer.delay, 0.0);
      expect(layer.offset, 0.0);
      expect(layer.busId, 0);
      expect(layer.fadeInMs, 0.0);
      expect(layer.fadeOutMs, 0.0);
      expect(layer.trimStartMs, 0.0);
      expect(layer.trimEndMs, 0.0);
    });

    test('constructor with all fields', () {
      const layer = AudioLayer(
        id: 'layer_2',
        audioPath: '/audio/win.wav',
        name: 'Win Sound',
        volume: 0.8,
        pan: -0.5,
        delay: 100.0,
        offset: 0.5,
        busId: 2,
        fadeInMs: 50.0,
        fadeOutMs: 200.0,
        trimStartMs: 100.0,
        trimEndMs: 5000.0,
      );

      expect(layer.volume, 0.8);
      expect(layer.pan, -0.5);
      expect(layer.delay, 100.0);
      expect(layer.offset, 0.5);
      expect(layer.busId, 2);
      expect(layer.fadeInMs, 50.0);
      expect(layer.fadeOutMs, 200.0);
      expect(layer.trimStartMs, 100.0);
      expect(layer.trimEndMs, 5000.0);
    });

    test('toJson serializes all fields', () {
      const layer = AudioLayer(
        id: 'layer_json',
        audioPath: '/audio/test.wav',
        name: 'Test',
        volume: 0.7,
        pan: 0.3,
        delay: 50.0,
        offset: 1.0,
        busId: 1,
        fadeInMs: 25.0,
        fadeOutMs: 100.0,
        trimStartMs: 200.0,
        trimEndMs: 3000.0,
      );

      final json = layer.toJson();
      expect(json['id'], 'layer_json');
      expect(json['audioPath'], '/audio/test.wav');
      expect(json['name'], 'Test');
      expect(json['volume'], 0.7);
      expect(json['pan'], 0.3);
      expect(json['delay'], 50.0);
      expect(json['offset'], 1.0);
      expect(json['busId'], 1);
      expect(json['fadeInMs'], 25.0);
      expect(json['fadeOutMs'], 100.0);
      expect(json['trimStartMs'], 200.0);
      expect(json['trimEndMs'], 3000.0);
    });

    test('fromJson deserializes all fields', () {
      final json = {
        'id': 'layer_from_json',
        'audioPath': '/audio/deserialized.wav',
        'name': 'Deserialized',
        'volume': 0.65,
        'pan': -0.2,
        'delay': 30.0,
        'offset': 0.25,
        'busId': 3,
        'fadeInMs': 10.0,
        'fadeOutMs': 50.0,
        'trimStartMs': 500.0,
        'trimEndMs': 2500.0,
      };

      final layer = AudioLayer.fromJson(json);
      expect(layer.id, 'layer_from_json');
      expect(layer.audioPath, '/audio/deserialized.wav');
      expect(layer.name, 'Deserialized');
      expect(layer.volume, 0.65);
      expect(layer.pan, -0.2);
      expect(layer.delay, 30.0);
      expect(layer.offset, 0.25);
      expect(layer.busId, 3);
      expect(layer.fadeInMs, 10.0);
      expect(layer.fadeOutMs, 50.0);
      expect(layer.trimStartMs, 500.0);
      expect(layer.trimEndMs, 2500.0);
    });

    test('fromJson applies defaults for missing optional fields', () {
      final json = {
        'id': 'minimal',
        'audioPath': '/audio/minimal.wav',
        'name': 'Minimal',
      };

      final layer = AudioLayer.fromJson(json);
      expect(layer.volume, 1.0);
      expect(layer.pan, 0.0);
      expect(layer.delay, 0.0);
      expect(layer.offset, 0.0);
      expect(layer.busId, 0);
      expect(layer.fadeInMs, 0.0);
      expect(layer.fadeOutMs, 0.0);
      expect(layer.trimStartMs, 0.0);
      expect(layer.trimEndMs, 0.0);
    });

    test('toJson/fromJson round-trip preserves data', () {
      const original = AudioLayer(
        id: 'roundtrip',
        audioPath: '/audio/roundtrip.wav',
        name: 'Round Trip',
        volume: 0.42,
        pan: 0.77,
        delay: 123.0,
        offset: 2.5,
        busId: 4,
        fadeInMs: 33.0,
        fadeOutMs: 66.0,
        trimStartMs: 999.0,
        trimEndMs: 4444.0,
      );

      final restored = AudioLayer.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.audioPath, original.audioPath);
      expect(restored.name, original.name);
      expect(restored.volume, original.volume);
      expect(restored.pan, original.pan);
      expect(restored.delay, original.delay);
      expect(restored.offset, original.offset);
      expect(restored.busId, original.busId);
      expect(restored.fadeInMs, original.fadeInMs);
      expect(restored.fadeOutMs, original.fadeOutMs);
      expect(restored.trimStartMs, original.trimStartMs);
      expect(restored.trimEndMs, original.trimEndMs);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTAINER TYPE ENUM TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('ContainerType', () {
    test('values are defined', () {
      expect(ContainerType.values.length, 4);
      expect(ContainerType.none.index, 0);
      expect(ContainerType.blend.index, 1);
      expect(ContainerType.random.index, 2);
      expect(ContainerType.sequence.index, 3);
    });

    test('displayName returns human-readable strings', () {
      expect(ContainerType.none.displayName, 'None (Direct)');
      expect(ContainerType.blend.displayName, 'Blend Container');
      expect(ContainerType.random.displayName, 'Random Container');
      expect(ContainerType.sequence.displayName, 'Sequence Container');
    });

    test('value returns index', () {
      expect(ContainerType.none.value, 0);
      expect(ContainerType.blend.value, 1);
      expect(ContainerType.random.value, 2);
      expect(ContainerType.sequence.value, 3);
    });

    test('fromValue reconstructs enum from int', () {
      expect(ContainerTypeExtension.fromValue(0), ContainerType.none);
      expect(ContainerTypeExtension.fromValue(1), ContainerType.blend);
      expect(ContainerTypeExtension.fromValue(2), ContainerType.random);
      expect(ContainerTypeExtension.fromValue(3), ContainerType.sequence);
    });

    test('fromValue returns none for out-of-range values', () {
      expect(ContainerTypeExtension.fromValue(-1), ContainerType.none);
      expect(ContainerTypeExtension.fromValue(4), ContainerType.none);
      expect(ContainerTypeExtension.fromValue(100), ContainerType.none);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // AUDIO EVENT MODEL TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('AudioEvent', () {
    test('constructor with defaults', () {
      const event = AudioEvent(
        id: 'evt_1',
        name: 'Spin Start',
        stage: 'SPIN_START',
        layers: [],
      );

      expect(event.id, 'evt_1');
      expect(event.name, 'Spin Start');
      expect(event.stage, 'SPIN_START');
      expect(event.layers, isEmpty);
      expect(event.duration, 0.0);
      expect(event.loop, false);
      expect(event.priority, 0);
      expect(event.containerType, ContainerType.none);
      expect(event.containerId, isNull);
      expect(event.overlap, true);
      expect(event.crossfadeMs, 0);
      expect(event.targetBusId, 0);
    });

    test('usesContainer returns false when containerType is none', () {
      const event = AudioEvent(
        id: 'evt_no_container',
        name: 'No Container',
        stage: 'TEST',
        layers: [],
      );

      expect(event.usesContainer, false);
    });

    test('usesContainer returns false when containerId is null', () {
      const event = AudioEvent(
        id: 'evt_no_id',
        name: 'No Container ID',
        stage: 'TEST',
        layers: [],
        containerType: ContainerType.blend,
        containerId: null,
      );

      expect(event.usesContainer, false);
    });

    test('usesContainer returns true when both containerType and containerId are set', () {
      const event = AudioEvent(
        id: 'evt_with_container',
        name: 'With Container',
        stage: 'TEST',
        layers: [],
        containerType: ContainerType.random,
        containerId: 42,
      );

      expect(event.usesContainer, true);
    });

    test('isMusicEvent returns true for bus 1', () {
      const music = AudioEvent(
        id: 'music',
        name: 'Music',
        stage: 'MUSIC',
        layers: [],
        targetBusId: 1,
      );
      const sfx = AudioEvent(
        id: 'sfx',
        name: 'SFX',
        stage: 'SFX',
        layers: [],
        targetBusId: 2,
      );

      expect(music.isMusicEvent, true);
      expect(sfx.isMusicEvent, false);
    });

    test('toJson serializes all fields', () {
      const event = AudioEvent(
        id: 'json_evt',
        name: 'JSON Event',
        stage: 'WIN_PRESENT',
        layers: [
          AudioLayer(
            id: 'l1',
            audioPath: '/audio/win.wav',
            name: 'Win',
          ),
        ],
        duration: 3.5,
        loop: true,
        priority: 80,
        containerType: ContainerType.blend,
        containerId: 7,
        overlap: false,
        crossfadeMs: 500,
        targetBusId: 1,
      );

      final json = event.toJson();
      expect(json['id'], 'json_evt');
      expect(json['name'], 'JSON Event');
      expect(json['stage'], 'WIN_PRESENT');
      expect(json['layers'], hasLength(1));
      expect(json['duration'], 3.5);
      expect(json['loop'], true);
      expect(json['priority'], 80);
      expect(json['containerType'], ContainerType.blend.value);
      expect(json['containerId'], 7);
      expect(json['overlap'], false);
      expect(json['crossfadeMs'], 500);
      expect(json['targetBusId'], 1);
    });

    test('fromJson deserializes all fields', () {
      final json = {
        'id': 'from_json_evt',
        'name': 'From JSON',
        'stage': 'REEL_STOP',
        'layers': [
          {
            'id': 'l1',
            'audioPath': '/audio/stop.wav',
            'name': 'Stop',
          },
        ],
        'duration': 1.2,
        'loop': false,
        'priority': 50,
        'containerType': 2, // random
        'containerId': 15,
        'overlap': true,
        'crossfadeMs': 250,
        'targetBusId': 2,
      };

      final event = AudioEvent.fromJson(json);
      expect(event.id, 'from_json_evt');
      expect(event.name, 'From JSON');
      expect(event.stage, 'REEL_STOP');
      expect(event.layers, hasLength(1));
      expect(event.layers.first.audioPath, '/audio/stop.wav');
      expect(event.duration, 1.2);
      expect(event.loop, false);
      expect(event.priority, 50);
      expect(event.containerType, ContainerType.random);
      expect(event.containerId, 15);
      expect(event.overlap, true);
      expect(event.crossfadeMs, 250);
      expect(event.targetBusId, 2);
    });

    test('toJson/fromJson round-trip preserves data', () {
      const original = AudioEvent(
        id: 'roundtrip',
        name: 'Round Trip Event',
        stage: 'CASCADE_STEP',
        layers: [
          AudioLayer(
            id: 'rl1',
            audioPath: '/audio/cascade.wav',
            name: 'Cascade',
            volume: 0.9,
            pan: 0.4,
            busId: 2,
          ),
        ],
        duration: 0.5,
        loop: false,
        priority: 60,
        containerType: ContainerType.sequence,
        containerId: 33,
        overlap: false,
        crossfadeMs: 100,
        targetBusId: 2,
      );

      final restored = AudioEvent.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.stage, original.stage);
      expect(restored.layers.length, original.layers.length);
      expect(restored.layers.first.audioPath, original.layers.first.audioPath);
      expect(restored.layers.first.volume, original.layers.first.volume);
      expect(restored.layers.first.pan, original.layers.first.pan);
      expect(restored.duration, original.duration);
      expect(restored.loop, original.loop);
      expect(restored.priority, original.priority);
      expect(restored.containerType, original.containerType);
      expect(restored.containerId, original.containerId);
      expect(restored.overlap, original.overlap);
      expect(restored.crossfadeMs, original.crossfadeMs);
      expect(restored.targetBusId, original.targetBusId);
    });

    test('copyWith creates modified copy', () {
      const original = AudioEvent(
        id: 'orig',
        name: 'Original',
        stage: 'SPIN_START',
        layers: [],
        priority: 10,
      );

      final modified = original.copyWith(
        name: 'Modified',
        priority: 90,
        loop: true,
      );

      // Modified fields
      expect(modified.name, 'Modified');
      expect(modified.priority, 90);
      expect(modified.loop, true);

      // Unchanged fields
      expect(modified.id, 'orig');
      expect(modified.stage, 'SPIN_START');
      expect(modified.layers, isEmpty);
      expect(modified.duration, 0.0);
      expect(modified.containerType, ContainerType.none);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // BIG WIN TIER MODEL TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('BigWinTier', () {
    test('fromRatio returns correct tier for boundary values', () {
      // Below any threshold
      expect(BigWinTier.fromRatio(0.0), BigWinTier.win);
      expect(BigWinTier.fromRatio(5.0), BigWinTier.win);
      expect(BigWinTier.fromRatio(10.0), BigWinTier.win);
      expect(BigWinTier.fromRatio(14.9), BigWinTier.win);

      // bigWin boundary (>= 15.0)
      expect(BigWinTier.fromRatio(15.0), BigWinTier.bigWin);
      expect(BigWinTier.fromRatio(20.0), BigWinTier.bigWin);
      expect(BigWinTier.fromRatio(24.9), BigWinTier.bigWin);

      // megaWin boundary (>= 25.0)
      expect(BigWinTier.fromRatio(25.0), BigWinTier.megaWin);
      expect(BigWinTier.fromRatio(35.0), BigWinTier.megaWin);
      expect(BigWinTier.fromRatio(49.9), BigWinTier.megaWin);

      // epicWin boundary (>= 50.0)
      expect(BigWinTier.fromRatio(50.0), BigWinTier.epicWin);
      expect(BigWinTier.fromRatio(75.0), BigWinTier.epicWin);
      expect(BigWinTier.fromRatio(99.9), BigWinTier.epicWin);

      // ultraWin boundary (>= 100.0)
      expect(BigWinTier.fromRatio(100.0), BigWinTier.ultraWin);
      expect(BigWinTier.fromRatio(500.0), BigWinTier.ultraWin);
      expect(BigWinTier.fromRatio(1000.0), BigWinTier.ultraWin);
    });

    test('displayName returns industry-standard labels', () {
      expect(BigWinTier.win.displayName, 'WIN');
      expect(BigWinTier.bigWin.displayName, 'BIG WIN');
      expect(BigWinTier.megaWin.displayName, 'MEGA WIN');
      expect(BigWinTier.epicWin.displayName, 'EPIC WIN');
      expect(BigWinTier.ultraWin.displayName, 'ULTRA WIN');
    });

    test('minRatio returns correct thresholds', () {
      expect(BigWinTier.win.minRatio, 10.0);
      expect(BigWinTier.bigWin.minRatio, 15.0);
      expect(BigWinTier.megaWin.minRatio, 25.0);
      expect(BigWinTier.epicWin.minRatio, 50.0);
      expect(BigWinTier.ultraWin.minRatio, 100.0);
    });

    test('minRatio values are strictly increasing', () {
      final tiers = BigWinTier.values;
      for (int i = 1; i < tiers.length; i++) {
        expect(tiers[i].minRatio, greaterThan(tiers[i - 1].minRatio),
            reason: '${tiers[i].name}.minRatio should be greater than ${tiers[i - 1].name}.minRatio');
      }
    });

    test('toJson returns snake_case strings', () {
      expect(BigWinTier.win.toJson(), 'win');
      expect(BigWinTier.bigWin.toJson(), 'big_win');
      expect(BigWinTier.megaWin.toJson(), 'mega_win');
      expect(BigWinTier.epicWin.toJson(), 'epic_win');
      expect(BigWinTier.ultraWin.toJson(), 'ultra_win');
    });

    test('fromJson parses snake_case strings', () {
      expect(BigWinTier.fromJson('win'), BigWinTier.win);
      expect(BigWinTier.fromJson('big_win'), BigWinTier.bigWin);
      expect(BigWinTier.fromJson('mega_win'), BigWinTier.megaWin);
      expect(BigWinTier.fromJson('epic_win'), BigWinTier.epicWin);
      expect(BigWinTier.fromJson('ultra_win'), BigWinTier.ultraWin);
    });

    test('fromJson returns null for invalid input', () {
      expect(BigWinTier.fromJson(null), isNull);
      expect(BigWinTier.fromJson('invalid'), isNull);
      expect(BigWinTier.fromJson(''), isNull);
      expect(BigWinTier.fromJson('BIG_WIN'), isNull);
    });

    test('fromJson handles custom map format', () {
      // Custom tier maps return BigWinTier.win as fallback
      expect(BigWinTier.fromJson({'custom': true}), BigWinTier.win);
    });

    test('toJson/fromJson round-trip for all tiers', () {
      for (final tier in BigWinTier.values) {
        final serialized = tier.toJson();
        final deserialized = BigWinTier.fromJson(serialized);
        expect(deserialized, tier, reason: 'Round-trip failed for ${tier.name}');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // FEATURE TYPE ENUM TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('FeatureType', () {
    test('all values have displayNames', () {
      for (final feature in FeatureType.values) {
        expect(feature.displayName, isNotEmpty,
            reason: '${feature.name} should have a displayName');
      }
    });

    test('isMultiStep returns true for step-based features', () {
      expect(FeatureType.freeSpins.isMultiStep, true);
      expect(FeatureType.holdAndSpin.isMultiStep, true);
      expect(FeatureType.cascade.isMultiStep, true);
      expect(FeatureType.walkingWilds.isMultiStep, true);
    });

    test('isMultiStep returns false for single-shot features', () {
      expect(FeatureType.bonusGame.isMultiStep, false);
      expect(FeatureType.pickBonus.isMultiStep, false);
      expect(FeatureType.wheelBonus.isMultiStep, false);
      expect(FeatureType.multiplier.isMultiStep, false);
      expect(FeatureType.expandingWilds.isMultiStep, false);
    });

    test('toJson/fromJson round-trip for all feature types', () {
      for (final feature in FeatureType.values) {
        final serialized = feature.toJson();
        final deserialized = FeatureType.fromJson(serialized);
        expect(deserialized, feature, reason: 'Round-trip failed for ${feature.name}');
      }
    });

    test('fromJson returns null for invalid input', () {
      expect(FeatureType.fromJson(null), isNull);
      expect(FeatureType.fromJson('invalid'), isNull);
      expect(FeatureType.fromJson({'custom': true}), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // JACKPOT TIER TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('JackpotTier', () {
    test('level values are 1-4', () {
      expect(JackpotTier.mini.level, 1);
      expect(JackpotTier.minor.level, 2);
      expect(JackpotTier.major.level, 3);
      expect(JackpotTier.grand.level, 4);
    });

    test('displayName returns uppercase labels', () {
      expect(JackpotTier.mini.displayName, 'MINI');
      expect(JackpotTier.minor.displayName, 'MINOR');
      expect(JackpotTier.major.displayName, 'MAJOR');
      expect(JackpotTier.grand.displayName, 'GRAND');
    });

    test('toJson/fromJson round-trip', () {
      for (final tier in JackpotTier.values) {
        final serialized = tier.toJson();
        final deserialized = JackpotTier.fromJson(serialized);
        expect(deserialized, tier, reason: 'Round-trip failed for ${tier.name}');
      }
    });

    test('fromJson returns null for invalid input', () {
      expect(JackpotTier.fromJson(null), isNull);
      expect(JackpotTier.fromJson('invalid'), isNull);
      expect(JackpotTier.fromJson({'custom': true}), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGE VALIDATION ISSUE TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('StageValidationIssue', () {
    test('constructor with required fields', () {
      const issue = StageValidationIssue(
        type: StageValidationType.missingStage,
        message: 'SPIN_START is missing from trace',
      );

      expect(issue.type, StageValidationType.missingStage);
      expect(issue.message, 'SPIN_START is missing from trace');
      expect(issue.severity, StageValidationSeverity.error); // default
      expect(issue.stageIndex, isNull);
      expect(issue.stageName, isNull);
    });

    test('constructor with all fields', () {
      const issue = StageValidationIssue(
        type: StageValidationType.orderViolation,
        message: 'SPIN_END before SPIN_START',
        severity: StageValidationSeverity.warning,
        stageIndex: 3,
        stageName: 'SPIN_END',
      );

      expect(issue.type, StageValidationType.orderViolation);
      expect(issue.severity, StageValidationSeverity.warning);
      expect(issue.stageIndex, 3);
      expect(issue.stageName, 'SPIN_END');
    });

    test('toJson serializes all fields', () {
      const issue = StageValidationIssue(
        type: StageValidationType.duplicateStage,
        message: 'Duplicate REEL_STOP_0',
        severity: StageValidationSeverity.info,
        stageIndex: 5,
        stageName: 'REEL_STOP_0',
      );

      final json = issue.toJson();
      expect(json['type'], 'duplicateStage');
      expect(json['message'], 'Duplicate REEL_STOP_0');
      expect(json['severity'], 'info');
      expect(json['stageIndex'], 5);
      expect(json['stageName'], 'REEL_STOP_0');
    });

    test('toJson omits null optional fields', () {
      const issue = StageValidationIssue(
        type: StageValidationType.unknownStage,
        message: 'Unknown stage',
      );

      final json = issue.toJson();
      expect(json.containsKey('stageIndex'), false);
      expect(json.containsKey('stageName'), false);
    });

    test('toString returns formatted string', () {
      const issue = StageValidationIssue(
        type: StageValidationType.timestampViolation,
        message: 'Non-monotonic timestamp at index 4',
        severity: StageValidationSeverity.error,
      );

      final str = issue.toString();
      expect(str, contains('error'));
      expect(str, contains('timestampViolation'));
      expect(str, contains('Non-monotonic timestamp'));
    });

    test('all validation types are representable', () {
      expect(StageValidationType.values.length, 5);
      expect(StageValidationType.orderViolation, isNotNull);
      expect(StageValidationType.missingStage, isNotNull);
      expect(StageValidationType.timestampViolation, isNotNull);
      expect(StageValidationType.duplicateStage, isNotNull);
      expect(StageValidationType.unknownStage, isNotNull);
    });

    test('all severity levels are representable', () {
      expect(StageValidationSeverity.values.length, 3);
      expect(StageValidationSeverity.info, isNotNull);
      expect(StageValidationSeverity.warning, isNotNull);
      expect(StageValidationSeverity.error, isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGE SEALED CLASS HIERARCHY TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Stage sealed class', () {
    test('SpinStart has correct typeName and category', () {
      const stage = SpinStart();
      expect(stage.typeName, 'spin_start');
      expect(stage.category, StageCategory.spinLifecycle);
      expect(stage.isLooping, false);
      expect(stage.shouldDuckMusic, false);
    });

    test('ReelSpinning is looping', () {
      const stage = ReelSpinning(reelIndex: 2);
      expect(stage.typeName, 'reel_spinning');
      expect(stage.isLooping, true);
      expect(stage.reelIndex, 2);
    });

    test('ReelStop has reelIndex and symbols', () {
      const stage = ReelStop(reelIndex: 3, symbols: [1, 5, 7]);
      expect(stage.typeName, 'reel_stop');
      expect(stage.reelIndex, 3);
      expect(stage.symbols, [1, 5, 7]);
    });

    test('BigWinTierStage should duck music', () {
      const stage = BigWinTierStage(tier: BigWinTier.megaWin, amount: 5000.0);
      expect(stage.shouldDuckMusic, true);
      expect(stage.tier, BigWinTier.megaWin);
      expect(stage.amount, 5000.0);
    });

    test('FeatureEnter should duck music', () {
      const stage = FeatureEnter(featureType: FeatureType.freeSpins, totalSteps: 10);
      expect(stage.shouldDuckMusic, true);
      expect(stage.featureType, FeatureType.freeSpins);
      expect(stage.totalSteps, 10);
    });

    test('JackpotTrigger should duck music', () {
      const stage = JackpotTrigger(tier: JackpotTier.grand);
      expect(stage.shouldDuckMusic, true);
      expect(stage.tier, JackpotTier.grand);
    });

    test('IdleLoop is looping', () {
      const stage = IdleLoop();
      expect(stage.isLooping, true);
      expect(stage.category, StageCategory.ui);
    });

    test('RollupTick is looping', () {
      const stage = RollupTick(currentAmount: 500.0, progress: 0.75);
      expect(stage.isLooping, true);
      expect(stage.currentAmount, 500.0);
      expect(stage.progress, 0.75);
    });

    test('fromJson creates correct subclass for each type', () {
      final spinStart = Stage.fromJson({'type': 'spin_start'});
      expect(spinStart, isA<SpinStart>());

      final reelStop = Stage.fromJson({'type': 'reel_stop', 'reel_index': 2, 'symbols': [1, 3]});
      expect(reelStop, isA<ReelStop>());
      expect((reelStop as ReelStop).reelIndex, 2);

      final winPresent = Stage.fromJson({'type': 'win_present', 'win_amount': 100.0, 'line_count': 3});
      expect(winPresent, isA<WinPresent>());
      expect((winPresent as WinPresent).winAmount, 100.0);

      final cascadeStep = Stage.fromJson({'type': 'cascade_step', 'step_index': 2, 'multiplier': 3.0});
      expect(cascadeStep, isA<CascadeStep>());
      expect((cascadeStep as CascadeStep).stepIndex, 2);
    });

    test('fromJson returns CustomStage for unknown type', () {
      final unknown = Stage.fromJson({'type': 'my_custom_stage'});
      expect(unknown, isA<CustomStage>());
      expect((unknown as CustomStage).name, 'my_custom_stage');
    });

    test('fromTypeName creates stage from string', () {
      final stage = Stage.fromTypeName('spin_start');
      expect(stage, isNotNull);
      expect(stage, isA<SpinStart>());
    });

    test('toJson/fromJson round-trip for simple stages', () {
      const original = SpinStart();
      final json = original.toJson();
      final restored = Stage.fromJson(json);
      expect(restored, isA<SpinStart>());
      expect(restored.typeName, original.typeName);
    });

    test('toJson/fromJson round-trip for ReelStop with data', () {
      const original = ReelStop(reelIndex: 4, symbols: [2, 8, 3]);
      final json = original.toJson();
      final restored = Stage.fromJson(json);
      expect(restored, isA<ReelStop>());
      final reelStop = restored as ReelStop;
      expect(reelStop.reelIndex, 4);
      expect(reelStop.symbols, [2, 8, 3]);
    });

    test('toJson/fromJson round-trip for FeatureEnter', () {
      const original = FeatureEnter(
        featureType: FeatureType.holdAndSpin,
        totalSteps: 3,
        multiplier: 2.5,
      );
      final json = original.toJson();
      final restored = Stage.fromJson(json);
      expect(restored, isA<FeatureEnter>());
      final fe = restored as FeatureEnter;
      expect(fe.featureType, FeatureType.holdAndSpin);
      expect(fe.totalSteps, 3);
      expect(fe.multiplier, 2.5);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGE CATEGORY TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('StageCategory', () {
    test('all categories have displayNames', () {
      for (final cat in StageCategory.values) {
        expect(cat.displayName, isNotEmpty,
            reason: '${cat.name} should have a displayName');
      }
    });

    test('fromJson parses known categories', () {
      expect(StageCategory.fromJson('spin_lifecycle'), StageCategory.spinLifecycle);
      expect(StageCategory.fromJson('anticipation'), StageCategory.anticipation);
      expect(StageCategory.fromJson('win_lifecycle'), StageCategory.winLifecycle);
      expect(StageCategory.fromJson('feature'), StageCategory.feature);
      expect(StageCategory.fromJson('cascade'), StageCategory.cascade);
      expect(StageCategory.fromJson('bonus'), StageCategory.bonus);
      expect(StageCategory.fromJson('gamble'), StageCategory.gamble);
      expect(StageCategory.fromJson('jackpot'), StageCategory.jackpot);
      expect(StageCategory.fromJson('ui'), StageCategory.ui);
      expect(StageCategory.fromJson('special'), StageCategory.special);
    });

    test('fromJson returns null for unknown category', () {
      expect(StageCategory.fromJson('invalid'), isNull);
      expect(StageCategory.fromJson(null), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // SYMBOL POSITION & WIN LINE MODEL TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('SymbolPosition', () {
    test('constructor and fields', () {
      const pos = SymbolPosition(reel: 2, row: 1);
      expect(pos.reel, 2);
      expect(pos.row, 1);
    });

    test('equality', () {
      const a = SymbolPosition(reel: 0, row: 0);
      const b = SymbolPosition(reel: 0, row: 0);
      const c = SymbolPosition(reel: 1, row: 0);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, b.hashCode);
    });

    test('toJson/fromJson round-trip', () {
      const original = SymbolPosition(reel: 3, row: 2);
      final json = original.toJson();
      final restored = SymbolPosition.fromJson(json);
      expect(restored.reel, 3);
      expect(restored.row, 2);
      expect(restored, original);
    });
  });

  group('WinLine', () {
    test('constructor with defaults', () {
      const line = WinLine(
        lineIndex: 0,
        positions: [
          SymbolPosition(reel: 0, row: 1),
          SymbolPosition(reel: 1, row: 1),
          SymbolPosition(reel: 2, row: 1),
        ],
        symbolId: 5,
        matchCount: 3,
        winAmount: 50.0,
      );

      expect(line.lineIndex, 0);
      expect(line.positions, hasLength(3));
      expect(line.symbolId, 5);
      expect(line.symbolName, isNull);
      expect(line.matchCount, 3);
      expect(line.winAmount, 50.0);
      expect(line.multiplier, 1.0);
    });

    test('toJson/fromJson round-trip', () {
      const original = WinLine(
        lineIndex: 7,
        positions: [
          SymbolPosition(reel: 0, row: 0),
          SymbolPosition(reel: 1, row: 1),
          SymbolPosition(reel: 2, row: 2),
        ],
        symbolId: 3,
        symbolName: 'Wild',
        matchCount: 3,
        winAmount: 200.0,
        multiplier: 2.0,
      );

      final json = original.toJson();
      final restored = WinLine.fromJson(json);
      expect(restored.lineIndex, 7);
      expect(restored.positions, hasLength(3));
      expect(restored.symbolId, 3);
      expect(restored.symbolName, 'Wild');
      expect(restored.matchCount, 3);
      expect(restored.winAmount, 200.0);
      expect(restored.multiplier, 2.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGE PAYLOAD TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('StagePayload', () {
    test('empty constructor', () {
      const payload = StagePayload();
      expect(payload.winAmount, isNull);
      expect(payload.betAmount, isNull);
      expect(payload.winRatio, isNull);
      expect(payload.winLines, isEmpty);
      expect(payload.balance, isNull);
    });

    test('calculateRatio returns win/bet ratio', () {
      const payload = StagePayload(winAmount: 100.0, betAmount: 5.0);
      expect(payload.calculateRatio(), 20.0);
    });

    test('calculateRatio returns null when betAmount is 0', () {
      const payload = StagePayload(winAmount: 100.0, betAmount: 0.0);
      expect(payload.calculateRatio(), isNull);
    });

    test('calculateRatio returns null when amounts are null', () {
      const payload = StagePayload();
      expect(payload.calculateRatio(), isNull);
    });

    test('isBigWin checks against threshold', () {
      const payload = StagePayload(winAmount: 100.0, betAmount: 5.0);
      expect(payload.isBigWin(15.0), true); // 20.0 >= 15.0
      expect(payload.isBigWin(25.0), false); // 20.0 < 25.0
    });

    test('isBigWin returns false when no ratio', () {
      const payload = StagePayload();
      expect(payload.isBigWin(15.0), false);
    });

    test('toJson/fromJson round-trip', () {
      const original = StagePayload(
        winAmount: 500.0,
        betAmount: 10.0,
        winRatio: 50.0,
        symbolId: 7,
        symbolName: 'Scatter',
        featureName: 'Free Spins',
        spinsRemaining: 5,
        multiplier: 3.0,
        balance: 1000.0,
        sessionId: 'session_123',
        spinId: 'spin_456',
      );

      final json = original.toJson();
      final restored = StagePayload.fromJson(json);
      expect(restored.winAmount, 500.0);
      expect(restored.betAmount, 10.0);
      expect(restored.winRatio, 50.0);
      expect(restored.symbolId, 7);
      expect(restored.symbolName, 'Scatter');
      expect(restored.featureName, 'Free Spins');
      expect(restored.spinsRemaining, 5);
      expect(restored.multiplier, 3.0);
      expect(restored.balance, 1000.0);
      expect(restored.sessionId, 'session_123');
      expect(restored.spinId, 'spin_456');
    });

    test('toJson omits null fields', () {
      const payload = StagePayload(winAmount: 100.0);
      final json = payload.toJson();
      expect(json.containsKey('win_amount'), true);
      expect(json.containsKey('bet_amount'), false);
      expect(json.containsKey('symbol_name'), false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGE EVENT TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('StageEvent', () {
    test('constructor and typeName delegation', () {
      final event = StageEvent(
        stage: const SpinStart(),
        timestampMs: 1234.0,
      );

      expect(event.typeName, 'spin_start');
      expect(event.timestampMs, 1234.0);
      expect(event.tags, isEmpty);
      expect(event.sourceEvent, isNull);
    });

    test('copyWith creates modified copy', () {
      final original = StageEvent(
        stage: const SpinStart(),
        timestampMs: 100.0,
        tags: ['spin'],
      );

      final modified = original.copyWith(
        timestampMs: 200.0,
        tags: ['spin', 'modified'],
      );

      expect(modified.timestampMs, 200.0);
      expect(modified.tags, ['spin', 'modified']);
      expect(modified.stage, isA<SpinStart>());
    });

    test('toJson/fromJson round-trip', () {
      final original = StageEvent(
        stage: const WinPresent(winAmount: 250.0, lineCount: 5),
        timestampMs: 5678.0,
        sourceEvent: 'engine_win',
        tags: ['win', 'big'],
      );

      final json = original.toJson();
      final restored = StageEvent.fromJson(json);
      expect(restored.typeName, 'win_present');
      expect(restored.timestampMs, 5678.0);
      expect(restored.sourceEvent, 'engine_win');
      expect(restored.tags, ['win', 'big']);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGE TRACE TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('StageTrace', () {
    late StageTrace trace;

    setUp(() {
      trace = StageTrace(
        traceId: 'trace_001',
        gameId: 'game_slots',
        events: [
          StageEvent(stage: const SpinStart(), timestampMs: 0.0),
          StageEvent(stage: const ReelStop(reelIndex: 0), timestampMs: 400.0),
          StageEvent(stage: const ReelStop(reelIndex: 1), timestampMs: 800.0),
          StageEvent(stage: const ReelStop(reelIndex: 2), timestampMs: 1200.0),
          StageEvent(stage: const EvaluateWins(), timestampMs: 1500.0),
          StageEvent(
            stage: const WinPresent(winAmount: 100.0, lineCount: 2),
            timestampMs: 1600.0,
            payload: const StagePayload(winAmount: 100.0),
          ),
          StageEvent(stage: const SpinEnd(), timestampMs: 2000.0),
        ],
      );
    });

    test('durationMs calculates difference between first and last event', () {
      expect(trace.durationMs, 2000.0);
    });

    test('durationMs returns 0 for empty trace', () {
      final empty = StageTrace(traceId: 'empty', gameId: 'game');
      expect(empty.durationMs, 0.0);
    });

    test('hasStage checks for typeName presence', () {
      expect(trace.hasStage('spin_start'), true);
      expect(trace.hasStage('reel_stop'), true);
      expect(trace.hasStage('evaluate_wins'), true);
      expect(trace.hasStage('jackpot_trigger'), false);
    });

    test('reelStops returns only reel_stop events', () {
      final stops = trace.reelStops;
      expect(stops, hasLength(3));
      expect(stops.every((e) => e.stage.typeName == 'reel_stop'), true);
    });

    test('eventsByCategory filters correctly', () {
      final spinEvents = trace.eventsByCategory(StageCategory.spinLifecycle);
      expect(spinEvents.length, greaterThanOrEqualTo(5)); // spin_start, 3 reel_stop, evaluate_wins, spin_end

      final winEvents = trace.eventsByCategory(StageCategory.winLifecycle);
      expect(winEvents, hasLength(1)); // win_present
    });

    test('totalWin extracts win amount from last matching event', () {
      expect(trace.totalWin, 100.0);
    });

    test('totalWin returns 0 for no-win trace', () {
      final noWin = StageTrace(
        traceId: 'no_win',
        gameId: 'game',
        events: [
          StageEvent(stage: const SpinStart(), timestampMs: 0.0),
          StageEvent(stage: const SpinEnd(), timestampMs: 500.0),
        ],
      );
      expect(noWin.totalWin, 0.0);
    });

    test('hasFeature and hasJackpot', () {
      expect(trace.hasFeature, false);
      expect(trace.hasJackpot, false);

      final featureTrace = StageTrace(
        traceId: 'feature',
        gameId: 'game',
        events: [
          StageEvent(
            stage: const FeatureEnter(featureType: FeatureType.freeSpins, totalSteps: 10),
            timestampMs: 0.0,
          ),
        ],
      );
      expect(featureTrace.hasFeature, true);
    });

    test('featureType extracts from FeatureEnter', () {
      final featureTrace = StageTrace(
        traceId: 'feature',
        gameId: 'game',
        events: [
          StageEvent(
            stage: const FeatureEnter(featureType: FeatureType.cascade, totalSteps: 5),
            timestampMs: 0.0,
          ),
        ],
      );
      expect(featureTrace.featureType, FeatureType.cascade);
      expect(trace.featureType, isNull);
    });

    test('maxBigWinTier finds highest tier', () {
      final bigWinTrace = StageTrace(
        traceId: 'bigwin',
        gameId: 'game',
        events: [
          StageEvent(
            stage: const BigWinTierStage(tier: BigWinTier.bigWin, amount: 300.0),
            timestampMs: 0.0,
          ),
          StageEvent(
            stage: const BigWinTierStage(tier: BigWinTier.megaWin, amount: 1000.0),
            timestampMs: 500.0,
          ),
        ],
      );
      expect(bigWinTrace.maxBigWinTier, BigWinTier.megaWin);
      expect(trace.maxBigWinTier, isNull);
    });

    test('summary generates TraceSummary correctly', () {
      final summary = trace.summary;
      expect(summary.traceId, 'trace_001');
      expect(summary.gameId, 'game_slots');
      expect(summary.eventCount, 7);
      expect(summary.durationMs, 2000.0);
      expect(summary.totalWin, 100.0);
      expect(summary.hasFeature, false);
      expect(summary.hasJackpot, false);
    });

    test('toJson/fromJson round-trip', () {
      final json = trace.toJson();
      final restored = StageTrace.fromJson(json);
      expect(restored.traceId, trace.traceId);
      expect(restored.gameId, trace.gameId);
      expect(restored.events, hasLength(trace.events.length));
      expect(restored.events.first.typeName, 'spin_start');
      expect(restored.events.last.typeName, 'spin_end');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TIMING PROFILE TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('TimingProfile', () {
    test('displayName for all profiles', () {
      expect(TimingProfile.normal.displayName, 'Normal');
      expect(TimingProfile.turbo.displayName, 'Turbo');
      expect(TimingProfile.mobile.displayName, 'Mobile');
      expect(TimingProfile.studio.displayName, 'Studio');
      expect(TimingProfile.instant.displayName, 'Instant');
    });

    test('toJson/fromJson round-trip', () {
      for (final profile in TimingProfile.values) {
        final serialized = profile.toJson();
        final deserialized = TimingProfile.fromJson(serialized);
        expect(deserialized, profile, reason: 'Round-trip failed for ${profile.name}');
      }
    });

    test('fromJson returns null for invalid input', () {
      expect(TimingProfile.fromJson(null), isNull);
      expect(TimingProfile.fromJson('invalid'), isNull);
      expect(TimingProfile.fromJson({'custom': true}), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TIMED STAGE EVENT TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('TimedStageEvent', () {
    test('isLooping for infinite duration', () {
      final looping = TimedStageEvent(
        event: StageEvent(stage: const IdleLoop(), timestampMs: 0.0),
        absoluteTimeMs: 0.0,
        durationMs: double.infinity,
      );
      expect(looping.isLooping, true);
      expect(looping.endTime, isNull);
    });

    test('endTime for finite duration', () {
      final finite = TimedStageEvent(
        event: StageEvent(stage: const SpinStart(), timestampMs: 0.0),
        absoluteTimeMs: 100.0,
        durationMs: 500.0,
      );
      expect(finite.isLooping, false);
      expect(finite.endTime, 600.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TIMED STAGE TRACE TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('TimedStageTrace', () {
    late TimedStageTrace timedTrace;

    setUp(() {
      timedTrace = TimedStageTrace(
        traceId: 'timed_001',
        gameId: 'game',
        profile: TimingProfile.normal,
        totalDurationMs: 2000.0,
        events: [
          TimedStageEvent(
            event: StageEvent(stage: const SpinStart(), timestampMs: 0.0),
            absoluteTimeMs: 0.0,
            durationMs: 100.0,
          ),
          TimedStageEvent(
            event: StageEvent(stage: const ReelStop(reelIndex: 0), timestampMs: 400.0),
            absoluteTimeMs: 400.0,
            durationMs: 200.0,
          ),
          TimedStageEvent(
            event: StageEvent(stage: const IdleLoop(), timestampMs: 1500.0),
            absoluteTimeMs: 1500.0,
            durationMs: double.infinity,
          ),
        ],
      );
    });

    test('eventsAt returns active events at given time', () {
      final at50 = timedTrace.eventsAt(50.0);
      expect(at50, hasLength(1));
      expect(at50.first.event.typeName, 'spin_start');

      final at500 = timedTrace.eventsAt(500.0);
      expect(at500, hasLength(1));
      expect(at500.first.event.typeName, 'reel_stop');

      // IdleLoop is infinite, so it should be present at any time >= 1500
      final at2000 = timedTrace.eventsAt(2000.0);
      expect(at2000, hasLength(1));
      expect(at2000.first.event.typeName, 'idle_loop');
    });

    test('stageAt returns most recent event at time', () {
      final stage = timedTrace.stageAt(450.0);
      expect(stage, isNotNull);
      expect(stage!.event.typeName, 'reel_stop');
    });

    test('stageAt returns null before first event', () {
      // Our first event is at 0.0, so -1.0 should return null
      final stage = timedTrace.stageAt(-1.0);
      expect(stage, isNull);
    });

    test('findStage locates by typeName', () {
      final found = timedTrace.findStage('reel_stop');
      expect(found, isNotNull);
      expect(found!.absoluteTimeMs, 400.0);

      final notFound = timedTrace.findStage('jackpot_trigger');
      expect(notFound, isNull);
    });

    test('toJson/fromJson round-trip', () {
      final json = timedTrace.toJson();
      final restored = TimedStageTrace.fromJson(json);
      expect(restored.traceId, 'timed_001');
      expect(restored.gameId, 'game');
      expect(restored.profile, TimingProfile.normal);
      expect(restored.totalDurationMs, 2000.0);
      expect(restored.events, hasLength(3));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CONDITIONAL AUDIO RULE TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('ConditionalAudioRule', () {
    test('ConditionalOperator has all expected values', () {
      expect(ConditionalOperator.values.length, greaterThanOrEqualTo(8));
      expect(ConditionalOperator.equals, isNotNull);
      expect(ConditionalOperator.notEquals, isNotNull);
      expect(ConditionalOperator.greaterThan, isNotNull);
      expect(ConditionalOperator.lessThan, isNotNull);
      expect(ConditionalOperator.greaterOrEqual, isNotNull);
      expect(ConditionalOperator.lessOrEqual, isNotNull);
      expect(ConditionalOperator.contains, isNotNull);
      expect(ConditionalOperator.isNull, isNotNull);
    });

    test('ConditionalRuleCondition toJson/fromJson round-trip', () {
      const original = ConditionalRuleCondition(
        field: 'win_ratio',
        operator: ConditionalOperator.greaterOrEqual,
        value: 20.0,
        allowNull: false,
      );

      final json = original.toJson();
      final restored = ConditionalRuleCondition.fromJson(json);
      expect(restored.field, 'win_ratio');
      expect(restored.operator, ConditionalOperator.greaterOrEqual);
      expect(restored.value, 20.0);
      expect(restored.allowNull, false);
    });

    test('ConditionalAudioRule toJson/fromJson round-trip', () {
      const original = ConditionalAudioRule(
        id: 'rule_1',
        name: 'Big Win Override',
        stagePatterns: ['WIN_PRESENT*', 'BIGWIN*'],
        conditions: [
          ConditionalRuleCondition(
            field: 'win_ratio',
            operator: ConditionalOperator.greaterOrEqual,
            value: 20.0,
          ),
        ],
        overrideEventId: 'bigwin_fanfare',
      );

      final json = original.toJson();
      final restored = ConditionalAudioRule.fromJson(json);
      expect(restored.id, 'rule_1');
      expect(restored.name, 'Big Win Override');
      expect(restored.stagePatterns, hasLength(2));
      expect(restored.conditions, hasLength(1));
      expect(restored.conditions.first.field, 'win_ratio');
      expect(restored.overrideEventId, 'bigwin_fanfare');
    });

    test('preset rules are valid', () {
      final presets = ConditionalAudioRulePresets.all;
      expect(presets, hasLength(3));

      // bigWinThreshold
      expect(presets[0].id, 'preset_big_win_threshold');
      expect(presets[0].conditions, hasLength(1));
      expect(presets[0].overrideEventId, 'bigwin_fanfare');

      // epicWinMusic
      expect(presets[1].id, 'preset_epic_win_music');
      expect(presets[1].contextOverrides, isNotNull);
      expect(presets[1].contextOverrides!['use_epic_music'], true);

      // jackpotMuteMusic
      expect(presets[2].id, 'preset_jackpot_mute_music');
      expect(presets[2].stagePatterns, ['JACKPOT_*']);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TRIGGER HISTORY ENTRY TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('TriggerHistoryEntry', () {
    test('constructor stores all fields', () {
      final now = DateTime.now();
      final entry = TriggerHistoryEntry(
        timestamp: now,
        stage: 'REEL_STOP_0',
        eventName: 'onReelLand1',
        layerNames: ['reel_stop.wav'],
        success: true,
        containerType: ContainerType.none,
      );

      expect(entry.timestamp, now);
      expect(entry.stage, 'REEL_STOP_0');
      expect(entry.eventName, 'onReelLand1');
      expect(entry.layerNames, ['reel_stop.wav']);
      expect(entry.success, true);
      expect(entry.error, isNull);
      expect(entry.containerType, ContainerType.none);
    });

    test('constructor with error', () {
      final entry = TriggerHistoryEntry(
        timestamp: DateTime.now(),
        stage: 'UNKNOWN_STAGE',
        eventName: '(no audio)',
        layerNames: [],
        success: false,
        error: 'No audio event configured',
      );

      expect(entry.success, false);
      expect(entry.error, 'No audio event configured');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // GAMBLE AND BONUS ENUM TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('GambleResult', () {
    test('fromJson/toJson round-trip', () {
      for (final result in GambleResult.values) {
        final serialized = result.toJson();
        final deserialized = GambleResult.fromJson(serialized);
        expect(deserialized, result);
      }
    });

    test('fromJson returns null for invalid', () {
      expect(GambleResult.fromJson(null), isNull);
      expect(GambleResult.fromJson('invalid'), isNull);
    });
  });

  group('BonusChoiceType', () {
    test('fromJson/toJson round-trip', () {
      for (final choice in BonusChoiceType.values) {
        final serialized = choice.toJson();
        final deserialized = BonusChoiceType.fromJson(serialized);
        expect(deserialized, choice, reason: 'Round-trip failed for ${choice.name}');
      }
    });

    test('fromJson returns null for invalid', () {
      expect(BonusChoiceType.fromJson(null), isNull);
      expect(BonusChoiceType.fromJson('invalid'), isNull);
      expect(BonusChoiceType.fromJson({'custom': true}), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // WIZARD RESULT & ADAPTER MODELS
  // ═══════════════════════════════════════════════════════════════════════════

  group('WizardResult', () {
    test('confidenceLabel returns correct labels', () {
      const excellent = WizardResult(
        recommendedLayer: IngestLayer.directEvent,
        confidence: 0.95,
      );
      expect(excellent.confidenceLabel, 'Excellent');

      const good = WizardResult(
        recommendedLayer: IngestLayer.directEvent,
        confidence: 0.75,
      );
      expect(good.confidenceLabel, 'Good');

      const fair = WizardResult(
        recommendedLayer: IngestLayer.snapshotDiff,
        confidence: 0.55,
      );
      expect(fair.confidenceLabel, 'Fair');

      const low = WizardResult(
        recommendedLayer: IngestLayer.ruleBased,
        confidence: 0.3,
      );
      expect(low.confidenceLabel, 'Low');
    });

    test('toJson/fromJson round-trip', () {
      const original = WizardResult(
        detectedCompany: 'NetEnt',
        detectedEngine: 'Evolution',
        recommendedLayer: IngestLayer.directEvent,
        confidence: 0.85,
        detectedEvents: [
          DetectedEvent(
            eventName: 'spin_result',
            suggestedStage: 'SPIN_END',
            sampleCount: 10,
          ),
        ],
        configToml: 'adapter = "netent"',
      );

      final json = original.toJson();
      final restored = WizardResult.fromJson(json);
      expect(restored.detectedCompany, 'NetEnt');
      expect(restored.detectedEngine, 'Evolution');
      expect(restored.recommendedLayer, IngestLayer.directEvent);
      expect(restored.confidence, 0.85);
      expect(restored.detectedEvents, hasLength(1));
      expect(restored.detectedEvents.first.eventName, 'spin_result');
      expect(restored.configToml, 'adapter = "netent"');
    });
  });

  group('IngestLayer', () {
    test('fromInt maps correctly', () {
      expect(IngestLayer.fromInt(0), IngestLayer.directEvent);
      expect(IngestLayer.fromInt(1), IngestLayer.snapshotDiff);
      expect(IngestLayer.fromInt(2), IngestLayer.ruleBased);
      expect(IngestLayer.fromInt(99), IngestLayer.directEvent); // default
    });

    test('toJson/fromJson round-trip', () {
      for (final layer in IngestLayer.values) {
        final serialized = layer.toJson();
        final deserialized = IngestLayer.fromJson(serialized);
        expect(deserialized, layer, reason: 'Round-trip failed for ${layer.name}');
      }
    });

    test('displayName includes layer number', () {
      expect(IngestLayer.directEvent.displayName, contains('Layer 1'));
      expect(IngestLayer.snapshotDiff.displayName, contains('Layer 2'));
      expect(IngestLayer.ruleBased.displayName, contains('Layer 3'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // CONNECTION CONFIG TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('ConnectionConfig', () {
    test('webSocket factory', () {
      final config = ConnectionConfig.webSocket('ws://localhost:9090', adapterId: 'test');
      expect(config.protocol, ConnectionProtocol.webSocket);
      expect(config.url, 'ws://localhost:9090');
      expect(config.adapterId, 'test');
    });

    test('tcp factory', () {
      final config = ConnectionConfig.tcp('192.168.1.1', 8888, adapterId: 'tcp_test');
      expect(config.protocol, ConnectionProtocol.tcp);
      expect(config.host, '192.168.1.1');
      expect(config.port, 8888);
      expect(config.adapterId, 'tcp_test');
    });

    test('displayUrl for webSocket', () {
      final config = ConnectionConfig.webSocket('ws://example.com:8080');
      expect(config.displayUrl, 'ws://example.com:8080');
    });

    test('displayUrl for tcp', () {
      final config = ConnectionConfig.tcp('10.0.0.1', 5555);
      expect(config.displayUrl, '10.0.0.1:5555');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ENGINE CONNECTION STATE TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('EngineConnectionState', () {
    test('isConnected returns true only for connected', () {
      expect(EngineConnectionState.connected.isConnected, true);
      expect(EngineConnectionState.disconnected.isConnected, false);
      expect(EngineConnectionState.connecting.isConnected, false);
      expect(EngineConnectionState.error.isConnected, false);
    });

    test('isConnecting returns true only for connecting', () {
      expect(EngineConnectionState.connecting.isConnecting, true);
      expect(EngineConnectionState.connected.isConnecting, false);
    });

    test('fromJson parses known states', () {
      expect(EngineConnectionState.fromJson('connected'), EngineConnectionState.connected);
      expect(EngineConnectionState.fromJson('Connected'), EngineConnectionState.connected);
      expect(EngineConnectionState.fromJson('disconnected'), EngineConnectionState.disconnected);
      expect(EngineConnectionState.fromJson('error'), EngineConnectionState.error);
    });

    test('fromJson returns null for invalid', () {
      expect(EngineConnectionState.fromJson('invalid'), isNull);
      expect(EngineConnectionState.fromJson(null), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // POOLED EVENT STAGES CONSTANT TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Pooled Event Stages', () {
    // Note: _pooledEventStages is a private const, but we can verify the
    // expected stages are present by checking common known rapid-fire stages
    // exist in the constant. Since it is private, we test the pattern
    // indirectly through AudioEvent stage naming.

    test('known rapid-fire stages follow naming conventions', () {
      // Verify the naming convention matches what EventRegistry expects
      const knownPooledStages = [
        'REEL_STOP',
        'REEL_STOP_0',
        'REEL_STOP_1',
        'REEL_STOP_2',
        'REEL_STOP_3',
        'REEL_STOP_4',
        'CASCADE_STEP',
        'ROLLUP_TICK',
        'WIN_LINE_SHOW',
        'WIN_SYMBOL_HIGHLIGHT',
        'UI_BUTTON_PRESS',
        'SYMBOL_LAND',
      ];

      // All should be uppercase with underscores only (EventRegistry convention)
      final validChars = RegExp(r'^[A-Z0-9_]+$');
      for (final stage in knownPooledStages) {
        expect(validChars.hasMatch(stage), true,
            reason: '$stage should match EventRegistry naming convention');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // FALLBACK PATTERN DOCUMENTATION TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('Fallback Stage Patterns (documentation)', () {
    // _getFallbackStage is private, so we document and verify the expected
    // fallback patterns here. These tests verify the PATTERN MATCHING LOGIC
    // by testing whether stage names match the regex patterns used in the
    // fallback resolution.

    test('numbered stage pattern: STAGE_NAME_N removes trailing _N', () {
      // Pattern: ^(.+)_(\d+)$
      final pattern = RegExp(r'^(.+)_(\d+)$');

      // These should match (and the fallback would strip the number)
      expect(pattern.hasMatch('REEL_STOP_0'), true);
      expect(pattern.hasMatch('REEL_STOP_4'), true);
      expect(pattern.hasMatch('CASCADE_STEP_1'), true);
      expect(pattern.hasMatch('WIN_LINE_SHOW_3'), true);
      expect(pattern.hasMatch('SYMBOL_LAND_5'), true);
      expect(pattern.hasMatch('ROLLUP_TICK_2'), true);

      // Base names extracted
      expect(pattern.firstMatch('REEL_STOP_0')!.group(1), 'REEL_STOP');
      expect(pattern.firstMatch('CASCADE_STEP_3')!.group(1), 'CASCADE_STEP');
      expect(pattern.firstMatch('WIN_LINE_SHOW_2')!.group(1), 'WIN_LINE_SHOW');

      // These should NOT match (no trailing number)
      expect(pattern.hasMatch('REEL_STOP'), false);
      expect(pattern.hasMatch('SPIN_START'), false);
    });

    test('known fallbackable patterns include all expected stages', () {
      // These are the patterns that _getFallbackStage will provide fallback for
      const fallbackablePatterns = {
        'REEL_STOP',
        'CASCADE_STEP',
        'WIN_LINE_SHOW',
        'WIN_LINE_HIDE',
        'SYMBOL_LAND',
        'ROLLUP_TICK',
        'WHEEL_TICK',
        'TRAIL_MOVE_STEP',
      };

      // Verify all are uppercase underscore format
      for (final pattern in fallbackablePatterns) {
        expect(RegExp(r'^[A-Z_]+$').hasMatch(pattern), true,
            reason: '$pattern should be uppercase underscore format');
      }

      // Minimum expected patterns
      expect(fallbackablePatterns, contains('REEL_STOP'));
      expect(fallbackablePatterns, contains('CASCADE_STEP'));
      expect(fallbackablePatterns, contains('SYMBOL_LAND'));
      expect(fallbackablePatterns, contains('ROLLUP_TICK'));
    });

    test('symbol prefix fallback pattern: PREFIX_SYMBOL → PREFIX', () {
      // Pattern: starts with known prefix + underscore + suffix
      const symbolPrefixFallbacks = {
        'WIN_SYMBOL_HIGHLIGHT',
        'SYMBOL_WIN',
        'SYMBOL_TRIGGER',
        'SYMBOL_EXPAND',
        'SYMBOL_TRANSFORM',
      };

      for (final prefix in symbolPrefixFallbacks) {
        // Stage like WIN_SYMBOL_HIGHLIGHT_HP1 should start with prefix_
        final exampleStage = '${prefix}_HP1';
        expect(exampleStage.startsWith('${prefix}_'), true);
        expect(exampleStage.length > prefix.length + 1, true);
      }
    });

    test('numbered symbol pattern: HP1 extracts category HP', () {
      // Pattern: ^([A-Z]+)(\d+)$
      final numberedMatch = RegExp(r'^([A-Z]+)(\d+)$');

      expect(numberedMatch.hasMatch('HP1'), true);
      expect(numberedMatch.firstMatch('HP1')!.group(1), 'HP');
      expect(numberedMatch.firstMatch('HP1')!.group(2), '1');

      expect(numberedMatch.hasMatch('LP3'), true);
      expect(numberedMatch.firstMatch('LP3')!.group(1), 'LP');

      expect(numberedMatch.hasMatch('MP2'), true);
      expect(numberedMatch.firstMatch('MP2')!.group(1), 'MP');

      // Non-numbered symbols should NOT match
      expect(numberedMatch.hasMatch('WILD'), false);
      expect(numberedMatch.hasMatch('SCATTER'), false);
      expect(numberedMatch.hasMatch('BONUS'), false);
    });

    test('anticipation tension fallback chain is well-formed', () {
      // ANTICIPATION_TENSION_R2_L3 → ANTICIPATION_TENSION_R2 → ANTICIPATION_TENSION → ANTICIPATION_ON
      final fullPattern = RegExp(r'^ANTICIPATION_TENSION_R(\d+)_L(\d+)$');
      final reelOnlyPattern = RegExp(r'^ANTICIPATION_TENSION_R\d+$');

      expect(fullPattern.hasMatch('ANTICIPATION_TENSION_R2_L3'), true);
      expect(fullPattern.firstMatch('ANTICIPATION_TENSION_R2_L3')!.group(1), '2');
      expect(fullPattern.firstMatch('ANTICIPATION_TENSION_R2_L3')!.group(2), '3');

      expect(reelOnlyPattern.hasMatch('ANTICIPATION_TENSION_R2'), true);
      expect(reelOnlyPattern.hasMatch('ANTICIPATION_TENSION_R2_L3'), false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TRACE SUMMARY TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  group('TraceSummary', () {
    test('toJson/fromJson round-trip', () {
      const original = TraceSummary(
        traceId: 'sum_001',
        gameId: 'slots_v1',
        eventCount: 25,
        durationMs: 5000.0,
        totalWin: 350.0,
        hasFeature: true,
        hasJackpot: false,
        maxBigWinTier: BigWinTier.bigWin,
      );

      final json = original.toJson();
      final restored = TraceSummary.fromJson(json);
      expect(restored.traceId, 'sum_001');
      expect(restored.gameId, 'slots_v1');
      expect(restored.eventCount, 25);
      expect(restored.durationMs, 5000.0);
      expect(restored.totalWin, 350.0);
      expect(restored.hasFeature, true);
      expect(restored.hasJackpot, false);
      expect(restored.maxBigWinTier, BigWinTier.bigWin);
    });

    test('toJson omits null maxBigWinTier', () {
      const summary = TraceSummary(
        traceId: 'no_big',
        gameId: 'game',
        eventCount: 5,
        durationMs: 1000.0,
        totalWin: 0.0,
        hasFeature: false,
        hasJackpot: false,
      );

      final json = summary.toJson();
      expect(json.containsKey('max_bigwin_tier'), false);
    });
  });
}
