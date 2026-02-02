// Plugin Sandbox Service Tests
//
// Tests for plugin isolation, crash recovery, and resource limits.

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/plugin_sandbox_service.dart';

void main() {
  late PluginSandboxService service;

  setUp(() async {
    service = PluginSandboxService.instance;
    await service.clearAll();
  });

  tearDown(() async {
    await service.clearAll();
  });

  group('Sandbox Creation', () {
    test('should create a sandbox', () {
      final sandbox = service.createSandbox(
        pluginId: 'com.fabfilter.pro-q-3',
        pluginName: 'Pro-Q 3',
        trackId: 1,
        slotIndex: 0,
      );

      expect(sandbox.pluginId, 'com.fabfilter.pro-q-3');
      expect(sandbox.pluginName, 'Pro-Q 3');
      expect(sandbox.trackId, 1);
      expect(sandbox.slotIndex, 0);
      expect(sandbox.status, PluginSandboxStatus.unloaded);
      expect(sandbox.crashCount, 0);
    });

    test('should create multiple sandboxes', () {
      service.createSandbox(
        pluginId: 'plugin_1',
        pluginName: 'Plugin 1',
        trackId: 1,
        slotIndex: 0,
      );
      service.createSandbox(
        pluginId: 'plugin_2',
        pluginName: 'Plugin 2',
        trackId: 1,
        slotIndex: 1,
      );
      service.createSandbox(
        pluginId: 'plugin_3',
        pluginName: 'Plugin 3',
        trackId: 2,
        slotIndex: 0,
      );

      expect(service.allSandboxes.length, 3);
    });

    test('should apply custom resource limits', () {
      const customLimits = PluginResourceLimits(
        maxCpuPercent: 0.50,
        maxMemoryBytes: 1024 * 1024 * 1024,
        timeoutMs: 60000,
      );

      final sandbox = service.createSandbox(
        pluginId: 'heavy_plugin',
        pluginName: 'Heavy Plugin',
        trackId: 1,
        slotIndex: 0,
        limits: customLimits,
      );

      expect(sandbox.limits.maxCpuPercent, 0.50);
      expect(sandbox.limits.maxMemoryBytes, 1024 * 1024 * 1024);
      expect(sandbox.limits.timeoutMs, 60000);
    });

    test('should remove sandbox', () {
      final sandbox = service.createSandbox(
        pluginId: 'plugin_1',
        pluginName: 'Plugin 1',
        trackId: 1,
        slotIndex: 0,
      );

      expect(service.allSandboxes.length, 1);

      service.removeSandbox(sandbox.sandboxId);

      expect(service.allSandboxes, isEmpty);
    });
  });

  group('Resource Limits', () {
    test('should have correct default limits', () {
      const limits = PluginResourceLimits();

      expect(limits.maxCpuPercent, 0.25);
      expect(limits.maxMemoryBytes, 512 * 1024 * 1024);
      expect(limits.timeoutMs, 30000);
      expect(limits.maxCrashes, 3);
      expect(limits.crashCooldownMs, 5000);
    });

    test('should have correct audio plugin limits', () {
      expect(PluginResourceLimits.audio.maxCpuPercent, 0.30);
      expect(PluginResourceLimits.audio.maxMemoryBytes, 256 * 1024 * 1024);
      expect(PluginResourceLimits.audio.timeoutMs, 10000);
    });

    test('should have correct instrument plugin limits', () {
      expect(PluginResourceLimits.instrument.maxCpuPercent, 0.40);
      expect(PluginResourceLimits.instrument.maxMemoryBytes, 1024 * 1024 * 1024);
    });

    test('should have correct development limits', () {
      expect(PluginResourceLimits.development.maxCpuPercent, 0.80);
      expect(PluginResourceLimits.development.maxMemoryBytes, 2048 * 1024 * 1024);
      expect(PluginResourceLimits.development.maxCrashes, 10);
    });

    test('copyWith should create modified limits', () {
      const original = PluginResourceLimits();
      final modified = original.copyWith(maxCpuPercent: 0.50, timeoutMs: 45000);

      expect(modified.maxCpuPercent, 0.50);
      expect(modified.timeoutMs, 45000);
      expect(modified.maxMemoryBytes, original.maxMemoryBytes); // Unchanged
    });
  });

  group('Sandbox State', () {
    test('should detect over CPU limit', () {
      final sandbox = service.createSandbox(
        pluginId: 'plugin_1',
        pluginName: 'Plugin 1',
        trackId: 1,
        slotIndex: 0,
      );

      sandbox.currentCpuUsage = 0.20;
      expect(sandbox.isOverCpuLimit, false);

      sandbox.currentCpuUsage = 0.30; // Over 0.25 default
      expect(sandbox.isOverCpuLimit, true);
    });

    test('should detect over memory limit', () {
      final sandbox = service.createSandbox(
        pluginId: 'plugin_1',
        pluginName: 'Plugin 1',
        trackId: 1,
        slotIndex: 0,
      );

      sandbox.currentMemoryBytes = 256 * 1024 * 1024;
      expect(sandbox.isOverMemoryLimit, false);

      sandbox.currentMemoryBytes = 600 * 1024 * 1024; // Over 512 MB default
      expect(sandbox.isOverMemoryLimit, true);
    });

    test('should track crashes', () {
      final sandbox = service.createSandbox(
        pluginId: 'plugin_1',
        pluginName: 'Plugin 1',
        trackId: 1,
        slotIndex: 0,
      );

      expect(sandbox.crashCount, 0);
      expect(sandbox.canRestart, true);

      sandbox.recordCrash('Test crash 1');
      expect(sandbox.crashCount, 1);
      expect(sandbox.status, PluginSandboxStatus.crashed);
      expect(sandbox.errorMessage, 'Test crash 1');

      sandbox.recordCrash('Test crash 2');
      sandbox.recordCrash('Test crash 3');
      expect(sandbox.crashCount, 3);
      expect(sandbox.canRestart, false); // Max crashes reached
    });

    test('should serialize to JSON', () {
      final sandbox = service.createSandbox(
        pluginId: 'plugin_1',
        pluginName: 'Plugin 1',
        trackId: 1,
        slotIndex: 0,
      );
      sandbox.currentCpuUsage = 0.15;
      sandbox.currentMemoryBytes = 100 * 1024 * 1024;
      sandbox.lastPresetName = 'Default';

      final json = sandbox.toJson();

      expect(json['pluginId'], 'plugin_1');
      expect(json['pluginName'], 'Plugin 1');
      expect(json['trackId'], 1);
      expect(json['slotIndex'], 0);
      expect(json['status'], 'unloaded');
      expect(json['crashCount'], 0);
      expect(json['currentCpuUsage'], 0.15);
      expect(json['lastPresetName'], 'Default');
    });
  });

  group('Plugin Lifecycle', () {
    test('should start plugin', () async {
      final sandbox = service.createSandbox(
        pluginId: 'plugin_1',
        pluginName: 'Plugin 1',
        trackId: 1,
        slotIndex: 0,
      );

      expect(sandbox.status, PluginSandboxStatus.unloaded);

      final result = await service.startPlugin(sandbox.sandboxId);

      expect(result, true);
      expect(sandbox.status, PluginSandboxStatus.running);
    });

    test('should stop plugin', () async {
      final sandbox = service.createSandbox(
        pluginId: 'plugin_1',
        pluginName: 'Plugin 1',
        trackId: 1,
        slotIndex: 0,
      );

      await service.startPlugin(sandbox.sandboxId);
      expect(sandbox.status, PluginSandboxStatus.running);

      final result = await service.stopPlugin(sandbox.sandboxId);

      expect(result, true);
      expect(sandbox.status, PluginSandboxStatus.unloaded);
    });

    test('should stop plugin and preserve state', () async {
      final sandbox = service.createSandbox(
        pluginId: 'plugin_1',
        pluginName: 'Plugin 1',
        trackId: 1,
        slotIndex: 0,
      );

      await service.startPlugin(sandbox.sandboxId);
      await service.stopPlugin(sandbox.sandboxId, preserveState: true);

      expect(sandbox.preservedState, isNotNull);
      expect(sandbox.preservedState, isNotEmpty);
    });

    test('should kill unresponsive plugin', () async {
      final sandbox = service.createSandbox(
        pluginId: 'plugin_1',
        pluginName: 'Plugin 1',
        trackId: 1,
        slotIndex: 0,
      );

      await service.startPlugin(sandbox.sandboxId);

      await service.killPlugin(sandbox.sandboxId, 'Unresponsive for 30s');

      expect(sandbox.status, PluginSandboxStatus.killed);
      expect(sandbox.errorMessage, 'Unresponsive for 30s');
    });

    test('should not start when max crashes reached', () async {
      final sandbox = service.createSandbox(
        pluginId: 'plugin_1',
        pluginName: 'Plugin 1',
        trackId: 1,
        slotIndex: 0,
      );

      // Simulate 3 crashes (max default)
      sandbox.recordCrash('Crash 1');
      sandbox.recordCrash('Crash 2');
      sandbox.recordCrash('Crash 3');

      final result = await service.startPlugin(sandbox.sandboxId);

      expect(result, false);
    });
  });

  group('Crash Recovery', () {
    test('should recover crashed plugin', () async {
      final sandbox = service.createSandbox(
        pluginId: 'plugin_1',
        pluginName: 'Plugin 1',
        trackId: 1,
        slotIndex: 0,
      );

      await service.startPlugin(sandbox.sandboxId);

      // Simulate crash
      sandbox.recordCrash('Test crash');
      sandbox.preservedState = [1, 2, 3, 4, 5];

      // Wait for cooldown (modify for faster test)
      sandbox.lastCrashTime = DateTime.now().subtract(const Duration(seconds: 10));

      final result = await service.recoverPlugin(sandbox.sandboxId);

      expect(result, true);
      expect(sandbox.status, PluginSandboxStatus.running);
    });

    test('should emit recovery event', () async {
      final sandbox = service.createSandbox(
        pluginId: 'plugin_1',
        pluginName: 'Plugin 1',
        trackId: 1,
        slotIndex: 0,
      );

      await service.startPlugin(sandbox.sandboxId);
      sandbox.recordCrash('Test crash');
      sandbox.lastCrashTime = DateTime.now().subtract(const Duration(seconds: 10));

      final events = <PluginSandboxEvent>[];
      final subscription = service.events.listen(events.add);

      await service.recoverPlugin(sandbox.sandboxId);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(events.any((e) => e is PluginRecoveredEvent), true);

      await subscription.cancel();
    });
  });

  group('Events', () {
    test('should emit started event', () async {
      final sandbox = service.createSandbox(
        pluginId: 'plugin_1',
        pluginName: 'Plugin 1',
        trackId: 1,
        slotIndex: 0,
      );

      final completer = Completer<PluginStartedEvent>();
      final subscription = service.events.listen((event) {
        if (event is PluginStartedEvent && !completer.isCompleted) {
          completer.complete(event);
        }
      });

      await service.startPlugin(sandbox.sandboxId);

      final event = await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw TimeoutException('No event received'),
      );

      expect(event.sandboxId, sandbox.sandboxId);

      await subscription.cancel();
    });

    test('should emit killed event', () async {
      final sandbox = service.createSandbox(
        pluginId: 'plugin_1',
        pluginName: 'Plugin 1',
        trackId: 1,
        slotIndex: 0,
      );

      await service.startPlugin(sandbox.sandboxId);

      final completer = Completer<PluginKilledEvent>();
      final subscription = service.events.listen((event) {
        if (event is PluginKilledEvent && !completer.isCompleted) {
          completer.complete(event);
        }
      });

      await service.killPlugin(sandbox.sandboxId, 'Test kill');

      final event = await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw TimeoutException('No event received'),
      );

      expect(event.sandboxId, sandbox.sandboxId);
      expect(event.reason, 'Test kill');

      await subscription.cancel();
    });
  });

  group('Monitoring', () {
    test('should start and stop monitoring', () {
      expect(service.isMonitoring, false);

      service.startMonitoring();
      expect(service.isMonitoring, true);

      service.stopMonitoring();
      expect(service.isMonitoring, false);
    });

    test('should update metrics', () {
      final sandbox = service.createSandbox(
        pluginId: 'plugin_1',
        pluginName: 'Plugin 1',
        trackId: 1,
        slotIndex: 0,
      );

      service.updateMetrics(
        sandbox.sandboxId,
        cpuUsage: 0.15,
        memoryBytes: 100 * 1024 * 1024,
      );

      expect(sandbox.currentCpuUsage, 0.15);
      expect(sandbox.currentMemoryBytes, 100 * 1024 * 1024);
    });
  });

  group('Statistics', () {
    test('should return correct statistics', () async {
      service.createSandbox(
        pluginId: 'plugin_1',
        pluginName: 'Plugin 1',
        trackId: 1,
        slotIndex: 0,
      );

      final sandbox2 = service.createSandbox(
        pluginId: 'plugin_2',
        pluginName: 'Plugin 2',
        trackId: 1,
        slotIndex: 1,
      );

      await service.startPlugin(sandbox2.sandboxId);
      sandbox2.currentCpuUsage = 0.10;
      sandbox2.currentMemoryBytes = 50 * 1024 * 1024;

      final stats = service.getStatistics();

      expect(stats['totalSandboxes'], 2);
      expect(stats['activeSandboxes'], 1);
      expect(stats['crashedSandboxes'], 0);
      expect(stats['totalCpuUsage'], 0.10);
    });

    test('should get sandboxes for track', () {
      service.createSandbox(
        pluginId: 'plugin_1',
        pluginName: 'Plugin 1',
        trackId: 1,
        slotIndex: 0,
      );
      service.createSandbox(
        pluginId: 'plugin_2',
        pluginName: 'Plugin 2',
        trackId: 1,
        slotIndex: 1,
      );
      service.createSandbox(
        pluginId: 'plugin_3',
        pluginName: 'Plugin 3',
        trackId: 2,
        slotIndex: 0,
      );

      final track1Sandboxes = service.getSandboxesForTrack(1);
      final track2Sandboxes = service.getSandboxesForTrack(2);

      expect(track1Sandboxes.length, 2);
      expect(track2Sandboxes.length, 1);
    });
  });

  group('State Preservation', () {
    test('should preserve all states', () async {
      final sandbox1 = service.createSandbox(
        pluginId: 'plugin_1',
        pluginName: 'Plugin 1',
        trackId: 1,
        slotIndex: 0,
      );
      final sandbox2 = service.createSandbox(
        pluginId: 'plugin_2',
        pluginName: 'Plugin 2',
        trackId: 1,
        slotIndex: 1,
      );

      await service.startPlugin(sandbox1.sandboxId);
      await service.startPlugin(sandbox2.sandboxId);

      await service.preserveAllStates();

      expect(sandbox1.preservedState, isNotNull);
      expect(sandbox2.preservedState, isNotNull);
    });
  });

  group('Clear All', () {
    test('should clear all sandboxes', () async {
      service.createSandbox(
        pluginId: 'plugin_1',
        pluginName: 'Plugin 1',
        trackId: 1,
        slotIndex: 0,
      );
      service.createSandbox(
        pluginId: 'plugin_2',
        pluginName: 'Plugin 2',
        trackId: 1,
        slotIndex: 1,
      );

      expect(service.allSandboxes.length, 2);

      await service.clearAll();

      expect(service.allSandboxes, isEmpty);
      expect(service.isMonitoring, false);
    });
  });
}
