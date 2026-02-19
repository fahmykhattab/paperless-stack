#!/bin/bash
# Transcribe audio file using faster-whisper Docker container
# Usage: transcribe.sh <audio_file> [language]

AUDIO_FILE="$1"
LANGUAGE="${2:-de}"

if [ -z "$AUDIO_FILE" ] || [ ! -f "$AUDIO_FILE" ]; then
    echo "Error: Audio file not found: $AUDIO_FILE"
    exit 1
fi

AUDIO_DIR="/home/openclaw/.openclaw/workspace/audio"
FILENAME=$(basename "$AUDIO_FILE")

# Copy audio to the shared directory if not already there
if [[ "$AUDIO_FILE" != "$AUDIO_DIR/"* ]]; then
    cp "$AUDIO_FILE" "$AUDIO_DIR/"
fi

# Run transcription inside container
docker exec faster-whisper python3 -c "
from faster_whisper import WhisperModel
import json

model = WhisperModel('small', device='cpu', compute_type='int8')
segments, info = model.transcribe('/tmp/audio/$FILENAME', language='$LANGUAGE')
result = [{'start': s.start, 'end': s.end, 'text': s.text.strip()} for s in segments]
print(json.dumps({'language': info.language, 'segments': result}, ensure_ascii=False))
"