#!/usr/bin/env python3
"""Simple transcription script using faster-whisper."""

import sys
import os
from faster_whisper import WhisperModel

def transcribe(audio_path, language="de"):
    # Use small model for balance of speed/accuracy
    model = WhisperModel("small", device="cpu", compute_type="int8")
    
    segments, info = model.transcribe(audio_path, language=language)
    
    print(f"Detected language: {info.language} (probability: {info.language_probability:.2f})")
    
    full_text = []
    for segment in segments:
        print(f"[{segment.start:.2f}s -> {segment.end:.2f}s] {segment.text}")
        full_text.append(segment.text.strip())
    
    return " ".join(full_text)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: transcribe.py <audio_file> [language]")
        sys.exit(1)
    
    audio_file = sys.argv[1]
    language = sys.argv[2] if len(sys.argv) > 2 else "de"
    
    if not os.path.exists(audio_file):
        print(f"Error: File not found: {audio_file}")
        sys.exit(1)
    
    text = transcribe(audio_file, language)
    print(f"\n=== Full Transcript ===\n{text}")