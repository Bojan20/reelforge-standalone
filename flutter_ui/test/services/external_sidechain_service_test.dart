/// External Sidechain Service Tests
///
/// Tests for professional sidechain routing:
/// - Configuration CRUD
/// - Source selection (track, bus, aux, external, M/S)
/// - Filter controls (HPF, LPF, BPF)
/// - Monitoring mode
/// - Serialization
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge_ui/services/external_sidechain_service.dart';

void main() {
  group('ExternalSidechainService', () {
    late ExternalSidechainService service;

    setUp(() {
      service = ExternalSidechainService.instance;
      service.clear();
      service.init();
    });

    tearDown(() {
      service.clear();
    });

    group('Initialization', () {
      test('should initialize successfully', () {
        expect(service.isInitialized, isTrue);
      });

      test('should have available sources after init', () {
        expect(service.availableSources, isNotEmpty);
      });
    });

    group('Configuration Management', () {
      test('should create configuration with default values', () {
        final config = service.createConfiguration(processorId: 1);

        expect(config.id, greaterThan(0));
        expect(config.processorId, equals(1));
        expect(config.sourceType, equals(SidechainSourceType.internal));
        expect(config.filterType, equals(SidechainFilterType.off));
        expect(config.mix, equals(0.0));
        expect(config.enabled, isTrue);
      });

      test('should create configuration with custom values', () {
        final config = service.createConfiguration(
          processorId: 2,
          sourceType: SidechainSourceType.track,
          sourceId: 1,
          filterType: SidechainFilterType.highPass,
          filterFrequency: 300.0,
          filterQ: 2.0,
        );

        expect(config.sourceType, equals(SidechainSourceType.track));
        expect(config.sourceId, equals(1));
        expect(config.filterType, equals(SidechainFilterType.highPass));
        expect(config.filterFrequency, equals(300.0));
        expect(config.filterQ, equals(2.0));
      });

      test('should retrieve configuration by ID', () {
        final config = service.createConfiguration(processorId: 3);
        final retrieved = service.getConfiguration(config.id);

        expect(retrieved, isNotNull);
        expect(retrieved!.id, equals(config.id));
        expect(retrieved.processorId, equals(3));
      });

      test('should retrieve configuration by processor ID', () {
        service.createConfiguration(processorId: 4);
        final retrieved = service.getConfigurationForProcessor(4);

        expect(retrieved, isNotNull);
        expect(retrieved!.processorId, equals(4));
      });

      test('should update configuration', () {
        final config = service.createConfiguration(processorId: 5);
        final updated = config.copyWith(
          filterType: SidechainFilterType.lowPass,
          filterFrequency: 5000.0,
        );

        service.updateConfiguration(updated);
        final retrieved = service.getConfiguration(config.id);

        expect(retrieved!.filterType, equals(SidechainFilterType.lowPass));
        expect(retrieved.filterFrequency, equals(5000.0));
      });

      test('should remove configuration', () {
        final config = service.createConfiguration(processorId: 6);
        service.removeConfiguration(config.id);

        expect(service.getConfiguration(config.id), isNull);
      });

      test('should list all configurations', () {
        service.createConfiguration(processorId: 7);
        service.createConfiguration(processorId: 8);
        service.createConfiguration(processorId: 9);

        expect(service.allConfigurations.length, equals(3));
      });
    });

    group('Source Selection', () {
      test('should set source to track', () {
        final config = service.createConfiguration(processorId: 10);
        service.setSource(config.id, SidechainSourceType.track, sourceId: 1);

        final updated = service.getConfiguration(config.id);
        expect(updated!.sourceType, equals(SidechainSourceType.track));
        expect(updated.sourceId, equals(1));
      });

      test('should set source to bus', () {
        final config = service.createConfiguration(processorId: 11);
        service.setSource(config.id, SidechainSourceType.bus, sourceId: 2);

        final updated = service.getConfiguration(config.id);
        expect(updated!.sourceType, equals(SidechainSourceType.bus));
        expect(updated.sourceId, equals(2));
      });

      test('should get sources filtered by type', () {
        final trackSources = service.getSourcesByType(SidechainSourceType.track);
        final busSources = service.getSourcesByType(SidechainSourceType.bus);

        expect(trackSources, isNotEmpty);
        expect(busSources, isNotEmpty);
        expect(trackSources.every((s) => s.type == SidechainSourceType.track), isTrue);
        expect(busSources.every((s) => s.type == SidechainSourceType.bus), isTrue);
      });
    });

    group('Filter Controls', () {
      test('should set filter type', () {
        final config = service.createConfiguration(processorId: 12);
        service.setFilterType(config.id, SidechainFilterType.bandPass);

        final updated = service.getConfiguration(config.id);
        expect(updated!.filterType, equals(SidechainFilterType.bandPass));
      });

      test('should set filter frequency', () {
        final config = service.createConfiguration(processorId: 13);
        service.setFilterFrequency(config.id, 1000.0);

        final updated = service.getConfiguration(config.id);
        expect(updated!.filterFrequency, equals(1000.0));
      });

      test('should clamp filter frequency to valid range', () {
        final config = service.createConfiguration(processorId: 14);

        service.setFilterFrequency(config.id, 5.0); // Below min
        var updated = service.getConfiguration(config.id);
        expect(updated!.filterFrequency, equals(20.0));

        service.setFilterFrequency(config.id, 30000.0); // Above max
        updated = service.getConfiguration(config.id);
        expect(updated!.filterFrequency, equals(20000.0));
      });

      test('should set filter Q', () {
        final config = service.createConfiguration(processorId: 15);
        service.setFilterQ(config.id, 3.0);

        final updated = service.getConfiguration(config.id);
        expect(updated!.filterQ, equals(3.0));
      });

      test('should clamp filter Q to valid range', () {
        final config = service.createConfiguration(processorId: 16);

        service.setFilterQ(config.id, 0.01); // Below min
        var updated = service.getConfiguration(config.id);
        expect(updated!.filterQ, equals(0.1));

        service.setFilterQ(config.id, 20.0); // Above max
        updated = service.getConfiguration(config.id);
        expect(updated!.filterQ, equals(10.0));
      });

      test('should set all filter parameters at once', () {
        final config = service.createConfiguration(processorId: 17);
        service.setFilter(
          config.id,
          type: SidechainFilterType.highPass,
          frequency: 500.0,
          q: 2.5,
          gainDb: -3.0,
        );

        final updated = service.getConfiguration(config.id);
        expect(updated!.filterType, equals(SidechainFilterType.highPass));
        expect(updated.filterFrequency, equals(500.0));
        expect(updated.filterQ, equals(2.5));
      });
    });

    group('Mix and Gain', () {
      test('should set mix level', () {
        final config = service.createConfiguration(processorId: 18);
        service.setMix(config.id, 0.75);

        final updated = service.getConfiguration(config.id);
        expect(updated!.mix, equals(0.75));
      });

      test('should clamp mix to 0-1 range', () {
        final config = service.createConfiguration(processorId: 19);

        service.setMix(config.id, -0.5);
        var updated = service.getConfiguration(config.id);
        expect(updated!.mix, equals(0.0));

        service.setMix(config.id, 1.5);
        updated = service.getConfiguration(config.id);
        expect(updated!.mix, equals(1.0));
      });

      test('should set gain in dB', () {
        final config = service.createConfiguration(processorId: 20);
        service.setGainDb(config.id, -6.0);

        final updated = service.getConfiguration(config.id);
        expect(updated!.gainDb, equals(-6.0));
      });

      test('should clamp gain to valid range', () {
        final config = service.createConfiguration(processorId: 21);

        service.setGainDb(config.id, -30.0);
        var updated = service.getConfiguration(config.id);
        expect(updated!.gainDb, equals(-24.0));

        service.setGainDb(config.id, 30.0);
        updated = service.getConfiguration(config.id);
        expect(updated!.gainDb, equals(24.0));
      });
    });

    group('Monitoring', () {
      test('should enable monitoring', () {
        final config = service.createConfiguration(processorId: 22);
        service.setMonitoring(config.id, true);

        final updated = service.getConfiguration(config.id);
        expect(updated!.monitoring, isTrue);
        expect(service.isMonitoringActive, isTrue);
        expect(service.monitoringProcessorId, equals(22));
      });

      test('should disable monitoring', () {
        final config = service.createConfiguration(processorId: 23);
        service.setMonitoring(config.id, true);
        service.setMonitoring(config.id, false);

        final updated = service.getConfiguration(config.id);
        expect(updated!.monitoring, isFalse);
        expect(service.isMonitoringActive, isFalse);
      });

      test('should only allow one processor to monitor at a time', () {
        final config1 = service.createConfiguration(processorId: 24);
        final config2 = service.createConfiguration(processorId: 25);

        service.setMonitoring(config1.id, true);
        service.setMonitoring(config2.id, true);

        final updated1 = service.getConfiguration(config1.id);
        final updated2 = service.getConfiguration(config2.id);

        expect(updated1!.monitoring, isFalse);
        expect(updated2!.monitoring, isTrue);
        expect(service.monitoringProcessorId, equals(25));
      });
    });

    group('M/S Mode', () {
      test('should enable mid sidechain mode', () {
        final config = service.createConfiguration(processorId: 26);
        service.enableMsMode(config.id, false);

        final updated = service.getConfiguration(config.id);
        expect(updated!.sourceType, equals(SidechainSourceType.mid));
        expect(service.isMsMode(config.id), isTrue);
      });

      test('should enable side sidechain mode', () {
        final config = service.createConfiguration(processorId: 27);
        service.enableMsMode(config.id, true);

        final updated = service.getConfiguration(config.id);
        expect(updated!.sourceType, equals(SidechainSourceType.side));
        expect(service.isMsMode(config.id), isTrue);
      });
    });

    group('Enable/Disable', () {
      test('should enable configuration', () {
        final config = service.createConfiguration(processorId: 28);
        service.setEnabled(config.id, true);

        expect(service.getConfiguration(config.id)!.enabled, isTrue);
      });

      test('should disable configuration', () {
        final config = service.createConfiguration(processorId: 29);
        service.setEnabled(config.id, false);

        expect(service.getConfiguration(config.id)!.enabled, isFalse);
      });
    });

    group('Serialization', () {
      test('should serialize to JSON', () {
        service.createConfiguration(processorId: 30);
        service.createConfiguration(processorId: 31);

        final json = service.toJson();

        expect(json['configurations'], isA<List>());
        expect((json['configurations'] as List).length, equals(2));
        expect(json['nextConfigId'], isA<int>());
      });

      test('should deserialize from JSON', () {
        final config1 = service.createConfiguration(processorId: 32);
        service.setMix(config1.id, 0.5);
        service.setFilterType(config1.id, SidechainFilterType.highPass);

        final json = service.toJson();
        service.clear();

        service.fromJson(json);

        expect(service.allConfigurations.length, equals(1));
        final loaded = service.allConfigurations.first;
        expect(loaded.mix, equals(0.5));
        expect(loaded.filterType, equals(SidechainFilterType.highPass));
      });

      test('should handle empty JSON', () {
        service.fromJson({});
        expect(service.allConfigurations, isEmpty);
      });
    });

    group('dB Conversions', () {
      test('should convert dB to linear correctly', () {
        expect(service.dbToLinear(0.0), closeTo(1.0, 0.001));
        expect(service.dbToLinear(-6.0), closeTo(0.501, 0.01));
        expect(service.dbToLinear(6.0), closeTo(1.995, 0.01));
        expect(service.dbToLinear(-20.0), closeTo(0.1, 0.001));
      });

      test('should convert linear to dB correctly', () {
        expect(service.linearToDb(1.0), closeTo(0.0, 0.001));
        expect(service.linearToDb(0.5), closeTo(-6.02, 0.1));
        expect(service.linearToDb(2.0), closeTo(6.02, 0.1));
        expect(service.linearToDb(0.0), equals(-60.0));
      });
    });

    group('SidechainConfiguration Model', () {
      test('copyWith should preserve unchanged values', () {
        const original = SidechainConfiguration(
          id: 1,
          processorId: 2,
          sourceType: SidechainSourceType.track,
          filterType: SidechainFilterType.highPass,
          mix: 0.5,
        );

        final updated = original.copyWith(mix: 0.75);

        expect(updated.id, equals(1));
        expect(updated.processorId, equals(2));
        expect(updated.sourceType, equals(SidechainSourceType.track));
        expect(updated.filterType, equals(SidechainFilterType.highPass));
        expect(updated.mix, equals(0.75));
      });

      test('should serialize and deserialize correctly', () {
        const original = SidechainConfiguration(
          id: 100,
          processorId: 200,
          sourceType: SidechainSourceType.bus,
          sourceId: 5,
          filterType: SidechainFilterType.bandPass,
          filterFrequency: 1500.0,
          filterQ: 2.5,
          mix: 0.8,
          gainDb: -3.0,
          monitoring: true,
          enabled: false,
        );

        final json = original.toJson();
        final restored = SidechainConfiguration.fromJson(json);

        expect(restored.id, equals(original.id));
        expect(restored.processorId, equals(original.processorId));
        expect(restored.sourceType, equals(original.sourceType));
        expect(restored.sourceId, equals(original.sourceId));
        expect(restored.filterType, equals(original.filterType));
        expect(restored.filterFrequency, equals(original.filterFrequency));
        expect(restored.filterQ, equals(original.filterQ));
        expect(restored.mix, equals(original.mix));
        expect(restored.gainDb, equals(original.gainDb));
        expect(restored.monitoring, equals(original.monitoring));
        expect(restored.enabled, equals(original.enabled));
      });
    });
  });
}
