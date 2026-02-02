// container_groups_service.dart — Nested Container Groups
import 'package:flutter/foundation.dart';

class ContainerGroup {
  final String id;
  final String name;
  final List<String> containerIds;
  const ContainerGroup({required this.id, required this.name, this.containerIds = const []});
}

class ContainerGroupsService extends ChangeNotifier {
  static final instance = ContainerGroupsService._();
  ContainerGroupsService._();
  
  final Map<String, ContainerGroup> _groups = {};
  
  void createGroup(String id, String name) {
    _groups[id] = ContainerGroup(id: id, name: name);
    notifyListeners();
  }
  
  void addToGroup(String groupId, String containerId) {
    final group = _groups[groupId];
    if (group != null) {
      _groups[groupId] = ContainerGroup(id: group.id, name: group.name, containerIds: [...group.containerIds, containerId]);
      notifyListeners();
    }
  }
  
  List<ContainerGroup> get allGroups => _groups.values.toList();
}
