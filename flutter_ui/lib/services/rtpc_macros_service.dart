// rtpc_macros_service.dart — RTPC Macro System
import 'package:flutter/foundation.dart';

class RtpcMacro {
  final String id;
  final String name;
  final List<String> rtpcIds;
  final double value;
  const RtpcMacro({required this.id, required this.name, this.rtpcIds = const [], this.value = 0.0});
}

class RtpcMacrosService extends ChangeNotifier {
  static final instance = RtpcMacrosService._();
  RtpcMacrosService._();
  
  final Map<String, RtpcMacro> _macros = {};
  
  void createMacro(String id, String name, List<String> rtpcIds) {
    _macros[id] = RtpcMacro(id: id, name: name, rtpcIds: rtpcIds);
    notifyListeners();
  }
  
  void setMacroValue(String macroId, double value) {
    final macro = _macros[macroId];
    if (macro != null) {
      _macros[macroId] = RtpcMacro(id: macro.id, name: macro.name, rtpcIds: macro.rtpcIds, value: value.clamp(0.0, 1.0));
      notifyListeners();
    }
  }
  
  List<RtpcMacro> get allMacros => _macros.values.toList();
}
