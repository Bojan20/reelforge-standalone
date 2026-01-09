// Stub methods for EngineApi - to be added to main file

  void setClipFxChainBypass(String clipId, bool bypass) {
    _ffi.setClipFxChainBypass(clipId, bypass);
  }

  void clearClipFx(String clipId) {
    _ffi.clearClipFx(clipId);
  }

  void setClipFxInputGain(String clipId, double db) {
    _ffi.setClipFxInputGain(clipId, db);
  }

  void setClipFxOutputGain(String clipId, double db) {
    _ffi.setClipFxOutputGain(clipId, db);
  }

  void setClipFxBypass(String clipId, String slotId, bool bypass) {
    _ffi.setClipFxBypass(clipId, slotId, bypass);
  }

  void setClipFxGainParams(String clipId, String slotId, double db, double pan) {
    _ffi.setClipFxGainParams(clipId, slotId, db, pan);
  }

  void setClipFxCompressorParams(String clipId, String slotId, {
    required double ratio,
    required double thresholdDb,
    required double attackMs,
    required double releaseMs,
    required double knee,
  }) {
    _ffi.setClipFxCompressorParams(clipId, slotId, ratio, thresholdDb, attackMs, releaseMs, knee);
  }

  void setClipFxLimiterParams(String clipId, String slotId, double ceilingDb) {
    _ffi.setClipFxLimiterParams(clipId, slotId, ceilingDb);
  }

  void setClipFxGateParams(String clipId, String slotId, {
    required double thresholdDb,
    required double attackMs,
    required double releaseMs,
  }) {
    _ffi.setClipFxGateParams(clipId, slotId, thresholdDb, attackMs, releaseMs);
  }

  void setClipFxSaturationParams(String clipId, String slotId, {
    required double drive,
    required int type,
  }) {
    _ffi.setClipFxSaturationParams(clipId, slotId, drive, type);
  }

  void setClipFxWetDry(String clipId, String slotId, double wetDry) {
    _ffi.setClipFxWetDry(clipId, slotId, wetDry);
  }
