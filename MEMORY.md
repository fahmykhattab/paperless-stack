# MEMORY.md - Long-Term Memory

## User Context
- **Name:** Fahmy
- **Timezone:** Europe/Vienna
- **Host:** Proxmox (pve)
- **OpenClaw Deployment:** Owner and primary user

## Assistant Identity
- **Name:** kemo
- **Vibe:** calm, helpful, concise — no fluff, just competence
- **Emoji:** 🐱

## Key Decisions & Preferences
- Docker preferred for containerized deployments (future: Paperless-ngx with AI plugins)
- TTS voice reply capability confirmed working via Telegram
- User can send German voice messages (but transcription not yet working - needs Whisper setup)
- **OpenAI API not an option** — user prefers free/self-hosted solutions
- **Voice transcription:** ✅ Working via faster-whisper (see TOOLS.md for details)

## Project Context
### Document Management Setup (Feb 2026)
- Requested integrated solution: Paperless-ngx + PaperlessAI + PaperlessGPT
- Awaiting deployment method choice (Docker vs bare-metal)
- Docker not currently installed — will install as part of setup

## System Notes
- Host: pve (Proxmox)
- Shell: bash
- Channel: Telegram (direct)
- Capabilities: inline buttons, TTS, audio replies

### OpenClaw VM (ID 102)
- **IP:** 192.168.178.110
- **SSH:** `ssh fahmy@192.168.178.110`
- **Dashboard:** http://192.168.178.110:18789/
- **Specs:** 4 vCPUs, 8GB RAM, 20GB disk
- **OS:** Ubuntu 24.04 LTS
- **OpenClaw:** v2026.2.17 (systemd service)

## Paperless-ngx AI Setup (Feb 2026)

### Built-in ML Auto-Tagging (NLTK)
- Requires at least 2 documents with same tag for training
- Command: `python3 /usr/src/paperless/src/manage.py document_create_classifier`
- Triggers: "No automatic matching items, not training" until documents are labeled

### PaperlessGPT Plugin Status
- **Official repo:** `https://github.com/icereed/paperless-gpt` (correct, working)
- **Docker:** `icereed/paperless-gpt:latest` / `ghcr.io/icereed/paperless-gpt:latest`
- **OCR providers:** LLM-based (OpenAI/Ollama/Mistral/Claude), Google Document AI, Azure Document Intelligence, Docling Server
- **OCR modes:** `image`, `pdf`, `whole_pdf`
- **Integration:** Works alongside paperless-ngx; joins same Docker network (`paperless`)
- **Ollama endpoint:** `http://172.19.0.1:11434` (Docker gateway IP for Linux hosts)

### Active Deployment (Feb 2026)
- **Deployment method:** Docker container (same network as paperless-ngx)
- **Docker network:** `workspace-paperless_net`
- **Container name:** `workspace-paperless-gpt-1`
- **Paperless-ngx UI:** `http://localhost:8000`
- **PaperlessGPT UI:** `http://localhost:8081`
- **LLM model:** `qwen3-vl:235b-cloud` (for both OCR and classification)
- **Ollama endpoint:** `http://172.19.0.1:11434` (Docker gateway IP for Linux)
- **Manual tag:** `paperless-gpt`
- **Auto tag:** `paperless-gpt-auto`
- **OCR complete tag:** `paperless-gpt-ocr-complete`

### Key Lessons Learned (Feb 2026)
- **Linux Docker networking:** `host.docker.internal` does NOT work on Linux; use Docker gateway IP (`172.x.x.1`)
- **PaperlessGPT is a separate web service:** AI features accessible via `http://localhost:8081`, not directly in paperless-ngx UI
- **Model names must match exactly:** Ollama model `qwen3-vl:235b-cloud` ≠ `qwen3-vl:cloud`

### Failed Installation (Earlier Attempt)
- Attempted `damiankempf/PaperlessGPT` — repository returned 404
- That repo is defunct/incorrect; official version is now `icereed/paperless-gpt`
