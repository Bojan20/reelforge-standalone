// audio_warping_service.dart — Time-Stretch Individual Clips
import 'package:flutter/foundation.dart';

class WarpMarker {
  final String id;
  final double position;
  final double targetPosition;
  
  const WarpMarker({required this.id, required this.position, required this.targetPosition});
}

class AudioWarpingService extends ChangeNotifier {
  static final instance = AudioWarpingService._();
  AudioWarpingService._();
  
  final Map<String, List<WarpMarker>> _warpMarkers = {};
  
  void addWarpMarker(String clipId, WarpMarker marker) {
    _warpMarkers.putIfAbsent(clipId, () => []).add(marker);
    notifyListeners();
  }
  
  void removeWarpMarker(String clipId, String markerId) {
    _warpMarkers[clipId]?.removeWhere((m) => m.id == markerId);
    notifyListeners();
  }
  
  List<WarpMarker> getMarkers(String clipId) => _warpMarkers[clipId] ?? [];
  
  double calculateStretchRatio(String clipId) {
    final markers = getMarkers(clipId);
    if (markers.isEmpty) return 1.0;
    final totalOriginal = markers.fold<double>(0, (sum, m) => sum + m.position);
    final totalTarget = markers.fold<double>(0, (sum, m) => sum + m.targetPosition);
    return totalOriginal > 0 ? totalTarget / totalOriginal : 1.0;
  }
}
