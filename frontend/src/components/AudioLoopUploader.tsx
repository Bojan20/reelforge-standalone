import { useRef } from 'react';
import { useAudioLoopAnalyzer } from '../hooks/useAudioLoopAnalyzer';

export function AudioLoopUploader() {
  const fileInputRef = useRef<HTMLInputElement>(null);
  const { analyzeFile, isAnalyzing, error, result } = useAudioLoopAnalyzer();

  const handleFileSelect = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;

    const metadata = await analyzeFile(file);

    if (metadata) {
      console.log('🎯 READY TO SAVE TO REELFORGE MODEL:');
      console.log({
        spriteName: file.name.replace(/\.(wav|mp3|ogg)$/i, ''),
        start: 0,
        duration: Math.round(metadata.duration * 1000),
        bpm: metadata.bpm ? Math.round(metadata.bpm) : undefined,
        beatsPerBar: metadata.beatsPerBar,
        loopBars: metadata.loopBars,
      });
    }
  };

  const handleButtonClick = () => {
    fileInputRef.current?.click();
  };

  return (
    <div style={{ padding: '20px', fontFamily: 'monospace' }}>
      <h2>🎵 ReelForge Loop Analyzer</h2>

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
          padding: '10px 20px',
          fontSize: '16px',
          cursor: isAnalyzing ? 'not-allowed' : 'pointer',
          backgroundColor: isAnalyzing ? '#ccc' : '#4CAF50',
          color: 'white',
          border: 'none',
          borderRadius: '4px',
        }}
      >
        {isAnalyzing ? '⏳ Analyzing...' : '📂 Upload Audio Loop'}
      </button>

      {error && (
        <div style={{ marginTop: '20px', padding: '10px', backgroundColor: '#ffebee', color: '#c62828', borderRadius: '4px' }}>
          ❌ Error: {error}
        </div>
      )}

      {result && (
        <div style={{ marginTop: '20px', padding: '20px', backgroundColor: '#e8f5e9', borderRadius: '4px' }}>
          <h3>✅ Analysis Complete</h3>
          <table style={{ width: '100%', borderCollapse: 'collapse' }}>
            <tbody>
              <tr>
                <td style={{ padding: '8px', fontWeight: 'bold' }}>File:</td>
                <td style={{ padding: '8px' }}>{result.fileName}</td>
              </tr>
              <tr>
                <td style={{ padding: '8px', fontWeight: 'bold' }}>Duration:</td>
                <td style={{ padding: '8px' }}>{result.duration.toFixed(2)}s</td>
              </tr>
              <tr>
                <td style={{ padding: '8px', fontWeight: 'bold' }}>BPM:</td>
                <td style={{ padding: '8px' }}>
                  {result.bpm ? Math.round(result.bpm) : 'N/A'}
                </td>
              </tr>
              <tr>
                <td style={{ padding: '8px', fontWeight: 'bold' }}>Beats per Bar:</td>
                <td style={{ padding: '8px' }}>{result.beatsPerBar || 'N/A'}</td>
              </tr>
              <tr>
                <td style={{ padding: '8px', fontWeight: 'bold' }}>Loop Bars:</td>
                <td style={{ padding: '8px' }}>{result.loopBars || 'N/A'}</td>
              </tr>
              <tr>
                <td style={{ padding: '8px', fontWeight: 'bold' }}>Confidence:</td>
                <td style={{ padding: '8px' }}>
                  {(result.confidence * 100).toFixed(0)}%
                  {result.confidence < 0.7 && ' ⚠️ Low confidence - manual verification recommended'}
                </td>
              </tr>
            </tbody>
          </table>

          <div style={{ marginTop: '20px', padding: '10px', backgroundColor: '#fff3e0', borderRadius: '4px' }}>
            <h4>📋 JSON for Template:</h4>
            <pre style={{ backgroundColor: '#f5f5f5', padding: '10px', borderRadius: '4px', overflow: 'auto' }}>
              {JSON.stringify(
                {
                  soundSprites: {
                    [result.fileName.replace(/\.(wav|mp3|ogg)$/i, '')]: {
                      start: 0,
                      duration: Math.round(result.duration * 1000),
                      bpm: result.bpm ? Math.round(result.bpm) : undefined,
                      beatsPerBar: result.beatsPerBar,
                      loopBars: result.loopBars,
                    },
                  },
                },
                null,
                2
              )}
            </pre>
          </div>
        </div>
      )}
    </div>
  );
}
