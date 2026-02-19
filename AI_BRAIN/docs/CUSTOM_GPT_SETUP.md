# FluxForge ACC — Custom GPT Setup Guide

## Overview

This Custom GPT connects ChatGPT directly to your local FluxForge Studio codebase via the ACC (AI Control Core) server. ChatGPT can read files, search code, and submit patches — all through API calls.

---

## Prerequisites

1. **ACC server running:**
   ```bash
   cd ai-control-core/acc && cargo run --release
   ```

2. **ngrok tunnel (exposes localhost):**
   ```bash
   ngrok http 8787
   ```
   Copy the HTTPS URL (e.g. `https://abc123.ngrok-free.app`)

---

## Step 1: Create Custom GPT

1. Go to https://chatgpt.com/gpts/editor
2. Name: **FluxForge Coder**
3. Description: *Failover coding assistant for FluxForge Studio — reads code, writes patches*

---

## Step 2: Paste Instructions

Copy this into the **Instructions** field:

```
You are a FALLBACK IMPLEMENTER for FluxForge Studio, a professional DAW + Slot Audio Middleware built with Flutter (Dart) + Rust (FFI bridge).

## Your Workflow

1. ALWAYS call getProjectContext FIRST to understand the project
2. Read relevant files before making any changes
3. Use searchCode to find where things are defined
4. Output changes as unified diff patches via applyPatch
5. Create tasks via createTask before starting work

## Rules

- Output ONLY unified diff patches for code changes
- NEVER modify files in AI_BRAIN/memory/** — they are LOCKED
- Small, focused patches — one task = one patch
- Always read relevant files BEFORE writing patches
- Dart: Provider pattern (ChangeNotifier + GetIt), import 'package:flutter_ui/...'
- Rust: ZERO allocations in audio thread, lock-free via rtrb ring buffer
- Rust naming: snake_case everywhere
- Dart naming: camelCase for variables, PascalCase for classes
- NEVER use Spacer() in unbounded Column
- NEVER hardcode win tier labels (use WIN 1, WIN 2, etc.)

## Diff Format

Patches MUST follow this format:
- Start with `diff --git a/path b/path`
- Use relative paths from repo root
- Context lines must EXACTLY match the file
- For new files: `--- /dev/null` and `+++ b/path`

## When Unsure

- Call listDirectory to explore the file tree
- Call searchCode to find implementations
- Call readFile to read the actual code
- Check getProjectContext for architecture and constraints
```

---

## Step 3: Configure Actions

1. Click **"Create new action"**
2. Choose **"Import from URL"** — NOT available, so:
3. Click **"Import from schema"**
4. Paste the contents of `ai-control-core/acc/openapi.json`
5. **Replace** `https://YOUR_NGROK_URL.ngrok-free.app` with your actual ngrok URL

---

## Step 4: Authentication

1. In the Actions editor, click **"Authentication"**
2. Choose **"API Key"**
3. Auth Type: **Custom**
4. Custom Header Name: `x-acc-key`
5. API Key: `fluxforge-acc-2026` (or whatever you set in `acc.config.json`)

---

## Step 5: Test

Ask ChatGPT:
> "Read the file crates/rf-engine/src/ffi.rs and tell me what FFI functions are exported"

It should:
1. Call `getProjectContext` first
2. Call `readFile` with path `crates/rf-engine/src/ffi.rs`
3. Analyze and respond

---

## Usage Pattern

### When Claude hits limits:

1. Start ACC server: `cd ai-control-core/acc && cargo run --release`
2. Start tunnel: `ngrok http 8787`
3. Update ngrok URL in Custom GPT actions (if changed)
4. Tell ChatGPT: *"Create task TASK_XXX: [description]. Read the relevant files and implement it."*
5. ChatGPT reads code via API, writes patch, submits via `/patch/apply`
6. ACC runs gates (locked paths + flutter analyze) and auto-merges

### When Claude is back:

1. Stop ngrok tunnel
2. Claude reviews any commits made by ChatGPT
3. Continue normal workflow

---

## Security Notes

- **ngrok URL changes on every restart** — update in Custom GPT when needed
- **API key required** — set in `acc.config.json`, configured in Custom GPT auth
- **Locked paths enforced** — AI_BRAIN/memory/** cannot be modified
- **Flutter analyze gate** — broken code is rejected automatically
- **Read-only by default** — only `/patch/apply` can modify code (through git)
- **No binary files** — images, audio, compiled files are blocked

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "Failed to connect" | Check ngrok is running, URL matches |
| "Unauthorized" | Check API key matches in config + Custom GPT |
| "Path not found" | Use relative paths from repo root, no leading `/` |
| "File too large" | Use `line_start`/`line_end` params |
| Patch rejected | Check gate_results in response for details |

---

## Quick Reference — ngrok

```bash
# Install (once)
brew install ngrok

# Auth (once)
ngrok config add-authtoken YOUR_TOKEN

# Run
ngrok http 8787

# Static domain (paid plan, URL never changes):
ngrok http --domain=fluxforge.ngrok.io 8787
```
