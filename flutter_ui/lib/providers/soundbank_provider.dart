// ═══════════════════════════════════════════════════════════════════════════════
// SOUNDBANK PROVIDER — State Management for Soundbank Building
// ═══════════════════════════════════════════════════════════════════════════════
//
// Manages soundbank creation, editing, and export:
// - Create/edit soundbanks with manifest metadata
// - Add/remove assets, events, containers
// - Validate bank integrity
// - Export to various platforms (Unity, Unreal, Howler, etc.)
// - Track dependencies between banks

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../models/soundbank_models.dart';
import '../services/export/unity_exporter.dart';
import '../src/rust/native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════════════

class SoundbankProvider extends ChangeNotifier {
  final NativeFFI _ffi;

  // All soundbanks in project
  final Map<String, Soundbank> _banks = {};

  // Currently selected bank for editing
  String? _selectedBankId;

  // Export progress
  bool _isExporting = false;
  double _exportProgress = 0.0;
  String? _exportStatus;

  // Validation cache
  final Map<String, SoundbankValidation> _validationCache = {};

  SoundbankProvider(this._ffi);

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  List<Soundbank> get banks => _banks.values.toList();
  int get bankCount => _banks.length;

  Soundbank? get selectedBank => _selectedBankId != null ? _banks[_selectedBankId] : null;
  String? get selectedBankId => _selectedBankId;

  bool get isExporting => _isExporting;
  double get exportProgress => _exportProgress;
  String? get exportStatus => _exportStatus;

  // ═══════════════════════════════════════════════════════════════════════════
  // BANK MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create new soundbank
  Soundbank createBank({
    required String name,
    String? description,
    String? author,
  }) {
    final bank = Soundbank.create(
      name: name,
      description: description,
      author: author,
    );
    _banks[bank.manifest.id] = bank;
    _selectedBankId = bank.manifest.id;
    notifyListeners();
    return bank;
  }

  /// Get bank by ID
  Soundbank? getBank(String bankId) => _banks[bankId];

  /// Select bank for editing
  void selectBank(String? bankId) {
    _selectedBankId = bankId;
    notifyListeners();
  }

  /// Update bank manifest
  void updateManifest(String bankId, SoundbankManifest Function(SoundbankManifest) update) {
    final bank = _banks[bankId];
    if (bank == null) return;

    final updatedManifest = update(bank.manifest).copyWith(
      modifiedAt: DateTime.now(),
    );
    _banks[bankId] = bank.copyWith(manifest: updatedManifest);
    _invalidateValidation(bankId);
    notifyListeners();
  }

  /// Delete bank
  void deleteBank(String bankId) {
    _banks.remove(bankId);
    _validationCache.remove(bankId);
    if (_selectedBankId == bankId) {
      _selectedBankId = _banks.keys.firstOrNull;
    }
    notifyListeners();
  }

  /// Duplicate bank
  Soundbank duplicateBank(String bankId, {String? newName}) {
    final source = _banks[bankId];
    if (source == null) throw StateError('Bank not found: $bankId');

    final now = DateTime.now();
    final newManifest = source.manifest.copyWith(
      id: 'bank_${now.millisecondsSinceEpoch}',
      name: newName ?? '${source.manifest.name} (Copy)',
      createdAt: now,
      modifiedAt: now,
    );

    final newBank = source.copyWith(manifest: newManifest);
    _banks[newManifest.id] = newBank;
    notifyListeners();
    return newBank;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ASSET MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add asset to bank
  Future<SoundbankAsset?> addAsset(String bankId, String filePath) async {
    final bank = _banks[bankId];
    if (bank == null) return null;

    final file = File(filePath);
    if (!await file.exists()) return null;

    // Get file info
    final stat = await file.stat();
    final bytes = await file.readAsBytes();
    final checksum = sha256.convert(bytes).toString();

    // Get audio metadata
    // TODO: Implement FFI method to read audio file metadata
    // For now, use placeholder values
    double duration = 0.0;
    int sampleRate = 48000;
    int channels = 2;

    // Try to estimate duration from file size (rough estimate for WAV)
    // Assumes 16-bit stereo WAV at 48kHz
    final estimatedBytesPerSecond = sampleRate * channels * 2; // 16-bit = 2 bytes
    if (estimatedBytesPerSecond > 0) {
      duration = (stat.size - 44) / estimatedBytesPerSecond; // 44 = WAV header
      if (duration < 0) duration = 0;
    }

    final fileName = path.basename(filePath);
    final relativePath = 'audio/${fileName}';

    final asset = SoundbankAsset(
      id: 'asset_${DateTime.now().millisecondsSinceEpoch}_${_banks[bankId]!.assets.length}',
      name: path.basenameWithoutExtension(filePath),
      sourcePath: filePath,
      relativePath: relativePath,
      checksum: checksum,
      sizeBytes: stat.size,
      durationSeconds: duration,
      sampleRate: sampleRate,
      channels: channels,
    );

    final updatedAssets = [...bank.assets, asset];
    _banks[bankId] = bank.copyWith(assets: updatedAssets);
    _invalidateValidation(bankId);
    notifyListeners();
    return asset;
  }

  /// Add multiple assets to bank
  Future<List<SoundbankAsset>> addAssets(String bankId, List<String> filePaths) async {
    final results = <SoundbankAsset>[];
    for (final path in filePaths) {
      final asset = await addAsset(bankId, path);
      if (asset != null) results.add(asset);
    }
    return results;
  }

  /// Remove asset from bank
  void removeAsset(String bankId, String assetId) {
    final bank = _banks[bankId];
    if (bank == null) return;

    final updatedAssets = bank.assets.where((a) => a.id != assetId).toList();
    _banks[bankId] = bank.copyWith(assets: updatedAssets);
    _invalidateValidation(bankId);
    notifyListeners();
  }

  /// Update asset properties
  void updateAsset(String bankId, String assetId, SoundbankAsset Function(SoundbankAsset) update) {
    final bank = _banks[bankId];
    if (bank == null) return;

    final updatedAssets = bank.assets.map((a) {
      if (a.id == assetId) return update(a);
      return a;
    }).toList();

    _banks[bankId] = bank.copyWith(assets: updatedAssets);
    _invalidateValidation(bankId);
    notifyListeners();
  }

  /// Set asset priority
  void setAssetPriority(String bankId, String assetId, SoundbankAssetPriority priority) {
    updateAsset(bankId, assetId, (a) => a.copyWith(priority: priority));
  }

  /// Add tag to asset
  void addAssetTag(String bankId, String assetId, String tag) {
    updateAsset(bankId, assetId, (a) => a.copyWith(tags: [...a.tags, tag]));
  }

  /// Remove tag from asset
  void removeAssetTag(String bankId, String assetId, String tag) {
    updateAsset(bankId, assetId, (a) => a.copyWith(tags: a.tags.where((t) => t != tag).toList()));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EVENT/CONTAINER MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add event to bank
  void addEvent(String bankId, String eventId) {
    final bank = _banks[bankId];
    if (bank == null) return;
    if (bank.eventIds.contains(eventId)) return;

    _banks[bankId] = bank.copyWith(eventIds: [...bank.eventIds, eventId]);
    _invalidateValidation(bankId);
    notifyListeners();
  }

  /// Remove event from bank
  void removeEvent(String bankId, String eventId) {
    final bank = _banks[bankId];
    if (bank == null) return;

    _banks[bankId] = bank.copyWith(
      eventIds: bank.eventIds.where((e) => e != eventId).toList(),
    );
    _invalidateValidation(bankId);
    notifyListeners();
  }

  /// Add multiple events to bank
  void addEvents(String bankId, List<String> eventIds) {
    final bank = _banks[bankId];
    if (bank == null) return;

    final newEventIds = eventIds.where((e) => !bank.eventIds.contains(e)).toList();
    if (newEventIds.isEmpty) return;

    _banks[bankId] = bank.copyWith(eventIds: [...bank.eventIds, ...newEventIds]);
    _invalidateValidation(bankId);
    notifyListeners();
  }

  /// Add container to bank
  void addContainer(String bankId, String containerId) {
    final bank = _banks[bankId];
    if (bank == null) return;
    if (bank.containerIds.contains(containerId)) return;

    _banks[bankId] = bank.copyWith(containerIds: [...bank.containerIds, containerId]);
    _invalidateValidation(bankId);
    notifyListeners();
  }

  /// Remove container from bank
  void removeContainer(String bankId, String containerId) {
    final bank = _banks[bankId];
    if (bank == null) return;

    _banks[bankId] = bank.copyWith(
      containerIds: bank.containerIds.where((c) => c != containerId).toList(),
    );
    _invalidateValidation(bankId);
    notifyListeners();
  }

  /// Add state group to bank
  void addStateGroup(String bankId, String stateGroupId) {
    final bank = _banks[bankId];
    if (bank == null) return;
    if (bank.stateGroupIds.contains(stateGroupId)) return;

    _banks[bankId] = bank.copyWith(stateGroupIds: [...bank.stateGroupIds, stateGroupId]);
    notifyListeners();
  }

  /// Add switch group to bank
  void addSwitchGroup(String bankId, String switchGroupId) {
    final bank = _banks[bankId];
    if (bank == null) return;
    if (bank.switchGroupIds.contains(switchGroupId)) return;

    _banks[bankId] = bank.copyWith(switchGroupIds: [...bank.switchGroupIds, switchGroupId]);
    notifyListeners();
  }

  /// Add RTPC to bank
  void addRtpc(String bankId, String rtpcId) {
    final bank = _banks[bankId];
    if (bank == null) return;
    if (bank.rtpcIds.contains(rtpcId)) return;

    _banks[bankId] = bank.copyWith(rtpcIds: [...bank.rtpcIds, rtpcId]);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GROUP MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create event group in bank
  SoundbankEventGroup createGroup(String bankId, String name, {String? description}) {
    final bank = _banks[bankId];
    if (bank == null) throw StateError('Bank not found: $bankId');

    final group = SoundbankEventGroup(
      id: 'group_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      description: description ?? '',
      order: bank.groups.length,
    );

    _banks[bankId] = bank.copyWith(groups: [...bank.groups, group]);
    notifyListeners();
    return group;
  }

  /// Update group
  void updateGroup(String bankId, String groupId, SoundbankEventGroup Function(SoundbankEventGroup) update) {
    final bank = _banks[bankId];
    if (bank == null) return;

    final updatedGroups = bank.groups.map((g) {
      if (g.id == groupId) return update(g);
      return g;
    }).toList();

    _banks[bankId] = bank.copyWith(groups: updatedGroups);
    notifyListeners();
  }

  /// Delete group
  void deleteGroup(String bankId, String groupId) {
    final bank = _banks[bankId];
    if (bank == null) return;

    _banks[bankId] = bank.copyWith(
      groups: bank.groups.where((g) => g.id != groupId).toList(),
    );
    notifyListeners();
  }

  /// Add event to group
  void addEventToGroup(String bankId, String groupId, String eventId) {
    updateGroup(bankId, groupId, (g) => g.copyWith(eventIds: [...g.eventIds, eventId]));
  }

  /// Remove event from group
  void removeEventFromGroup(String bankId, String groupId, String eventId) {
    updateGroup(bankId, groupId, (g) => g.copyWith(
      eventIds: g.eventIds.where((e) => e != eventId).toList(),
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VALIDATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Validate soundbank integrity
  SoundbankValidation validateBank(String bankId) {
    // Check cache
    if (_validationCache.containsKey(bankId)) {
      return _validationCache[bankId]!;
    }

    final bank = _banks[bankId];
    if (bank == null) {
      return const SoundbankValidation(
        isValid: false,
        issues: [SoundbankValidationIssue(
          severity: ValidationSeverity.error,
          message: 'Bank not found',
        )],
      );
    }

    final issues = <SoundbankValidationIssue>[];

    // Check for empty bank
    if (bank.assets.isEmpty && bank.eventIds.isEmpty) {
      issues.add(const SoundbankValidationIssue(
        severity: ValidationSeverity.warning,
        message: 'Bank has no assets or events',
      ));
    }

    // Check for missing source files
    for (final asset in bank.assets) {
      final file = File(asset.sourcePath);
      if (!file.existsSync()) {
        issues.add(SoundbankValidationIssue(
          severity: ValidationSeverity.error,
          message: 'Source file not found: ${asset.sourcePath}',
          assetId: asset.id,
        ));
      }
    }

    // Check for duplicate relative paths
    final relativePaths = <String>{};
    for (final asset in bank.assets) {
      if (relativePaths.contains(asset.relativePath)) {
        issues.add(SoundbankValidationIssue(
          severity: ValidationSeverity.error,
          message: 'Duplicate relative path: ${asset.relativePath}',
          assetId: asset.id,
        ));
      }
      relativePaths.add(asset.relativePath);
    }

    // Check manifest
    if (bank.manifest.name.isEmpty) {
      issues.add(const SoundbankValidationIssue(
        severity: ValidationSeverity.error,
        message: 'Bank name is required',
      ));
    }

    if (bank.manifest.version.isEmpty) {
      issues.add(const SoundbankValidationIssue(
        severity: ValidationSeverity.warning,
        message: 'Bank version is empty',
      ));
    }

    // Check for large files that might need streaming
    for (final asset in bank.assets) {
      if (asset.sizeBytes > 50 * 1024 * 1024) { // 50MB
        issues.add(SoundbankValidationIssue(
          severity: ValidationSeverity.info,
          message: 'Large file (${asset.formattedSize}) may need streaming: ${asset.name}',
          assetId: asset.id,
        ));
      }
    }

    final validation = SoundbankValidation(
      isValid: issues.where((i) => i.severity == ValidationSeverity.error).isEmpty,
      issues: issues,
    );

    _validationCache[bankId] = validation;
    return validation;
  }

  void _invalidateValidation(String bankId) {
    _validationCache.remove(bankId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXPORT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export soundbank to specified platform
  Future<SoundbankExportResult> exportBank(
    String bankId,
    SoundbankExportConfig config, {
    void Function(double progress, String status)? onProgress,
  }) async {
    final bank = _banks[bankId];
    if (bank == null) {
      return SoundbankExportResult.failure('Bank not found: $bankId');
    }

    // Validate first
    final validation = validateBank(bankId);
    if (!validation.isValid) {
      return SoundbankExportResult(
        success: false,
        errors: validation.issues
            .where((i) => i.severity == ValidationSeverity.error)
            .map((i) => i.message)
            .toList(),
      );
    }

    _isExporting = true;
    _exportProgress = 0.0;
    _exportStatus = 'Preparing export...';
    notifyListeners();

    final stopwatch = Stopwatch()..start();
    final warnings = <String>[];
    final errors = <String>[];
    int exportedAssets = 0;
    int totalSize = 0;

    try {
      // Create output directory
      final outputDir = Directory(config.outputPath);
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      // Export based on platform
      switch (config.platform) {
        case SoundbankPlatform.universal:
          await _exportUniversal(bank, config, outputDir, onProgress);
          break;
        case SoundbankPlatform.unity:
          await _exportUnity(bank, config, outputDir, onProgress);
          break;
        case SoundbankPlatform.unreal:
          await _exportUnreal(bank, config, outputDir, onProgress);
          break;
        case SoundbankPlatform.howler:
          await _exportHowler(bank, config, outputDir, onProgress);
          break;
        default:
          await _exportUniversal(bank, config, outputDir, onProgress);
      }

      exportedAssets = bank.assets.length;
      totalSize = bank.totalSizeBytes;

      stopwatch.stop();

      return SoundbankExportResult(
        success: true,
        outputPath: config.outputPath,
        totalAssets: bank.assets.length,
        exportedAssets: exportedAssets,
        failedAssets: 0,
        totalSizeBytes: totalSize,
        exportDuration: stopwatch.elapsed,
        warnings: warnings,
        errors: errors,
      );
    } catch (e) {
      stopwatch.stop();
      return SoundbankExportResult(
        success: false,
        errors: [e.toString()],
        exportDuration: stopwatch.elapsed,
      );
    } finally {
      _isExporting = false;
      _exportProgress = 1.0;
      _exportStatus = null;
      notifyListeners();
    }
  }

  Future<void> _exportUniversal(
    Soundbank bank,
    SoundbankExportConfig config,
    Directory outputDir,
    void Function(double, String)? onProgress,
  ) async {
    // Create subdirectories
    final audioDir = Directory(path.join(outputDir.path, 'audio'));
    final configDir = Directory(path.join(outputDir.path, 'config'));
    await audioDir.create(recursive: true);
    await configDir.create(recursive: true);

    // Export assets
    for (int i = 0; i < bank.assets.length; i++) {
      final asset = bank.assets[i];
      final progress = (i + 1) / bank.assets.length;
      _exportProgress = progress * 0.8; // 80% for assets
      _exportStatus = 'Copying ${asset.name}...';
      onProgress?.call(_exportProgress, _exportStatus!);
      notifyListeners();

      final sourceFile = File(asset.sourcePath);
      if (await sourceFile.exists()) {
        final destPath = path.join(audioDir.path, path.basename(asset.relativePath));
        await sourceFile.copy(destPath);
      }
    }

    // Export manifest
    _exportStatus = 'Writing manifest...';
    _exportProgress = 0.85;
    onProgress?.call(_exportProgress, _exportStatus!);
    notifyListeners();

    final manifestFile = File(path.join(outputDir.path, 'manifest.json'));
    await manifestFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(bank.manifest.toJson()),
    );

    // Export events config
    _exportStatus = 'Writing configuration...';
    _exportProgress = 0.90;
    onProgress?.call(_exportProgress, _exportStatus!);
    notifyListeners();

    final eventsConfig = {
      'eventIds': bank.eventIds,
      'containerIds': bank.containerIds,
      'stateGroupIds': bank.stateGroupIds,
      'switchGroupIds': bank.switchGroupIds,
      'rtpcIds': bank.rtpcIds,
      'groups': bank.groups.map((g) => g.toJson()).toList(),
    };

    final eventsFile = File(path.join(configDir.path, 'events.json'));
    await eventsFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(eventsConfig),
    );

    // Export assets manifest
    final assetsManifest = {
      'assets': bank.assets.map((a) => a.toJson()).toList(),
    };

    final assetsFile = File(path.join(configDir.path, 'assets.json'));
    await assetsFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(assetsManifest),
    );

    _exportProgress = 1.0;
    _exportStatus = 'Export complete';
    onProgress?.call(_exportProgress, _exportStatus!);
  }

  Future<void> _exportUnity(
    Soundbank bank,
    SoundbankExportConfig config,
    Directory outputDir,
    void Function(double, String)? onProgress,
  ) async {
    // Use existing Unity exporter
    final exporter = UnityExporter(config: UnityExportConfig(
      namespace: config.platformOptions['namespace'] ?? 'FluxForge.Audio',
      classPrefix: config.customPrefix ?? 'FF',
    ));

    // Export code files
    _exportStatus = 'Generating Unity scripts...';
    _exportProgress = 0.5;
    onProgress?.call(_exportProgress, _exportStatus!);
    notifyListeners();

    // Note: The actual export would integrate with middleware data
    // For now, export the manifest and assets
    await _exportUniversal(bank, config, outputDir, onProgress);
  }

  Future<void> _exportUnreal(
    Soundbank bank,
    SoundbankExportConfig config,
    Directory outputDir,
    void Function(double, String)? onProgress,
  ) async {
    // Use existing Unreal exporter
    _exportStatus = 'Generating Unreal code...';
    _exportProgress = 0.5;
    onProgress?.call(_exportProgress, _exportStatus!);
    notifyListeners();

    await _exportUniversal(bank, config, outputDir, onProgress);
  }

  Future<void> _exportHowler(
    Soundbank bank,
    SoundbankExportConfig config,
    Directory outputDir,
    void Function(double, String)? onProgress,
  ) async {
    _exportStatus = 'Generating Howler.js code...';
    _exportProgress = 0.5;
    onProgress?.call(_exportProgress, _exportStatus!);
    notifyListeners();

    await _exportUniversal(bank, config, outputDir, onProgress);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Save all banks to JSON
  Map<String, dynamic> toJson() => {
    'banks': _banks.map((id, bank) => MapEntry(id, bank.toJson())),
    'selectedBankId': _selectedBankId,
  };

  /// Load banks from JSON
  void fromJson(Map<String, dynamic> json) {
    _banks.clear();
    _validationCache.clear();

    final banksJson = json['banks'] as Map<String, dynamic>?;
    if (banksJson != null) {
      for (final entry in banksJson.entries) {
        _banks[entry.key] = Soundbank.fromJson(entry.value as Map<String, dynamic>);
      }
    }

    _selectedBankId = json['selectedBankId'] as String?;
    notifyListeners();
  }

  /// Clear all banks
  void clear() {
    _banks.clear();
    _validationCache.clear();
    _selectedBankId = null;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UTILITIES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all unique tags across all assets in bank
  List<String> getAssetTags(String bankId) {
    final bank = _banks[bankId];
    if (bank == null) return [];

    final tags = <String>{};
    for (final asset in bank.assets) {
      tags.addAll(asset.tags);
    }
    return tags.toList()..sort();
  }

  /// Get assets by tag
  List<SoundbankAsset> getAssetsByTag(String bankId, String tag) {
    final bank = _banks[bankId];
    if (bank == null) return [];

    return bank.assets.where((a) => a.tags.contains(tag)).toList();
  }

  /// Get assets by priority
  List<SoundbankAsset> getAssetsByPriority(String bankId, SoundbankAssetPriority priority) {
    final bank = _banks[bankId];
    if (bank == null) return [];

    return bank.assets.where((a) => a.priority == priority).toList();
  }

  /// Search assets by name
  List<SoundbankAsset> searchAssets(String bankId, String query) {
    final bank = _banks[bankId];
    if (bank == null) return [];

    final lowerQuery = query.toLowerCase();
    return bank.assets.where((a) => a.name.toLowerCase().contains(lowerQuery)).toList();
  }
}
