// dsp_analyzer_service.dart — Signal Analyzer
import 'package:flutter/foundation.dart';

class DspAnalyzerService extends ChangeNotifier {
  static final instance = DspAnalyzerService._();
  DspAnalyzerService._();
  
  double _peakL = 0.0, _peakR = 0.0;
  double _rmsL = 0.0, _rmsR = 0.0;
  
  double get peakL => _peakL;
  double get peakR => _peakR;
  double get rmsL => _rmsL;
  double get rmsR => _rmsR;
  
  void updateMetrics(double peakL, double peakR, double rmsL, double rmsR) {
    _peakL = peakL;
    _peakR = peakR;
    _rmsL = rmsL;
    _rmsR = rmsR;
    notifyListeners();
  }
}
