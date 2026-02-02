// audio_signature_service.dart — Audio Fingerprinting
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

class AudioSignature {
  final String hash;
  final double duration;
  final int sampleRate;
  final int channels;
  const AudioSignature({required this.hash, required this.duration, required this.sampleRate, required this.channels});
}

class AudioSignatureService extends ChangeNotifier {
  static final instance = AudioSignatureService._();
  AudioSignatureService._();
  
  final Map<String, AudioSignature> _signatures = {};
  
  AudioSignature generateSignature(String audioPath, List<double> samples, double sampleRate, int channels) {
    final hash = sha256.convert(utf8.encode(samples.map((s) => s.toStringAsFixed(6)).join(','))).toString();
    final sig = AudioSignature(hash: hash, duration: samples.length / sampleRate, sampleRate: sampleRate.toInt(), channels: channels);
    _signatures[audioPath] = sig;
    notifyListeners();
    return sig;
  }
  
  AudioSignature? getSignature(String audioPath) => _signatures[audioPath];
  bool areSimilar(String path1, String path2) => _signatures[path1]?.hash == _signatures[path2]?.hash;
}
