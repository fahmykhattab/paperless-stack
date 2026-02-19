#!/bin/bash
#
# Paperless-ngx + PaperlessGPT + Paperless-AI One-Liner Deployment
# Usage: curl -fsSL https://your-domain/deploy-paperless.sh | bash
#   Or:  ./deploy-paperless-stack.sh [OPTIONS]
#
# Options (via environment variables):
#   PAPERLESS_DIR      - Installation directory (default: /opt/paperless)
#   OLLAMA_HOST        - Ollama host URL (default: auto-detect or http://host.docker.internal:11434)
#   OLLAMA_MODEL       - LLM model for classification (default: qwen3-vl:235b-cloud)
#   PAPERLESS_URL      - Paperless URL (default: http://localhost:8000)
#   PAPERLESS_PORT     - Paperless port (default: 8000)
#   PAPERLESSGPT_PORT  - PaperlessGPT port (default: 8081)
#   PAPERLESSAI_PORT   - Paperless-AI port (default: 3000)
#   TZ                 - Timezone (default: Europe/Berlin)
#
# For unattended install with custom credentials:
#   PAPERLESS_ADMIN_USER=admin PAPERLESS_ADMIN_PASSWORD=secret ./deploy-paperless-stack.sh
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
PAPERLESS_DIR="${PAPERLESS_DIR:-/opt/paperless}"
OLLAMA_HOST="${OLLAMA_HOST:-}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen3-vl:235b-cloud}"
PAPERLESS_URL="${PAPERLESS_URL:-http://localhost:8000}"
PAPERLESS_PORT="${PAPERLESS_PORT:-8000}"
PAPERLESSGPT_PORT="${PAPERLESSGPT_PORT:-8081}"
PAPERLESSAI_PORT="${PAPERLESSAI_PORT:-3000}"
TZ="${TZ:-Europe/Berlin}"

# Credentials (auto-generated if not set)
PAPERLESS_ADMIN_USER="${PAPERLESS_ADMIN_USER:-}"
PAPERLESS_ADMIN_PASSWORD="${PAPERLESS_ADMIN_PASSWORD:-}"
PAPERLESS_SECRET_KEY="${PAPERLESS_SECRET_KEY:-}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-paperless}"
PAPERLESS_API_TOKEN="${PAPERLESS_API_TOKEN:-}"
PAPERLESSAI_API_KEY="${PAPERLESSAI_API_KEY:-}"

# Helper functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

generate_random_string() {
    local length="${1:-32}"
    # Temporarily disable pipefail to avoid SIGPIPE from head
    set +o pipefail
    if command -v openssl &>/dev/null; then
        openssl rand -base64 $((length * 2)) 2>/dev/null | tr -dc 'a-zA-Z0-9' | head -c "$length"
    else
        tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w "$length" | head -n 1
    fi
    set -o pipefail
}

generate_hex_key() {
    local length="${1:-64}"
    # Temporarily disable pipefail to avoid SIGPIPE from head
    set +o pipefail
    if command -v openssl &>/dev/null; then
        openssl rand -hex "$((length / 2))" 2>/dev/null | head -c "$length"
    else
        tr -dc 'a-f0-9' < /dev/urandom | fold -w "$length" | head -n 1
    fi
    set -o pipefail
}

# Detect Ollama host
detect_ollama_host() {
    if [[ -n "$OLLAMA_HOST" ]]; then
        echo "$OLLAMA_HOST"
        return
    fi
    
    # Try common locations
    local host_ip=""
    
    # Check if Ollama is running locally
    if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
        host_ip=$(ip route | grep default | awk '{print $3}' 2>/dev/null || echo "host.docker.internal")
        echo "http://${host_ip}:11434"
        return
    fi
    
    # Try Docker gateway IP (for Linux)
    host_ip=$(ip route show default | awk '/default/ {print $3}' 2>/dev/null)
    if [[ -n "$host_ip" ]] && curl -s "http://${host_ip}:11434/api/tags" >/dev/null 2>&1; then
        echo "http://${host_ip}:11434"
        return
    fi
    
    # Default fallback
    echo "http://host.docker.internal:11434"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root. Use: sudo $0"
        exit 1
    fi
    
    # Check Docker
    if ! command -v docker &>/dev/null; then
        log_warn "Docker not found. Installing Docker..."
        curl -fsSL https://get.docker.com | sh
        systemctl enable --now docker
        log_success "Docker installed successfully"
    fi
    
    if ! docker ps &>/dev/null; then
        log_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi
    
    # Check Docker Compose
    if ! docker compose version &>/dev/null; then
        log_error "Docker Compose not available. Please install Docker Compose."
        exit 1
    fi
    
    log_success "Prerequisites OK"
}

# Generate credentials
generate_credentials() {
    log_info "Generating credentials..."
    
    PAPERLESS_ADMIN_USER="${PAPERLESS_ADMIN_USER:-admin}"
    PAPERLESS_ADMIN_PASSWORD="${PAPERLESS_ADMIN_PASSWORD:-$(generate_random_string 16)}"
    PAPERLESS_SECRET_KEY="${PAPERLESS_SECRET_KEY:-$(generate_random_string 32)}"
    PAPERLESS_API_TOKEN="${PAPERLESS_API_TOKEN:-$(generate_hex_key 40)}"
    PAPERLESSAI_API_KEY="${PAPERLESSAI_API_KEY:-$(generate_hex_key 128)}"
    
    # Detect Ollama host
    OLLAMA_HOST=$(detect_ollama_host)
    
    # Detect public/private IP for PAPERLESS_URL
    local host_ip=$(ip route get 1 | awk '{print $7; exit}' 2>/dev/null || hostname -I | awk '{print $1}')
    if [[ -n "$host_ip" ]]; then
        PAPERLESS_URL="http://${host_ip}:${PAPERLESS_PORT}"
    fi
    
    log_success "Credentials generated"
}

# Create directory structure
create_directories() {
    log_info "Creating directories..."
    
    mkdir -p "$PAPERLESS_DIR"/{data,media,export,consume,pgdata,redis,prompts}
    
    log_success "Directories created at $PAPERLESS_DIR"
}

# Create docker-compose.yaml
create_docker_compose() {
    log_info "Creating docker-compose.yaml..."
    
    # Extract Ollama host IP for Docker networking
    local ollama_ip=$(echo "$OLLAMA_HOST" | sed 's|http://||' | sed 's|:.*||')
    
    cat > "$PAPERLESS_DIR/docker-compose.yaml" << 'COMPOSE_EOF'
# ==========================================
# Paperless-ngx + PaperlessGPT + Paperless-AI
# Auto-generated deployment configuration
# ==========================================

services:
  # ==========================================
  # PostgreSQL - Database for paperless-ngx
  # ==========================================
  postgres:
    image: docker.io/postgres:16
    container_name: paperless-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: paperless
      POSTGRES_USER: paperless
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - ./pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U paperless -d paperless"]
      interval: 5s
      timeout: 10s
      retries: 5

  # ==========================================
  # Redis - Message broker for paperless-ngx
  # ==========================================
  redis:
    image: docker.io/redis:7-alpine
    container_name: paperless-redis
    restart: unless-stopped
    volumes:
      - ./redis:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 10s
      retries: 5

  # ==========================================
  # Paperless-ngx - Document Management System
  # ==========================================
  paperless-ngx:
    image: ghcr.io/paperless-ngx/paperless-ngx:latest
    container_name: paperless-ngx
    restart: unless-stopped
    ports:
      - "${PAPERLESS_PORT}:8000"
    environment:
      # Database
      PAPERLESS_DBHOST: postgres
      PAPERLESS_DBNAME: paperless
      PAPERLESS_DBUSER: paperless
      PAPERLESS_DBPASS: ${POSTGRES_PASSWORD}
      PAPERLESS_REDIS: redis://redis:6379
      # Security
      PAPERLESS_SECRET_KEY: "${PAPERLESS_SECRET_KEY}"
      PAPERLESS_ADMIN_USER: "${PAPERLESS_ADMIN_USER}"
      PAPERLESS_ADMIN_PASSWORD: "${PAPERLESS_ADMIN_PASSWORD}"
      # Locale
      PAPERLESS_TIME_ZONE: ${TZ}
      PAPERLESS_OCR_LANGUAGE: deu+eng+ara
      PAPERLESS_OCR_LANGUAGES: deu eng ara
      # Performance
      PAPERLESS_TASK_WORKERS: 2
      PAPERLESS_THREADS_PER_WORKER: 2
      # URLs
      PAPERLESS_URL: "${PAPERLESS_URL}"
    volumes:
      - ./data:/usr/src/paperless/data
      - ./media:/usr/src/paperless/media
      - ./export:/usr/src/paperless/export
      - ./consume:/usr/src/paperless/consume
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_started
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8000 || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5

  # ==========================================
  # Paperless-GPT - LLM-powered OCR & Tagging
  # ==========================================
  paperless-gpt:
    image: icereed/paperless-gpt:latest
    container_name: paperless-gpt
    restart: unless-stopped
    ports:
      - "${PAPERLESSGPT_PORT}:8080"
    environment:
      # Paperless-ngx connection
      PAPERLESS_BASE_URL: "http://paperless-ngx:8000"
      PAPERLESS_API_TOKEN: "${PAPERLESS_API_TOKEN}"
      # LLM via Ollama - classification & tagging
      LLM_PROVIDER: "ollama"
      LLM_MODEL: "${OLLAMA_MODEL}"
      LLM_LANGUAGE: "English"
      # OCR via Ollama Vision
      OCR_PROVIDER: "llm"
      VISION_LLM_PROVIDER: "ollama"
      VISION_LLM_MODEL: "${OLLAMA_MODEL}"
      OLLAMA_HOST: "${OLLAMA_HOST_DOCKER}"
      OLLAMA_CONTEXT_LENGTH: "8192"
      # Processing
      OCR_PROCESS_MODE: "image"
      PDF_SKIP_EXISTING_OCR: "false"
      LOG_LEVEL: "info"
      # Tags
      MANUAL_TAG: "paperless-gpt"
      AUTO_TAG: "paperless-gpt-auto"
      AUTO_OCR_TAG: "paperless-gpt-ocr-auto"
      # PDF output
      CREATE_LOCAL_PDF: "false"
      CREATE_LOCAL_HOCR: "false"
      PDF_UPLOAD: "false"
      PDF_REPLACE: "false"
      PDF_COPY_METADATA: "true"
      PDF_OCR_TAGGING: "true"
      PDF_OCR_COMPLETE_TAG: "paperless-gpt-ocr-complete"
      TOKEN_LIMIT: "4000"
    volumes:
      - ./prompts:/app/prompts
    depends_on:
      paperless-ngx:
        condition: service_healthy
    extra_hosts:
      - "host.docker.internal:host-gateway"

  # ==========================================
  # Paperless-AI - Auto classification & RAG chat
  # ==========================================
  paperless-ai:
    image: clusterzx/paperless-ai:latest
    container_name: paperless-ai
    restart: unless-stopped
    ports:
      - "${PAPERLESSAI_PORT}:3000"
    environment:
      PUID: "1000"
      PGID: "1000"
    volumes:
      - paperless-ai_data:/app/data
    extra_hosts:
      - "host.docker.internal:host-gateway"

volumes:
  paperless-ai_data:
COMPOSE_EOF

    log_success "docker-compose.yaml created"
}

# Create .env file for the stack
create_env_file() {
    log_info "Creating .env file..."
    
    # For Docker, we need to use host.docker.internal or gateway IP
    local ollama_docker_host="http://host.docker.internal:11434"
    
    # Try to get Docker gateway IP for Linux
    local gateway_ip=$(ip route show default | awk '/default/ {print $3}' 2>/dev/null)
    if [[ -n "$gateway_ip" ]]; then
        ollama_docker_host="http://${gateway_ip}:11434"
    fi
    
    cat > "$PAPERLESS_DIR/.env" << EOF
# Paperless Stack Configuration
# Generated on $(date)

# Directory
PAPERLESS_DIR=$PAPERLESS_DIR

# Ports
PAPERLESS_PORT=$PAPERLESS_PORT
PAPERLESSGPT_PORT=$PAPERLESSGPT_PORT
PAPERLESSAI_PORT=$PAPERLESSAI_PORT

# Timezone
TZ=$TZ

# Database
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# Paperless-ngx
PAPERLESS_ADMIN_USER=$PAPERLESS_ADMIN_USER
PAPERLESS_ADMIN_PASSWORD=$PAPERLESS_ADMIN_PASSWORD
PAPERLESS_SECRET_KEY=$PAPERLESS_SECRET_KEY
PAPERLESS_URL=$PAPERLESS_URL

# Paperless API Token (generate in Paperless UI: Settings -> API Auth Tokens)
PAPERLESS_API_TOKEN=$PAPERLESS_API_TOKEN

# Ollama
OLLAMA_MODEL=$OLLAMA_MODEL
OLLAMA_HOST=$OLLAMA_HOST
OLLAMA_HOST_DOCKER=$ollama_docker_host

# Paperless-AI
PAPERLESSAI_API_KEY=$PAPERLESSAI_API_KEY
EOF

    chmod 600 "$PAPERLESS_DIR/.env"
    log_success ".env file created"
}

# Create PaperlessGPT prompt templates
create_prompts() {
    log_info "Creating PaperlessGPT prompt templates..."
    
    cat > "$PAPERLESS_DIR/prompts/tag_prompt.tmpl" << 'EOF'
I will provide you with the content and the title of a document.
Your task is to select appropriate tags for the document from the list of available tags I will provide.
Only select tags from the provided list. Respond only with the selected tags as a comma-separated list, without any additional information.
The content is likely in {{.Language}}.

The data will be provided using an XML-like format for clarity:

<available_tags>
{{.AvailableTags | join ", "}}
</available_tags>

<title>
{{.Title}}
</title>

<content>
{{.Content}}
</content>

Please concisely select the {{.Language}} tags from the list above that best describe the document.
Be very selective and only choose the most relevant tags since too many tags will make the document less discoverable.
EOF

    cat > "$PAPERLESS_DIR/prompts/correspondent_prompt.tmpl" << 'EOF'
I will provide you with the content of a document. Your task is to suggest a correspondent that is most relevant to the document.

Correspondents are the senders of documents that reach you. In the other direction, correspondents are the recipients of documents that you send.
In Paperless-ngx we can imagine correspondents as virtual drawers in which all documents of a person or company are stored.
With just one click, we can find all the documents assigned to a specific correspondent.
Try to suggest a correspondent, either from the example list or come up with a new correspondent.

Respond only with a correspondent, without any additional information!

Be sure to choose a correspondent that is most relevant to the document.
Try to avoid any legal or financial suffixes like "GmbH" or "AG" in the correspondent name.
For example use "Microsoft" instead of "Microsoft Ireland Operations Limited" or "Amazon" instead of "Amazon EU S.a.r.l.".

If you can't find a suitable correspondent, you can respond with "Unknown".

The data will be provided using an XML-like format for clarity:

Important constraints:
- Prefer an exact or normalized match from <example_correspondents> where possible.
- Never return a name that appears in <blacklisted_correspondents>.

<example_correspondents>
{{.AvailableCorrespondents | join ", "}}
</example_correspondents>

<blacklisted_correspondents>
{{.BlackList | join ", "}}
</blacklisted_correspondents>

<title>
{{.Title}}
</title>

<content>
{{.Content}}
</content>

The content is likely in {{.Language}}.
EOF

    cat > "$PAPERLESS_DIR/prompts/title_prompt.tmpl" << 'EOF'
I will provide you with the content of a document that has been partially read by OCR (so it may contain errors).
Your task is to find a suitable document title that I can use as the title in the paperless-ngx program.
If the original title is already adding value and not just a technical filename you can use it as extra information to enhance your suggestion.
Respond only with the title, without any additional information. The content is likely in {{.Language}}.

The data will be provided using an XML-like format for clarity:

<original_title>{{.Title}}</original_title>
<content>
{{.Content}}
</content>
EOF

    cat > "$PAPERLESS_DIR/prompts/document_type_prompt.tmpl" << 'EOF'
I will provide you with the content and the title of a document.
Your task is to select the most appropriate document type for the document from the list of available document types I will provide.
Only select a document type from the provided list. Respond only with the selected document type name, without any additional information.
If none of the available document types fit the document, respond with an empty string.
The content is likely in {{.Language}}.

The data will be provided using an XML-like format for clarity:

<available_document_types>
{{.AvailableDocumentTypes | join ", "}}
</available_document_types>

<title>
{{.Title}}
</title>

<content>
{{.Content}}
</content>

Please select the single most appropriate {{.Language}} document type from the list above that best categorizes this document.
Be selective and only choose a document type if it clearly matches the document's nature (e.g., Invoice, Contract, Receipt, Letter, etc.).
EOF

    cat > "$PAPERLESS_DIR/prompts/ocr_prompt.tmpl" << 'EOF'
Just transcribe the text in this image and preserve the formatting and layout (high quality OCR).
Do that for ALL the text in the image. Be thorough and pay attention. This is very important.
The image is from a text document so be sure to continue until the bottom of the page.
Thanks a lot! You tend to forget about some text in the image so please focus! Use markdown format but without a code block.
EOF

    cat > "$PAPERLESS_DIR/prompts/created_date_prompt.tmpl" << 'EOF'
I will provide you with the content of a document. Your task is to find the date when the document was created.
Respond only with the date in YYYY-MM-DD format, without any additional information.
If no day was found, use the first day of the month. If no month was found, use January. If no date was found at all, answer with today's date.
The content is likely in {{.Language}}. Today's date is {{.Today}}.

The data will be provided using an XML-like format for clarity:

<content>
{{.Content}}
</content>
EOF

    cat > "$PAPERLESS_DIR/prompts/custom_field_prompt.tmpl" << 'EOF'
You are an assistant that extracts information from documents and returns it as a JSON object.
The user will provide you with the content of a document, its title, creation date and document type.
You have to find the values for a list of custom fields that are provided as an XML list.

**Document Details:**
- **Language:** {{ .Language }}
- **Title:** {{ .Title }}
- **Creation Date:** {{ .CreatedDate }}
- **Content:**
{{ .Content }}
- **Document Type:** {{ .DocumentType }}

**Custom Fields to Extract:**
{{ .CustomFieldsXML }}

**Instructions:**
1.  Analyze the document content to find the values for the custom fields listed in the XML. The language of the custom fields and of the document may differ.
2.  The `type` attribute in each `<field>` tag indicates the data type you should look for (e.g., `string`, `date`, `integer`).
3.  For fields of type `monetary`, the value must be a number with two decimal places and a period as the decimal separator. You must also identify the currency from the document and place its three-letter code (e.g., EUR, USD) at the beginning of the value. For example, if the document shows '1.664,58 €', the correct format would be `EUR1664.58`.
4.  Return a valid JSON array where each object contains the `field` (the **name** of the custom field) and the `value` you extracted.
5.  If you cannot find a value for a specific field, do not include it in the JSON array.
6.  If a specific field is not relevant for the given document type (e.g., an 'Invoice Number' field for a delivery slip), simply omit that field from the JSON array. Do not return an empty array unless none of the fields are relevant.
7.  Ensure the output is only the JSON array, with no additional text or explanations.

**Example Output:**
```json
[
  {
    "field": "Invoice Number",
    "value": "INV-2023-001"
  },
  {
    "field": "Due Date",
    "value": "2023-10-26"
  }
]
```
EOF

    cat > "$PAPERLESS_DIR/prompts/adhoc-analysis_prompt.tmpl" << 'EOF'
Summarize the following documents. For each document, extract the correspondent, invoice date, invoice number, and total amount.
Display the results in a table sorted by date.
Finally, calculate and display the total amount of all invoices.
Skip documents that are not invoices.

<documents>
{{ range .Documents }}
<document>
    <title>{{ .Title }}</title>
    <content>{{ .Content }}</content>
    <correspondent>{{ .Correspondent }}</correspondent>
    <document_type>{{ .DocumentTypeName }}</document_type>
    <created_date>{{ .CreatedDate }}</created_date>
    {{ range .CustomFields }}
    <custom_field>
        <name>{{ .Name }}</name>
        <value>{{ .Value }}</value>
    </custom_field>
    {{ end }}
</document>
{{ end }}
</documents>
EOF

    log_success "Prompt templates created"
}

# Create Paperless-AI configuration
create_paperless_ai_config() {
    log_info "Creating Paperless-AI configuration..."
    
    # Get host IP for Paperless-AI to connect
    local host_ip=$(ip route get 1 | awk '{print $7; exit}' 2>/dev/null || hostname -I | awk '{print $1}')
    
    # System prompt for Paperless-AI (multiline)
    local system_prompt='You are a personalized document analyzer. Your task is to analyze documents and extract relevant information.\n\nAnalyze the document content and extract the following information into a structured JSON object:\n\n1. title: Create a concise, meaningful title for the document\n2. correspondent: Identify the sender/institution but do not include addresses\n3. tags: Select up to 4 relevant thematic tags\n4. document_date: Extract the document date (format: YYYY-MM-DD)\n5. document_type: Determine a precise type that classifies the document (e.g. Invoice, Contract, Employer, Information and so on)\n6. language: Determine the document language (e.g. "de" or "en")\n      \nImportant rules for the analysis:\n\nFor tags:\n- FIRST check the existing tags before suggesting new ones\n- Use only relevant categories\n- Maximum 4 tags per document, less if sufficient (at least 1)\n- Avoid generic or too specific tags\n- Use only the most important information for tag creation\n- The output language is the one used in the document! IMPORTANT!\n\nFor the title:\n- Short and concise, NO ADDRESSES\n- Contains the most important identification features\n- For invoices/orders, mention invoice/order number if available\n- The output language is the one used in the document! IMPORTANT!\n\nFor the correspondent:\n- Identify the sender or institution\n- When generating the correspondent, always create the shortest possible form of the company name (e.g. "Amazon" instead of "Amazon EU SARL, German branch")\n\nFor the document date:\n- Extract the date of the document\n- Use the format YYYY-MM-DD\n- If multiple dates are present, use the most relevant one\n\nFor the language:\n- Determine the document language\n- Use language codes like "de" for German or "en" for English\n- If the language is not clear, use "und" as a placeholder'

    # Note: Paperless-AI stores its config in a Docker volume, but we can create an initial .env
    # that will be used on first startup if mounted to /app/data/.env
    # The container manages its own config, so we'll note what needs to be configured
    
    log_success "Paperless-AI will be configured via web UI at http://${host_ip}:${PAPERLESSAI_PORT}"
}

# Start the stack
start_stack() {
    log_info "Starting Paperless stack..."
    
    cd "$PAPERLESS_DIR"
    
    # Pull images first
    docker compose pull
    
    # Start services
    docker compose up -d
    
    log_success "Stack started. Waiting for services to be healthy..."
    
    # Wait for Paperless-ngx to be ready
    local max_wait=120
    local waited=0
    while ! curl -sf http://localhost:${PAPERLESS_PORT}/api/ >/dev/null 2>&1; do
        if [[ $waited -ge $max_wait ]]; then
            log_warn "Paperless-ngx taking longer than expected. Check logs: docker compose logs paperless-ngx"
            break
        fi
        sleep 5
        waited=$((waited + 5))
        echo -n "."
    done
    echo ""
    
    log_success "Paperless-ngx is ready!"
}

# Print summary
print_summary() {
    local host_ip=$(ip route get 1 | awk '{print $7; exit}' 2>/dev/null || hostname -I | awk '{print $1}')
    
    echo ""
    echo "=========================================="
    echo "  Paperless Stack Deployed Successfully!"
    echo "=========================================="
    echo ""
    echo "📍 Services:"
    echo "   Paperless-ngx:  http://${host_ip}:${PAPERLESS_PORT}"
    echo "   PaperlessGPT:   http://${host_ip}:${PAPERLESSGPT_PORT}"
    echo "   Paperless-AI:   http://${host_ip}:${PAPERLESSAI_PORT}"
    echo ""
    echo "🔑 Credentials:"
    echo "   Admin User:     ${PAPERLESS_ADMIN_USER}"
    echo "   Admin Password: ${PAPERLESS_ADMIN_PASSWORD}"
    echo ""
    echo "🤖 AI Configuration:"
    echo "   Ollama Host:    ${OLLAMA_HOST}"
    echo "   LLM Model:      ${OLLAMA_MODEL}"
    echo ""
    echo "📁 Installation Directory: ${PAPERLESS_DIR}"
    echo ""
    echo "⚙️  Post-Installation Steps:"
    echo "   1. Login to Paperless-ngx and create an API token"
    echo "   2. Configure Paperless-AI via its web UI"
    echo "   3. Add the 'paperless-gpt' tag in Paperless-ngx for auto-processing"
    echo ""
    echo "📝 API Token for PaperlessGPT/Paperless-AI:"
    echo "   ${PAPERLESS_API_TOKEN}"
    echo ""
    echo "   Generate a real token in Paperless UI: Settings → API Auth Tokens"
    echo "   Then update: docker-compose.yaml (PAPERLESS_API_TOKEN) and restart"
    echo ""
    echo "💡 Useful Commands:"
    echo "   cd ${PAPERLESS_DIR}"
    echo "   docker compose logs -f        # View logs"
    echo "   docker compose restart        # Restart all services"
    echo "   docker compose down           # Stop all services"
    echo "   docker compose up -d          # Start all services"
    echo ""
    echo "📄 Configuration saved to: ${PAPERLESS_DIR}/.env"
    echo ""
}

# Save credentials to file
save_credentials() {
    local creds_file="$PAPERLESS_DIR/credentials.txt"
    
    cat > "$creds_file" << EOF
# Paperless Stack Credentials
# Generated on $(date)
# ⚠️  KEEP THIS FILE SECURE - DELETE AFTER STORING CREDENTIALS

PAPERLESS_URL=http://$(ip route get 1 | awk '{print $7; exit}' 2>/dev/null || hostname -I | awk '{print $1}'):${PAPERLESS_PORT}
PAPERLESS_ADMIN_USER=${PAPERLESS_ADMIN_USER}
PAPERLESS_ADMIN_PASSWORD=${PAPERLESS_ADMIN_PASSWORD}
PAPERLESS_API_TOKEN=${PAPERLESS_API_TOKEN}
PAPERLESSAI_API_KEY=${PAPERLESSAI_API_KEY}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
OLLAMA_HOST=${OLLAMA_HOST}
OLLAMA_MODEL=${OLLAMA_MODEL}
EOF
    
    chmod 600 "$creds_file"
    log_info "Credentials saved to: $creds_file"
}

# Main installation flow
main() {
    echo ""
    echo "=========================================="
    echo "  Paperless Stack Deployment Script"
    echo "  Paperless-ngx + PaperlessGPT + Paperless-AI"
    echo "=========================================="
    echo ""
    
    check_prerequisites
    generate_credentials
    create_directories
    create_docker_compose
    create_env_file
    create_prompts
    create_paperless_ai_config
    start_stack
    save_credentials
    print_summary
}

# Run main function
main "$@"