# TOOLS.md - Local Notes

Skills define _how_ tools work. This file is for _your_ specifics — the stuff that's unique to your setup.

## Audio Transcription
- **Status:** ✅ Working
- **Method:** faster-whisper (via wrapper script)
- **Wrapper:** `/usr/local/bin/whisper` (emulates whisper CLI)
- **venv:** `/home/openclaw/.openclaw/workspace/venv`
- **Model:** `small` (default), supports tiny/base/small/medium/large
- **Language:** `de` (German), auto-detected
- **Usage:** `whisper <audio_file> --model small --language de --output_format txt`
- **Skills compatible:** `openai-whisper` (skill checks for `whisper` binary)
- **Notes:**
  - Uses faster-whisper (CTranslate2) — faster than original OpenAI whisper
  - First run downloads model to `~/.cache/huggingface/hub`
  - No OpenAI API needed — fully local, free

## What Goes Here

Things like:

- Camera names and locations
- SSH hosts and aliases
- Preferred voices for TTS
- Speaker/room names
- Device nicknames
- Anything environment-specific

## Examples

```markdown
### Cameras

- living-room → Main area, 180° wide angle
- front-door → Entrance, motion-triggered

### SSH

- home-server → 192.168.1.100, user: admin

### TTS

- Preferred voice: "Nova" (warm, slightly British)
- Default speaker: Kitchen HomePod
```

## Why Separate?

Skills are shared. Your setup is yours. Keeping them apart means you can update skills without losing your notes, and share skills without leaking your infrastructure.

---

Add whatever helps you do your job. This is your cheat sheet.
