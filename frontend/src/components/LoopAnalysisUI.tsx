import { useState } from 'react';
import { analyzeAudioLoop, DEFAULT_ANALYSIS_SETTINGS, type AnalysisSettings, type LoopAnalysisResult } from '../core/advancedLoopAnalyzer';
import { AudioContextManager } from '../core/AudioContextManager';

interface BPMPickerDialogProps {
  result: LoopAnalysisResult;
  onConfirm: (bpm: number, loopBars: number) => void;
  onCancel: () => void;
}

export function BPMPickerDialog({ result, onConfirm, onCancel }: BPMPickerDialogProps) {
  const [selectedIndex, setSelectedIndex] = useState(0);

  const handleConfirm = () => {
    const candidate = result.candidates[selectedIndex];
    onConfirm(candidate.bpm, candidate.loopBarsGuess);
  };

  return (
    <div className="bpm-picker-dialog">
      <div className="dialog-header">
        <h3>⚠️ Low Confidence BPM Detection</h3>
        <p>
          Confidence: {(result.confidence * 100).toFixed(0)}% 
          (threshold: {DEFAULT_ANALYSIS_SETTINGS.confidenceThreshold * 100}%)
        </p>
        <p className="help-text">
          Please verify and select the correct BPM from the candidates below:
        </p>
      </div>

      <div className="candidates-list">
        {result.candidates.slice(0, 3).map((candidate, index) => (
          <div
            key={index}
            className={`candidate-item ${selectedIndex === index ? 'selected' : ''}`}
            onClick={() => setSelectedIndex(index)}
          >
            <input
              type="radio"
              name="bpm-candidate"
              checked={selectedIndex === index}
              onChange={() => setSelectedIndex(index)}
            />
            <div className="candidate-info">
              <div className="candidate-main">
                <span className="bpm-value">{candidate.bpm.toFixed(1)} BPM</span>
                <span className="arrow">→</span>
                <span className="bars-value">{candidate.loopBarsGuess} bars</span>
                {index === 0 && <span className="badge recommended">RECOMMENDED</span>}
              </div>
              <div className="candidate-details">
                <span className="score">Score: {(candidate.score * 100).toFixed(0)}%</span>
                <span className="error">
                  Bar Fit Error: {(candidate.barFitError * 100).toFixed(1)}%
                </span>
              </div>
            </div>
          </div>
        ))}
      </div>

      <details className="debug-section">
        <summary>🔍 Debug Information</summary>
        <div className="debug-content">
          <div className="debug-row">
            <span>Sample Rate:</span>
            <span>{result.debug.sampleRate} Hz</span>
          </div>
          <div className="debug-row">
            <span>Raw Duration:</span>
            <span>{result.debug.rawDurationSec.toFixed(3)}s</span>
          </div>
          <div className="debug-row">
            <span>Effective Duration:</span>
            <span>{result.debug.effectiveDurationSec.toFixed(3)}s</span>
          </div>
          <div className="debug-notes">
            <strong>Analysis Notes:</strong>
            <ul>
              {result.debug.notes.map((note, i) => (
                <li key={i}>{note}</li>
              ))}
            </ul>
          </div>
        </div>
      </details>

      <div className="dialog-actions">
        <button className="btn-cancel" onClick={onCancel}>
          Cancel
        </button>
        <button className="btn-confirm" onClick={handleConfirm}>
          Confirm Selection
        </button>
      </div>
    </div>
  );
}

interface LoopAnalysisUIProps {
  audioFile: File;
  onAnalysisComplete: (bpm: number, loopBars: number, confidence: number) => void;
}

export function LoopAnalysisUI({ audioFile, onAnalysisComplete }: LoopAnalysisUIProps) {
  const [analyzing, setAnalyzing] = useState(false);
  const [result, setResult] = useState<LoopAnalysisResult | null>(null);
  const [showPicker, setShowPicker] = useState(false);
  const [settings, setSettings] = useState<AnalysisSettings>(DEFAULT_ANALYSIS_SETTINGS);

  const handleAnalyze = async () => {
    setAnalyzing(true);
    try {
      const arrayBuffer = await audioFile.arrayBuffer();
      const audioBuffer = await AudioContextManager.decodeAudioData(arrayBuffer);

      const analysisResult = analyzeAudioLoop(audioBuffer, settings);
      setResult(analysisResult);

      if (analysisResult.confidence < settings.confidenceThreshold) {
        setShowPicker(true);
      } else {
        onAnalysisComplete(
          analysisResult.bpm!,
          analysisResult.loopBars!,
          analysisResult.confidence
        );
      }
    } catch (error) {
      console.error('Analysis failed:', error);
      alert('Failed to analyze audio file');
    } finally {
      setAnalyzing(false);
    }
  };

  const handleConfirm = (bpm: number, loopBars: number) => {
    setShowPicker(false);
    onAnalysisComplete(bpm, loopBars, result!.confidence);
  };

  const handleCancel = () => {
    setShowPicker(false);
    setResult(null);
  };

  return (
    <div className="loop-analysis-ui">
      <div className="settings-panel">
        <h4>Analysis Settings</h4>
        
        <div className="setting-row">
          <label>BPM Range:</label>
          <input
            type="number"
            value={settings.bpmMin}
            onChange={(e) => setSettings({ ...settings, bpmMin: Number(e.target.value) })}
            min={40}
            max={200}
          />
          <span>to</span>
          <input
            type="number"
            value={settings.bpmMax}
            onChange={(e) => setSettings({ ...settings, bpmMax: Number(e.target.value) })}
            min={40}
            max={200}
          />
        </div>

        <div className="setting-row">
          <label>Allowed Loop Bars:</label>
          <div className="checkbox-group">
            {[2, 4, 8, 16, 32, 64].map((bars) => (
              <label key={bars}>
                <input
                  type="checkbox"
                  checked={settings.allowedLoopBars.includes(bars)}
                  onChange={(e) => {
                    if (e.target.checked) {
                      setSettings({
                        ...settings,
                        allowedLoopBars: [...settings.allowedLoopBars, bars].sort((a, b) => a - b),
                      });
                    } else {
                      setSettings({
                        ...settings,
                        allowedLoopBars: settings.allowedLoopBars.filter((b) => b !== bars),
                      });
                    }
                  }}
                />
                {bars}
              </label>
            ))}
          </div>
        </div>

        <div className="setting-row">
          <label>Confidence Threshold:</label>
          <input
            type="range"
            min={0}
            max={1}
            step={0.05}
            value={settings.confidenceThreshold}
            onChange={(e) =>
              setSettings({ ...settings, confidenceThreshold: Number(e.target.value) })
            }
          />
          <span>{(settings.confidenceThreshold * 100).toFixed(0)}%</span>
        </div>

        <div className="setting-row">
          <label>Max Trim Leading (sec):</label>
          <input
            type="number"
            value={settings.maxTrimLeadingSec}
            onChange={(e) =>
              setSettings({ ...settings, maxTrimLeadingSec: Number(e.target.value) })
            }
            min={0}
            max={2}
            step={0.1}
          />
        </div>

        <div className="setting-row">
          <label>Max Trim Tail (sec):</label>
          <input
            type="number"
            value={settings.maxTrimTailSec}
            onChange={(e) =>
              setSettings({ ...settings, maxTrimTailSec: Number(e.target.value) })
            }
            min={0}
            max={5}
            step={0.1}
          />
        </div>
      </div>

      <button
        className="btn-analyze"
        onClick={handleAnalyze}
        disabled={analyzing}
      >
        {analyzing ? 'Analyzing...' : 'Analyze Loop'}
      </button>

      {result && !showPicker && (
        <div className="result-display">
          <h4>✅ Analysis Complete</h4>
          <div className="result-main">
            <div className="result-item">
              <span className="label">BPM:</span>
              <span className="value">{result.bpm?.toFixed(1)}</span>
            </div>
            <div className="result-item">
              <span className="label">Loop Bars:</span>
              <span className="value">{result.loopBars}</span>
            </div>
            <div className="result-item">
              <span className="label">Confidence:</span>
              <span className={`value ${result.confidence >= 0.7 ? 'high' : 'low'}`}>
                {(result.confidence * 100).toFixed(0)}%
              </span>
            </div>
          </div>
        </div>
      )}

      {showPicker && result && (
        <BPMPickerDialog
          result={result}
          onConfirm={handleConfirm}
          onCancel={handleCancel}
        />
      )}
    </div>
  );
}

export const loopAnalysisStyles = `
.loop-analysis-ui {
  padding: 20px;
  max-width: 600px;
}

.settings-panel {
  background: #f5f5f5;
  padding: 15px;
  border-radius: 8px;
  margin-bottom: 20px;
}

.settings-panel h4 {
  margin-top: 0;
  margin-bottom: 15px;
}

.setting-row {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 12px;
}

.setting-row label {
  min-width: 150px;
  font-weight: 500;
}

.setting-row input[type="number"] {
  width: 80px;
  padding: 5px;
}

.setting-row input[type="range"] {
  flex: 1;
}

.checkbox-group {
  display: flex;
  gap: 15px;
  flex-wrap: wrap;
}

.checkbox-group label {
  display: flex;
  align-items: center;
  gap: 5px;
  min-width: auto;
}

.btn-analyze {
  width: 100%;
  padding: 12px;
  background: #007bff;
  color: white;
  border: none;
  border-radius: 6px;
  font-size: 16px;
  font-weight: 600;
  cursor: pointer;
  transition: background 0.2s;
}

.btn-analyze:hover:not(:disabled) {
  background: #0056b3;
}

.btn-analyze:disabled {
  background: #ccc;
  cursor: not-allowed;
}

.result-display {
  margin-top: 20px;
  padding: 15px;
  background: #e8f5e9;
  border-radius: 8px;
}

.result-main {
  display: flex;
  flex-direction: column;
  gap: 10px;
  margin-top: 10px;
}

.result-item {
  display: flex;
  justify-content: space-between;
  font-size: 16px;
}

.result-item .label {
  font-weight: 500;
}

.result-item .value {
  font-weight: 700;
  font-size: 18px;
}

.result-item .value.high {
  color: #2e7d32;
}

.result-item .value.low {
  color: #f57c00;
}

.bpm-picker-dialog {
  position: fixed;
  top: 50%;
  left: 50%;
  transform: translate(-50%, -50%);
  background: white;
  padding: 25px;
  border-radius: 12px;
  box-shadow: 0 4px 20px rgba(0, 0, 0, 0.3);
  max-width: 500px;
  width: 90%;
  z-index: 1000;
}

.dialog-header h3 {
  margin: 0 0 10px 0;
  color: #f57c00;
}

.dialog-header p {
  margin: 5px 0;
  color: #666;
}

.help-text {
  font-weight: 500;
  color: #333 !important;
  margin-top: 15px !important;
}

.candidates-list {
  margin: 20px 0;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.candidate-item {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  padding: 12px;
  border: 2px solid #ddd;
  border-radius: 8px;
  cursor: pointer;
  transition: all 0.2s;
}

.candidate-item:hover {
  border-color: #007bff;
  background: #f8f9fa;
}

.candidate-item.selected {
  border-color: #007bff;
  background: #e7f3ff;
}

.candidate-info {
  flex: 1;
}

.candidate-main {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 5px;
}

.bpm-value {
  font-size: 18px;
  font-weight: 700;
  color: #007bff;
}

.arrow {
  color: #999;
}

.bars-value {
  font-size: 16px;
  font-weight: 600;
}

.badge.recommended {
  background: #4caf50;
  color: white;
  padding: 2px 8px;
  border-radius: 4px;
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
}

.candidate-details {
  display: flex;
  gap: 15px;
  font-size: 13px;
  color: #666;
}

.debug-section {
  margin: 20px 0;
  padding: 10px;
  background: #f5f5f5;
  border-radius: 6px;
}

.debug-section summary {
  cursor: pointer;
  font-weight: 600;
  user-select: none;
}

.debug-content {
  margin-top: 10px;
  font-size: 13px;
}

.debug-row {
  display: flex;
  justify-content: space-between;
  padding: 5px 0;
  border-bottom: 1px solid #ddd;
}

.debug-notes {
  margin-top: 10px;
}

.debug-notes ul {
  margin: 5px 0;
  padding-left: 20px;
}

.debug-notes li {
  margin: 3px 0;
  color: #555;
}

.dialog-actions {
  display: flex;
  gap: 10px;
  justify-content: flex-end;
  margin-top: 20px;
}

.btn-cancel,
.btn-confirm {
  padding: 10px 20px;
  border: none;
  border-radius: 6px;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s;
}

.btn-cancel {
  background: #f5f5f5;
  color: #333;
}

.btn-cancel:hover {
  background: #e0e0e0;
}

.btn-confirm {
  background: #007bff;
  color: white;
}

.btn-confirm:hover {
  background: #0056b3;
}
`;
