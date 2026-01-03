import type {
  ReelForgeProject,
  TemplateJSON,
  AudioSpriteFile,
  AudioSpriteItem,
  GameEvent,
  Command,
  CommandType,
  PlayCommand,
  StopCommand,
  FadeCommand,
  PauseCommand,
  ExecuteCommand,
  TemplateCommand,
} from './types';

export function parseTemplateJSON(raw: string): TemplateJSON {
  const parsed = JSON.parse(raw);
  // Ensure all required properties exist with defaults
  if (!parsed.soundManifest) {
    parsed.soundManifest = [];
  }
  if (!parsed.soundDefinitions) {
    parsed.soundDefinitions = { soundSprites: {} };
  }
  if (!parsed.soundDefinitions.soundSprites) {
    parsed.soundDefinitions.soundSprites = {};
  }

  // Commands can be at root level OR inside soundDefinitions
  // Support both formats
  if (!parsed.commands) {
    if (parsed.soundDefinitions?.commands) {
      // Move commands from soundDefinitions to root level
      parsed.commands = parsed.soundDefinitions.commands;
    } else {
      parsed.commands = {};
    }
  }
  return parsed as TemplateJSON;
}

export function projectToTemplateJson(project: ReelForgeProject): TemplateJSON {
  const soundManifest = project.spriteFiles.map((sf) => ({
    id: sf.id,
    src: [sf.filePath],
  }));

  const soundSprites: Record<string, any> = {};
  project.spriteItems.forEach((si) => {
    soundSprites[si.spriteId] = {
      soundId: si.soundId,
      spriteId: si.spriteId,
      startTime: si.startTime,
      duration: si.duration,
      tags: si.tags || [],
    };
  });

  const commands: Record<string, TemplateCommand[]> = {};
  project.events.forEach((evt) => {
    commands[evt.id] = evt.commands.map(cmd => {
      const templateCmd: TemplateCommand = {
        command: cmd.type as any,
      };

      if ('soundId' in cmd) {
        templateCmd.spriteId = cmd.soundId;
      }
      if ('volume' in cmd) {
        templateCmd.volume = cmd.volume;
      }
      if ('loop' in cmd) {
        templateCmd.loop = cmd.loop ? 1 : 0;
      }
      if ('loopCount' in cmd) {
        templateCmd.loopCount = cmd.loopCount;
      }
      if ('pan' in cmd) {
        templateCmd.pan = cmd.pan;
      }
      if ('overall' in cmd) {
        templateCmd.overall = cmd.overall;
      }
      if ('delay' in cmd) {
        templateCmd.delay = cmd.delay;
      }
      if ('duration' in cmd) {
        templateCmd.duration = cmd.duration;
      }
      if ('durationUp' in cmd) {
        templateCmd.durationUp = cmd.durationUp;
      }
      if ('durationDown' in cmd) {
        templateCmd.durationDown = cmd.durationDown;
      }
      if ('eventId' in cmd) {
        templateCmd.commandId = cmd.eventId;
      }
      if ('fadeDuration' in cmd) {
        templateCmd.fadeDuration = cmd.fadeDuration;
      }

      return templateCmd;
    });
  });

  return {
    soundManifest,
    soundDefinitions: { soundSprites },
    commands,
  };
}

export function templateJsonToProject(raw: TemplateJSON): ReelForgeProject {
  const spriteFiles: AudioSpriteFile[] = (raw.soundManifest || []).map((m) => ({
    id: m.id,
    fileName: m.id,
    filePath: m.src?.[0] || '',
    format: m.src?.[0]?.split('.').pop() || 'mp3',
    dateAdded: new Date().toISOString(),
  }));

  const spriteItems: AudioSpriteItem[] = Object.entries(raw.soundDefinitions?.soundSprites || {}).map(
    ([key, sprite]) => ({
      id: key,
      soundId: sprite.soundId,
      spriteId: sprite.spriteId,
      startTime: (sprite.startTime || 0) / 1000,
      duration: (sprite.duration || 0) / 1000,
      tags: sprite.tags || [],
      name: key,
    })
  );

  // Commands can be at root level OR inside soundDefinitions - support both formats
  const commandsSource = raw.commands || (raw.soundDefinitions as any)?.commands || {};

  const events: GameEvent[] = [];
  for (const [eventId, cmds] of Object.entries(commandsSource)) {
    // Handle empty events or non-array values
    const commandsArray = Array.isArray(cmds) ? cmds : [];

    events.push({
      id: eventId,
      eventName: eventId,
      commands: commandsArray.map(cmd => {
        // Handle case where cmd might be null/undefined or not an object
        if (!cmd || typeof cmd !== 'object') {
          return { type: 'Play', soundId: '', volume: 1 } as PlayCommand;
        }

        const baseCmd = {
          type: cmd.command as CommandType,
          soundId: cmd.spriteId || cmd.commandId || '',
        };

        if (cmd.command === 'Play') {
          return {
            ...baseCmd,
            volume: cmd.volume ?? 1.0,
            loop: cmd.loop === 1,
            loopCount: cmd.loopCount,
            fadeIn: cmd.duration,
            delay: cmd.delay ?? 0,
            pan: cmd.pan ?? 0,
            overall: cmd.overall ?? false,
          } as PlayCommand;
        }

        if (cmd.command === 'Stop') {
          return {
            ...baseCmd,
            fadeOut: cmd.duration,
            delay: cmd.delay ?? 0,
            overall: cmd.overall ?? false,
          } as StopCommand;
        }

        if (cmd.command === 'Fade') {
          return {
            ...baseCmd,
            targetVolume: cmd.volume ?? 1.0,
            duration: cmd.duration,
            durationUp: cmd.durationUp,
            durationDown: cmd.durationDown,
            delay: cmd.delay ?? 0,
            overall: cmd.overall ?? false,
          } as FadeCommand;
        }

        if (cmd.command === 'Pause') {
          return {
            ...baseCmd,
            delay: cmd.delay ?? 0,
            overall: cmd.overall ?? false,
          } as PauseCommand;
        }

        if (cmd.command === 'Execute') {
          return {
            type: 'Execute',
            eventId: cmd.commandId || '',
            delay: cmd.delay,
            fadeDuration: cmd.fadeDuration,
            volume: cmd.volume,
          } as ExecuteCommand;
        }

        return baseCmd as Command;
      }),
      description: `Triggered for ${eventId}`,
    });
  }

  return {
    id: "proj_001",
    name: "Playa Slot Template",
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    spriteFiles,
    spriteItems,
    spriteLists: [],
    events,
    buses: [],
    settings: {
      defaultVolume: 0.7,
      exportFormat: "json",
    },
  };
}
