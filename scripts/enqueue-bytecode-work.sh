#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DB_PATH=${PROGRESS_DB:-"$PROJECT_ROOT/state/progress.db"}
CLASS_FQN=""
LIMIT=""
PACKAGE_INFO_ONLY=0

usage() {
  cat >&2 <<'USAGE'
usage: scripts/enqueue-bytecode-work.sh [--db path] [--class fqn] [--limit n] [--package-info-only]

Seeds bytecode_aligner work_queue rows from the class inventory. The command is
idempotent and never duplicates an existing bytecode_aligner row for a class.
USAGE
}

sql_quote() {
  printf "%s" "$1" | sed "s/'/''/g"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --db)
      DB_PATH=$2
      shift 2
      ;;
    --class)
      CLASS_FQN=$2
      shift 2
      ;;
    --limit)
      LIMIT=$2
      shift 2
      ;;
    --package-info-only)
      PACKAGE_INFO_ONLY=1
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

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "missing required command: sqlite3" >&2
  exit 1
fi

if [ ! -f "$DB_PATH" ]; then
  echo "missing progress database: $DB_PATH" >&2
  exit 1
fi

class_filter="1 = 1"
if [ -n "$CLASS_FQN" ]; then
  quoted_class=$(sql_quote "$CLASS_FQN")
  class_filter="classes.fqn = '$quoted_class'"
fi

package_filter="1 = 1"
if [ "$PACKAGE_INFO_ONLY" -eq 1 ]; then
  package_filter="classes.fqn LIKE '%package-info'"
fi

limit_clause=""
if [ -n "$LIMIT" ]; then
  case "$LIMIT" in
    ''|*[!0-9]*)
      echo "--limit must be a non-negative integer" >&2
      exit 1
      ;;
  esac
  limit_clause="LIMIT $LIMIT"
fi

sqlite3 "$DB_PATH" <<SQL
PRAGMA foreign_keys = ON;
BEGIN IMMEDIATE;

DROP TABLE IF EXISTS selected_bytecode_work;
CREATE TEMP TABLE selected_bytecode_work AS
SELECT
  classes.fqn,
  classes.subproject_name,
  CASE
    WHEN classes.fqn LIKE '%package-info' THEN 1000000
    ELSE 0
  END AS priority
FROM classes
WHERE $class_filter
  AND $package_filter
  AND NOT EXISTS (
    SELECT 1
    FROM work_queue
    JOIN roles ON roles.id = work_queue.role_id
    WHERE roles.name = 'bytecode_aligner'
      AND work_queue.target_class_fqn = classes.fqn
  )
ORDER BY
  CASE WHEN classes.fqn LIKE '%package-info' THEN 0 ELSE 1 END,
  classes.subproject_name,
  classes.fqn
$limit_clause;

INSERT INTO work_queue(role_id, subproject_name, target_class_fqn, priority)
SELECT
  roles.id,
  selected_bytecode_work.subproject_name,
  selected_bytecode_work.fqn,
  selected_bytecode_work.priority
FROM selected_bytecode_work
CROSS JOIN roles
WHERE roles.name = 'bytecode_aligner';

COMMIT;

.headers on
.mode column
SELECT COUNT(*) AS inserted_rows FROM selected_bytecode_work;
SELECT
  COUNT(*) AS open_bytecode_rows
FROM work_queue
JOIN roles ON roles.id = work_queue.role_id
WHERE roles.name = 'bytecode_aligner'
  AND work_queue.completed_at IS NULL;
SQL
