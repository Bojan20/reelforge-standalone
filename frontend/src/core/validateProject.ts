import type { ReelForgeProject, AudioFileObject, Command, PlayCommand, StopCommand, FadeCommand, PauseCommand } from './types';

/** Type guard: check if command has soundId property */
function hasSoundId(cmd: Command): cmd is PlayCommand | StopCommand | FadeCommand | PauseCommand {
  return cmd.type === 'Play' || cmd.type === 'Stop' || cmd.type === 'Fade' || cmd.type === 'Pause';
}

export const defaultBuses = [
  { id: 'master' as const, name: 'Master', volume: 1 },
  { id: 'music' as const, name: 'Music', volume: 1 },
  { id: 'sfx' as const, name: 'SFX', volume: 1 },
  { id: 'ambience' as const, name: 'Ambience', volume: 1 },
  { id: 'voice' as const, name: 'Voice', volume: 1 }
];

export function ensureProjectBuses(project: ReelForgeProject): ReelForgeProject {
  if (!project.buses || project.buses.length === 0) {
    return {
      ...project,
      buses: defaultBuses
    };
  }

  // Filter out invalid/old buses (e.g., 'ui' bus)
  const validBusIds = new Set(defaultBuses.map(b => b.id));
  const validBuses = project.buses.filter(b => validBusIds.has(b.id));

  const existingBusIds = new Set(validBuses.map(b => b.id));
  const missingBuses = defaultBuses.filter(b => !existingBusIds.has(b.id));

  if (missingBuses.length > 0 || validBuses.length < project.buses.length) {
    return {
      ...project,
      buses: [...validBuses, ...missingBuses]
    };
  }

  return project;
}

/** Details for validation issues - discriminated by code */
export type ValidationDetails =
  | { event: string; soundId: string }
  | { spriteId: string; soundId: string }
  | { spriteId: string; count: number }
  | { eventName: string; count: number };

export interface ValidationIssue {
  type: 'error' | 'warning';
  code: string;
  message: string;
  details?: ValidationDetails;
  autoFixable?: boolean;
}

export interface AutoFixResult {
  fixed: boolean;
  message: string;
  addedSprites?: Array<{ spriteId: string; soundId: string }>;
  connectedSounds?: Array<{ soundId: string; fileName: string }>;
}

export function validateProject(
  project: ReelForgeProject,
  audioFiles: AudioFileObject[]
): ValidationIssue[] {
  const issues: ValidationIssue[] = [];

  // 1) Check if project has any events
  if (!project.events.length) {
    issues.push({
      type: 'warning',
      code: 'NO_EVENTS',
      message: 'Project has no events.'
    });
  }

  // 2) Build sets for validation
  const importedFiles = new Set(audioFiles.map(f => f.name));

  // 3) Check event commands for missing sound references
  const missingSoundIds = new Set<string>();
  for (const ev of project.events) {
    for (const cmd of ev.commands) {
      if (hasSoundId(cmd)) {
        const soundId = cmd.soundId;
        if (soundId && !importedFiles.has(soundId)) {
          missingSoundIds.add(soundId);
          issues.push({
            type: 'error',
            code: 'MISSING_SOUND',
            message: `Event "${ev.eventName}" uses soundId "${soundId}" which is not imported.`,
            details: { event: ev.eventName, soundId },
            autoFixable: false
          });
        }
      }
    }
  }

  // 4) Check sprites without imported audio files
  for (const s of project.spriteItems) {
    if (!importedFiles.has(s.soundId)) {
      issues.push({
        type: 'warning',
        code: 'SPRITE_NO_FILE',
        message: `Sprite "${s.spriteId}" (soundId "${s.soundId}") has no imported audio file.`,
        details: { spriteId: s.spriteId, soundId: s.soundId }
      });
    }
  }

  // 5) Check for duplicate sprite IDs
  const spriteIdCounts = new Map<string, number>();
  for (const s of project.spriteItems) {
    spriteIdCounts.set(s.spriteId, (spriteIdCounts.get(s.spriteId) || 0) + 1);
  }
  for (const [spriteId, count] of spriteIdCounts.entries()) {
    if (count > 1) {
      issues.push({
        type: 'error',
        code: 'DUPLICATE_SPRITE',
        message: `Sprite ID "${spriteId}" is used ${count} times.`,
        details: { spriteId, count }
      });
    }
  }

  // 6) Check for duplicate event names
  const eventNameCounts = new Map<string, number>();
  for (const ev of project.events) {
    eventNameCounts.set(ev.eventName, (eventNameCounts.get(ev.eventName) || 0) + 1);
  }
  for (const [eventName, count] of eventNameCounts.entries()) {
    if (count > 1) {
      issues.push({
        type: 'error',
        code: 'DUPLICATE_EVENT',
        message: `Event name "${eventName}" is used ${count} times.`,
        details: { eventName, count }
      });
    }
  }

  return issues;
}

export function autoFixMissingSprites(
  project: ReelForgeProject,
  audioFiles: AudioFileObject[]
): AutoFixResult {
  const spriteIds = new Set(project.spriteItems.map(s => s.spriteId));
  const importedFileNames = new Set(audioFiles.map(f => f.name));
  const missingSpriteIds = new Set<string>();

  // Find all missing sprite IDs (spriteId is not a standard field, but may exist in legacy data)
  for (const ev of project.events) {
    for (const cmd of ev.commands) {
      if (hasSoundId(cmd)) {
        // Check for legacy spriteId field using soundId as identifier
        const spriteId = cmd.soundId;
        if (spriteId && !spriteIds.has(spriteId)) {
          missingSpriteIds.add(spriteId);
        }
      }
    }
  }

  if (missingSpriteIds.size === 0) {
    return {
      fixed: false,
      message: 'No missing sprites to fix.'
    };
  }

  const addedSprites: Array<{ spriteId: string; soundId: string }> = [];

  // Try to auto-create sprites for missing IDs
  for (const spriteId of missingSpriteIds) {
    // Strategy 1: Check if there's an imported file with the same name as spriteId
    if (importedFileNames.has(spriteId)) {
      project.spriteItems.push({
        id: `sprite_${Date.now()}_${Math.random().toString(36).substring(2, 11)}`,
        spriteId,
        soundId: spriteId,
        startTime: 0,
        duration: 0,
        tags: ['auto-generated']
      });
      addedSprites.push({ spriteId, soundId: spriteId });
      continue;
    }

    // Strategy 2: Try to find a similar file name (case-insensitive, with/without extension)
    const lowerSpriteId = spriteId.toLowerCase();
    let foundMatch = false;

    for (const audioFile of audioFiles) {
      const fileName = audioFile.name;
      const fileNameLower = fileName.toLowerCase();
      const fileNameWithoutExt = fileName.replace(/\.(mp3|wav|ogg|m4a)$/i, '').toLowerCase();

      if (fileNameLower === lowerSpriteId || fileNameWithoutExt === lowerSpriteId) {
        project.spriteItems.push({
          id: `sprite_${Date.now()}_${Math.random().toString(36).substring(2, 11)}`,
          spriteId,
          soundId: fileName,
          startTime: 0,
          duration: 0,
          tags: ['auto-generated']
        });
        addedSprites.push({ spriteId, soundId: fileName });
        foundMatch = true;
        break;
      }
    }

    // Strategy 3: If no match found, create sprite anyway but it will show as missing file
    if (!foundMatch) {
      project.spriteItems.push({
        id: `sprite_${Date.now()}_${Math.random().toString(36).substring(2, 11)}`,
        spriteId,
        soundId: spriteId,
        startTime: 0,
        duration: 0,
        tags: ['auto-generated', 'missing-file']
      });
      addedSprites.push({ spriteId, soundId: spriteId });
    }
  }

  return {
    fixed: true,
    message: `Auto-fixed ${addedSprites.length} missing sprite(s).`,
    addedSprites
  };
}

export function autoFixMissingSounds(
  project: ReelForgeProject,
  audioFiles: AudioFileObject[]
): AutoFixResult {
  const importedFileNames = new Set(audioFiles.map(f => f.name));
  const missingSoundIds = new Set<string>();

  // Find all missing sound IDs in commands
  for (const ev of project.events) {
    for (const cmd of ev.commands) {
      if (hasSoundId(cmd)) {
        const soundId = cmd.soundId;
        if (soundId && !importedFileNames.has(soundId)) {
          missingSoundIds.add(soundId);
        }
      }
    }
  }

  if (missingSoundIds.size === 0) {
    return {
      fixed: false,
      message: 'No missing sounds to fix.'
    };
  }

  const connectedSounds: Array<{ soundId: string; fileName: string }> = [];
  let fixedCount = 0;

  // Try to auto-connect sounds by finding similar file names
  for (const soundId of missingSoundIds) {
    const lowerSoundId = soundId.toLowerCase();
    let foundMatch = false;

    for (const audioFile of audioFiles) {
      const fileName = audioFile.name;
      const fileNameLower = fileName.toLowerCase();
      const fileNameWithoutExt = fileName.replace(/\.(mp3|wav|ogg|m4a)$/i, '').toLowerCase();

      // Strategy 1: Exact match (case-insensitive)
      if (fileNameLower === lowerSoundId || fileNameWithoutExt === lowerSoundId) {
        // Update all commands that use this soundId
        for (const ev of project.events) {
          for (const cmd of ev.commands) {
            if (hasSoundId(cmd) && cmd.soundId === soundId) {
              // Mutate the command's soundId to the matched file name
              (cmd as { soundId: string }).soundId = fileName;
              fixedCount++;
            }
          }
        }
        connectedSounds.push({ soundId, fileName });
        foundMatch = true;
        break;
      }
    }

    // Strategy 2: Partial match (contains)
    if (!foundMatch) {
      for (const audioFile of audioFiles) {
        const fileName = audioFile.name;
        const fileNameWithoutExt = fileName.replace(/\.(mp3|wav|ogg|m4a)$/i, '').toLowerCase();

        if (fileNameWithoutExt.includes(lowerSoundId) || lowerSoundId.includes(fileNameWithoutExt)) {
          // Update all commands that use this soundId
          for (const ev of project.events) {
            for (const cmd of ev.commands) {
              if (hasSoundId(cmd) && cmd.soundId === soundId) {
                // Mutate the command's soundId to the matched file name
                (cmd as { soundId: string }).soundId = fileName;
                fixedCount++;
              }
            }
          }
          connectedSounds.push({ soundId, fileName });
          foundMatch = true;
          break;
        }
      }
    }
  }

  if (connectedSounds.length === 0) {
    return {
      fixed: false,
      message: 'Could not auto-connect any sounds. No matching files found.'
    };
  }

  return {
    fixed: true,
    message: `Auto-connected ${connectedSounds.length} sound(s) to imported files (${fixedCount} command(s) updated).`,
    connectedSounds
  };
}
