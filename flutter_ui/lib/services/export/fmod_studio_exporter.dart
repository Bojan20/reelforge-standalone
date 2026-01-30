/// FMOD Studio Exporter
///
/// P2-06: Export FluxForge middleware data to FMOD Studio project format.
/// Generates .fspro project structure with events, banks, parameters.
///
/// FMOD Studio Project Structure:
/// - .fspro (XML project file)
/// - Metadata/ (event definitions, parameters, banks)
/// - Build/ (compiled banks)
/// - Assets/ (audio files)

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../../models/middleware_models.dart';
import '../../models/slot_audio_events.dart';

/// FMOD Studio project configuration
class FmodStudioConfig {
  /// Project name
  final String projectName;

  /// Master bank name
  final String masterBankName;

  /// Sample rate (Hz)
  final int sampleRate;

  /// Speaker mode (mono, stereo, 5.1, 7.1, 7.1.4)
  final String speakerMode;

  /// Enable profiling
  final bool enableProfiling;

  /// Export audio files (copy to Assets/)
  final bool exportAudioFiles;

  const FmodStudioConfig({
    this.projectName = 'FluxForge_Export',
    this.masterBankName = 'Master',
    this.sampleRate = 48000,
    this.speakerMode = 'stereo',
    this.enableProfiling = true,
    this.exportAudioFiles = true,
  });
}

/// FMOD Studio exporter
class FmodStudioExporter {
  final FmodStudioConfig config;

  const FmodStudioExporter({this.config = const FmodStudioConfig()});

  /// Export to FMOD Studio project directory
  Future<FmodExportResult> export({
    required String outputPath,
    required List<SlotCompositeEvent> events,
    required List<RtpcDefinition> rtpcs,
    required List<StateGroup> stateGroups,
    required List<SwitchGroup> switchGroups,
    required List<DuckingRule> duckingRules,
    Map<String, String>? audioPathMapping, // FluxForge path → FMOD relative path
  }) async {
    final projectDir = Directory(outputPath);
    if (!await projectDir.exists()) {
      await projectDir.create(recursive: true);
    }

    final result = FmodExportResult(
      projectPath: outputPath,
      projectName: config.projectName,
      files: [],
    );

    try {
      // 1. Create project structure
      await _createProjectStructure(projectDir);

      // 2. Generate .fspro project file
      final fspro = await _generateFsproFile(projectDir, events, rtpcs, stateGroups);
      result.files.add(fspro);

      // 3. Generate Metadata XML files
      final metadataFiles = await _generateMetadataFiles(
        projectDir,
        events,
        rtpcs,
        stateGroups,
        switchGroups,
      );
      result.files.addAll(metadataFiles);

      // 4. Generate Master Bank
      final masterBank = await _generateMasterBank(projectDir, events);
      result.files.add(masterBank);

      // 5. Copy audio files (if enabled)
      if (config.exportAudioFiles && audioPathMapping != null) {
        final copiedFiles = await _copyAudioFiles(projectDir, audioPathMapping);
        result.files.addAll(copiedFiles);
      }

      // 6. Generate build manifest
      final manifest = await _generateManifest(projectDir, result);
      result.files.add(manifest);

      result.success = true;
    } catch (e) {
      result.success = false;
      result.error = e.toString();
    }

    return result;
  }

  /// Create FMOD Studio project directory structure
  Future<void> _createProjectStructure(Directory projectDir) async {
    final dirs = [
      'Metadata',
      'Metadata/Event',
      'Metadata/Bank',
      'Metadata/Parameter',
      'Metadata/Effect',
      'Build',
      'Assets',
    ];

    for (final dirName in dirs) {
      final dir = Directory(path.join(projectDir.path, dirName));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }
  }

  /// Generate .fspro project file (XML)
  Future<String> _generateFsproFile(
    Directory projectDir,
    List<SlotCompositeEvent> events,
    List<RtpcDefinition> rtpcs,
    List<StateGroup> stateGroups,
  ) async {
    final xml = StringBuffer();
    xml.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    xml.writeln('<objects serializationModel="Studio.02.02.00">');
    xml.writeln('  <object class="MasterAssetFolder" id="{${_generateGuid()}}">');
    xml.writeln('    <property name="name">');
    xml.writeln('      <value>${config.projectName}</value>');
    xml.writeln('    </property>');
    xml.writeln('  </object>');
    xml.writeln('</objects>');

    final file = File(path.join(projectDir.path, '${config.projectName}.fspro'));
    await file.writeAsString(xml.toString());
    return file.path;
  }

  /// Generate Metadata XML files
  Future<List<String>> _generateMetadataFiles(
    Directory projectDir,
    List<SlotCompositeEvent> events,
    List<RtpcDefinition> rtpcs,
    List<StateGroup> stateGroups,
    List<SwitchGroup> switchGroups,
  ) async {
    final files = <String>[];

    // Generate event XMLs
    for (final event in events) {
      final file = await _generateEventMetadata(projectDir, event);
      files.add(file);
    }

    // Generate parameter XMLs (RTPCs)
    for (final rtpc in rtpcs) {
      final file = await _generateParameterMetadata(projectDir, rtpc);
      files.add(file);
    }

    // Generate state groups (game parameters)
    for (final group in stateGroups) {
      final file = await _generateStateGroupMetadata(projectDir, group);
      files.add(file);
    }

    return files;
  }

  /// Generate event metadata XML
  Future<String> _generateEventMetadata(Directory projectDir, SlotCompositeEvent event) async {
    final xml = StringBuffer();
    xml.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    xml.writeln('<objects serializationModel="Studio.02.02.00">');
    xml.writeln('  <object class="Event" id="{${_generateGuid()}}">');
    xml.writeln('    <property name="name">');
    xml.writeln('      <value>${_sanitizeName(event.eventName)}</value>');
    xml.writeln('    </property>');

    // Event tracks (layers)
    xml.writeln('    <relationship name="masterTrack">');
    for (final layer in event.layers) {
      xml.writeln('      <destination>');
      xml.writeln('        <object class="GroupTrack">');
      xml.writeln('          <property name="name">');
      xml.writeln('            <value>Layer_${layer.id}</value>');
      xml.writeln('          </property>');

      // Audio file reference
      if (layer.audioPath != null) {
        xml.writeln('          <relationship name="modules">');
        xml.writeln('            <destination>');
        xml.writeln('              <object class="SingleSound">');
        xml.writeln('                <property name="audioFile">');
        xml.writeln('                  <value>event:/${_getRelativeAudioPath(layer.audioPath!)}</value>');
        xml.writeln('                </property>');
        xml.writeln('                <property name="volume">');
        xml.writeln('                  <value>${layer.volume}</value>');
        xml.writeln('                </property>');
        xml.writeln('              </object>');
        xml.writeln('            </destination>');
        xml.writeln('          </relationship>');
      }

      xml.writeln('        </object>');
      xml.writeln('      </destination>');
    }
    xml.writeln('    </relationship>');
    xml.writeln('  </object>');
    xml.writeln('</objects>');

    final file = File(path.join(projectDir.path, 'Metadata', 'Event', '${event.id}.xml'));
    await file.writeAsString(xml.toString());
    return file.path;
  }

  /// Generate parameter metadata (RTPC)
  Future<String> _generateParameterMetadata(Directory projectDir, RtpcDefinition rtpc) async {
    final xml = StringBuffer();
    xml.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    xml.writeln('<objects serializationModel="Studio.02.02.00">');
    xml.writeln('  <object class="GameParameter" id="{${_generateGuid()}}">');
    xml.writeln('    <property name="name">');
    xml.writeln('      <value>${_sanitizeName(rtpc.name)}</value>');
    xml.writeln('    </property>');
    xml.writeln('    <property name="minimum">');
    xml.writeln('      <value>${rtpc.min}</value>');
    xml.writeln('    </property>');
    xml.writeln('    <property name="maximum">');
    xml.writeln('      <value>${rtpc.max}</value>');
    xml.writeln('    </property>');
    xml.writeln('    <property name="initialValue">');
    xml.writeln('      <value>${rtpc.value}</value>');
    xml.writeln('    </property>');
    xml.writeln('  </object>');
    xml.writeln('</objects>');

    final file = File(path.join(projectDir.path, 'Metadata', 'Parameter', '${rtpc.id}.xml'));
    await file.writeAsString(xml.toString());
    return file.path;
  }

  /// Generate state group metadata
  Future<String> _generateStateGroupMetadata(Directory projectDir, StateGroup group) async {
    final xml = StringBuffer();
    xml.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    xml.writeln('<objects serializationModel="Studio.02.02.00">');
    xml.writeln('  <object class="GameParameter" id="{${_generateGuid()}}">');
    xml.writeln('    <property name="name">');
    xml.writeln('      <value>State_${_sanitizeName(group.name)}</value>');
    xml.writeln('    </property>');
    xml.writeln('    <property name="isEnum">');
    xml.writeln('      <value>true</value>');
    xml.writeln('    </property>');

    // States as enum values
    xml.writeln('    <relationship name="enumValues">');
    for (final state in group.states) {
      xml.writeln('      <destination>');
      xml.writeln('        <value>${_sanitizeName(state.name)}</value>');
      xml.writeln('      </destination>');
    }
    xml.writeln('    </relationship>');

    xml.writeln('  </object>');
    xml.writeln('</objects>');

    final file = File(path.join(projectDir.path, 'Metadata', 'Parameter', '${group.name}_state.xml'));
    await file.writeAsString(xml.toString());
    return file.path;
  }

  /// Generate Master Bank
  Future<String> _generateMasterBank(Directory projectDir, List<SlotCompositeEvent> events) async {
    final xml = StringBuffer();
    xml.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    xml.writeln('<objects serializationModel="Studio.02.02.00">');
    xml.writeln('  <object class="Bank" id="{${_generateGuid()}}">');
    xml.writeln('    <property name="name">');
    xml.writeln('      <value>${config.masterBankName}</value>');
    xml.writeln('    </property>');

    // Include all events in master bank
    xml.writeln('    <relationship name="eventReferences">');
    for (final event in events) {
      xml.writeln('      <destination>event:/${_sanitizeName(event.eventName)}</destination>');
    }
    xml.writeln('    </relationship>');

    xml.writeln('  </object>');
    xml.writeln('</objects>');

    final file = File(path.join(projectDir.path, 'Metadata', 'Bank', '${config.masterBankName}.xml'));
    await file.writeAsString(xml.toString());
    return file.path;
  }

  /// Copy audio files to Assets/ directory
  Future<List<String>> _copyAudioFiles(
    Directory projectDir,
    Map<String, String> audioPathMapping,
  ) async {
    final assetsDir = Directory(path.join(projectDir.path, 'Assets'));
    final copiedFiles = <String>[];

    for (final entry in audioPathMapping.entries) {
      final sourcePath = entry.key;
      final relativeTarget = entry.value;

      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) continue;

      final targetFile = File(path.join(assetsDir.path, relativeTarget));
      await targetFile.parent.create(recursive: true);
      await sourceFile.copy(targetFile.path);

      copiedFiles.add(targetFile.path);
    }

    return copiedFiles;
  }

  /// Generate build manifest (JSON)
  Future<String> _generateManifest(Directory projectDir, FmodExportResult result) async {
    final manifest = {
      'projectName': config.projectName,
      'exportDate': DateTime.now().toIso8601String(),
      'sampleRate': config.sampleRate,
      'speakerMode': config.speakerMode,
      'eventCount': result.files.where((f) => f.contains('Event')).length,
      'parameterCount': result.files.where((f) => f.contains('Parameter')).length,
      'files': result.files.map((f) => path.relative(f, from: projectDir.path)).toList(),
    };

    final file = File(path.join(projectDir.path, 'export_manifest.json'));
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));
    return file.path;
  }

  /// Sanitize name for FMOD (no special chars)
  String _sanitizeName(String name) {
    return name
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
  }

  /// Get relative audio path for FMOD
  String _getRelativeAudioPath(String absolutePath) {
    return path.basename(absolutePath);
  }

  /// Generate GUID for FMOD objects
  String _generateGuid() {
    // Simple GUID generation (not cryptographically secure)
    final rand = DateTime.now().millisecondsSinceEpoch;
    return '${rand.toRadixString(16).padLeft(8, '0')}-'
           '${(rand ~/ 1000).toRadixString(16).padLeft(4, '0')}-'
           '4${(rand ~/ 100).toRadixString(16).padLeft(3, '0')}-'
           'a${(rand ~/ 10).toRadixString(16).padLeft(3, '0')}-'
           '${rand.toRadixString(16).padLeft(12, '0')}';
  }
}

/// FMOD Studio export result
class FmodExportResult {
  final String projectPath;
  final String projectName;
  final List<String> files;
  bool success;
  String? error;

  FmodExportResult({
    required this.projectPath,
    required this.projectName,
    required this.files,
    this.success = false,
    this.error,
  });

  /// Summary string
  String get summary {
    if (!success) {
      return 'Export failed: $error';
    }

    return 'Exported to: $projectPath\n'
           'Files: ${files.length}\n'
           'Events: ${files.where((f) => f.contains('Event')).length}\n'
           'Parameters: ${files.where((f) => f.contains('Parameter')).length}';
  }
}
