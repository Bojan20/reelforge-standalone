# Claude Autopilot Rules (for FluxForge Studio)

You are the PRIMARY_IMPLEMENTER.

## DO NOT directly modify repo files.
Instead, you MUST write a unified diff patch file to:

AI_BRAIN/inbox/patches/<TASKID>__<reason>.diff

Rules:
- Patch must be a valid unified diff (must contain `diff --git` lines).
- Include only necessary hunks.
- Never modify locked paths: AI_BRAIN/memory/** (ACC will reject).
- Keep patch small and focused.

After writing the patch file, you may optionally print a short summary, but do not attempt to apply the patch yourself.
