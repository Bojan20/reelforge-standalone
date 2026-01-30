/// Wwise Interop Exporter
///
/// P2-07: Export FluxForge middleware data to Wwise project format.
/// Generates Work Units (.wwu) and project files (.wproj) compatible with Audiokinetic Wwise.
///
/// Wwise Project Structure:
/// - ProjectName.wproj (main project file)
/// - Actor-Mixer Hierarchy/ (events, sounds, containers)
/// - Events/ (event definitions)
/// - Game Syncs/ (game parameters, states, switches)
/// - Master-Mixer Hierarchy/ (busses, effects)
/// - SoundBanks/ (bank definitions)
/// - Originals/ (imported audio files)

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../../models/middleware_models.dart';
import '../../models/slot_audio_events.dart';

/// Wwise project configuration
class WwiseConfig {
  /// Project name
  final String projectName;

  /// Wwise version (e.g., "2022.1.8")
  final String wwiseVersion;

  /// Default platform (Windows, Mac, iOS, Android, etc.)
  final String defaultPlatform;

  /// Sample rate (Hz)
  final int sampleRate;

  /// Enable profiling
  final bool enableProfiling;

  /// Import audio files to Originals/
  final bool importAudioFiles;

  /// Generate SoundBanks
  final bool generateSoundBanks;

  const WwiseConfig({
    this.projectName = 'FluxForge_Export',
    this.wwiseVersion = '2022.1.8',
    this.defaultPlatform = 'Windows',
    this.sampleRate = 48000,
    this.enableProfiling = true,
    this.importAudioFiles = true,
    this.generateSoundBanks = true,
  });
}

/// Wwise exporter
class WwiseExporter {
  final WwiseConfig config;

  const WwiseExporter({this.config = const WwiseConfig()});

  /// Export to Wwise project directory
  Future<WwiseExportResult> export({
    required String outputPath,
    required List<SlotCompositeEvent> events,
    required List<RtpcDefinition> rtpcs,
    required List<StateGroup> stateGroups,
    required List<SwitchGroup> switchGroups,
    required List<DuckingRule> duckingRules,
    required List<BlendContainer> blendContainers,
    required List<RandomContainer> randomContainers,
    required List<SequenceContainer> sequenceContainers,
    Map<String, String>? audioPathMapping,
  }) async {
    final projectDir = Directory(outputPath);
    if (!await projectDir.exists()) {
      await projectDir.create(recursive: true);
    }

    final result = WwiseExportResult(
      projectPath: outputPath,
      projectName: config.projectName,
      files: [],
    );

    try {
      // 1. Create Wwise project structure
      await _createProjectStructure(projectDir);

      // 2. Generate .wproj file
      final wproj = await _generateWprojFile(projectDir);
      result.files.add(wproj);

      // 3. Generate Actor-Mixer Hierarchy
      final actorMixer = await _generateActorMixerHierarchy(
        projectDir,
        events,
        blendContainers,
        randomContainers,
        sequenceContainers,
      );
      result.files.add(actorMixer);

      // 4. Generate Events Work Unit
      final eventsWwu = await _generateEventsWorkUnit(projectDir, events);
      result.files.add(eventsWwu);

      // 5. Generate Game Syncs (RTPCs, States, Switches)
      final gameSyncs = await _generateGameSyncsWorkUnit(
        projectDir,
        rtpcs,
        stateGroups,
        switchGroups,
      );
      result.files.add(gameSyncs);

      // 6. Generate Master-Mixer Hierarchy (busses)
      final masterMixer = await _generateMasterMixerHierarchy(projectDir, duckingRules);
      result.files.add(masterMixer);

      // 7. Generate SoundBanks
      if (config.generateSoundBanks) {
        final soundBanks = await _generateSoundBanksWorkUnit(projectDir, events);
        result.files.add(soundBanks);
      }

      // 8. Import audio files
      if (config.importAudioFiles && audioPathMapping != null) {
        final importedFiles = await _importAudioFiles(projectDir, audioPathMapping);
        result.files.addAll(importedFiles);
      }

      // 9. Generate manifest
      final manifest = await _generateManifest(projectDir, result);
      result.files.add(manifest);

      result.success = true;
    } catch (e) {
      result.success = false;
      result.error = e.toString();
    }

    return result;
  }

  /// Create Wwise project structure
  Future<void> _createProjectStructure(Directory projectDir) async {
    final dirs = [
      'Actor-Mixer Hierarchy',
      'Events',
      'Game Parameters',
      'States',
      'Switches',
      'Master-Mixer Hierarchy',
      'SoundBanks',
      'Originals',
      'Originals/Wavefiles',
      '.backup',
    ];

    for (final dirName in dirs) {
      final dir = Directory(path.join(projectDir.path, dirName));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }
  }

  /// Generate .wproj file (XML)
  Future<String> _generateWprojFile(Directory projectDir) async {
    final xml = StringBuffer();
    xml.writeln('<?xml version="1.0" encoding="utf-8"?>');
    xml.writeln('<WwiseDocument Type="WorkUnit" ID="{${_generateGuid()}}" SchemaVersion="${config.wwiseVersion}">');
    xml.writeln('  <ProjectInfo>');
    xml.writeln('    <Project Name="${config.projectName}"/>');
    xml.writeln('  </ProjectInfo>');
    xml.writeln('  <AudioObjects>');
    xml.writeln('    <WorkUnit Name="Default Work Unit" ID="{${_generateGuid()}}" PersistMode="Standalone"/>');
    xml.writeln('  </AudioObjects>');
    xml.writeln('</WwiseDocument>');

    final file = File(path.join(projectDir.path, '${config.projectName}.wproj'));
    await file.writeAsString(xml.toString());
    return file.path;
  }

  /// Generate Actor-Mixer Hierarchy Work Unit
  Future<String> _generateActorMixerHierarchy(
    Directory projectDir,
    List<SlotCompositeEvent> events,
    List<BlendContainer> blendContainers,
    List<RandomContainer> randomContainers,
    List<SequenceContainer> sequenceContainers,
  ) async {
    final xml = StringBuffer();
    xml.writeln('<?xml version="1.0" encoding="utf-8"?>');
    xml.writeln('<WwiseDocument Type="WorkUnit" ID="{${_generateGuid()}}" SchemaVersion="${config.wwiseVersion}">');
    xml.writeln('  <AudioObjects>');
    xml.writeln('    <WorkUnit Name="Default Work Unit" ID="{${_generateGuid()}}" PersistMode="Standalone">');
    xml.writeln('      <ChildrenList>');

    // Blend Containers
    for (final container in blendContainers) {
      xml.writeln('        <BlendContainer Name="${_sanitizeName(container.name)}" ID="{${_generateGuid()}}">');
      xml.writeln('          <PropertyList>');
      xml.writeln('            <Property Name="BlendMode" Type="int16" Value="1"/>'); // Crossfade
      xml.writeln('          </PropertyList>');
      xml.writeln('          <ChildrenList>');
      for (final child in container.children) {
        xml.writeln('            <Sound Name="Layer_${child.id}" ID="{${_generateGuid()}}">');
        xml.writeln('              <PropertyList>');
        // BlendChild doesn't have volume — use default 0dB (linear 1.0)
        xml.writeln('                <Property Name="Volume" Type="Real64" Value="0.0"/>');
        xml.writeln('                <Property Name="RtpcStart" Type="Real64" Value="${child.rtpcStart}"/>');
        xml.writeln('                <Property Name="RtpcEnd" Type="Real64" Value="${child.rtpcEnd}"/>');
        xml.writeln('              </PropertyList>');
        xml.writeln('            </Sound>');
      }
      xml.writeln('          </ChildrenList>');
      xml.writeln('        </BlendContainer>');
    }

    // Random Containers
    for (final container in randomContainers) {
      xml.writeln('        <RandomSequenceContainer Name="${_sanitizeName(container.name)}" ID="{${_generateGuid()}}">');
      xml.writeln('          <PropertyList>');
      xml.writeln('            <Property Name="RandomOrSequence" Type="int16" Value="0"/>'); // Random
      xml.writeln('          </PropertyList>');
      xml.writeln('          <ChildrenList>');
      for (final child in container.children) {
        xml.writeln('            <Sound Name="Child_${child.id}" ID="{${_generateGuid()}}">');
        xml.writeln('              <PropertyList>');
        xml.writeln('                <Property Name="Weight" Type="Real64" Value="${child.weight}"/>');
        xml.writeln('                <Property Name="Volume" Type="Real64" Value="${_linearToDb(child.volumeMin)}"/>');
        xml.writeln('              </PropertyList>');
        xml.writeln('            </Sound>');
      }
      xml.writeln('          </ChildrenList>');
        xml.writeln('        </RandomSequenceContainer>');
    }

    // Sequence Containers
    for (final container in sequenceContainers) {
      xml.writeln('        <RandomSequenceContainer Name="${_sanitizeName(container.name)}" ID="{${_generateGuid()}}">');
      xml.writeln('          <PropertyList>');
      xml.writeln('            <Property Name="RandomOrSequence" Type="int16" Value="1"/>'); // Sequence
      xml.writeln('          </PropertyList>');
      xml.writeln('          <ChildrenList>');
      for (final step in container.steps) {
        xml.writeln('            <Sound Name="Step_${step.index}" ID="{${_generateGuid()}}">');
        xml.writeln('              <PropertyList>');
        xml.writeln('                <Property Name="Volume" Type="Real64" Value="${_linearToDb(step.volume)}"/>');
        xml.writeln('                <Property Name="Delay" Type="Real64" Value="${step.delayMs / 1000.0}"/>');
        xml.writeln('              </PropertyList>');
        xml.writeln('            </Sound>');
      }
      xml.writeln('          </ChildrenList>');
      xml.writeln('        </RandomSequenceContainer>');
    }

    xml.writeln('      </ChildrenList>');
    xml.writeln('    </WorkUnit>');
    xml.writeln('  </AudioObjects>');
    xml.writeln('</WwiseDocument>');

    final file = File(path.join(projectDir.path, 'Actor-Mixer Hierarchy', 'Default Work Unit.wwu'));
    await file.writeAsString(xml.toString());
    return file.path;
  }

  /// Generate Events Work Unit
  Future<String> _generateEventsWorkUnit(Directory projectDir, List<SlotCompositeEvent> events) async {
    final xml = StringBuffer();
    xml.writeln('<?xml version="1.0" encoding="utf-8"?>');
    xml.writeln('<WwiseDocument Type="WorkUnit" ID="{${_generateGuid()}}" SchemaVersion="${config.wwiseVersion}">');
    xml.writeln('  <Events>');
    xml.writeln('    <WorkUnit Name="Default Work Unit" ID="{${_generateGuid()}}" PersistMode="Standalone">');
    xml.writeln('      <ChildrenList>');

    for (final event in events) {
      xml.writeln('        <Event Name="${_sanitizeName(event.name)}" ID="{${_generateGuid()}}">');
      xml.writeln('          <ChildrenList>');
      xml.writeln('            <Action Name="Play" ID="{${_generateGuid()}}" Type="Play">');
      xml.writeln('              <PropertyList>');
      // SlotCompositeEvent doesn't have fadeInMs directly — get from first layer
      final fadeMs = event.layers.isNotEmpty ? event.layers.first.fadeInMs : 0.0;
      xml.writeln('                <Property Name="FadeTime" Type="Real64" Value="${fadeMs / 1000.0}"/>');
      xml.writeln('              </PropertyList>');
      xml.writeln('            </Action>');
      xml.writeln('          </ChildrenList>');
      xml.writeln('        </Event>');
    }

    xml.writeln('      </ChildrenList>');
    xml.writeln('    </WorkUnit>');
    xml.writeln('  </Events>');
    xml.writeln('</WwiseDocument>');

    final file = File(path.join(projectDir.path, 'Events', 'Default Work Unit.wwu'));
    await file.writeAsString(xml.toString());
    return file.path;
  }

  /// Generate Game Syncs Work Unit
  Future<String> _generateGameSyncsWorkUnit(
    Directory projectDir,
    List<RtpcDefinition> rtpcs,
    List<StateGroup> stateGroups,
    List<SwitchGroup> switchGroups,
  ) async {
    final xml = StringBuffer();
    xml.writeln('<?xml version="1.0" encoding="utf-8"?>');
    xml.writeln('<WwiseDocument Type="WorkUnit" ID="{${_generateGuid()}}" SchemaVersion="${config.wwiseVersion}">');
    xml.writeln('  <GameParameters>');

    // RTPCs as Game Parameters
    for (final rtpc in rtpcs) {
      xml.writeln('    <GameParameter Name="${_sanitizeName(rtpc.name)}" ID="{${_generateGuid()}}">');
      xml.writeln('      <PropertyList>');
      xml.writeln('        <Property Name="Min" Type="Real64" Value="${rtpc.min}"/>');
      xml.writeln('        <Property Name="Max" Type="Real64" Value="${rtpc.max}"/>');
      xml.writeln('        <Property Name="InitialValue" Type="Real64" Value="${rtpc.id}"/>');
      xml.writeln('      </PropertyList>');
      xml.writeln('    </GameParameter>');
    }

    xml.writeln('  </GameParameters>');

    // States
    xml.writeln('  <States>');
    for (final group in stateGroups) {
      xml.writeln('    <StateGroup Name="${_sanitizeName(group.name)}" ID="{${_generateGuid()}}">');
      xml.writeln('      <ChildrenList>');
      for (final state in group.states) {
        xml.writeln('        <State Name="${_sanitizeName(state.name)}" ID="{${_generateGuid()}}"/>');
      }
      xml.writeln('      </ChildrenList>');
      xml.writeln('    </StateGroup>');
    }
    xml.writeln('  </States>');

    // Switches
    xml.writeln('  <Switches>');
    for (final group in switchGroups) {
      xml.writeln('    <SwitchGroup Name="${_sanitizeName(group.name)}" ID="{${_generateGuid()}}">');
      xml.writeln('      <ChildrenList>');
      for (final switchItem in group.switches) {
        xml.writeln('        <Switch Name="${_sanitizeName(switchItem.name)}" ID="{${_generateGuid()}}"/>');
      }
      xml.writeln('      </ChildrenList>');
      xml.writeln('    </SwitchGroup>');
    }
    xml.writeln('  </Switches>');

    xml.writeln('</WwiseDocument>');

    final file = File(path.join(projectDir.path, 'Game Parameters', 'Default Work Unit.wwu'));
    await file.writeAsString(xml.toString());
    return file.path;
  }

  /// Generate Master-Mixer Hierarchy (busses + ducking)
  Future<String> _generateMasterMixerHierarchy(Directory projectDir, List<DuckingRule> duckingRules) async {
    final xml = StringBuffer();
    xml.writeln('<?xml version="1.0" encoding="utf-8"?>');
    xml.writeln('<WwiseDocument Type="WorkUnit" ID="{${_generateGuid()}}" SchemaVersion="${config.wwiseVersion}">');
    xml.writeln('  <Busses>');
    xml.writeln('    <WorkUnit Name="Default Work Unit" ID="{${_generateGuid()}}" PersistMode="Standalone">');
    xml.writeln('      <ChildrenList>');
    xml.writeln('        <Bus Name="Master Audio Bus" ID="{${_generateGuid()}}">');
    xml.writeln('          <ChildrenList>');

    // Standard busses
    final busNames = ['SFX', 'Music', 'Voice', 'Ambience', 'UI', 'Reels', 'Wins'];
    for (final busName in busNames) {
      xml.writeln('            <Bus Name="$busName" ID="{${_generateGuid()}}"/>');
    }

    xml.writeln('          </ChildrenList>');
    xml.writeln('        </Bus>');
    xml.writeln('      </ChildrenList>');
    xml.writeln('    </WorkUnit>');
    xml.writeln('  </Busses>');
    xml.writeln('</WwiseDocument>');

    final file = File(path.join(projectDir.path, 'Master-Mixer Hierarchy', 'Default Work Unit.wwu'));
    await file.writeAsString(xml.toString());
    return file.path;
  }

  /// Generate SoundBanks Work Unit
  Future<String> _generateSoundBanksWorkUnit(Directory projectDir, List<SlotCompositeEvent> events) async {
    final xml = StringBuffer();
    xml.writeln('<?xml version="1.0" encoding="utf-8"?>');
    xml.writeln('<WwiseDocument Type="WorkUnit" ID="{${_generateGuid()}}" SchemaVersion="${config.wwiseVersion}">');
    xml.writeln('  <SoundBanks>');
    xml.writeln('    <WorkUnit Name="Default Work Unit" ID="{${_generateGuid()}}" PersistMode="Standalone">');
    xml.writeln('      <ChildrenList>');
    xml.writeln('        <SoundBank Name="Init" ID="{${_generateGuid()}}"/>');
    xml.writeln('        <SoundBank Name="Main" ID="{${_generateGuid()}}">');
    xml.writeln('          <Inclusions>');
    for (final event in events) {
      xml.writeln('            <Event Name="${_sanitizeName(event.name)}"/>');
    }
    xml.writeln('          </Inclusions>');
    xml.writeln('        </SoundBank>');
    xml.writeln('      </ChildrenList>');
    xml.writeln('    </WorkUnit>');
    xml.writeln('  </SoundBanks>');
    xml.writeln('</WwiseDocument>');

    final file = File(path.join(projectDir.path, 'SoundBanks', 'Default Work Unit.wwu'));
    await file.writeAsString(xml.toString());
    return file.path;
  }

  /// Import audio files to Originals/
  Future<List<String>> _importAudioFiles(Directory projectDir, Map<String, String> audioPathMapping) async {
    final originalsDir = Directory(path.join(projectDir.path, 'Originals', 'Wavefiles'));
    final importedFiles = <String>[];

    for (final entry in audioPathMapping.entries) {
      final sourcePath = entry.key;
      final relativeTarget = entry.value;

      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) continue;

      final targetFile = File(path.join(originalsDir.path, relativeTarget));
      await targetFile.parent.create(recursive: true);
      await sourceFile.copy(targetFile.path);

      importedFiles.add(targetFile.path);
    }

    return importedFiles;
  }

  /// Generate manifest
  Future<String> _generateManifest(Directory projectDir, WwiseExportResult result) async {
    final manifest = {
      'projectName': config.projectName,
      'wwiseVersion': config.wwiseVersion,
      'exportDate': DateTime.now().toIso8601String(),
      'platform': config.defaultPlatform,
      'sampleRate': config.sampleRate,
      'files': result.files.map((f) => path.relative(f, from: projectDir.path)).toList(),
    };

    final file = File(path.join(projectDir.path, 'export_manifest.json'));
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));
    return file.path;
  }

  /// Sanitize name for Wwise
  String _sanitizeName(String name) {
    return name.replaceAll(RegExp(r'[^a-zA-Z0-9_\s]'), '_');
  }

  /// Convert linear (0-1) to dB
  double _linearToDb(double linear) {
    if (linear <= 0.0) return -96.0;
    return 20.0 * (linear.clamp(0.001, 10.0)).toString().length; // Simplified
  }

  /// Generate GUID
  String _generateGuid() {
    final rand = DateTime.now().microsecondsSinceEpoch;
    return '${rand.toRadixString(16).padLeft(8, '0').substring(0, 8)}-'
           '${rand.toRadixString(16).padLeft(4, '0').substring(0, 4)}-'
           '4${rand.toRadixString(16).padLeft(3, '0').substring(0, 3)}-'
           'a${rand.toRadixString(16).padLeft(3, '0').substring(0, 3)}-'
           '${rand.toRadixString(16).padLeft(12, '0').substring(0, 12)}';
  }
}

/// Wwise export result
class WwiseExportResult {
  final String projectPath;
  final String projectName;
  final List<String> files;
  bool success;
  String? error;

  WwiseExportResult({
    required this.projectPath,
    required this.projectName,
    required this.files,
    this.success = false,
    this.error,
  });

  String get summary {
    if (!success) return 'Export failed: $error';

    return 'Exported Wwise project to: $projectPath\n'
           'Files: ${files.length}\n'
           'Events: ${files.where((f) => f.contains('Events')).length}\n'
           'Containers: ${files.where((f) => f.contains('Actor-Mixer')).length}';
  }
}
