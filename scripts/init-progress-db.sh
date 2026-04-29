#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DB_PATH=${PROGRESS_DB:-"$PROJECT_ROOT/state/progress.db"}
JAR_PATH=${GROUND_TRUTH_JAR:-"$PROJECT_ROOT/ground_truth/26.1.2.jar"}
MANIFEST_PATH=${GROUND_TRUTH_MANIFEST:-"$PROJECT_ROOT/ground_truth/26.1.2.json"}
SCHEMA_PATH="$PROJECT_ROOT/scripts/progress-schema.sql"
ENQUEUE_PATH="$PROJECT_ROOT/scripts/enqueue-work.sql"

sql_quote() {
  printf "%s" "$1" | sed "s/'/''/g"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

class_subproject_awk='
function subproject(path) {
  if (path ~ /^com\/mojang\/brigadier\//) return "brigadier"
  if (path ~ /^com\/mojang\/datafixers\// || path ~ /^com\/mojang\/serialization\//) return "datafixerupper"
  if (path ~ /^com\/mojang\/authlib\//) return "authlib"
  if (path ~ /^com\/mojang\/blaze3d\//) return "blaze3d"
  if (path ~ /^net\/minecraft\/server\// || path ~ /^net\/minecraft\/gametest\//) return "minecraft-server"
  if (path ~ /^net\/minecraft\/client\// || path ~ /^net\/minecraft\/realms\// || path ~ /^com\/mojang\/realmsclient\//) return "minecraft-client"
  return "minecraft-common"
}

/\.class$/ {
  class_path = $0
  fqn = class_path
  sub(/\.class$/, "", fqn)
  gsub(/\//, ".", fqn)
  print fqn "\t" class_path "\t" subproject(class_path)
}
'

record_manifest_toolchain() {
  if [ ! -f "$MANIFEST_PATH" ] || ! command -v jq >/dev/null 2>&1; then
    return
  fi

  local component
  local major
  component=$(jq -r '.javaVersion.component // empty' "$MANIFEST_PATH")
  major=$(jq -r '.javaVersion.majorVersion // empty' "$MANIFEST_PATH")

  if [ -z "$component" ] || [ -z "$major" ]; then
    return
  fi

  local quoted_component
  local quoted_value
  quoted_component=$(sql_quote "$component")
  quoted_value=$(sql_quote "$component:$major")

  sqlite3 "$DB_PATH" <<SQL
PRAGMA foreign_keys = ON;
BEGIN;
INSERT INTO toolchain_probes(vendor, major, minor, patch, source_id, chosen, probed_at)
SELECT '$quoted_component', $major, 0, 0, probe_sources.id, 1, CURRENT_TIMESTAMP
FROM probe_sources
WHERE probe_sources.name = 'MANIFEST'
  AND NOT EXISTS (
    SELECT 1
    FROM toolchain_probes
    JOIN probe_sources AS existing_sources ON existing_sources.id = toolchain_probes.source_id
    WHERE toolchain_probes.vendor = '$quoted_component'
      AND toolchain_probes.major = $major
      AND existing_sources.name = 'MANIFEST'
  );

INSERT OR REPLACE INTO toolchain(component, value, probe_id, set_at)
SELECT 'jdk', '$quoted_value', toolchain_probes.id, CURRENT_TIMESTAMP
FROM toolchain_probes
JOIN probe_sources ON probe_sources.id = toolchain_probes.source_id
WHERE toolchain_probes.vendor = '$quoted_component'
  AND toolchain_probes.major = $major
  AND probe_sources.name = 'MANIFEST'
ORDER BY toolchain_probes.id DESC
LIMIT 1;
COMMIT;
SQL
}

require_command sqlite3
require_command jar

if [ ! -f "$JAR_PATH" ]; then
  echo "missing ground-truth jar: $JAR_PATH" >&2
  exit 1
fi

mkdir -p "$(dirname "$DB_PATH")"

class_tsv=$(mktemp)
trap 'rm -f "$class_tsv"' EXIT

jar tf "$JAR_PATH" | awk "$class_subproject_awk" | sort -u > "$class_tsv"

sqlite3 "$DB_PATH" < "$SCHEMA_PATH"

sqlite3 "$DB_PATH" <<SQL
PRAGMA foreign_keys = ON;
DROP TABLE IF EXISTS imported_classes;
CREATE TABLE imported_classes(
  fqn TEXT NOT NULL,
  class_path TEXT NOT NULL,
  subproject_name TEXT NOT NULL
);
.mode tabs
.import $class_tsv imported_classes
BEGIN;
INSERT INTO classes(fqn, subproject_name, target_tier_id)
SELECT DISTINCT imported_classes.fqn, imported_classes.subproject_name, tiers.id
FROM imported_classes
JOIN tiers ON tiers.name = 'A'
ON CONFLICT(fqn) DO UPDATE SET subproject_name = excluded.subproject_name;
COMMIT;
DROP TABLE imported_classes;
SQL

record_manifest_toolchain
sqlite3 "$DB_PATH" < "$ENQUEUE_PATH"

sqlite3 "$DB_PATH" <<SQL
.headers on
.mode column
SELECT 'classes' AS metric, COUNT(*) AS value FROM classes
UNION ALL
SELECT 'work_queue', COUNT(*) FROM work_queue
UNION ALL
SELECT 'subprojects_with_classes', COUNT(DISTINCT subproject_name) FROM classes;

SELECT subproject_name, COUNT(*) AS class_count
FROM classes
GROUP BY subproject_name
ORDER BY class_count DESC;
SQL
