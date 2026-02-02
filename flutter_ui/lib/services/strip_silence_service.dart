// strip_silence_service.dart — Remove Silent Regions
import 'package:flutter/foundation.dart';

class SilentRegion {
  final double startTime;
  final double endTime;
  
  const SilentRegion({required this.startTime, required this.endTime});
  double get duration => endTime - startTime;
}

class StripSilenceService extends ChangeNotifier {
  static final instance = StripSilenceService._();
  StripSilenceService._();
  
  double _thresholdDb = -40.0;
  double _minDurationMs = 100.0;
  
  double get thresholdDb => _thresholdDb;
  double get minDurationMs => _minDurationMs;
  
  void setThreshold(double db) {
    _thresholdDb = db.clamp(-96.0, 0.0);
    notifyListeners();
  }
  
  void setMinDuration(double ms) {
    _minDurationMs = ms.clamp(10.0, 5000.0);
    notifyListeners();
  }
  
  List<SilentRegion> detectSilence(List<double> audioSamples, double sampleRate) {
    final threshold = _dbToLinear(_thresholdDb);
    final minSamples = (_minDurationMs / 1000.0 * sampleRate).round();
    final regions = <SilentRegion>[];
    
    int silentStart = -1;
    for (int i = 0; i < audioSamples.length; i++) {
      if (audioSamples[i].abs() < threshold) {
        if (silentStart == -1) silentStart = i;
      } else {
        if (silentStart >= 0 && (i - silentStart) >= minSamples) {
          regions.add(SilentRegion(startTime: silentStart / sampleRate, endTime: i / sampleRate));
        }
        silentStart = -1;
      }
    }
    return regions;
  }
  
  double _dbToLinear(double db) => db <= -96.0 ? 0.0 : pow(10, db / 20.0).toDouble();
}

double pow(num x, num exp) => x is int && exp is int && exp >= 0 ? List.filled(exp, x).fold(1, (a, b) => a * b) : 1.0;
