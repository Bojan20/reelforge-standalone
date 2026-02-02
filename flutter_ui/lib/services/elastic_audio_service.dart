// elastic_audio_service.dart — Pitch Correction Per Clip
import 'package:flutter/foundation.dart';

enum ElasticMode { polyphonic, monophonic, rhythmic }

class ElasticAudioConfig {
  final ElasticMode mode;
  final double pitchShift;
  final bool preserveFormants;
  
  const ElasticAudioConfig({this.mode = ElasticMode.polyphonic, this.pitchShift = 0.0, this.preserveFormants = true});
}

class ElasticAudioService extends ChangeNotifier {
  static final instance = ElasticAudioService._();
  ElasticAudioService._();
  
  final Map<String, ElasticAudioConfig> _clipConfigs = {};
  
  void setClipConfig(String clipId, ElasticAudioConfig config) {
    _clipConfigs[clipId] = config;
    notifyListeners();
  }
  
  ElasticAudioConfig? getClipConfig(String clipId) => _clipConfigs[clipId];
  
  void removeClipConfig(String clipId) {
    _clipConfigs.remove(clipId);
    notifyListeners();
  }
}
