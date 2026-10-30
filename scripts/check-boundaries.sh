#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

if rg -n 'SFSpeechRecognizer|URLSession|URLRequest|AVAudioFile|AVAudioRecorder|FileHandle' Sources Apps --glob '*.swift'; then
    echo "Boundary check failed: review the matches above." >&2
    exit 1
fi

# Direct data writes are limited to draft/cursor persistence. CameraRecorder owns user-triggered movies.
if rg -n 'write\(to:' Sources Apps --glob '*.swift' --glob '!ReadingSessionStore.swift'; then
    echo "Boundary check failed: file writes must stay in ReadingSessionStore." >&2
    exit 1
fi

if rg -n 'AVCaptureMovieFileOutput|PHPhotoLibrary' Sources Apps --glob '*.swift' --glob '!CameraRecorder.swift'; then
    echo "Boundary check failed: recording/photo export must stay in CameraRecorder." >&2
    exit 1
fi

echo "Boundary check passed: no network/legacy recognizer; draft writes and explicit camera recording stay in their owners."
