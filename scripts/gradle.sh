#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
GRADLE_VERSION=${GRADLE_VERSION:-"$(sed -n 's/^gradle.version=//p' "$PROJECT_ROOT/gradle.properties" 2>/dev/null | head -1)"}
GRADLE_VERSION=${GRADLE_VERSION:-"9.5.0"}
GRADLE_CACHE_DIR=${GRADLE_CACHE_DIR:-"$PROJECT_ROOT/.gradle/distributions"}
GRADLE_HOME="$GRADLE_CACHE_DIR/gradle-$GRADLE_VERSION"
GRADLE_ZIP="$GRADLE_CACHE_DIR/gradle-$GRADLE_VERSION-bin.zip"
GRADLE_URL=${GRADLE_URL:-"https://services.gradle.org/distributions/gradle-$GRADLE_VERSION-bin.zip"}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

download_gradle() {
  require_command curl
  require_command sha256sum
  require_command unzip

  mkdir -p "$GRADLE_CACHE_DIR"

  local expected_sha256
  expected_sha256=$(curl -fsSL "$GRADLE_URL.sha256" | tr -d '[:space:]')

  if [ ! -f "$GRADLE_ZIP" ]; then
    curl -fL "$GRADLE_URL" -o "$GRADLE_ZIP"
  fi

  local actual_sha256
  actual_sha256=$(sha256sum "$GRADLE_ZIP" | awk '{print $1}')

  if [ "$actual_sha256" != "$expected_sha256" ]; then
    rm -f "$GRADLE_ZIP"
    echo "Gradle checksum mismatch for $GRADLE_URL" >&2
    echo "expected: $expected_sha256" >&2
    echo "actual:   $actual_sha256" >&2
    exit 1
  fi

  if [ ! -x "$GRADLE_HOME/bin/gradle" ]; then
    unzip -q "$GRADLE_ZIP" -d "$GRADLE_CACHE_DIR"
  fi
}

download_gradle
exec "$GRADLE_HOME/bin/gradle" --project-dir "$PROJECT_ROOT" "$@"
