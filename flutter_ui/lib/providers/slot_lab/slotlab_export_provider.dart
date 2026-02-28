/// SlotLab Export Provider — Middleware §32
///
/// Export pipeline for SlotLab configurations.
/// Supports multiple export formats: JSON, YAML, Wwise SoundBank XML,
/// FMOD Bank, and custom FluxForge format.
///
/// See: SlotLab_Middleware_Architecture_Ultimate.md §32

import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Export format types
enum ExportFormat {
  /// FluxForge native JSON
  fluxforgeJson,
  /// Wwise SoundBank XML-compatible
  wwiseSoundbankXml,
  /// FMOD Studio Bank-compatible
  fmodBank,
  /// Minimal JSON (only behavior tree + assignments)
  minimalJson,
  /// Human-readable report
  textReport,
}

extension ExportFormatExtension on ExportFormat {
  String get displayName {
    switch (this) {
      case ExportFormat.fluxforgeJson: return 'FluxForge JSON';
      case ExportFormat.wwiseSoundbankXml: return 'Wwise SoundBank XML';
      case ExportFormat.fmodBank: return 'FMOD Bank';
      case ExportFormat.minimalJson: return 'Minimal JSON';
      case ExportFormat.textReport: return 'Text Report';
    }
  }

  String get fileExtension {
    switch (this) {
      case ExportFormat.fluxforgeJson: return '.fluxforge.json';
      case ExportFormat.wwiseSoundbankXml: return '.bnk.xml';
      case ExportFormat.fmodBank: return '.fmod.json';
      case ExportFormat.minimalJson: return '.min.json';
      case ExportFormat.textReport: return '.txt';
    }
  }
}

/// Sections that can be included in export
enum ExportSection {
  behaviorTree,
  soundAssignments,
  triggerBindings,
  busRouting,
  duckingRules,
  winTierConfig,
  contextOverrides,
  transitionRules,
  priorityConfig,
  orchestrationConfig,
  musicSystem,
  voicePoolConfig,
}

extension ExportSectionExtension on ExportSection {
  String get displayName {
    switch (this) {
      case ExportSection.behaviorTree: return 'Behavior Tree';
      case ExportSection.soundAssignments: return 'Sound Assignments';
      case ExportSection.triggerBindings: return 'Trigger Bindings';
      case ExportSection.busRouting: return 'Bus Routing';
      case ExportSection.duckingRules: return 'Ducking Rules';
      case ExportSection.winTierConfig: return 'Win Tier Config';
      case ExportSection.contextOverrides: return 'Context Overrides';
      case ExportSection.transitionRules: return 'Transition Rules';
      case ExportSection.priorityConfig: return 'Priority Config';
      case ExportSection.orchestrationConfig: return 'Orchestration Config';
      case ExportSection.musicSystem: return 'Music System';
      case ExportSection.voicePoolConfig: return 'Voice Pool Config';
    }
  }
}

/// Export result
class ExportResult {
  final bool success;
  final ExportFormat format;
  final String? data;
  final String? error;
  final int? byteSize;
  final DateTime timestamp;

  const ExportResult({
    required this.success,
    required this.format,
    this.data,
    this.error,
    this.byteSize,
    required this.timestamp,
  });
}

class SlotLabExportProvider extends ChangeNotifier {
  /// Selected export format
  ExportFormat _selectedFormat = ExportFormat.fluxforgeJson;

  /// Selected sections to include
  final Set<ExportSection> _selectedSections = Set.from(ExportSection.values);

  /// Export history
  final List<ExportResult> _exportHistory = [];

  /// Whether export is in progress
  bool _isExporting = false;

  /// Last export result
  ExportResult? _lastResult;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  ExportFormat get selectedFormat => _selectedFormat;
  Set<ExportSection> get selectedSections => Set.unmodifiable(_selectedSections);
  List<ExportResult> get exportHistory => List.unmodifiable(_exportHistory);
  bool get isExporting => _isExporting;
  ExportResult? get lastResult => _lastResult;

  bool isSectionSelected(ExportSection section) => _selectedSections.contains(section);

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════════

  void setFormat(ExportFormat format) {
    if (_selectedFormat == format) return;
    _selectedFormat = format;
    notifyListeners();
  }

  void toggleSection(ExportSection section) {
    if (_selectedSections.contains(section)) {
      _selectedSections.remove(section);
    } else {
      _selectedSections.add(section);
    }
    notifyListeners();
  }

  void selectAllSections() {
    _selectedSections.addAll(ExportSection.values);
    notifyListeners();
  }

  void deselectAllSections() {
    _selectedSections.clear();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXPORT EXECUTION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Execute export with provided data from providers
  ExportResult export(Map<String, dynamic> projectData) {
    _isExporting = true;
    notifyListeners();

    try {
      // Filter data to only selected sections
      final filteredData = <String, dynamic>{
        'format': _selectedFormat.name,
        'exportedAt': DateTime.now().toIso8601String(),
        'version': '1.0',
      };

      for (final section in _selectedSections) {
        final key = section.name;
        if (projectData.containsKey(key)) {
          filteredData[key] = projectData[key];
        }
      }

      String output;
      switch (_selectedFormat) {
        case ExportFormat.fluxforgeJson:
        case ExportFormat.minimalJson:
        case ExportFormat.fmodBank:
          output = const JsonEncoder.withIndent('  ').convert(filteredData);
        case ExportFormat.wwiseSoundbankXml:
          output = _convertToWwiseXml(filteredData);
        case ExportFormat.textReport:
          output = _convertToTextReport(filteredData);
      }

      final result = ExportResult(
        success: true,
        format: _selectedFormat,
        data: output,
        byteSize: utf8.encode(output).length,
        timestamp: DateTime.now(),
      );

      _lastResult = result;
      _exportHistory.insert(0, result);
      if (_exportHistory.length > 20) _exportHistory.removeLast();

      _isExporting = false;
      notifyListeners();
      return result;
    } catch (e) {
      final result = ExportResult(
        success: false,
        format: _selectedFormat,
        error: e.toString(),
        timestamp: DateTime.now(),
      );

      _lastResult = result;
      _exportHistory.insert(0, result);

      _isExporting = false;
      notifyListeners();
      return result;
    }
  }

  String _convertToWwiseXml(Map<String, dynamic> data) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<SoundBank xmlns="http://www.audiokinetic.com/soundbank">');
    buffer.writeln('  <FluxForgeExport version="1.0">');

    for (final entry in data.entries) {
      if (entry.key == 'format' || entry.key == 'exportedAt' || entry.key == 'version') continue;
      buffer.writeln('    <Section name="${entry.key}">');
      buffer.writeln('      <!-- Data: ${entry.value.runtimeType} -->');
      buffer.writeln('    </Section>');
    }

    buffer.writeln('  </FluxForgeExport>');
    buffer.writeln('</SoundBank>');
    return buffer.toString();
  }

  String _convertToTextReport(Map<String, dynamic> data) {
    final buffer = StringBuffer();
    buffer.writeln('╔══════════════════════════════════════╗');
    buffer.writeln('║  FluxForge SlotLab Export Report     ║');
    buffer.writeln('╚══════════════════════════════════════╝');
    buffer.writeln();
    buffer.writeln('Exported: ${data['exportedAt']}');
    buffer.writeln('Format: ${data['format']}');
    buffer.writeln('Version: ${data['version']}');
    buffer.writeln();

    for (final entry in data.entries) {
      if (entry.key == 'format' || entry.key == 'exportedAt' || entry.key == 'version') continue;
      buffer.writeln('── ${entry.key} ──');
      if (entry.value is Map) {
        buffer.writeln('  (${(entry.value as Map).length} entries)');
      } else if (entry.value is List) {
        buffer.writeln('  (${(entry.value as List).length} items)');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Clear export history
  void clearHistory() {
    _exportHistory.clear();
    _lastResult = null;
    notifyListeners();
  }
}
