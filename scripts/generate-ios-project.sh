#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v xcodegen >/dev/null 2>&1 || { echo "Please install XcodeGen first." >&2; exit 1; }
export TELEPROMPTER_PACKAGE_ROOT="$PROJECT_ROOT"
xcodegen generate --spec "$PROJECT_ROOT/project.yml" --project "$PROJECT_ROOT" --project-root "$PROJECT_ROOT"
printf 'Open in Xcode: %s/SmartTeleprompterProbe-iPadProject.xcodeproj\n' "$PROJECT_ROOT"
