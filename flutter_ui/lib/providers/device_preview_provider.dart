import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

/// Device category enum matching Rust DeviceCategory
enum DeviceCategory {
  smartphone,
  headphone,
  laptopTablet,
  tvSoundbar,
  btSpeaker,
  referenceMonitor,
  casinoEnvironment,
  custom;

  String get displayName {
    switch (this) {
      case smartphone: return 'Smartphones';
      case headphone: return 'Headphones';
      case laptopTablet: return 'Laptop / Tablet';
      case tvSoundbar: return 'TV / Soundbar';
      case btSpeaker: return 'BT Speakers';
      case referenceMonitor: return 'Reference Monitors';
      case casinoEnvironment: return 'Casino / Environment';
      case custom: return 'Custom';
    }
  }
}

/// Device profile data loaded from Rust
class DeviceProfileInfo {
  final int id;
  final String name;
  final DeviceCategory category;
  final double hpfFreq;
  final double maxSpl;
  final double drcAmount;
  final String stereoMode;
  final String distortion;
  final double envNoiseFloor;
  final int frPoints;

  const DeviceProfileInfo({
    required this.id,
    required this.name,
    required this.category,
    required this.hpfFreq,
    required this.maxSpl,
    required this.drcAmount,
    required this.stereoMode,
    required this.distortion,
    required this.envNoiseFloor,
    required this.frPoints,
  });

  factory DeviceProfileInfo.fromJson(Map<String, dynamic> json) {
    final catStr = json['category'] as String? ?? 'custom';
    final cat = switch (catStr) {
      'smartphone' => DeviceCategory.smartphone,
      'headphone' => DeviceCategory.headphone,
      'laptop_tablet' => DeviceCategory.laptopTablet,
      'tv_soundbar' => DeviceCategory.tvSoundbar,
      'bt_speaker' => DeviceCategory.btSpeaker,
      'reference_monitor' => DeviceCategory.referenceMonitor,
      'casino_environment' => DeviceCategory.casinoEnvironment,
      _ => DeviceCategory.custom,
    };
    return DeviceProfileInfo(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? 'Unknown',
      category: cat,
      hpfFreq: (json['hpf_freq'] as num?)?.toDouble() ?? 0.0,
      maxSpl: (json['max_spl'] as num?)?.toDouble() ?? 0.0,
      drcAmount: (json['drc_amount'] as num?)?.toDouble() ?? 0.0,
      stereoMode: json['stereo'] as String? ?? 'stereo',
      distortion: json['distortion'] as String? ?? 'none',
      envNoiseFloor: (json['env_noise_floor'] as num?)?.toDouble() ?? -90.0,
      frPoints: json['fr_points'] as int? ?? 0,
    );
  }
}

/// Provider for the Device Preview monitoring engine
class DevicePreviewProvider extends ChangeNotifier {
  bool _initialized = false;
  bool _active = false;
  int _currentProfileId = 0;
  List<DeviceProfileInfo> _profiles = [];
  List<List<double>>? _currentFrCurve;

  // A/B comparison
  int _aProfileId = 0;
  int _bProfileId = 0;
  bool _isCompareMode = false;
  bool _showingB = false;

  // Getters
  bool get initialized => _initialized;
  bool get active => _active;
  int get currentProfileId => _currentProfileId;
  List<DeviceProfileInfo> get profiles => _profiles;
  List<List<double>>? get currentFrCurve => _currentFrCurve;
  bool get isCompareMode => _isCompareMode;
  bool get showingB => _showingB;

  /// Get profiles filtered by category
  List<DeviceProfileInfo> profilesByCategory(DeviceCategory category) {
    return _profiles.where((p) => p.category == category).toList();
  }

  /// Get current profile info
  DeviceProfileInfo? get currentProfile {
    if (_currentProfileId == 0) return null;
    return _profiles.firstWhereOrNull((p) => p.id == _currentProfileId);
  }

  /// Initialize the engine
  void init({double sampleRate = 48000.0}) {
    if (_initialized) return;
    final ok = NativeFFI.instance.devicePreviewInit(sampleRate);
    if (ok) {
      _initialized = true;
      _loadProfiles();
      notifyListeners();
    }
  }

  /// Destroy the engine
  void destroy() {
    if (!_initialized) return;
    NativeFFI.instance.devicePreviewDestroy();
    _initialized = false;
    _active = false;
    _currentProfileId = 0;
    notifyListeners();
  }

  /// Toggle active state
  void toggleActive() {
    if (!_initialized) return;
    _active = !_active;
    NativeFFI.instance.devicePreviewSetActive(_active);
    notifyListeners();
  }

  /// Set active state directly
  void setActive(bool value) {
    if (!_initialized || _active == value) return;
    _active = value;
    NativeFFI.instance.devicePreviewSetActive(value);
    notifyListeners();
  }

  /// Load a profile
  void loadProfile(int profileId) {
    if (!_initialized) return;
    final ok = NativeFFI.instance.devicePreviewLoadProfile(profileId);
    if (ok) {
      _currentProfileId = profileId;
      _currentFrCurve = NativeFFI.instance.devicePreviewProfileFrCurve(profileId);
      if (!_active) {
        _active = true;
        NativeFFI.instance.devicePreviewSetActive(true);
      }
      notifyListeners();
    }
  }

  /// Bypass
  void bypass() {
    if (!_initialized) return;
    NativeFFI.instance.devicePreviewBypass();
    _currentProfileId = 0;
    _currentFrCurve = null;
    notifyListeners();
  }

  // ── A/B Comparison ──────────────────────────────────────────────────

  /// Start A/B comparison mode
  void startCompare(int profileA, int profileB) {
    _aProfileId = profileA;
    _bProfileId = profileB;
    _isCompareMode = true;
    _showingB = false;
    loadProfile(profileA);
  }

  /// Toggle between A and B
  void toggleAB() {
    if (!_isCompareMode) return;
    _showingB = !_showingB;
    loadProfile(_showingB ? _bProfileId : _aProfileId);
  }

  /// Exit comparison mode
  void exitCompare() {
    _isCompareMode = false;
    _showingB = false;
    notifyListeners();
  }

  // ── Internal ────────────────────────────────────────────────────────

  void _loadProfiles() {
    final json = NativeFFI.instance.devicePreviewAllProfilesJson();
    if (json != null) {
      try {
        final list = jsonDecode(json) as List;
        _profiles = list.map((e) => DeviceProfileInfo.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {
        _profiles = [];
      }
    }
  }

  @override
  void dispose() {
    destroy();
    super.dispose();
  }
}
