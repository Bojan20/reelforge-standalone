// comping_service.dart — Take Lanes & Comping
import 'package:flutter/foundation.dart';

class TakeLane {
  final String id;
  final String trackId;
  final int laneIndex;
  final List<AudioTake> takes;
  final List<CompRegion> compRegions;
  
  const TakeLane({required this.id, required this.trackId, required this.laneIndex, this.takes = const [], this.compRegions = const []});
}

class AudioTake {
  final String id;
  final String audioPath;
  final double startTime;
  final double duration;
  final bool isActive;
  
  const AudioTake({required this.id, required this.audioPath, required this.startTime, required this.duration, this.isActive = false});
}

class CompRegion {
  final String takeId;
  final double startTime;
  final double duration;
  
  const CompRegion({required this.takeId, required this.startTime, required this.duration});
}

class CompingService extends ChangeNotifier {
  static final instance = CompingService._();
  CompingService._();
  
  final Map<String, TakeLane> _lanes = {};
  
  TakeLane? getLane(String trackId) => _lanes[trackId];
  
  void createLane(String trackId) {
    _lanes[trackId] = TakeLane(id: 'lane_$trackId', trackId: trackId, laneIndex: _lanes.length);
    notifyListeners();
  }
  
  void addTake(String trackId, AudioTake take) {
    final lane = _lanes[trackId];
    if (lane != null) {
      _lanes[trackId] = TakeLane(id: lane.id, trackId: lane.trackId, laneIndex: lane.laneIndex, takes: [...lane.takes, take], compRegions: lane.compRegions);
      notifyListeners();
    }
  }
  
  void createCompRegion(String trackId, CompRegion region) {
    final lane = _lanes[trackId];
    if (lane != null) {
      _lanes[trackId] = TakeLane(id: lane.id, trackId: lane.trackId, laneIndex: lane.laneIndex, takes: lane.takes, compRegions: [...lane.compRegions, region]);
      notifyListeners();
    }
  }
}
