/// Shared Memory Metering Reader
///
/// Zero-latency push model: Reads directly from Rust shared memory.
/// No FFI overhead, no 50ms polling. Instant meter updates.
///
/// Architecture:
///   Audio Thread → SharedMeterBuffer (atomics) ← SharedMeterReader (reads)
///
/// Usage:
///   final reader = SharedMeterReader.instance;
///   await reader.initialize();
///
///   // Poll sequence first (fast - just one atomic read)
///   if (reader.hasChanged) {
///     final meters = reader.readMeters();
///     // Update UI
///   }

import 'dart:ffi';
import 'dart:typed_data';
import '../src/rust/native_ffi.dart';

/// Meter data snapshot (immutable, can be shared across isolates)
class SharedMeterSnapshot {
  final int sequence;

  // Master meters (normalized 0-1, not dB)
  final double masterPeakL;
  final double masterPeakR;
  final double masterRmsL;
  final double masterRmsR;

  // LUFS
  final double lufsShort;
  final double lufsIntegrated;
  final double lufsMomentary;

  // True Peak (dBTP)
  final double truePeakL;
  final double truePeakR;
  final double truePeakMax;

  // Stereo analysis
  final double correlation;
  final double balance;
  final double stereoWidth;

  // Dynamics
  final double dynamicRange;
  final double crestFactorL;
  final double crestFactorR;
  final double psr; // Peak-to-Short-term Ratio
  final double gainReduction;

  // Transport
  final int playbackPositionSamples;
  final bool isPlaying;
  final int sampleRate;

  // Channel peaks (6 channels, L/R each)
  final Float64List channelPeaks;

  // Spectrum (32 bands)
  final Float64List spectrumBands;

  const SharedMeterSnapshot({
    required this.sequence,
    required this.masterPeakL,
    required this.masterPeakR,
    required this.masterRmsL,
    required this.masterRmsR,
    required this.lufsShort,
    required this.lufsIntegrated,
    required this.lufsMomentary,
    required this.truePeakL,
    required this.truePeakR,
    required this.truePeakMax,
    required this.correlation,
    required this.balance,
    required this.stereoWidth,
    required this.dynamicRange,
    required this.crestFactorL,
    required this.crestFactorR,
    required this.psr,
    required this.gainReduction,
    required this.playbackPositionSamples,
    required this.isPlaying,
    required this.sampleRate,
    required this.channelPeaks,
    required this.spectrumBands,
  });

  /// Empty/default snapshot
  static final SharedMeterSnapshot empty = SharedMeterSnapshot(
    sequence: 0,
    masterPeakL: 0,
    masterPeakR: 0,
    masterRmsL: 0,
    masterRmsR: 0,
    lufsShort: -60,
    lufsIntegrated: -60,
    lufsMomentary: -60,
    truePeakL: -60,
    truePeakR: -60,
    truePeakMax: -60,
    correlation: 1.0,
    balance: 0,
    stereoWidth: 1.0,
    dynamicRange: 0,
    crestFactorL: 0,
    crestFactorR: 0,
    psr: 0,
    gainReduction: 0,
    playbackPositionSamples: 0,
    isPlaying: false,
    sampleRate: 48000,
    channelPeaks: Float64List(12),
    spectrumBands: Float64List(32),
  );

  /// Convert dB to normalized (0-1) for meter display
  double get masterPeakLNormalized => _dbToNormalized(masterPeakL);
  double get masterPeakRNormalized => _dbToNormalized(masterPeakR);
  double get masterRmsLNormalized => _dbToNormalized(masterRmsL);
  double get masterRmsRNormalized => _dbToNormalized(masterRmsR);

  static double _dbToNormalized(double db, {double minDb = -60, double maxDb = 0}) {
    if (db <= minDb) return 0;
    if (db >= maxDb) return 1;
    return (db - minDb) / (maxDb - minDb);
  }
}

/// Shared Memory Meter Reader - singleton
class SharedMeterReader {
  static SharedMeterReader? _instance;
  static SharedMeterReader get instance => _instance ??= SharedMeterReader._();

  SharedMeterReader._();

  // FFI reference
  final NativeFFI _ffi = NativeFFI.instance;

  // Cached buffer pointer and offsets
  Pointer<Void>? _bufferPtr;
  Map<int, int>? _fieldOffsets;
  int _bufferSize = 0;

  // Last known sequence (for change detection)
  int _lastSequence = 0;

  // Initialization state
  bool _initialized = false;

  /// Initialize the reader (call once at app startup)
  Future<bool> initialize() async {
    if (_initialized) return true;

    try {
      _bufferPtr = _ffi.meteringGetSharedBufferPtr();
      _bufferSize = _ffi.meteringGetSharedBufferSize();
      _fieldOffsets = _ffi.meteringGetAllFieldOffsets();

      if (_bufferPtr == null ||
          _bufferPtr!.address == 0 ||
          _bufferSize == 0 ||
          _fieldOffsets == null ||
          _fieldOffsets!.isEmpty) {
        return false;
      }

      _initialized = true;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Check if buffer has changed since last read
  bool get hasChanged {
    if (!_initialized) return false;
    final currentSeq = _ffi.meteringGetSequence();
    return currentSeq != _lastSequence;
  }

  /// Get current sequence number
  int get currentSequence {
    if (!_initialized) return 0;
    return _ffi.meteringGetSequence();
  }

  /// Read f64 from buffer at offset
  double _readF64(int offset) {
    if (_bufferPtr == null || offset < 0) return 0;
    final ptr = Pointer<Uint64>.fromAddress(_bufferPtr!.address + offset);
    return _bitsToDouble(ptr.value);
  }

  /// Read u32 from buffer at offset
  int _readU32(int offset) {
    if (_bufferPtr == null || offset < 0) return 0;
    final ptr = Pointer<Uint32>.fromAddress(_bufferPtr!.address + offset);
    return ptr.value;
  }

  /// Read u64 from buffer at offset
  int _readU64(int offset) {
    if (_bufferPtr == null || offset < 0) return 0;
    final ptr = Pointer<Uint64>.fromAddress(_bufferPtr!.address + offset);
    return ptr.value;
  }

  /// Convert u64 bits to f64
  static double _bitsToDouble(int bits) {
    final bytes = ByteData(8)..setUint64(0, bits, Endian.little);
    return bytes.getFloat64(0, Endian.little);
  }

  /// Read all meters from shared memory (fast - no FFI calls, just memory reads)
  SharedMeterSnapshot readMeters() {
    if (!_initialized || _fieldOffsets == null) {
      return SharedMeterSnapshot.empty;
    }

    final offsets = _fieldOffsets!;

    // Read sequence first
    final sequence = _readU64(offsets[0]!);
    _lastSequence = sequence;

    // Read channel peaks array (12 values: 6 channels * 2 channels each)
    final channelPeaksBase = offsets[22]!;
    final channelPeaks = Float64List(12);
    for (int i = 0; i < 12; i++) {
      channelPeaks[i] = _readF64(channelPeaksBase + i * 8);
    }

    // Read spectrum bands array (32 values)
    final spectrumBase = offsets[23]!;
    final spectrum = Float64List(32);
    for (int i = 0; i < 32; i++) {
      spectrum[i] = _readF64(spectrumBase + i * 8);
    }

    return SharedMeterSnapshot(
      sequence: sequence,
      masterPeakL: _readF64(offsets[1]!),
      masterPeakR: _readF64(offsets[2]!),
      masterRmsL: _readF64(offsets[3]!),
      masterRmsR: _readF64(offsets[4]!),
      lufsShort: _readF64(offsets[5]!),
      lufsIntegrated: _readF64(offsets[6]!),
      lufsMomentary: _readF64(offsets[7]!),
      truePeakL: _readF64(offsets[8]!),
      truePeakR: _readF64(offsets[9]!),
      truePeakMax: _readF64(offsets[10]!),
      correlation: _readF64(offsets[11]!),
      balance: _readF64(offsets[12]!),
      stereoWidth: _readF64(offsets[13]!),
      dynamicRange: _readF64(offsets[14]!),
      crestFactorL: _readF64(offsets[15]!),
      crestFactorR: _readF64(offsets[16]!),
      psr: _readF64(offsets[17]!),
      gainReduction: _readF64(offsets[18]!),
      playbackPositionSamples: _readU64(offsets[19]!),
      isPlaying: _readU32(offsets[20]!) != 0,
      sampleRate: _readU32(offsets[21]!),
      channelPeaks: channelPeaks,
      spectrumBands: spectrum,
    );
  }

  /// Read all meters as JSON (convenience/debugging)
  /// Uses FFI - slower than readMeters()
  String? readAllJson() {
    return _ffi.meteringReadAllJson();
  }

  /// Dispose resources
  void dispose() {
    _bufferPtr = null;
    _fieldOffsets = null;
    _initialized = false;
  }
}
