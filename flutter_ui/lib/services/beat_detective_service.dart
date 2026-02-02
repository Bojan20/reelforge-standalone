// beat_detective_service.dart — Transient Detection & Quantize
import 'package:flutter/foundation.dart';

class Transient {
  final double position;
  final double strength;
  
  const Transient({required this.position, required this.strength});
}

class BeatDetectiveService extends ChangeNotifier {
  static final instance = BeatDetectiveService._();
  BeatDetectiveService._();
  
  double _sensitivity = 0.5;
  final Map<String, List<Transient>> _detectedTransients = {};
  
  double get sensitivity => _sensitivity;
  
  void setSensitivity(double value) {
    _sensitivity = value.clamp(0.0, 1.0);
    notifyListeners();
  }
  
  Future<List<Transient>> detectTransients(String clipId, List<double> audioSamples) async {
    final transients = <Transient>[];
    for (int i = 1; i < audioSamples.length; i++) {
      final diff = (audioSamples[i] - audioSamples[i - 1]).abs();
      if (diff > _sensitivity) {
        transients.add(Transient(position: i.toDouble(), strength: diff));
      }
    }
    _detectedTransients[clipId] = transients;
    notifyListeners();
    return transients;
  }
  
  List<Transient> getTransients(String clipId) => _detectedTransients[clipId] ?? [];
}
