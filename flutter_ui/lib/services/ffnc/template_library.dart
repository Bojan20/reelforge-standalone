/// Template Library — manages built-in and user-saved audio profile templates.
///
/// Templates are .ffap files without audio files — only configuration.
/// Built-in templates are bundled in assets/templates/.
/// User templates are saved to ~/.fluxforge/templates/.

import 'dart:io';
import 'package:path/path.dart' as p;

import 'profile_exporter.dart';
import 'profile_importer.dart';

class TemplateInfo {
  final String name;
  final String path;
  final bool isBuiltIn;
  final String description;
  final int? eventCount;
  final int? reelCount;

  const TemplateInfo({
    required this.name,
    required this.path,
    required this.isBuiltIn,
    this.description = '',
    this.eventCount,
    this.reelCount,
  });
}

class TemplateLibrary {
  TemplateLibrary._();
  static final instance = TemplateLibrary._();

  List<TemplateInfo> _builtIn = [];
  List<TemplateInfo> _user = [];
  bool _loaded = false;

  List<TemplateInfo> get builtInTemplates => List.unmodifiable(_builtIn);
  List<TemplateInfo> get userTemplates => List.unmodifiable(_user);
  List<TemplateInfo> get allTemplates => [..._builtIn, ..._user];

  /// Load template lists from disk.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    await _scanUserTemplates();
    _builtIn = _defaultBuiltInTemplates();
  }

  /// Refresh user templates (after save/delete).
  Future<void> refresh() async {
    await _scanUserTemplates();
  }

  /// Save current project as user template.
  Future<String> saveAsTemplate(String sourceFfapPath, String name) async {
    final dir = Directory(_userTemplateDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final safeName = name.replaceAll(RegExp(r'[^\w\s\-]'), '').trim().replaceAll(' ', '_');
    final destPath = p.join(_userTemplateDir, '$safeName.ffap');
    await File(sourceFfapPath).copy(destPath);
    await refresh();
    return destPath;
  }

  /// Delete a user template.
  Future<void> deleteTemplate(String name) async {
    final file = _user.where((t) => t.name == name).firstOrNull;
    if (file != null && File(file.path).existsSync()) {
      await File(file.path).delete();
      await refresh();
    }
  }

  /// Preview a template's contents.
  /// Returns null for built-in templates that haven't been bundled yet.
  Future<ProfilePreview?> previewTemplate(TemplateInfo template) async {
    if (template.isBuiltIn && !File(template.path).existsSync()) {
      // Built-in template not yet bundled — return synthetic preview
      return ProfilePreview(
        manifest: ProfileManifest(
          name: template.name,
          created: '',
          eventCount: template.eventCount ?? 0,
          reelCount: template.reelCount,
        ),
        eventCount: template.eventCount ?? 0,
        winTierCount: 0,
        musicLayerCount: 0,
        readme: '${template.name}\n${template.description}\n\n(Built-in template — details available after first use)',
        eventStages: [],
      );
    }
    return ProfileImporter.preview(template.path);
  }

  // ═══════════════════════════════════════════════════════════════
  // Internal
  // ═══════════════════════════════════════════════════════════════

  Future<void> _scanUserTemplates() async {
    final dir = Directory(_userTemplateDir);
    if (!dir.existsSync()) {
      _user = [];
      return;
    }

    _user = [];
    try {
      for (final entry in dir.listSync()) {
        if (entry is File && entry.path.endsWith('.ffap')) {
          final name = p.basenameWithoutExtension(entry.path).replaceAll('_', ' ');
          // Try to read manifest for metadata
          final preview = await ProfileImporter.preview(entry.path);
          _user.add(TemplateInfo(
            name: preview?.manifest.name ?? name,
            path: entry.path,
            isBuiltIn: false,
            description: '${preview?.eventCount ?? '?'} events',
            eventCount: preview?.eventCount,
            reelCount: preview?.manifest.reelCount,
          ));
        }
      }
    } catch (_) {}
  }

  List<TemplateInfo> _defaultBuiltInTemplates() {
    // Built-in templates will be bundled in assets/templates/
    // For now, return descriptions only — actual .ffap files created later
    return const [
      TemplateInfo(
        name: 'Classic 5-Reel',
        path: 'assets/templates/classic_5reel.ffap',
        isBuiltIn: true,
        description: 'Standard 5-reel slot with ~40 events',
        eventCount: 40,
        reelCount: 5,
      ),
      TemplateInfo(
        name: 'Megaways',
        path: 'assets/templates/megaways.ffap',
        isBuiltIn: true,
        description: 'Megaways with cascade mechanics, ~55 events',
        eventCount: 55,
        reelCount: 6,
      ),
      TemplateInfo(
        name: 'Cascading / Tumble',
        path: 'assets/templates/cascading.ffap',
        isBuiltIn: true,
        description: 'Tumble/cascade mechanics, ~48 events',
        eventCount: 48,
        reelCount: 5,
      ),
      TemplateInfo(
        name: 'Hold & Win',
        path: 'assets/templates/hold_and_win.ffap',
        isBuiltIn: true,
        description: 'Hold & win with respins, ~52 events',
        eventCount: 52,
        reelCount: 5,
      ),
      TemplateInfo(
        name: 'Bonus Wheel',
        path: 'assets/templates/bonus_wheel.ffap',
        isBuiltIn: true,
        description: 'Wheel bonus + pick games, ~45 events',
        eventCount: 45,
        reelCount: 5,
      ),
      TemplateInfo(
        name: 'Jackpot Progressive',
        path: 'assets/templates/jackpot_progressive.ffap',
        isBuiltIn: true,
        description: 'Progressive jackpot focus, ~50 events',
        eventCount: 50,
        reelCount: 5,
      ),
    ];
  }

  String get _userTemplateDir {
    final home = Platform.environment['HOME'] ?? '/tmp';
    return p.join(home, '.fluxforge', 'templates');
  }
}
