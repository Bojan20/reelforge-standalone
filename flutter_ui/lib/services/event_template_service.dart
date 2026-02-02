// event_template_service.dart — Event Template Presets
import 'package:flutter/foundation.dart';

class EventTemplate {
  final String id;
  final String name;
  final String category;
  final Map<String, dynamic> config;
  const EventTemplate({required this.id, required this.name, required this.category, required this.config});
}

class EventTemplateService extends ChangeNotifier {
  static final instance = EventTemplateService._();
  EventTemplateService._();
  
  final List<EventTemplate> _templates = [
    const EventTemplate(id: 'spin', name: 'Spin Sound', category: 'base', config: {'stage': 'SPIN_START', 'bus': 'sfx'}),
    const EventTemplate(id: 'win', name: 'Win Sound', category: 'wins', config: {'stage': 'WIN_PRESENT', 'bus': 'wins'}),
    const EventTemplate(id: 'feature', name: 'Feature Trigger', category: 'features', config: {'stage': 'FS_TRIGGER', 'bus': 'music'}),
  ];
  
  List<EventTemplate> get allTemplates => _templates;
  List<EventTemplate> getByCategory(String cat) => _templates.where((t) => t.category == cat).toList();
  EventTemplate? getById(String id) => _templates.where((t) => t.id == id).firstOrNull;
}
