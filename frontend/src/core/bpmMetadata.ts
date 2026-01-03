import { analyzeAudioLoop, type LoopAnalysisResult } from './advancedLoopAnalyzer';
import type { AudioSpriteItem, ReelForgeProject } from './types';

export interface BPMAnalysisOptions {
  minConfidence?: number;
  autoSave?: boolean;
  showWarnings?: boolean;
}

export async function analyzeAndSaveBPM(
  audioBuffer: AudioBuffer,
  spriteItem: AudioSpriteItem,
  project: ReelForgeProject,
  options: BPMAnalysisOptions = {}
): Promise<{
  success: boolean;
  analysis: LoopAnalysisResult;
  updatedSprite: AudioSpriteItem;
  warnings: string[];
}> {
  const {
    minConfidence = 0.5,
    autoSave = true,
  } = options;

  const analysis = await analyzeAudioLoop(audioBuffer);
  const warnings: string[] = [];

  if (!analysis.bpm) {
    warnings.push('BPM detection failed - no tempo found');
    return {
      success: false,
      analysis,
      updatedSprite: spriteItem,
      warnings,
    };
  }

  if (analysis.confidence < minConfidence) {
    warnings.push(
      `Low confidence (${(analysis.confidence * 100).toFixed(0)}%) - manual verification recommended`
    );
  }

  if (analysis.bpm < 70 || analysis.bpm > 160) {
    warnings.push(
      `BPM ${Math.round(analysis.bpm)} is outside typical range (70-160)`
    );
  }

  if (analysis.loopBars && ![2, 4, 8, 12, 16, 24, 32].includes(analysis.loopBars)) {
    warnings.push(
      `Loop bars ${analysis.loopBars} is unusual - common values: 4, 8, 16`
    );
  }

  const updatedSprite: AudioSpriteItem = {
    ...spriteItem,
    bpm: Math.round(analysis.bpm),
    beatsPerBar: analysis.beatsPerBar || 4,
    loopBars: analysis.loopBars || undefined,
    bpmConfidence: Math.round(analysis.confidence * 100) / 100,
  };

  if (autoSave) {
    const spriteIndex = project.spriteItems.findIndex(
      (s) => s.id === spriteItem.id
    );
    if (spriteIndex !== -1) {
      project.spriteItems[spriteIndex] = updatedSprite;
    }
  }

  console.log(`✅ BPM saved to sprite: ${spriteItem.spriteId}`, {
    bpm: updatedSprite.bpm,
    loopBars: updatedSprite.loopBars,
    confidence: updatedSprite.bpmConfidence,
  });

  return {
    success: true,
    analysis,
    updatedSprite,
    warnings,
  };
}

export function getBPMFromSprite(sprite: AudioSpriteItem): {
  bpm: number | null;
  confidence: number | null;
  hasMetadata: boolean;
} {
  return {
    bpm: sprite.bpm || null,
    confidence: sprite.bpmConfidence || null,
    hasMetadata: !!(sprite.bpm && sprite.bpmConfidence),
  };
}

export function clearBPMFromSprite(sprite: AudioSpriteItem): AudioSpriteItem {
  const { bpm, beatsPerBar, loopBars, bpmConfidence, ...rest } = sprite;
  return rest as AudioSpriteItem;
}

export function formatBPMDisplay(sprite: AudioSpriteItem): string {
  if (!sprite.bpm) return 'No BPM';

  const confidence = sprite.bpmConfidence
    ? ` (${(sprite.bpmConfidence * 100).toFixed(0)}%)`
    : '';
  const bars = sprite.loopBars ? ` · ${sprite.loopBars} bars` : '';

  return `${sprite.bpm} BPM${confidence}${bars}`;
}
