/// Template Library — manages built-in and user-saved audio profile templates.
///
/// Templates are .zip files without audio files — only configuration.
/// Built-in templates are bundled in assets/templates/.
/// User templates are saved to ~/.fluxforge/templates/.

import 'dart:io';
import 'package:path/path.dart' as p;

import 'profile_exporter.dart';
import 'profile_importer.dart';
import 'template_generator.dart';

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
    // Generate built-in templates if they don't exist yet
    await TemplateGenerator.ensureBuiltInTemplates();
    _builtIn = _defaultBuiltInTemplates();
    await _scanUserTemplates();
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
    final destPath = p.join(_userTemplateDir, '$safeName.zip');
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
        if (entry is File && entry.path.endsWith('.zip')) {
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
    return [
      TemplateInfo(
        name: 'Classic 5-Reel',
        path: TemplateGenerator.getTemplatePath('classic_5reel'),
        isBuiltIn: true,
        description: 'Standard 5-reel slot with ~47 events',
        eventCount: 47,
        reelCount: 5,
      ),
      TemplateInfo(
        name: 'Megaways',
        path: TemplateGenerator.getTemplatePath('megaways'),
        isBuiltIn: true,
        description: 'Megaways with cascade mechanics, ~53 events',
        eventCount: 53,
        reelCount: 6,
      ),
      TemplateInfo(
        name: 'Cascading / Tumble',
        path: TemplateGenerator.getTemplatePath('cascading'),
        isBuiltIn: true,
        description: 'Tumble/cascade mechanics, ~46 events',
        eventCount: 46,
        reelCount: 5,
      ),
      TemplateInfo(
        name: 'Hold & Win',
        path: TemplateGenerator.getTemplatePath('hold_and_win'),
        isBuiltIn: true,
        description: 'Hold & win with respins + jackpots, ~52 events',
        eventCount: 52,
        reelCount: 5,
      ),
      TemplateInfo(
        name: 'Bonus Wheel',
        path: TemplateGenerator.getTemplatePath('bonus_wheel'),
        isBuiltIn: true,
        description: 'Wheel bonus + pick games, ~47 events',
        eventCount: 47,
        reelCount: 5,
      ),
      TemplateInfo(
        name: 'Jackpot Progressive',
        path: TemplateGenerator.getTemplatePath('jackpot_progressive'),
        isBuiltIn: true,
        description: 'Progressive jackpot with 4+ tiers, ~50 events',
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
