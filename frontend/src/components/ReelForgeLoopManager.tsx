import { useRef, useState } from 'react';
import { useAudioLoopAnalyzer } from '../hooks/useAudioLoopAnalyzer';
import {
  ReelForgeModelIntegration,
  type ReelForgeTemplate,
} from '../utils/reelforgeModelIntegration';

export function ReelForgeLoopManager() {
  const fileInputRef = useRef<HTMLInputElement>(null);
  const { analyzeFile, isAnalyzing, error, result, needsUserConfirmation, updateMetadataWithCandidate } = useAudioLoopAnalyzer();
  const [template, setTemplate] = useState<ReelForgeTemplate>({
    soundSprites: {},
  });
  const [showCandidatePicker, setShowCandidatePicker] = useState(false);
  const [pendingFile, setPendingFile] = useState<string | null>(null);

  const handleFileSelect = async (
    event: React.ChangeEvent<HTMLInputElement>
  ) => {
    const file = event.target.files?.[0];
    if (!file) return;

    const metadata = await analyzeFile(file);

    if (metadata) {
      if (needsUserConfirmation && metadata.candidates && metadata.candidates.length > 1) {
        setPendingFile(file.name);
        setShowCandidatePicker(true);
      } else {
        addToTemplate(file.name, metadata);
      }
    }
  };

  const addToTemplate = (fileName: string, metadata: any) => {
    const spriteName = fileName.replace(/\.(wav|mp3|ogg)$/i, '');
    const sprite = ReelForgeModelIntegration.createSoundSpriteFromAnalysis(metadata);

    const updatedTemplate = ReelForgeModelIntegration.updateTemplateWithSprite(
      template,
      spriteName,
      sprite
    );

    setTemplate(updatedTemplate);
    console.log('✅ Added to template:', spriteName);
  };

  const handleCandidateSelect = (candidateIndex: number) => {
    const updatedMetadata = updateMetadataWithCandidate(candidateIndex);
    if (updatedMetadata && pendingFile) {
      addToTemplate(pendingFile, updatedMetadata);
    }
    setShowCandidatePicker(false);
    setPendingFile(null);
  };

  const handleCancelPicker = () => {
    setShowCandidatePicker(false);
    setPendingFile(null);
  };

  const handleSaveTemplate = () => {
    ReelForgeModelIntegration.saveTemplateToJSON(template, 'reelforge-template.json');
  };

  const handleButtonClick = () => {
    fileInputRef.current?.click();
  };

  return (
    <div style={{ padding: '20px', fontFamily: 'monospace', maxWidth: '800px' }}>
      <h1>🎮 ReelForge Loop Manager</h1>

      <div style={{ marginBottom: '20px' }}>
        <input
          ref={fileInputRef}
          type="file"
          accept="audio/*"
          onChange={handleFileSelect}
          style={{ display: 'none' }}
        />

        <button
          onClick={handleButtonClick}
          disabled={isAnalyzing}
          style={{
            padding: '12px 24px',
            fontSize: '16px',
            cursor: isAnalyzing ? 'not-allowed' : 'pointer',
            backgroundColor: isAnalyzing ? '#ccc' : '#4CAF50',
            color: 'white',
            border: 'none',
            borderRadius: '4px',
            marginRight: '10px',
          }}
        >
          {isAnalyzing ? '⏳ Analyzing...' : '📂 Add Audio Loop'}
        </button>

        <button
          onClick={handleSaveTemplate}
          disabled={Object.keys(template.soundSprites).length === 0}
          style={{
            padding: '12px 24px',
            fontSize: '16px',
            cursor:
              Object.keys(template.soundSprites).length === 0
                ? 'not-allowed'
                : 'pointer',
            backgroundColor:
              Object.keys(template.soundSprites).length === 0
                ? '#ccc'
                : '#2196F3',
            color: 'white',
            border: 'none',
            borderRadius: '4px',
          }}
        >
          💾 Save Template JSON
        </button>
      </div>

      {error && (
        <div
          style={{
            marginTop: '20px',
            padding: '10px',
            backgroundColor: '#ffebee',
            color: '#c62828',
            borderRadius: '4px',
          }}
        >
          ❌ Error: {error}
        </div>
      )}

      {showCandidatePicker && result && result.candidates && (
        <div
          style={{
            position: 'fixed',
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            backgroundColor: 'rgba(0, 0, 0, 0.5)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            zIndex: 1000,
          }}
        >
          <div
            style={{
              backgroundColor: 'white',
              padding: '30px',
              borderRadius: '12px',
              maxWidth: '600px',
              width: '90%',
              boxShadow: '0 4px 20px rgba(0, 0, 0, 0.3)',
            }}
          >
            <h3 style={{ marginTop: 0, color: '#f57c00' }}>
              ⚠️ Low Confidence BPM Detection
            </h3>
            <p style={{ color: '#666', marginBottom: '5px' }}>
              Confidence: {(result.confidence * 100).toFixed(0)}% (threshold: 70%)
            </p>
            <p style={{ fontWeight: 500, color: '#333', marginBottom: '20px' }}>
              Please verify and select the correct BPM:
            </p>

            <div style={{ display: 'flex', flexDirection: 'column', gap: '12px', marginBottom: '20px' }}>
              {result.candidates.slice(0, 3).map((candidate, index) => (
                <div
                  key={index}
                  onClick={() => handleCandidateSelect(index)}
                  style={{
                    padding: '15px',
                    border: '2px solid #ddd',
                    borderRadius: '8px',
                    cursor: 'pointer',
                    transition: 'all 0.2s',
                    backgroundColor: '#fff',
                  }}
                  onMouseEnter={(e) => {
                    e.currentTarget.style.borderColor = '#007bff';
                    e.currentTarget.style.backgroundColor = '#f8f9fa';
                  }}
                  onMouseLeave={(e) => {
                    e.currentTarget.style.borderColor = '#ddd';
                    e.currentTarget.style.backgroundColor = '#fff';
                  }}
                >
                  <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '5px' }}>
                    <span style={{ fontSize: '18px', fontWeight: 700, color: '#007bff' }}>
                      {candidate.bpm.toFixed(1)} BPM
                    </span>
                    <span style={{ color: '#999' }}>→</span>
                    <span style={{ fontSize: '16px', fontWeight: 600 }}>
                      {candidate.loopBarsGuess} bars
                    </span>
                    {index === 0 && (
                      <span
                        style={{
                          background: '#4caf50',
                          color: 'white',
                          padding: '2px 8px',
                          borderRadius: '4px',
                          fontSize: '11px',
                          fontWeight: 600,
                        }}
                      >
                        RECOMMENDED
                      </span>
                    )}
                  </div>
                  <div style={{ fontSize: '13px', color: '#666', display: 'flex', gap: '15px' }}>
                    <span>Score: {(candidate.score * 100).toFixed(0)}%</span>
                    <span>Bar Fit Error: {(candidate.barFitError * 100).toFixed(1)}%</span>
                  </div>
                </div>
              ))}
            </div>

            {result.debug && (
              <details style={{ marginBottom: '20px', padding: '10px', backgroundColor: '#f5f5f5', borderRadius: '6px' }}>
                <summary style={{ cursor: 'pointer', fontWeight: 600, userSelect: 'none' }}>
                  🔍 Debug Information
                </summary>
                <div style={{ marginTop: '10px', fontSize: '13px' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', padding: '5px 0', borderBottom: '1px solid #ddd' }}>
                    <span>Sample Rate:</span>
                    <span>{result.debug.sampleRate} Hz</span>
                  </div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', padding: '5px 0', borderBottom: '1px solid #ddd' }}>
                    <span>Raw Duration:</span>
                    <span>{result.debug.rawDurationSec.toFixed(3)}s</span>
                  </div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', padding: '5px 0', borderBottom: '1px solid #ddd' }}>
                    <span>Effective Duration:</span>
                    <span>{result.debug.effectiveDurationSec.toFixed(3)}s</span>
                  </div>
                  <div style={{ marginTop: '10px' }}>
                    <strong>Analysis Notes:</strong>
                    <ul style={{ margin: '5px 0', paddingLeft: '20px' }}>
                      {result.debug.notes.map((note, i) => (
                        <li key={i} style={{ margin: '3px 0', color: '#555' }}>{note}</li>
                      ))}
                    </ul>
                  </div>
                </div>
              </details>
            )}

            <div style={{ display: 'flex', gap: '10px', justifyContent: 'flex-end' }}>
              <button
                onClick={handleCancelPicker}
                style={{
                  padding: '10px 20px',
                  border: 'none',
                  borderRadius: '6px',
                  fontWeight: 600,
                  cursor: 'pointer',
                  backgroundColor: '#f5f5f5',
                  color: '#333',
                }}
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}

      {result && !showCandidatePicker && (
        <div
          style={{
            marginTop: '20px',
            padding: '20px',
            backgroundColor: result.confidence >= 0.7 ? '#e8f5e9' : '#fff3e0',
            borderRadius: '4px',
          }}
        >
          <h3>✅ Latest Analysis</h3>
          <table style={{ width: '100%', borderCollapse: 'collapse' }}>
            <tbody>
              <tr>
                <td style={{ padding: '8px', fontWeight: 'bold' }}>File:</td>
                <td style={{ padding: '8px' }}>{result.fileName}</td>
              </tr>
              <tr>
                <td style={{ padding: '8px', fontWeight: 'bold' }}>BPM:</td>
                <td style={{ padding: '8px' }}>
                  {result.bpm ? result.bpm.toFixed(1) : 'N/A'}
                </td>
              </tr>
              <tr>
                <td style={{ padding: '8px', fontWeight: 'bold' }}>
                  Loop Bars:
                </td>
                <td style={{ padding: '8px' }}>{result.loopBars || 'N/A'}</td>
              </tr>
              <tr>
                <td style={{ padding: '8px', fontWeight: 'bold' }}>
                  Confidence:
                </td>
                <td style={{ padding: '8px' }}>
                  {(result.confidence * 100).toFixed(0)}%
                  {result.confidence < 0.7 && ' ⚠️ Low - verified manually'}
                </td>
              </tr>
            </tbody>
          </table>

          {result.candidates && result.candidates.length > 1 && (
            <details style={{ marginTop: '15px' }}>
              <summary style={{ cursor: 'pointer', fontWeight: 600 }}>
                📊 All Candidates ({result.candidates.length})
              </summary>
              <div style={{ marginTop: '10px' }}>
                {result.candidates.map((c, i) => (
                  <div key={i} style={{ padding: '5px 0', fontSize: '14px', borderBottom: '1px solid #ddd' }}>
                    {i + 1}. {c.bpm.toFixed(1)} BPM → {c.loopBarsGuess} bars
                    (score: {(c.score * 100).toFixed(0)}%, error: {(c.barFitError * 100).toFixed(1)}%)
                  </div>
                ))}
              </div>
            </details>
          )}
        </div>
      )}

      {Object.keys(template.soundSprites).length > 0 && (
        <div
          style={{
            marginTop: '20px',
            padding: '20px',
            backgroundColor: '#e3f2fd',
            borderRadius: '4px',
          }}
        >
          <h3>📋 Current Template</h3>
          <div style={{ marginBottom: '10px' }}>
            <strong>Sprites:</strong> {Object.keys(template.soundSprites).length}
          </div>
          <pre
            style={{
              backgroundColor: '#f5f5f5',
              padding: '10px',
              borderRadius: '4px',
              overflow: 'auto',
              maxHeight: '300px',
            }}
          >
            {JSON.stringify(template, null, 2)}
          </pre>
        </div>
      )}
    </div>
  );
}
