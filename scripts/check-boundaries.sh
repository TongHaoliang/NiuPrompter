#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

if rg -n 'SFSpeechRecognizer|URLSession|URLRequest|AVAudioFile|AVAudioRecorder|FileHandle|write\(to:' Sources Apps --glob '*.swift'; then
    echo "Boundary check failed: review the matches above." >&2
    exit 1
fi

echo "Boundary check passed: no legacy recognizer, network client, audio-file writer, or recorder API references in Sources/Apps."
