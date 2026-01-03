/**
 * Audio Buffer to WAV Encoder
 *
 * Converts AudioBuffer to valid WAV file format.
 * This is needed for creating blob URLs that can be decoded by Web Audio API.
 *
 * WAV format: RIFF header + fmt chunk + data chunk
 * - 16-bit PCM encoding (industry standard)
 * - Supports mono and stereo
 *
 * @module utils/audioBufferToWav
 */

/**
 * Encode AudioBuffer to WAV ArrayBuffer
 *
 * @param audioBuffer - The AudioBuffer to encode
 * @returns ArrayBuffer containing valid WAV file data
 */
export function audioBufferToWav(audioBuffer: AudioBuffer): ArrayBuffer {
  const numChannels = audioBuffer.numberOfChannels;
  const sampleRate = audioBuffer.sampleRate;
  const bitsPerSample = 16; // 16-bit PCM
  const bytesPerSample = bitsPerSample / 8;
  const blockAlign = numChannels * bytesPerSample;
  const byteRate = sampleRate * blockAlign;
  const numSamples = audioBuffer.length;
  const dataSize = numSamples * blockAlign;

  // WAV file = 44 byte header + data
  const wavBuffer = new ArrayBuffer(44 + dataSize);
  const view = new DataView(wavBuffer);

  // RIFF chunk descriptor
  writeString(view, 0, 'RIFF');
  view.setUint32(4, 36 + dataSize, true); // File size - 8
  writeString(view, 8, 'WAVE');

  // fmt sub-chunk
  writeString(view, 12, 'fmt ');
  view.setUint32(16, 16, true); // Subchunk1Size (16 for PCM)
  view.setUint16(20, 1, true);  // AudioFormat (1 = PCM)
  view.setUint16(22, numChannels, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, byteRate, true);
  view.setUint16(32, blockAlign, true);
  view.setUint16(34, bitsPerSample, true);

  // data sub-chunk
  writeString(view, 36, 'data');
  view.setUint32(40, dataSize, true);

  // Interleave channels and write samples
  const offset = 44;

  if (numChannels === 1) {
    // Mono - direct copy
    const channelData = audioBuffer.getChannelData(0);
    for (let i = 0; i < numSamples; i++) {
      const sample = Math.max(-1, Math.min(1, channelData[i]));
      const intSample = sample < 0 ? sample * 0x8000 : sample * 0x7FFF;
      view.setInt16(offset + i * 2, intSample, true);
    }
  } else if (numChannels === 2) {
    // Stereo - interleave L/R
    const left = audioBuffer.getChannelData(0);
    const right = audioBuffer.getChannelData(1);
    for (let i = 0; i < numSamples; i++) {
      const sampleL = Math.max(-1, Math.min(1, left[i]));
      const sampleR = Math.max(-1, Math.min(1, right[i]));
      const intL = sampleL < 0 ? sampleL * 0x8000 : sampleL * 0x7FFF;
      const intR = sampleR < 0 ? sampleR * 0x8000 : sampleR * 0x7FFF;
      view.setInt16(offset + i * 4, intL, true);
      view.setInt16(offset + i * 4 + 2, intR, true);
    }
  } else {
    // Multi-channel - interleave all
    const channels: Float32Array[] = [];
    for (let ch = 0; ch < numChannels; ch++) {
      channels.push(audioBuffer.getChannelData(ch));
    }
    for (let i = 0; i < numSamples; i++) {
      for (let ch = 0; ch < numChannels; ch++) {
        const sample = Math.max(-1, Math.min(1, channels[ch][i]));
        const intSample = sample < 0 ? sample * 0x8000 : sample * 0x7FFF;
        view.setInt16(offset + (i * numChannels + ch) * 2, intSample, true);
      }
    }
  }

  return wavBuffer;
}

/**
 * Write ASCII string to DataView
 */
function writeString(view: DataView, offset: number, str: string): void {
  for (let i = 0; i < str.length; i++) {
    view.setUint8(offset + i, str.charCodeAt(i));
  }
}

/**
 * Create a blob URL from AudioBuffer
 * This URL can be fetched and decoded by Web Audio API
 *
 * @param audioBuffer - The AudioBuffer to convert
 * @returns A blob URL pointing to valid WAV data
 */
export function createAudioBlobUrl(audioBuffer: AudioBuffer): string {
  const wavBuffer = audioBufferToWav(audioBuffer);
  const blob = new Blob([wavBuffer], { type: 'audio/wav' });
  return URL.createObjectURL(blob);
}

export default audioBufferToWav;
