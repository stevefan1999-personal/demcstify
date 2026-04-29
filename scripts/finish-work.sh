#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DB_PATH=${PROGRESS_DB:-"$PROJECT_ROOT/state/progress.db"}
WORK_ID=""
VERDICT="PASS"
COMPILE_STATUS="UNKNOWN"
DIFF_STATUS="PENDING"
ACHIEVED_TIER=""
NOTES=""

usage() {
  cat >&2 <<'USAGE'
usage: scripts/finish-work.sh [--db path] --work-id id [--verdict PASS|FAIL|DEGRADED]
                              [--compile GREEN|RED|UNKNOWN]
                              [--diff IDENTICAL|DIFFERENT|PENDING]
                              [--achieved-tier A|B] [--notes text]

Finishes the latest attempt for a claimed work item. PASS marks the work item
complete; non-PASS releases the claim for retry.
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
    --work-id)
      WORK_ID=$2
      shift 2
      ;;
    --verdict)
      VERDICT=$2
      shift 2
      ;;
    --compile)
      COMPILE_STATUS=$2
      shift 2
      ;;
    --diff)
      DIFF_STATUS=$2
      shift 2
      ;;
    --achieved-tier)
      ACHIEVED_TIER=$2
      shift 2
      ;;
    --notes)
      NOTES=$2
      shift 2
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

if [ -z "$WORK_ID" ]; then
  usage
  exit 1
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "missing required command: sqlite3" >&2
  exit 1
fi

if [ ! -f "$DB_PATH" ]; then
  echo "missing progress database: $DB_PATH" >&2
  exit 1
fi

quoted_notes=$(sql_quote "$NOTES")
achieved_tier_expr="NULL"

if [ -n "$ACHIEVED_TIER" ]; then
  quoted_tier=$(sql_quote "$ACHIEVED_TIER")
  achieved_tier_expr="(SELECT id FROM tiers WHERE name = '$quoted_tier')"
fi

sqlite3 "$DB_PATH" <<SQL
PRAGMA foreign_keys = ON;
BEGIN IMMEDIATE;

UPDATE attempts
SET
  finished_at = CURRENT_TIMESTAMP,
  compile_status_id = (SELECT id FROM compile_statuses WHERE name = '$COMPILE_STATUS'),
  diff_status_id = (SELECT id FROM diff_statuses WHERE name = '$DIFF_STATUS'),
  achieved_tier_id = $achieved_tier_expr,
  verdict_id = (SELECT id FROM verdicts WHERE name = '$VERDICT'),
  notes = CASE
    WHEN '$quoted_notes' = '' THEN notes
    ELSE '$quoted_notes'
  END
WHERE id = (
  SELECT id
  FROM attempts
  WHERE work_queue_id = $WORK_ID
  ORDER BY started_at DESC, id DESC
  LIMIT 1
);

UPDATE work_queue
SET completed_at = CURRENT_TIMESTAMP
WHERE id = $WORK_ID
  AND '$VERDICT' = 'PASS';

UPDATE work_queue
SET claimed_by_agent_id = NULL,
    claimed_at = NULL
WHERE id = $WORK_ID
  AND '$VERDICT' <> 'PASS';

COMMIT;

.headers on
.mode column
SELECT
  work_queue.id AS work_id,
  roles.name AS role,
  work_queue.subproject_name,
  verdicts.name AS verdict,
  compile_statuses.name AS compile_status,
  diff_statuses.name AS diff_status,
  attempts.finished_at,
  work_queue.completed_at
FROM work_queue
JOIN attempts ON attempts.work_queue_id = work_queue.id
JOIN roles ON roles.id = work_queue.role_id
JOIN verdicts ON verdicts.id = attempts.verdict_id
JOIN compile_statuses ON compile_statuses.id = attempts.compile_status_id
JOIN diff_statuses ON diff_statuses.id = attempts.diff_status_id
WHERE work_queue.id = $WORK_ID
ORDER BY attempts.id DESC
LIMIT 1;
SQL
