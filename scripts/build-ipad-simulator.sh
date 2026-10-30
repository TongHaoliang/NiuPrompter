#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${TELEPROMPTER_IPAD_BUILD_ROOT:-/private/tmp/smartteleprompterprobe-ipad-build}"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen is required to generate the iPad project." >&2
    exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "xcodebuild from a full Xcode installation is required." >&2
    exit 1
fi

mkdir -p "$BUILD_ROOT"
export TELEPROMPTER_PACKAGE_ROOT="$PROJECT_ROOT"

xcodegen generate \
    --spec "$PROJECT_ROOT/project.yml" \
    --project "$BUILD_ROOT" \
    --project-root "$PROJECT_ROOT"

xcodebuild \
    -project "$BUILD_ROOT/SmartTeleprompterProbe-iPadProject.xcodeproj" \
    -scheme SmartTeleprompterProbe-iPad \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$BUILD_ROOT/DerivedData" \
    -clonedSourcePackagesDirPath "$BUILD_ROOT/SourcePackages" \
    -packageCachePath "$BUILD_ROOT/PackageCache" \
    CODE_SIGNING_ALLOWED=NO \
    build
