/// DSP Script Service — JSFX-style User-Scriptable Audio Effects
///
/// #30: Sample-level DSP scripting with instant compilation and custom GUI.
///
/// Features:
/// - Script editor with syntax highlighting metadata
/// - Built-in functions library (sin, cos, exp, log, min, max, etc.)
/// - Per-sample processing model (@sample block)
/// - Slider/knob parameter declarations (@slider)
/// - Init block for one-time setup (@init)
/// - Block processing for per-buffer operations (@block)
/// - Script library with save/load/share
/// - Compilation status and error reporting
/// - JSON serialization for persistence
library;

import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// SCRIPT PARAMETER (SLIDER)
// ═══════════════════════════════════════════════════════════════════════════════

/// A user-facing parameter declared in a DSP script
class ScriptParam {
  final int index; // 0-63
  String label;
  double value;
  double minVal;
  double maxVal;
  double defaultVal;
  double step;

  ScriptParam({
    required this.index,
    required this.label,
    this.value = 0,
    this.minVal = 0,
    this.maxVal = 1,
    this.defaultVal = 0,
    this.step = 0.01,
  });

  Map<String, dynamic> toJson() => {
    'index': index,
    'label': label,
    'value': value,
    'minVal': minVal,
    'maxVal': maxVal,
    'defaultVal': defaultVal,
    'step': step,
  };

  factory ScriptParam.fromJson(Map<String, dynamic> json) => ScriptParam(
    index: json['index'] as int? ?? 0,
    label: json['label'] as String? ?? '',
    value: (json['value'] as num?)?.toDouble() ?? 0,
    minVal: (json['minVal'] as num?)?.toDouble() ?? 0,
    maxVal: (json['maxVal'] as num?)?.toDouble() ?? 1,
    defaultVal: (json['defaultVal'] as num?)?.toDouble() ?? 0,
    step: (json['step'] as num?)?.toDouble() ?? 0.01,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// COMPILATION STATUS
// ═══════════════════════════════════════════════════════════════════════════════

/// Status of script compilation
enum CompileStatus {
  idle,
  compiling,
  success,
  error,
}

/// A compilation error with location info
class CompileError {
  final int line;
  final int column;
  final String message;
  final String severity; // 'error', 'warning', 'info'

  const CompileError({
    required this.line,
    this.column = 0,
    required this.message,
    this.severity = 'error',
  });

  Map<String, dynamic> toJson() => {
    'line': line,
    'column': column,
    'message': message,
    'severity': severity,
  };

  factory CompileError.fromJson(Map<String, dynamic> json) => CompileError(
    line: json['line'] as int? ?? 0,
    column: json['column'] as int? ?? 0,
    message: json['message'] as String? ?? '',
    severity: json['severity'] as String? ?? 'error',
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// DSP SCRIPT
// ═══════════════════════════════════════════════════════════════════════════════

/// A complete DSP script with source code, parameters, and metadata
class DspScript {
  final String id;
  String name;
  String? description;
  String? author;
  String sourceCode;
  final List<ScriptParam> params;
  CompileStatus compileStatus;
  final List<CompileError> errors;

  /// Processing stats
  double cpuUsage; // 0.0 to 1.0
  int sampleRate;
  int blockSize;

  /// Whether this script is actively processing audio
  bool active;

  DspScript({
    required this.id,
    required this.name,
    this.description,
    this.author,
    this.sourceCode = '',
    List<ScriptParam>? params,
    this.compileStatus = CompileStatus.idle,
    List<CompileError>? errors,
    this.cpuUsage = 0,
    this.sampleRate = 48000,
    this.blockSize = 512,
    this.active = false,
  }) : params = params ?? [],
       errors = errors ?? [];

  bool get hasErrors => errors.any((e) => e.severity == 'error');
  bool get isCompiled => compileStatus == CompileStatus.success;
  int get lineCount => sourceCode.split('\n').length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'author': author,
    'sourceCode': sourceCode,
    'params': params.map((p) => p.toJson()).toList(),
    'active': active,
  };

  factory DspScript.fromJson(Map<String, dynamic> json) => DspScript(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    description: json['description'] as String?,
    author: json['author'] as String?,
    sourceCode: json['sourceCode'] as String? ?? '',
    params: (json['params'] as List<dynamic>?)
        ?.map((p) => ScriptParam.fromJson(p as Map<String, dynamic>))
        .toList(),
    active: json['active'] as bool? ?? false,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// DSP SCRIPT SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

/// Service for managing DSP scripts and their compilation/execution
class DspScriptService extends ChangeNotifier {
  DspScriptService._();
  static final DspScriptService instance = DspScriptService._();

  /// All scripts
  final Map<String, DspScript> _scripts = {};

  /// Currently editing script ID
  String? _activeScriptId;

  /// Callback for compiling a script (sends to Rust engine)
  void Function(String scriptId, String sourceCode)? onCompile;

  /// Callback for toggling script processing
  void Function(String scriptId, bool active)? onToggleProcessing;

  /// Callback for parameter changes
  void Function(String scriptId, int paramIndex, double value)? onParamChanged;

  // Getters
  List<DspScript> get scripts => _scripts.values.toList();
  int get count => _scripts.length;
  int get activeCount => _scripts.values.where((s) => s.active).length;
  String? get activeScriptId => _activeScriptId;
  DspScript? get activeScript =>
      _activeScriptId != null ? _scripts[_activeScriptId!] : null;

  DspScript? getScript(String id) => _scripts[id];

  // ═══════════════════════════════════════════════════════════════════════════
  // SCRIPT CRUD
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a new script
  DspScript createScript(String name) {
    final id = 'script_${DateTime.now().millisecondsSinceEpoch}';
    final script = DspScript(
      id: id,
      name: name,
      sourceCode: _defaultTemplate,
    );
    _scripts[id] = script;
    _activeScriptId = id;
    notifyListeners();
    return script;
  }

  /// Remove a script
  void removeScript(String id) {
    final script = _scripts[id];
    if (script != null && script.active) {
      onToggleProcessing?.call(id, false);
    }
    _scripts.remove(id);
    if (_activeScriptId == id) {
      _activeScriptId = _scripts.keys.firstOrNull;
    }
    notifyListeners();
  }

  /// Rename a script
  void renameScript(String id, String newName) {
    final script = _scripts[id];
    if (script == null) return;
    script.name = newName;
    notifyListeners();
  }

  /// Set active (editing) script
  void setActiveScript(String? id) {
    _activeScriptId = id;
    notifyListeners();
  }

  /// Duplicate a script
  void duplicateScript(String id) {
    final script = _scripts[id];
    if (script == null) return;

    final newId = 'script_${DateTime.now().millisecondsSinceEpoch}';
    final json = script.toJson();
    json['id'] = newId;
    json['name'] = '${script.name} (Copy)';
    json['active'] = false;

    _scripts[newId] = DspScript.fromJson(json);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SOURCE CODE EDITING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Update source code
  void updateSourceCode(String id, String sourceCode) {
    final script = _scripts[id];
    if (script == null) return;
    script.sourceCode = sourceCode;
    script.compileStatus = CompileStatus.idle;
    script.errors.clear();
    notifyListeners();
  }

  /// Compile a script
  void compileScript(String id) {
    final script = _scripts[id];
    if (script == null) return;

    script.compileStatus = CompileStatus.compiling;
    script.errors.clear();
    notifyListeners();

    onCompile?.call(id, script.sourceCode);
  }

  /// Report compilation result (called from engine callback)
  void onCompileResult(String id, bool success, List<CompileError>? errors) {
    final script = _scripts[id];
    if (script == null) return;

    script.compileStatus = success ? CompileStatus.success : CompileStatus.error;
    script.errors.clear();
    if (errors != null) script.errors.addAll(errors);

    // Parse slider declarations from source code
    if (success) {
      _parseParams(script);
    }
    notifyListeners();
  }

  /// Toggle script processing on/off
  void toggleProcessing(String id) {
    final script = _scripts[id];
    if (script == null) return;
    if (!script.isCompiled && !script.active) return; // Can't activate uncompiled

    script.active = !script.active;
    onToggleProcessing?.call(id, script.active);
    notifyListeners();
  }

  /// Set a parameter value
  void setParam(String scriptId, int paramIndex, double value) {
    final script = _scripts[scriptId];
    if (script == null) return;

    final param = script.params.where((p) => p.index == paramIndex).firstOrNull;
    if (param == null) return;

    param.value = value.clamp(param.minVal, param.maxVal);
    onParamChanged?.call(scriptId, paramIndex, param.value);
    notifyListeners();
  }

  /// Reset a parameter to default
  void resetParam(String scriptId, int paramIndex) {
    final script = _scripts[scriptId];
    if (script == null) return;

    final param = script.params.where((p) => p.index == paramIndex).firstOrNull;
    if (param == null) return;

    param.value = param.defaultVal;
    onParamChanged?.call(scriptId, paramIndex, param.value);
    notifyListeners();
  }

  /// Update CPU usage stats
  void updateCpuUsage(String id, double cpuUsage) {
    final script = _scripts[id];
    if (script == null) return;
    script.cpuUsage = cpuUsage.clamp(0, 1);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PARAMETER PARSING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Parse @slider declarations from source code
  void _parseParams(DspScript script) {
    script.params.clear();
    final lines = script.sourceCode.split('\n');
    final sliderRe = RegExp(r'@slider(\d+)\s+(.+?)\s*=\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)');

    for (final line in lines) {
      final match = sliderRe.firstMatch(line.trim());
      if (match == null) continue;

      final index = int.tryParse(match.group(1)!) ?? 0;
      final label = match.group(2)!.trim();
      final defaultVal = double.tryParse(match.group(3)!) ?? 0;
      final minVal = double.tryParse(match.group(4)!) ?? 0;
      final maxVal = double.tryParse(match.group(5)!) ?? 1;

      script.params.add(ScriptParam(
        index: index.clamp(0, 63),
        label: label,
        value: defaultVal,
        minVal: minVal,
        maxVal: maxVal,
        defaultVal: defaultVal,
      ));
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILT-IN TEMPLATES
  // ═══════════════════════════════════════════════════════════════════════════

  static const String _defaultTemplate = '''// FluxForge DSP Script
// Sample-level audio processing

@slider1 Gain = 0, -24, 24
@slider2 Mix = 100, 0, 100

@init
  // One-time initialization
  gain_linear = 1.0;

@slider
  // Called when slider values change
  gain_linear = pow(10, slider1 / 20);
  mix = slider2 / 100;

@sample
  // Per-sample processing
  spl0 = spl0 * gain_linear * mix + spl0 * (1 - mix);
  spl1 = spl1 * gain_linear * mix + spl1 * (1 - mix);
''';

  static const String _distortionTemplate = '''// Soft Clipping Distortion
// Waveshaping with drive and tone controls

@slider1 Drive = 0, 0, 36
@slider2 Tone = 50, 0, 100
@slider3 Output = 0, -24, 6

@init
  drive_gain = 1.0;
  tone_coeff = 0.5;
  output_gain = 1.0;
  lp_l = 0; lp_r = 0;

@slider
  drive_gain = pow(10, slider1 / 20);
  tone_coeff = slider2 / 100;
  output_gain = pow(10, slider3 / 20);

@sample
  // Apply drive
  dl = spl0 * drive_gain;
  dr = spl1 * drive_gain;

  // Soft clip (tanh approximation)
  dl = dl / (1 + abs(dl));
  dr = dr / (1 + abs(dr));

  // One-pole lowpass for tone
  lp_l = lp_l + tone_coeff * (dl - lp_l);
  lp_r = lp_r + tone_coeff * (dr - lp_r);

  // Output
  spl0 = lp_l * output_gain;
  spl1 = lp_r * output_gain;
''';

  static const String _delayTemplate = '''// Simple Stereo Delay
// Ping-pong delay with feedback and mix

@slider1 Time_ms = 250, 1, 2000
@slider2 Feedback = 40, 0, 95
@slider3 Mix = 30, 0, 100

@init
  buf_size = 96000 * 2; // 2 seconds at 96kHz max
  buf_l = 0; buf_r = 0;
  write_pos = 0;

@slider
  delay_samples = floor(slider1 / 1000 * srate);
  fb = slider2 / 100;
  mix = slider3 / 100;

@sample
  // Read from delay buffer
  read_pos = write_pos - delay_samples;
  read_pos < 0 ? read_pos += buf_size;

  del_l = buf_l[read_pos];
  del_r = buf_r[read_pos];

  // Write to delay buffer (ping-pong: L→R, R→L)
  buf_l[write_pos] = spl0 + del_r * fb;
  buf_r[write_pos] = spl1 + del_l * fb;

  // Output
  spl0 = spl0 * (1 - mix) + del_l * mix;
  spl1 = spl1 * (1 - mix) + del_r * mix;

  // Advance write position
  write_pos = (write_pos + 1) % buf_size;
''';

  /// Load factory templates (skips already-present)
  void loadTemplates() {
    void addIfAbsent(String id, String name, String source, String? desc) {
      if (_scripts.containsKey(id)) return;
      _scripts[id] = DspScript(
        id: id,
        name: name,
        description: desc,
        sourceCode: source,
        author: 'FluxForge',
      );
    }

    addIfAbsent('template_gain', 'Gain + Mix', _defaultTemplate,
        'Simple gain control with wet/dry mix');
    addIfAbsent('template_distortion', 'Soft Clip Distortion', _distortionTemplate,
        'Waveshaping distortion with drive, tone, and output controls');
    addIfAbsent('template_delay', 'Stereo Delay', _delayTemplate,
        'Ping-pong delay with feedback and mix');

    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  Map<String, dynamic> toJson() => {
    'scripts': _scripts.values.map((s) => s.toJson()).toList(),
    'activeScriptId': _activeScriptId,
  };

  void fromJson(Map<String, dynamic> json) {
    _scripts.clear();
    _activeScriptId = json['activeScriptId'] as String?;
    final list = json['scripts'] as List<dynamic>?;
    if (list != null) {
      for (final item in list) {
        final script = DspScript.fromJson(item as Map<String, dynamic>);
        _scripts[script.id] = script;
      }
    }
    notifyListeners();
  }
}
