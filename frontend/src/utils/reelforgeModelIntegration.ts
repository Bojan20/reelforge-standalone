import type { AudioLoopMetadata } from '../hooks/useAudioLoopAnalyzer';

export interface SoundSprite {
  start: number;
  duration: number;
  bpm?: number;
  beatsPerBar?: number;
  loopBars?: number;
}

export interface ReelForgeTemplate {
  soundSprites: Record<string, SoundSprite>;
}

export class ReelForgeModelIntegration {
  static createSoundSpriteFromAnalysis(
    metadata: AudioLoopMetadata,
    spriteName?: string
  ): SoundSprite {
    const name = spriteName || metadata.fileName.replace(/\.(wav|mp3|ogg)$/i, '');

    const sprite: SoundSprite = {
      start: 0,
      duration: Math.round(metadata.duration * 1000),
    };

    if (metadata.bpm && metadata.confidence > 0.5) {
      sprite.bpm = Math.round(metadata.bpm);
      sprite.beatsPerBar = metadata.beatsPerBar || 4;
      sprite.loopBars = metadata.loopBars || undefined;
    }

    console.log(`✅ Created sound sprite: ${name}`, sprite);

    return sprite;
  }

  static updateTemplateWithSprite(
    template: ReelForgeTemplate,
    spriteName: string,
    sprite: SoundSprite
  ): ReelForgeTemplate {
    return {
      ...template,
      soundSprites: {
        ...template.soundSprites,
        [spriteName]: sprite,
      },
    };
  }

  static async saveTemplateToJSON(
    template: ReelForgeTemplate,
    filePath: string
  ): Promise<void> {
    const json = JSON.stringify(template, null, 2);

    console.log('💾 Saving template to:', filePath);
    console.log(json);

    const blob = new Blob([json], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filePath;
    a.click();
    URL.revokeObjectURL(url);
  }

  static validateSoundSprite(sprite: SoundSprite): {
    valid: boolean;
    warnings: string[];
  } {
    const warnings: string[] = [];

    if (sprite.bpm && (sprite.bpm < 70 || sprite.bpm > 160)) {
      warnings.push(
        `BPM ${sprite.bpm} is outside typical range (70-160). Verify manually.`
      );
    }

    if (
      sprite.loopBars &&
      ![2, 4, 8, 12, 16, 24, 32].includes(sprite.loopBars)
    ) {
      warnings.push(
        `Loop bars ${sprite.loopBars} is unusual. Common values: 4, 8, 16.`
      );
    }

    if (sprite.duration < 1000) {
      warnings.push(`Duration ${sprite.duration}ms is very short for a loop.`);
    }

    const valid = warnings.length === 0;

    return { valid, warnings };
  }
}

export function exampleUsage() {
  const template: ReelForgeTemplate = {
    soundSprites: {},
  };

  const metadata: AudioLoopMetadata = {
    fileName: 'BonusMusicLoop1.wav',
    duration: 15.98,
    bpm: 120,
    beatsPerBar: 4,
    loopBars: 8,
    confidence: 0.87,
    audioBuffer: {} as AudioBuffer,
  };

  const sprite = ReelForgeModelIntegration.createSoundSpriteFromAnalysis(
    metadata,
    's_BonusMusicLoop1'
  );

  const updatedTemplate = ReelForgeModelIntegration.updateTemplateWithSprite(
    template,
    's_BonusMusicLoop1',
    sprite
  );

  const validation = ReelForgeModelIntegration.validateSoundSprite(sprite);

  if (!validation.valid) {
    console.warn('⚠️ Validation warnings:', validation.warnings);
  }

  ReelForgeModelIntegration.saveTemplateToJSON(
    updatedTemplate,
    'template.json'
  );
}
