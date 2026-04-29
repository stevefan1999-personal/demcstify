#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
JAR_PATH=${GROUND_TRUTH_JAR:-"$PROJECT_ROOT/ground_truth/26.1.2.jar"}
OUTPUT_DIR=${VINEFLOWER_OUTPUT_DIR:-"$PROJECT_ROOT/ground_truth/src-vineflower"}
VINEFLOWER_VERSION=${VINEFLOWER_VERSION:-"1.12.0"}
VINEFLOWER_BASE_URL=${VINEFLOWER_BASE_URL:-"https://repo1.maven.org/maven2/org/vineflower/vineflower/$VINEFLOWER_VERSION"}
VINEFLOWER_CACHE_DIR=${VINEFLOWER_CACHE_DIR:-"$PROJECT_ROOT/.gradle/vineflower"}
VINEFLOWER_JAR=${VINEFLOWER_JAR:-"$VINEFLOWER_CACHE_DIR/vineflower-$VINEFLOWER_VERSION.jar"}
MODE="run"
CLEAN_OUTPUT=0
DOWNLOAD=0

usage() {
  cat >&2 <<'USAGE'
usage: scripts/decompile.sh [--dry-run] [--download] [--clean]

Runs pinned Vineflower against ground_truth/26.1.2.jar and writes decompiled
Java into ground_truth/src-vineflower. The output directory is gitignored.

Environment:
  VINEFLOWER_VERSION      Default: 1.12.0
  VINEFLOWER_JAR          Use an existing Vineflower jar
  VINEFLOWER_OPTIONS      Extra options passed before the source jar
  GROUND_TRUTH_JAR        Source jar override
  VINEFLOWER_OUTPUT_DIR   Output directory override
USAGE
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

download_vineflower() {
  require_command curl
  require_command sha1sum

  mkdir -p "$VINEFLOWER_CACHE_DIR"

  local jar_url="$VINEFLOWER_BASE_URL/vineflower-$VINEFLOWER_VERSION.jar"
  local sha1_url="$jar_url.sha1"
  local expected_sha1
  expected_sha1=$(curl -fsSL "$sha1_url" | tr -d '[:space:]')

  curl -fL "$jar_url" -o "$VINEFLOWER_JAR"

  local actual_sha1
  actual_sha1=$(sha1sum "$VINEFLOWER_JAR" | awk '{print $1}')

  if [ "$actual_sha1" != "$expected_sha1" ]; then
    rm -f "$VINEFLOWER_JAR"
    echo "Vineflower checksum mismatch for $jar_url" >&2
    echo "expected: $expected_sha1" >&2
    echo "actual:   $actual_sha1" >&2
    exit 1
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      MODE="dry-run"
      shift
      ;;
    --download)
      DOWNLOAD=1
      shift
      ;;
    --clean)
      CLEAN_OUTPUT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

require_command java

if [ ! -f "$JAR_PATH" ]; then
  echo "missing ground-truth jar: $JAR_PATH" >&2
  exit 1
fi

if [ "$MODE" = "dry-run" ]; then
  printf 'java -jar %q %s %q %q\n' "$VINEFLOWER_JAR" "${VINEFLOWER_OPTIONS:-}" "$JAR_PATH" "$OUTPUT_DIR"
  exit 0
fi

if [ "$DOWNLOAD" -eq 1 ] && [ ! -f "$VINEFLOWER_JAR" ]; then
  download_vineflower
fi

if [ ! -f "$VINEFLOWER_JAR" ]; then
  echo "missing Vineflower jar: $VINEFLOWER_JAR" >&2
  echo "rerun with --download or set VINEFLOWER_JAR=/path/to/vineflower.jar" >&2
  exit 1
fi

if [ "$CLEAN_OUTPUT" -eq 1 ]; then
  rm -rf "$OUTPUT_DIR"
fi

mkdir -p "$OUTPUT_DIR"

# shellcheck disable=SC2086
java -jar "$VINEFLOWER_JAR" ${VINEFLOWER_OPTIONS:-} "$JAR_PATH" "$OUTPUT_DIR"
