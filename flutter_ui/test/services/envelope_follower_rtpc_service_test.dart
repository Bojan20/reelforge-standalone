/// Envelope Follower RTPC Service Tests
///
/// Tests for envelope extraction and RTPC output:
/// - Follower configuration
/// - Attack/Release behavior
/// - Detection modes (Peak, RMS, Hybrid)
/// - Threshold gating
/// - Output range mapping
/// - RTPC integration
/// - Serialization
library;

import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/envelope_follower_rtpc_service.dart';

void main() {
  group('EnvelopeFollowerRtpcService', () {
    late EnvelopeFollowerRtpcService service;

    setUp(() {
      service = EnvelopeFollowerRtpcService.instance;
      service.clear();
      // Initialize without middleware for unit testing
    });

    tearDown(() {
      service.clear();
    });

    group('Follower Management', () {
      test('should create follower with default values', () {
        final follower = service.createFollower(name: 'Test Follower');

        expect(follower.id, greaterThan(0));
        expect(follower.name, equals('Test Follower'));
        expect(follower.mode, equals(EnvelopeDetectionMode.rms));
        expect(follower.attackMs, equals(10.0));
        expect(follower.releaseMs, equals(100.0));
        expect(follower.thresholdDb, equals(-60.0));
        expect(follower.enabled, isTrue);
      });

      test('should create follower with custom values', () {
        final follower = service.createFollower(
          name: 'Custom Follower',
          sourceType: EnvelopeSourceType.track,
          sourceId: 2,
          mode: EnvelopeDetectionMode.peak,
          attackMs: 5.0,
          releaseMs: 200.0,
        );

        expect(follower.sourceType, equals(EnvelopeSourceType.track));
        expect(follower.sourceId, equals(2));
        expect(follower.mode, equals(EnvelopeDetectionMode.peak));
        expect(follower.attackMs, equals(5.0));
        expect(follower.releaseMs, equals(200.0));
      });

      test('should retrieve follower by ID', () {
        final follower = service.createFollower(name: 'Retrievable');
        final retrieved = service.getFollower(follower.id);

        expect(retrieved, isNotNull);
        expect(retrieved!.name, equals('Retrievable'));
      });

      test('should update follower', () {
        final follower = service.createFollower(name: 'Original');
        final updated = follower.copyWith(
          name: 'Updated',
          attackMs: 20.0,
        );

        service.updateFollower(updated);
        final retrieved = service.getFollower(follower.id);

        expect(retrieved!.name, equals('Updated'));
        expect(retrieved.attackMs, equals(20.0));
      });

      test('should remove follower', () {
        final follower = service.createFollower(name: 'To Remove');
        service.removeFollower(follower.id);

        expect(service.getFollower(follower.id), isNull);
      });

      test('should list all followers', () {
        service.createFollower(name: 'Follower 1');
        service.createFollower(name: 'Follower 2');
        service.createFollower(name: 'Follower 3');

        expect(service.allFollowers.length, equals(3));
      });
    });

    group('Attack/Release', () {
      test('should set attack time', () {
        final follower = service.createFollower(name: 'Attack Test');
        service.setAttack(follower.id, 25.0);

        expect(service.getFollower(follower.id)!.attackMs, equals(25.0));
      });

      test('should clamp attack to valid range', () {
        final follower = service.createFollower(name: 'Attack Clamp');

        service.setAttack(follower.id, 0.01); // Below min
        expect(service.getFollower(follower.id)!.attackMs, equals(0.1));

        service.setAttack(follower.id, 1000.0); // Above max
        expect(service.getFollower(follower.id)!.attackMs, equals(500.0));
      });

      test('should set release time', () {
        final follower = service.createFollower(name: 'Release Test');
        service.setRelease(follower.id, 500.0);

        expect(service.getFollower(follower.id)!.releaseMs, equals(500.0));
      });

      test('should clamp release to valid range', () {
        final follower = service.createFollower(name: 'Release Clamp');

        service.setRelease(follower.id, 1.0); // Below min
        expect(service.getFollower(follower.id)!.releaseMs, equals(10.0));

        service.setRelease(follower.id, 10000.0); // Above max
        expect(service.getFollower(follower.id)!.releaseMs, equals(5000.0));
      });
    });

    group('Detection Mode', () {
      test('should set mode to peak', () {
        final follower = service.createFollower(name: 'Peak Mode');
        service.setMode(follower.id, EnvelopeDetectionMode.peak);

        expect(service.getFollower(follower.id)!.mode, equals(EnvelopeDetectionMode.peak));
      });

      test('should set mode to RMS', () {
        final follower = service.createFollower(name: 'RMS Mode');
        service.setMode(follower.id, EnvelopeDetectionMode.rms);

        expect(service.getFollower(follower.id)!.mode, equals(EnvelopeDetectionMode.rms));
      });

      test('should set mode to hybrid', () {
        final follower = service.createFollower(name: 'Hybrid Mode');
        service.setMode(follower.id, EnvelopeDetectionMode.hybrid);

        expect(service.getFollower(follower.id)!.mode, equals(EnvelopeDetectionMode.hybrid));
      });
    });

    group('Threshold Gate', () {
      test('should set threshold', () {
        final follower = service.createFollower(name: 'Threshold Test');
        service.setThreshold(follower.id, -40.0);

        expect(service.getFollower(follower.id)!.thresholdDb, equals(-40.0));
      });

      test('should clamp threshold to valid range', () {
        final follower = service.createFollower(name: 'Threshold Clamp');

        service.setThreshold(follower.id, -100.0); // Below min
        expect(service.getFollower(follower.id)!.thresholdDb, equals(-96.0));

        service.setThreshold(follower.id, 10.0); // Above max
        expect(service.getFollower(follower.id)!.thresholdDb, equals(0.0));
      });
    });

    group('Smoothing Filter', () {
      test('should set smoothing time', () {
        final follower = service.createFollower(name: 'Smoothing Test');
        service.setSmoothing(follower.id, 50.0);

        expect(service.getFollower(follower.id)!.smoothingMs, equals(50.0));
      });

      test('should clamp smoothing to valid range', () {
        final follower = service.createFollower(name: 'Smoothing Clamp');

        service.setSmoothing(follower.id, -10.0); // Below min
        expect(service.getFollower(follower.id)!.smoothingMs, equals(0.0));

        service.setSmoothing(follower.id, 500.0); // Above max
        expect(service.getFollower(follower.id)!.smoothingMs, equals(200.0));
      });
    });

    group('Output Range', () {
      test('should set output range', () {
        final follower = service.createFollower(name: 'Output Range Test');
        service.setOutputRange(follower.id, 0.2, 0.8);

        final updated = service.getFollower(follower.id);
        expect(updated!.minOutput, equals(0.2));
        expect(updated.maxOutput, equals(0.8));
      });

      test('should set inversion', () {
        final follower = service.createFollower(name: 'Inversion Test');
        service.setInverted(follower.id, true);

        expect(service.getFollower(follower.id)!.inverted, isTrue);
      });
    });

    group('RTPC Target', () {
      test('should set target RTPC', () {
        final follower = service.createFollower(name: 'RTPC Target Test');
        service.setTargetRtpc(follower.id, 42);

        expect(service.getFollower(follower.id)!.targetRtpcId, equals(42));
      });

      test('should clear target RTPC', () {
        final follower = service.createFollower(name: 'RTPC Clear Test');
        service.setTargetRtpc(follower.id, 42);
        service.clearTargetRtpc(follower.id);

        expect(service.getFollower(follower.id)!.targetRtpcId, isNull);
      });
    });

    group('Enable/Disable', () {
      test('should enable follower', () {
        final follower = service.createFollower(name: 'Enable Test');
        service.setEnabled(follower.id, true);

        expect(service.getFollower(follower.id)!.enabled, isTrue);
      });

      test('should disable follower', () {
        final follower = service.createFollower(name: 'Disable Test');
        service.setEnabled(follower.id, false);

        expect(service.getFollower(follower.id)!.enabled, isFalse);
      });

      test('should reset state when disabled', () {
        final follower = service.createFollower(name: 'Reset State Test');
        // Feed some input
        service.feedInput(follower.id, 0.8);
        // Now disable
        service.setEnabled(follower.id, false);

        final state = service.getState(follower.id);
        expect(state!.currentEnvelope, equals(0.0));
        expect(state.smoothedEnvelope, equals(0.0));
      });
    });

    group('Envelope Processing', () {
      test('should process sample and return envelope', () {
        final follower = service.createFollower(
          name: 'Process Test',
          mode: EnvelopeDetectionMode.peak,
          attackMs: 0.1, // Very fast attack
          releaseMs: 1000.0, // Slow release
        );

        // Feed a high level input
        final output = service.processSample(follower.id, 0.9);

        expect(output, greaterThan(0.0));
        expect(output, lessThanOrEqualTo(1.0));
      });

      test('should track increasing input levels', () {
        final follower = service.createFollower(
          name: 'Increasing Test',
          mode: EnvelopeDetectionMode.peak,
          attackMs: 0.1,
          releaseMs: 1000.0,
        );

        service.processSample(follower.id, 0.5);
        final output1 = service.getCurrentValue(follower.id);

        service.processSample(follower.id, 0.8);
        final output2 = service.getCurrentValue(follower.id);

        expect(output2, greaterThanOrEqualTo(output1));
      });

      test('should apply threshold gate', () {
        final follower = service.createFollower(name: 'Gate Test');
        service.setThreshold(follower.id, -20.0); // -20 dB = 0.1 linear

        // Input below threshold should not increase envelope
        final lowOutput = service.processSample(follower.id, 0.05);
        expect(lowOutput, closeTo(0.0, 0.1));

        // Input above threshold should increase envelope
        service.processSample(follower.id, 0.5);
        final highOutput = service.getCurrentValue(follower.id);
        expect(highOutput, greaterThan(0.0));
      });

      test('should process block of samples', () {
        final follower = service.createFollower(
          name: 'Block Test',
          mode: EnvelopeDetectionMode.rms,
        );

        final samples = List.generate(100, (i) => math.sin(i * 0.1) * 0.5);
        final output = service.processBlock(follower.id, samples);

        expect(output, greaterThan(0.0));
        expect(output, lessThanOrEqualTo(1.0));
      });

      test('should map to output range correctly', () {
        final follower = service.createFollower(
          name: 'Output Range Mapping',
          attackMs: 0.1,
          releaseMs: 1.0,
        );
        service.setOutputRange(follower.id, 0.25, 0.75);

        // Feed high input to get high envelope
        for (int i = 0; i < 100; i++) {
          service.processSample(follower.id, 0.9);
        }

        final output = service.getCurrentValue(follower.id);
        expect(output, greaterThanOrEqualTo(0.25));
        expect(output, lessThanOrEqualTo(0.75));
      });

      test('should apply inversion correctly', () {
        final follower1 = service.createFollower(
          name: 'Non-inverted',
          attackMs: 0.1,
        );
        final follower2 = service.createFollower(
          name: 'Inverted',
          attackMs: 0.1,
        );
        service.setInverted(follower2.id, true);

        // Feed same input to both
        for (int i = 0; i < 100; i++) {
          service.processSample(follower1.id, 0.8);
          service.processSample(follower2.id, 0.8);
        }

        final output1 = service.getCurrentValue(follower1.id);
        final output2 = service.getCurrentValue(follower2.id);

        // Inverted should be roughly (max - output1 + min)
        expect(output1 + output2, closeTo(1.0, 0.1));
      });
    });

    group('Feed Input', () {
      test('should accept input and update state', () {
        final follower = service.createFollower(name: 'Feed Test');

        service.feedInput(follower.id, 0.7);

        final state = service.getState(follower.id);
        expect(state, isNotNull);
        expect(state!.currentEnvelope, greaterThan(0.0));
      });

      test('should ignore input for disabled follower', () {
        final follower = service.createFollower(name: 'Disabled Feed');
        service.setEnabled(follower.id, false);

        service.feedInput(follower.id, 0.9);

        expect(service.getCurrentValue(follower.id), equals(0.0));
      });
    });

    group('Current Values', () {
      test('should return current output value', () {
        final follower = service.createFollower(name: 'Current Value Test');
        service.feedInput(follower.id, 0.5);

        final value = service.getCurrentValue(follower.id);
        expect(value, isA<double>());
      });

      test('should return current envelope level', () {
        final follower = service.createFollower(name: 'Envelope Level Test');
        service.feedInput(follower.id, 0.5);

        final envelope = service.getCurrentEnvelope(follower.id);
        expect(envelope, isA<double>());
        expect(envelope, greaterThanOrEqualTo(0.0));
      });

      test('should return envelope in dB', () {
        final follower = service.createFollower(name: 'Envelope dB Test');
        service.feedInput(follower.id, 1.0);

        final envelopeDb = service.getCurrentEnvelopeDb(follower.id);
        expect(envelopeDb, isA<double>());
        expect(envelopeDb, lessThanOrEqualTo(0.0));
      });

      test('should return -96 dB for zero envelope', () {
        final follower = service.createFollower(name: 'Zero dB Test');
        // Don't feed any input
        final envelopeDb = service.getCurrentEnvelopeDb(follower.id);
        expect(envelopeDb, equals(-96.0));
      });
    });

    group('Serialization', () {
      test('should serialize to JSON', () {
        service.createFollower(name: 'Follower A');
        service.createFollower(name: 'Follower B');

        final json = service.toJson();

        expect(json['followers'], isA<List>());
        expect((json['followers'] as List).length, equals(2));
        expect(json['nextId'], isA<int>());
      });

      test('should deserialize from JSON', () {
        final follower = service.createFollower(
          name: 'Persist Test',
          mode: EnvelopeDetectionMode.peak,
          attackMs: 15.0,
          releaseMs: 250.0,
        );
        service.setTargetRtpc(follower.id, 100);
        service.setThreshold(follower.id, -30.0);

        final json = service.toJson();
        service.clear();

        service.fromJson(json);

        expect(service.allFollowers.length, equals(1));
        final loaded = service.allFollowers.first;
        expect(loaded.name, equals('Persist Test'));
        expect(loaded.mode, equals(EnvelopeDetectionMode.peak));
        expect(loaded.attackMs, equals(15.0));
        expect(loaded.releaseMs, equals(250.0));
        expect(loaded.targetRtpcId, equals(100));
        expect(loaded.thresholdDb, equals(-30.0));
      });

      test('should handle empty JSON', () {
        service.fromJson({});
        expect(service.allFollowers, isEmpty);
      });
    });

    group('EnvelopeFollowerConfig Model', () {
      test('copyWith should preserve unchanged values', () {
        const original = EnvelopeFollowerConfig(
          id: 1,
          name: 'Original',
          sourceType: EnvelopeSourceType.bus,
          mode: EnvelopeDetectionMode.peak,
          attackMs: 5.0,
        );

        final updated = original.copyWith(attackMs: 10.0);

        expect(updated.id, equals(1));
        expect(updated.name, equals('Original'));
        expect(updated.sourceType, equals(EnvelopeSourceType.bus));
        expect(updated.mode, equals(EnvelopeDetectionMode.peak));
        expect(updated.attackMs, equals(10.0));
      });

      test('should serialize and deserialize correctly', () {
        const original = EnvelopeFollowerConfig(
          id: 50,
          name: 'Full Config',
          sourceType: EnvelopeSourceType.track,
          sourceId: 3,
          mode: EnvelopeDetectionMode.hybrid,
          attackMs: 8.0,
          releaseMs: 300.0,
          thresholdDb: -45.0,
          smoothingMs: 30.0,
          minOutput: 0.1,
          maxOutput: 0.9,
          targetRtpcId: 42,
          enabled: false,
          inverted: true,
        );

        final json = original.toJson();
        final restored = EnvelopeFollowerConfig.fromJson(json);

        expect(restored.id, equals(original.id));
        expect(restored.name, equals(original.name));
        expect(restored.sourceType, equals(original.sourceType));
        expect(restored.sourceId, equals(original.sourceId));
        expect(restored.mode, equals(original.mode));
        expect(restored.attackMs, equals(original.attackMs));
        expect(restored.releaseMs, equals(original.releaseMs));
        expect(restored.thresholdDb, equals(original.thresholdDb));
        expect(restored.smoothingMs, equals(original.smoothingMs));
        expect(restored.minOutput, equals(original.minOutput));
        expect(restored.maxOutput, equals(original.maxOutput));
        expect(restored.targetRtpcId, equals(original.targetRtpcId));
        expect(restored.enabled, equals(original.enabled));
        expect(restored.inverted, equals(original.inverted));
      });
    });

    group('Value Listeners', () {
      test('should notify listeners on input', () {
        final follower = service.createFollower(name: 'Listener Test');

        int callCount = 0;
        double lastValue = 0.0;
        int lastConfigId = 0;

        void listener(int configId, double value) {
          callCount++;
          lastConfigId = configId;
          lastValue = value;
        }

        service.addValueListener(listener);
        service.feedInput(follower.id, 0.5);

        expect(callCount, equals(1));
        expect(lastConfigId, equals(follower.id));
        expect(lastValue, greaterThan(0.0));

        service.removeValueListener(listener);
      });
    });
  });
}
