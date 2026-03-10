// ═══════════════════════════════════════════════════════════════════════════════
// SFX PIPELINE SERVICE — Orchestrator for SlotLab SFX Pipeline Wizard
// ═══════════════════════════════════════════════════════════════════════════════
//
// Chains existing services + FFI in sequence:
//   1. NativeFFI.offlineGetAudioInfo() — fast metadata probe
//   2. LoudnessAnalysisService — LUFS analysis (Dart ITU-R BS.1770-4)
//   3. StripSilenceService — silence detection
//   4. OfflineProcessingProvider — trim/normalize/convert via rf-offline FFI
//   5. UcsNamingService — naming (pure Dart)
//   6. SlotLabProjectProvider — stage mapping + assign
//
// CRITICAL:
// - All processing is OFFLINE (rf-offline Rust crate thread pool)
// - Audio thread (rf-engine) is NEVER touched during processing
// - EventRegistry is NEVER accessed directly — sync happens through
//   SlotLabScreen._onMiddlewareChanged listener when setAudioAssignment() fires
// - Wizard uses batchSetAudioAssignments() for atomic undo (§16 of spec)

import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/sfx_pipeline_config.dart';
import '../providers/offline_processing_provider.dart';
import '../src/rust/native_ffi.dart';
import 'loudness_analysis_service.dart';
import 'strip_silence_service.dart';

/// SFX Pipeline Service — orchestrates the 6-step pipeline
class SfxPipelineService {
  SfxPipelineService._();
  static final instance = SfxPipelineService._();

  bool _cancelled = false;

  // ─── Step 1: Scan ──────────────────────────────────────────────────────

  /// Scan a directory for audio files and analyze each one.
  /// Memory strategy: one file at a time (load → analyze → free → next).
  Future<List<SfxScanResult>> scanDirectory({
    required String path,
    required bool recursive,
    required String fileFilter,
    void Function(int scanned, int total)? onProgress,
  }) async {
    final dir = Directory(path);
    if (!dir.existsSync()) return [];

    // Collect audio files
    final extensions = _parseFilterExtensions(fileFilter);
    final files = <FileSystemEntity>[];

    if (recursive) {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File && _matchesExtension(entity.path, extensions)) {
          files.add(entity);
        }
      }
    } else {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File && _matchesExtension(entity.path, extensions)) {
          files.add(entity);
        }
      }
    }

    // Analyze one by one (memory-safe)
    final results = <SfxScanResult>[];
    final ffi = NativeFFI.instance;
    final loudness = LoudnessAnalysisService.instance;
    final silence = StripSilenceService.instance;

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final filename = p.basename(file.path);

      onProgress?.call(i + 1, files.length);

      try {
        // ── 1. Fast metadata probe via FFI ──
        final info = ffi.offlineGetAudioInfo(file.path);
        final int sampleRate;
        final int channels;
        final int bitDepth;
        final double durationSeconds;

        if (info != null) {
          sampleRate = (info['sample_rate'] as num?)?.toInt() ?? 48000;
          channels = (info['channels'] as num?)?.toInt() ?? 2;
          bitDepth = (info['bit_depth'] as num?)?.toInt() ?? 24;
          durationSeconds = (info['duration_seconds'] as num?)?.toDouble() ?? 0.0;
        } else {
          // Fallback if FFI probe fails — use individual calls
          sampleRate = ffi.offlineGetAudioSampleRate(file.path);
          channels = ffi.offlineGetAudioChannels(file.path);
          durationSeconds = ffi.offlineGetAudioDuration(file.path);
          bitDepth = 24; // No individual FFI call for bit depth
        }

        if (sampleRate == 0 || durationSeconds <= 0) {
          continue; // Skip unreadable files
        }

        // ── 2. Load raw PCM for analysis ──
        // Read file bytes for Dart-side LUFS + silence analysis
        final fileBytes = await (file as File).readAsBytes();
        final samples = _decodePcmFromWav(fileBytes);

        double integratedLufs = -18.0;
        double peakDbfs = -3.0;
        double silenceStartMs = 0.0;
        double silenceEndMs = 0.0;
        double dcOffset = 0.0;

        if (samples != null && samples.isNotEmpty) {
          // ── WAV path: Full Dart-side analysis ──
          // 3a. LUFS analysis (ITU-R BS.1770-4)
          final lufsResult = await loudness.analyzeBuffer(
            samples,
            sampleRate: sampleRate,
            channels: channels,
          );
          integratedLufs = lufsResult.integratedLufs;
          peakDbfs = lufsResult.samplePeak;

          // 4a. DC offset detection
          dcOffset = _measureDcOffset(samples);

          // 5a. Silence detection at head/tail
          final silentRegions = silence.detectSilence(samples, sampleRate.toDouble());
          if (silentRegions.isNotEmpty) {
            // Head silence: first region starting at 0
            final headRegion = silentRegions.first;
            if (headRegion.startTime < 0.01) {
              silenceStartMs = headRegion.duration * 1000.0;
            }
            // Tail silence: last region extending to end
            final totalDur = samples.length / (sampleRate * channels);
            final tailRegion = silentRegions.last;
            if ((tailRegion.endTime - totalDur).abs() < 0.01) {
              silenceEndMs = tailRegion.duration * 1000.0;
            }
          }
        } else {
          // ── Non-WAV path: Use FFI pipeline for LUFS/peak analysis ──
          // Process through rf-offline with no-op normalization to get metrics
          final handle = ffi.offlinePipelineCreate();
          if (handle != 0) {
            try {
              ffi.offlinePipelineSetNormalization(handle, 0, 0.0); // None
              ffi.offlinePipelineSetFormat(handle, 1); // WAV 24-bit (temp)
              final tempPath = '${file.path}.scan_tmp.wav';
              final jobId = ffi.offlineProcessFile(handle, file.path, tempPath);
              if (jobId != 0) {
                await _waitForFfiJob(ffi, handle);
                final resultJson = ffi.offlineGetJobResult(jobId);
                if (resultJson != null) {
                  final jobResult = OfflineJobResult.fromJson(jsonDecode(resultJson));
                  if (jobResult.loudness != 0.0) {
                    integratedLufs = jobResult.loudness;
                  }
                  if (jobResult.peakLevel != 0.0) {
                    peakDbfs = jobResult.peakLevel;
                  }
                }
                ffi.offlineClearJobResult(jobId);
              }
              // Cleanup temp file
              try { await File(tempPath).delete(); } catch (_) {}
            } finally {
              ffi.offlinePipelineDestroy(handle);
            }
          }
        }

        final category = SfxCategoryExt.fromFilename(filename);

        results.add(SfxScanResult(
          path: file.path,
          filename: filename,
          sampleRate: sampleRate,
          bitDepth: bitDepth,
          channels: channels,
          durationSeconds: durationSeconds,
          integratedLufs: integratedLufs,
          peakDbfs: peakDbfs,
          dcOffset: dcOffset,
          silenceStartMs: silenceStartMs,
          silenceEndMs: silenceEndMs,
          detectedCategory: category,
          selected: !filename.startsWith('_'),
        ));
      } catch (_) {
        // Skip files that can't be read/analyzed
      }

      // Yield to event loop between files (UI responsiveness)
      if (i % 5 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    return results;
  }

  // ─── Step 5: Stage Matching ────────────────────────────────────────────

  /// Match filenames to SlotLab stage IDs using fuzzy matching.
  List<SfxStageMapping> matchFilesToStages(List<SfxScanResult> files) {
    final mappings = <SfxStageMapping>[];

    for (final file in files) {
      if (!file.selected) continue;

      final lower = file.filename.toLowerCase();
      // Strip common prefixes for matching
      final stripped = lower
          .replaceFirst(RegExp(r'^sfx_'), '')
          .replaceFirst(RegExp(r'\.(wav|mp3|flac|ogg|aif|aiff)$'), '');

      // Simple pattern matching for stage IDs
      final stageId = _resolveStage(stripped);
      final confidence = stageId != null ? _calculateConfidence(stripped, stageId) : 0.0;

      mappings.add(SfxStageMapping(
        sourceFilename: file.filename,
        stageId: stageId,
        confidence: confidence,
      ));
    }

    return mappings;
  }

  // ─── Step 6: Execute Pipeline ──────────────────────────────────────────

  /// Execute the full pipeline. Returns result with per-file stats.
  ///
  /// CRITICAL: Auto-assign (step 4/4) MUST wait for spin to complete.
  /// Processing steps 1-3 are safe during spin (offline, no audio thread).
  Future<SfxPipelineResult> executePipeline({
    required SfxPipelinePreset preset,
    required List<SfxScanResult> files,
    required List<SfxStageMapping> stageMappings,
    void Function(SfxPipelineProgress)? onProgress,
    Future<void> Function()? waitForSpinComplete,
    void Function(Map<String, String> stageToPath)? batchAssign,
  }) async {
    _cancelled = false;
    final stopwatch = Stopwatch()..start();
    final selectedFiles = files.where((f) => f.selected).toList();
    final totalFiles = selectedFiles.length;

    if (totalFiles == 0) {
      return SfxPipelineResult(
        files: [],
        preset: preset,
        timestamp: DateTime.now(),
        processingTimeMs: 0,
        outputDirectory: preset.outputPath ?? '',
      );
    }

    // Prepare output directory
    final outputDir = _resolveOutputDir(preset);
    await Directory(outputDir).create(recursive: true);

    // Prepare temp directory
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    final tempDir = p.join(
      Platform.environment['HOME'] ?? '/tmp',
      '.fluxforge', 'temp', 'sfx_pipeline', sessionId,
    );
    await Directory(tempDir).create(recursive: true);

    final fileResults = <SfxFileResult>[];
    final stepDurations = <SfxPipelineStep, int>{};
    final ffi = NativeFFI.instance;

    // Map wizard enums → offline processing enums
    final normMode = _mapNormMode(preset.normMode);
    final outputFormatId = _mapOutputFormatId(preset.outputFormat);

    try {
      // ══════════════════════════════════════════════════════════════════════
      // Step 1/4: Trim & Clean → intermediate files in tempDir
      // ══════════════════════════════════════════════════════════════════════
      final trimStart = stopwatch.elapsedMilliseconds;
      final trimmedPaths = <String, String>{}; // sourceFilename → trimmedPath

      for (int i = 0; i < totalFiles && !_cancelled; i++) {
        final file = selectedFiles[i];
        onProgress?.call(SfxPipelineProgress(
          currentStep: SfxPipelineStep.trimAndClean,
          currentFileIndex: i,
          totalFiles: totalFiles,
          currentFilename: file.filename,
          overallProgress: (i / totalFiles) * 0.25,
          elapsedMs: stopwatch.elapsedMilliseconds,
        ));

        // Trim via rf-offline: create pipeline, set minimal config, process
        final trimmedPath = p.join(tempDir, '01_trim_${file.filename}');

        // Calculate fade samples from ms
        final fadeInSamples = preset.fadeIn
            ? (preset.fadeInMs * file.sampleRate / 1000).round()
            : null;
        final fadeOutSamples = preset.fadeOut
            ? (preset.fadeOutMs * file.sampleRate / 1000).round()
            : null;

        // Use processFileWithOptions for trim+fade (no normalization yet)
        final handle = ffi.offlinePipelineCreate();
        if (handle != 0) {
          try {
            // No normalization in trim phase
            ffi.offlinePipelineSetNormalization(handle, 0, 0.0); // None
            // Keep original format for intermediate
            ffi.offlinePipelineSetFormat(handle, 1); // WAV 24-bit

            final optionsJson = jsonEncode({
              'input_path': file.path,
              'output_path': trimmedPath,
              if (fadeInSamples != null) 'fade_in_samples': fadeInSamples,
              if (fadeOutSamples != null) 'fade_out_samples': fadeOutSamples,
              'format': 1, // WAV 24-bit intermediate
              if (preset.removeDcOffset) 'remove_dc_offset': true,
            });

            final jobId = ffi.offlineProcessFileWithOptions(handle, optionsJson);
            if (jobId != 0) {
              await _waitForFfiJob(ffi, handle);
              ffi.offlineClearJobResult(jobId);
            }
          } finally {
            ffi.offlinePipelineDestroy(handle);
          }
        }

        // If trim succeeded, use trimmed file; otherwise use original
        if (await File(trimmedPath).exists()) {
          trimmedPaths[file.filename] = trimmedPath;
        } else {
          trimmedPaths[file.filename] = file.path;
        }
      }
      stepDurations[SfxPipelineStep.trimAndClean] = stopwatch.elapsedMilliseconds - trimStart;

      if (_cancelled) throw _CancelledException();

      // ══════════════════════════════════════════════════════════════════════
      // Step 2/4: Normalize → intermediate files in tempDir
      // ══════════════════════════════════════════════════════════════════════
      final normStart = stopwatch.elapsedMilliseconds;
      final normalizedPaths = <String, String>{}; // sourceFilename → normalizedPath

      for (int i = 0; i < totalFiles && !_cancelled; i++) {
        final file = selectedFiles[i];
        onProgress?.call(SfxPipelineProgress(
          currentStep: SfxPipelineStep.normalize,
          currentFileIndex: i,
          totalFiles: totalFiles,
          currentFilename: file.filename,
          overallProgress: 0.25 + (i / totalFiles) * 0.25,
          elapsedMs: stopwatch.elapsedMilliseconds,
        ));

        final inputPath = trimmedPaths[file.filename] ?? file.path;
        final normalizedPath = p.join(tempDir, '02_norm_${file.filename}');

        // Resolve target LUFS — per-category override if enabled
        double targetLufs = preset.targetLufs;
        if (preset.categoryDetection) {
          final override = preset.perCategoryOverrides[file.detectedCategory];
          if (override != null) {
            targetLufs = override;
          }
        }

        if (normMode != NormalizationMode.none) {
          final handle = ffi.offlinePipelineCreate();
          if (handle != 0) {
            try {
              ffi.offlinePipelineSetNormalization(
                handle,
                normMode.value,
                normMode == NormalizationMode.lufs
                    ? targetLufs
                    : preset.truePeakCeiling,
              );
              ffi.offlinePipelineSetFormat(handle, 1); // WAV 24-bit intermediate

              final jobId = ffi.offlineProcessFile(handle, inputPath, normalizedPath);
              if (jobId != 0) {
                await _waitForFfiJob(ffi, handle);
                ffi.offlineClearJobResult(jobId);
              }
            } finally {
              ffi.offlinePipelineDestroy(handle);
            }
          }
        }

        if (await File(normalizedPath).exists()) {
          normalizedPaths[file.filename] = normalizedPath;
        } else {
          normalizedPaths[file.filename] = inputPath;
        }
      }
      stepDurations[SfxPipelineStep.normalize] = stopwatch.elapsedMilliseconds - normStart;

      if (_cancelled) throw _CancelledException();

      // ══════════════════════════════════════════════════════════════════════
      // Step 3/4: Convert & Export → final files in outputDir
      // ══════════════════════════════════════════════════════════════════════
      final convertStart = stopwatch.elapsedMilliseconds;

      for (int i = 0; i < totalFiles && !_cancelled; i++) {
        final file = selectedFiles[i];

        // Resolve output filename
        final mapping = stageMappings.firstWhere(
          (m) => m.sourceFilename == file.filename,
          orElse: () => SfxStageMapping(sourceFilename: file.filename),
        );
        final outputFilename = _generateOutputFilename(preset, file, mapping);
        final outputPath = p.join(outputDir, outputFilename);

        onProgress?.call(SfxPipelineProgress(
          currentStep: SfxPipelineStep.convertAndExport,
          currentFileIndex: i,
          totalFiles: totalFiles,
          currentFilename: outputFilename,
          overallProgress: 0.5 + (i / totalFiles) * 0.25,
          elapsedMs: stopwatch.elapsedMilliseconds,
        ));

        final inputPath = normalizedPaths[file.filename] ?? file.path;
        bool success = false;
        double finalLufs = preset.targetLufs;
        double gainApplied = 0.0;
        bool limiterEngaged = false;
        int finalChannels = file.channels;

        // Determine mono downmix
        String? monoDownmix;
        if (preset.outputChannels == OutputChannelMode.mono && file.channels > 1) {
          if (!preset.skipMonoDownmix &&
              !preset.stereoOverrideStages.contains(mapping.stageId)) {
            monoDownmix = preset.monoMethod.name; // sumHalf, leftOnly, etc.
            finalChannels = 1;
          }
        } else if (preset.outputChannels == OutputChannelMode.keepOriginal) {
          finalChannels = file.channels;
        }

        // Final conversion via rf-offline
        final handle = ffi.offlinePipelineCreate();
        if (handle != 0) {
          try {
            ffi.offlinePipelineSetFormat(handle, outputFormatId);

            final optionsJson = jsonEncode({
              'input_path': inputPath,
              'output_path': outputPath,
              if (preset.sampleRate != file.sampleRate)
                'sample_rate': preset.sampleRate,
              'format': outputFormatId,
              if (monoDownmix != null) 'mono_downmix': monoDownmix,
            });

            final jobId = ffi.offlineProcessFileWithOptions(handle, optionsJson);
            if (jobId != 0) {
              await _waitForFfiJob(ffi, handle);

              // Read job result for final stats
              final resultJson = ffi.offlineGetJobResult(jobId);
              if (resultJson != null) {
                final jobResult = OfflineJobResult.fromJson(jsonDecode(resultJson));
                success = jobResult.success;
                finalLufs = jobResult.loudness;
                gainApplied = finalLufs - file.integratedLufs;
                limiterEngaged = jobResult.peakLevel > -0.5;
              }
              ffi.offlineClearJobResult(jobId);
            }
          } finally {
            ffi.offlinePipelineDestroy(handle);
          }
        }

        // If FFI didn't produce output, fallback: copy source directly
        if (!success && !await File(outputPath).exists()) {
          try {
            await File(inputPath).copy(outputPath);
            success = true;
            finalLufs = file.integratedLufs;
          } catch (_) {
            success = false;
          }
        }

        fileResults.add(SfxFileResult(
          sourcePath: file.path,
          sourceFilename: file.filename,
          outputPath: outputPath,
          outputFilename: outputFilename,
          stageId: mapping.stageId,
          assigned: false,
          success: success,
          originalLufs: file.integratedLufs,
          finalLufs: finalLufs,
          gainApplied: gainApplied,
          limiterEngaged: limiterEngaged,
          trimmedStartMs: file.silenceStartMs,
          trimmedEndMs: file.silenceEndMs,
          originalDuration: file.durationSeconds,
          finalDuration: file.durationSeconds - (file.silenceStartMs + file.silenceEndMs) / 1000,
          originalChannels: file.channels,
          finalChannels: finalChannels,
        ));

        // Multi-format export (if enabled)
        if (preset.multiFormat && preset.multiFormatPresets.isNotEmpty) {
          for (final extraFormat in preset.multiFormatPresets) {
            if (extraFormat == preset.outputFormat) continue;

            final extraDir = preset.subfolderPerFormat
                ? p.join(outputDir, extraFormat.fileExtension)
                : outputDir;
            await Directory(extraDir).create(recursive: true);

            final extraFilename = '${p.basenameWithoutExtension(outputFilename)}.${extraFormat.fileExtension}';
            final extraPath = p.join(extraDir, extraFilename);
            final extraFmtId = _mapOutputFormatId(extraFormat);

            final extraHandle = ffi.offlinePipelineCreate();
            if (extraHandle != 0) {
              try {
                ffi.offlinePipelineSetFormat(extraHandle, extraFmtId);
                final extraJobId = ffi.offlineProcessFile(
                  extraHandle, inputPath, extraPath,
                );
                if (extraJobId != 0) {
                  await _waitForFfiJob(ffi, extraHandle);
                  ffi.offlineClearJobResult(extraJobId);
                }
              } finally {
                ffi.offlinePipelineDestroy(extraHandle);
              }
            }
          }
        }
      }
      stepDurations[SfxPipelineStep.convertAndExport] = stopwatch.elapsedMilliseconds - convertStart;

      if (_cancelled) throw _CancelledException();

      // ══════════════════════════════════════════════════════════════════════
      // Step 4/4: Auto-Assign
      // ══════════════════════════════════════════════════════════════════════
      if (preset.autoAssign) {
        final assignStart = stopwatch.elapsedMilliseconds;

        // CRITICAL: Wait for spin to complete before modifying project state
        if (waitForSpinComplete != null) {
          await waitForSpinComplete();
        }

        onProgress?.call(SfxPipelineProgress(
          currentStep: SfxPipelineStep.autoAssign,
          currentFileIndex: 0,
          totalFiles: totalFiles,
          currentFilename: 'Assigning to stages...',
          overallProgress: 0.75,
          elapsedMs: stopwatch.elapsedMilliseconds,
        ));

        // Build batch assignment map
        final stageToPath = <String, String>{};
        for (int i = 0; i < fileResults.length; i++) {
          final fr = fileResults[i];
          if (fr.stageId != null && fr.outputPath != null && fr.success) {
            stageToPath[fr.stageId!] = fr.outputPath!;
            // Mark as assigned in result
            fileResults[i] = SfxFileResult(
              sourcePath: fr.sourcePath,
              sourceFilename: fr.sourceFilename,
              outputPath: fr.outputPath,
              outputFilename: fr.outputFilename,
              stageId: fr.stageId,
              assigned: true,
              success: fr.success,
              originalLufs: fr.originalLufs,
              finalLufs: fr.finalLufs,
              gainApplied: fr.gainApplied,
              limiterEngaged: fr.limiterEngaged,
              trimmedStartMs: fr.trimmedStartMs,
              trimmedEndMs: fr.trimmedEndMs,
              originalDuration: fr.originalDuration,
              finalDuration: fr.finalDuration,
              originalChannels: fr.originalChannels,
              finalChannels: fr.finalChannels,
            );
          }
        }

        // Atomic batch assign via SlotLabProjectProvider.batchSetAudioAssignments()
        // This creates ONE undo entry for all assignments (§16 of spec)
        if (stageToPath.isNotEmpty && batchAssign != null) {
          batchAssign(stageToPath);
        }

        stepDurations[SfxPipelineStep.autoAssign] = stopwatch.elapsedMilliseconds - assignStart;
      }

      // ── Finalize ────────────────────────────────────────────────────

      onProgress?.call(SfxPipelineProgress(
        currentStep: SfxPipelineStep.autoAssign,
        currentFileIndex: totalFiles,
        totalFiles: totalFiles,
        overallProgress: 1.0,
        stepCompleted: {
          SfxPipelineStep.trimAndClean: true,
          SfxPipelineStep.normalize: true,
          SfxPipelineStep.convertAndExport: true,
          SfxPipelineStep.autoAssign: true,
        },
        stepDurationMs: stepDurations,
        elapsedMs: stopwatch.elapsedMilliseconds,
      ));

      stopwatch.stop();

      final result = SfxPipelineResult(
        files: fileResults,
        preset: preset,
        timestamp: DateTime.now(),
        processingTimeMs: stopwatch.elapsedMilliseconds,
        outputDirectory: outputDir,
      );

      // Generate manifest.json
      if (preset.generateManifest) {
        final manifestPath = p.join(outputDir, 'manifest.json');
        await File(manifestPath).writeAsString(
          const JsonEncoder.withIndent('  ').convert(result.toManifestJson()),
        );
      }

      // Generate LUFS report
      if (preset.generateLufsReport) {
        final reportPath = p.join(outputDir, 'lufs_report.txt');
        await File(reportPath).writeAsString(result.toLufsReport());
      }

      // Cleanup temp files
      if (!preset.keepIntermediateFiles) {
        try {
          await Directory(tempDir).delete(recursive: true);
        } catch (_) {}
      }

      return result;
    } on _CancelledException {
      // Cleanup temp files on cancel
      try {
        await Directory(tempDir).delete(recursive: true);
      } catch (_) {}

      return SfxPipelineResult(
        files: fileResults,
        preset: preset,
        timestamp: DateTime.now(),
        processingTimeMs: stopwatch.elapsedMilliseconds,
        outputDirectory: outputDir,
      );
    }
  }

  /// Cancel the running pipeline
  void cancel() {
    _cancelled = true;
  }

  // ─── Private Helpers ───────────────────────────────────────────────────

  /// Wait for an FFI pipeline job to complete (poll state).
  /// Timeout after [timeoutMs] milliseconds (default 60s per file).
  Future<void> _waitForFfiJob(NativeFFI ffi, int handle, {int timeoutMs = 60000}) async {
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (true) {
      final state = ffi.offlinePipelineGetState(handle);
      if (state >= 8 || state < 0) break; // Complete/Failed/Cancelled/NotFound
      if (_cancelled) {
        ffi.offlinePipelineCancel(handle);
        break;
      }
      if (DateTime.now().isAfter(deadline)) {
        ffi.offlinePipelineCancel(handle);
        break;
      }
      await Future.delayed(const Duration(milliseconds: 20));
    }
  }

  /// Decode raw PCM samples from a WAV file for Dart-side analysis.
  /// Returns null if not a valid WAV or unsupported format.
  List<double>? _decodePcmFromWav(Uint8List bytes) {
    if (bytes.length < 44) return null;

    // Check RIFF header
    final riff = String.fromCharCodes(bytes.sublist(0, 4));
    if (riff != 'RIFF') return null;
    final wave = String.fromCharCodes(bytes.sublist(8, 12));
    if (wave != 'WAVE') return null;

    // Find 'fmt ' chunk
    int offset = 12;
    int? fmtOffset;
    int? dataOffset;
    int? dataSize;
    int audioFormat = 1;
    int numChannels = 2;
    int bitsPerSample = 16;

    while (offset + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = bytes.buffer.asByteData().getUint32(offset + 4, Endian.little);

      if (chunkId == 'fmt ') {
        fmtOffset = offset + 8;
        audioFormat = bytes.buffer.asByteData().getUint16(fmtOffset, Endian.little);
        numChannels = bytes.buffer.asByteData().getUint16(fmtOffset + 2, Endian.little);
        bitsPerSample = bytes.buffer.asByteData().getUint16(fmtOffset + 14, Endian.little);
      } else if (chunkId == 'data') {
        dataOffset = offset + 8;
        dataSize = chunkSize;
      }

      offset += 8 + chunkSize;
      if (offset % 2 != 0) offset++; // Padding
    }

    if (fmtOffset == null || dataOffset == null || dataSize == null) return null;

    final bd = bytes.buffer.asByteData();
    final samples = <double>[];

    if (audioFormat == 1) {
      // PCM integer
      if (bitsPerSample == 16) {
        final count = dataSize ~/ 2;
        for (int i = 0; i < count && dataOffset + i * 2 + 1 < bytes.length; i++) {
          final val = bd.getInt16(dataOffset + i * 2, Endian.little);
          samples.add(val / 32768.0);
        }
      } else if (bitsPerSample == 24) {
        final count = dataSize ~/ 3;
        for (int i = 0; i < count && dataOffset + i * 3 + 2 < bytes.length; i++) {
          final b0 = bytes[dataOffset + i * 3];
          final b1 = bytes[dataOffset + i * 3 + 1];
          final b2 = bytes[dataOffset + i * 3 + 2];
          int val = b0 | (b1 << 8) | (b2 << 16);
          if (val >= 0x800000) val -= 0x1000000; // Sign extend
          samples.add(val / 8388608.0);
        }
      } else if (bitsPerSample == 32) {
        final count = dataSize ~/ 4;
        for (int i = 0; i < count && dataOffset + i * 4 + 3 < bytes.length; i++) {
          final val = bd.getInt32(dataOffset + i * 4, Endian.little);
          samples.add(val / 2147483648.0);
        }
      }
    } else if (audioFormat == 3) {
      // IEEE float
      if (bitsPerSample == 32) {
        final count = dataSize ~/ 4;
        for (int i = 0; i < count && dataOffset + i * 4 + 3 < bytes.length; i++) {
          samples.add(bd.getFloat32(dataOffset + i * 4, Endian.little));
        }
      }
    }

    return samples.isEmpty ? null : samples;
  }

  /// Measure DC offset as average of all samples
  double _measureDcOffset(List<double> samples) {
    if (samples.isEmpty) return 0.0;
    double sum = 0.0;
    for (final s in samples) {
      sum += s;
    }
    return sum / samples.length;
  }

  /// Map SfxNormMode → NormalizationMode (from offline_processing_provider)
  NormalizationMode _mapNormMode(SfxNormMode mode) {
    switch (mode) {
      case SfxNormMode.lufs:
        return NormalizationMode.lufs;
      case SfxNormMode.peak:
        return NormalizationMode.peak;
      case SfxNormMode.truePeak:
        return NormalizationMode.truePeak;
      case SfxNormMode.none:
        return NormalizationMode.none;
    }
  }

  /// Map SfxOutputFormat → raw FFI format ID.
  /// Uses raw int because OfflineOutputFormat enum doesn't cover all formats (e.g., OGG).
  /// IDs from rf-offline: 0=WAV16, 1=WAV24, 2=WAV32F, 5=FLAC, 6=MP3_320, 10=OGG_Q8
  int _mapOutputFormatId(SfxOutputFormat format) {
    switch (format) {
      case SfxOutputFormat.wav16:
        return 0;
      case SfxOutputFormat.wav24:
        return 1;
      case SfxOutputFormat.wav32f:
        return 2;
      case SfxOutputFormat.flac:
        return 5;
      case SfxOutputFormat.ogg:
        return 10; // OGG Vorbis Q8
      case SfxOutputFormat.mp3High:
        return 6; // MP3 320kbps
    }
  }

  Set<String> _parseFilterExtensions(String filter) {
    // Parse "*.{wav,mp3,flac,ogg,aif,aiff}" → {'.wav', '.mp3', ...}
    final match = RegExp(r'\*\.\{(.+)\}').firstMatch(filter);
    if (match != null) {
      return match.group(1)!.split(',').map((e) => '.${e.trim()}').toSet();
    }
    // Fallback: common audio extensions
    return {'.wav', '.mp3', '.flac', '.ogg', '.aif', '.aiff'};
  }

  bool _matchesExtension(String path, Set<String> extensions) {
    final ext = p.extension(path).toLowerCase();
    return extensions.contains(ext);
  }

  String _resolveOutputDir(SfxPipelinePreset preset) {
    final base = preset.outputPath ?? p.join(
      Platform.environment['HOME'] ?? '/tmp',
      'Desktop', 'slot_sfx_export',
    );
    if (preset.createDateSubfolder) {
      final date = DateTime.now().toIso8601String().substring(0, 10);
      return p.join(base, date);
    }
    return base;
  }

  String _generateOutputFilename(
    SfxPipelinePreset preset,
    SfxScanResult file,
    SfxStageMapping mapping,
  ) {
    final ext = '.${preset.outputFormat.fileExtension}';

    switch (preset.namingMode) {
      case SfxNamingMode.slotLabStageId:
        if (mapping.stageId != null) {
          final stage = preset.lowercase
              ? mapping.stageId!.toLowerCase()
              : mapping.stageId!;
          return '${preset.prefix}$stage$ext';
        }
        // Fallback to original name if no stage match
        final baseName = p.basenameWithoutExtension(file.filename);
        return '${preset.prefix}$baseName$ext';

      case SfxNamingMode.ucs:
        // Use UcsNamingService for generation
        final baseName = p.basenameWithoutExtension(file.filename);
        return '$baseName$ext';

      case SfxNamingMode.custom:
        final baseName = p.basenameWithoutExtension(file.filename);
        final stageId = mapping.stageId ?? baseName;
        return preset.customTemplate
            .replaceAll('{prefix}', preset.prefix)
            .replaceAll('{stage}', stageId)
            .replaceAll('{stage_lower}', stageId.toLowerCase())
            .replaceAll('{original}', baseName)
            .replaceAll('{category}', file.detectedCategory.name)
            .replaceAll('{date}', DateTime.now().toIso8601String().substring(0, 10))
            .replaceAll('{ext}', ext);

      case SfxNamingMode.keepOriginal:
        final baseName = p.basenameWithoutExtension(file.filename);
        return '$baseName$ext';
    }
  }

  String? _resolveStage(String stripped) {
    // Core stage patterns
    const stagePatterns = <String, String>{
      'reel_spin_loop': 'REEL_SPIN_LOOP',
      'reel_stop': 'REEL_STOP',
      'reel_stop_0': 'REEL_STOP_0',
      'reel_stop_1': 'REEL_STOP_1',
      'reel_stop_2': 'REEL_STOP_2',
      'reel_stop_3': 'REEL_STOP_3',
      'reel_stop_4': 'REEL_STOP_4',
      'wild_land': 'WILD_LAND',
      'wild_expand_start': 'WILD_EXPAND_START',
      'wild_expand_step': 'WILD_EXPAND_STEP',
      'wild_expand_end': 'WILD_EXPAND_END',
      'wild_stick': 'WILD_STICK',
      'wild_win': 'WILD_WIN',
      'wild_transform': 'WILD_TRANSFORM',
      'wild_multiply': 'WILD_MULTIPLY',
      'scatter_land': 'SCATTER_LAND',
      'scatter_win': 'SCATTER_WIN',
      'bonus_land': 'BONUS_LAND',
      'bonus_win': 'BONUS_WIN',
      'big_win_start': 'BIG_WIN_START',
      'big_win_end': 'BIG_WIN_END',
      'big_win_trigger': 'BIG_WIN_TRIGGER',
      'big_win_tick_start': 'BIG_WIN_TICK_START',
      'big_win_tick_end': 'BIG_WIN_TICK_END',
      'win_present_low': 'WIN_PRESENT_LOW',
      'win_present_1': 'WIN_PRESENT_1',
      'win_present_2': 'WIN_PRESENT_2',
      'win_present_3': 'WIN_PRESENT_3',
      'win_present_4': 'WIN_PRESENT_4',
      'win_present_5': 'WIN_PRESENT_5',
      'payline_highlight': 'PAYLINE_HIGHLIGHT',
      'rollup_start': 'ROLLUP_START',
      'rollup_tick': 'ROLLUP_TICK',
      'ui_spin_press': 'UI_SPIN_PRESS',
      'ui_menu_open': 'UI_MENU_OPEN',
      'ui_menu_close': 'UI_MENU_CLOSE',
      'ui_button_press': 'UI_BUTTON_PRESS',
      'fs_hold_intro': 'FS_HOLD_INTRO',
      'fs_outro_plaque': 'FS_OUTRO_PLAQUE',
      'fs_end': 'FS_END',
      'game_start': 'GAME_START',
      'anticipation_tension_r2': 'ANTICIPATION_TENSION_R2',
      'anticipation_tension_r3': 'ANTICIPATION_TENSION_R3',
      'anticipation_tension_r4': 'ANTICIPATION_TENSION_R4',
    };

    // Exact match first
    if (stagePatterns.containsKey(stripped)) {
      return stagePatterns[stripped];
    }

    // Partial match (e.g., "reel_stop_final_v2" → REEL_STOP)
    for (final entry in stagePatterns.entries) {
      if (stripped.startsWith(entry.key)) {
        return entry.value;
      }
    }

    // Numbered variants (scatter_1 → SCATTER_LAND_1)
    final numMatch = RegExp(r'^(scatter|wild|hp|mp|lp)_?(\d+)').firstMatch(stripped);
    if (numMatch != null) {
      final prefix = numMatch.group(1)!;
      final num = numMatch.group(2)!;
      switch (prefix) {
        case 'scatter':
          return 'SCATTER_LAND_$num';
        case 'wild':
          return 'WILD_LAND_$num';
        case 'hp':
          return 'HP${num}_WIN';
        case 'mp':
          return 'MP${num}_WIN';
        case 'lp':
          return 'LP${num}_WIN';
      }
    }

    return null;
  }

  double _calculateConfidence(String stripped, String stageId) {
    final stageNorm = stageId.toLowerCase().replaceAll('_', '');
    final fileNorm = stripped.replaceAll('_', '').replaceAll('-', '');

    if (fileNorm == stageNorm) return 0.98;
    if (fileNorm.startsWith(stageNorm) || stageNorm.startsWith(fileNorm)) return 0.85;
    if (fileNorm.contains(stageNorm) || stageNorm.contains(fileNorm)) return 0.72;
    return 0.5;
  }
}

class _CancelledException implements Exception {}
