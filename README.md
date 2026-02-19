# Paperless Stack Deploy

One-liner deployment script for **Paperless-ngx + PaperlessGPT + Paperless-AI** with Ollama LLM integration.

## What it deploys

| Service | Port | Purpose |
|---------|------|---------|
| Paperless-ngx | 8000 | Document management system |
| PaperlessGPT | 8081 | LLM-powered OCR & auto-tagging |
| Paperless-AI | 3000 | Auto-classification & RAG chat |
| PostgreSQL | - | Database backend |
| Redis | - | Message broker |

## Requirements

- Linux server with Docker & Docker Compose
- Ollama running with a vision-capable model (e.g., `qwen3-vl`, `llava`)
- Root access (for installation)

## Quick Start

```bash
# Run directly
curl -fsSL https://raw.githubusercontent.com/fahmykhattab/paperless-stack/main/deploy-paperless-stack.sh | sudo bash

# Or clone and run
git clone https://github.com/fahmykhattab/paperless-stack.git
cd paperless-stack
sudo bash deploy-paperless-stack.sh
```

## Configuration

Override defaults with environment variables:

```bash
sudo OLLAMA_MODEL=qwen3-vl:latest TZ=Europe/Vienna bash deploy-paperless-stack.sh
```

| Variable | Default | Description |
|----------|---------|-------------|
| `PAPERLESS_DIR` | `/opt/paperless` | Installation directory |
| `OLLAMA_HOST` | auto-detect | Ollama API URL |
| `OLLAMA_MODEL` | `qwen3-vl:235b-cloud` | LLM model for OCR & classification |
| `PAPERLESS_PORT` | 8000 | Paperless-ngx web UI port |
| `PAPERLESSGPT_PORT` | 8081 | PaperlessGPT port |
| `PAPERLESSAI_PORT` | 3000 | Paperless-AI port |
| `TZ` | `Europe/Berlin` | Timezone |

## Post-Installation

1. Login to Paperless-ngx at `http://your-ip:8000`
2. Generate an API token in Settings → API Auth Tokens
3. Update `PAPERLESS_API_TOKEN` in `.env` and restart: `docker compose restart`
4. Configure Paperless-AI via its web UI at `http://your-ip:3000`
5. Add the `paperless-gpt` tag in Paperless-ngx for auto-processing

## Features

- Auto-detects Ollama host (Docker gateway IP for Linux)
- Generates secure random credentials
- Includes 7 custom prompt templates for PaperlessGPT
- Health-checks services before completion
- Saves credentials to `credentials.txt`

## AI Capabilities

- **OCR**: Vision models can transcribe text from documents
- **Auto-tagging**: Documents tagged with `paperless-gpt` get auto-processed
- **Title generation**: Smart titles from document content
- **Correspondent extraction**: Identifies senders/organizations
- **Date extraction**: Parses document dates automatically
- **Custom fields**: Extracts invoice amounts, due dates, etc.

## License

MIT