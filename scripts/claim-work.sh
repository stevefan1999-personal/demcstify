#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DB_PATH=${PROGRESS_DB:-"$PROJECT_ROOT/state/progress.db"}
AGENT_NAME=${AGENT_NAME:-"codex-ultrawork-$(date -u +%Y%m%dT%H%M%SZ)-$$"}

sql_quote() {
  printf "%s" "$1" | sed "s/'/''/g"
}

usage() {
  cat >&2 <<'USAGE'
usage: scripts/claim-work.sh [--db path] [--agent name]

Atomically claims the lowest-layer unclaimed work_queue row and inserts a
PENDING attempts row for the claim.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --db)
      DB_PATH=$2
      shift 2
      ;;
    --agent)
      AGENT_NAME=$2
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

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "missing required command: sqlite3" >&2
  exit 1
fi

if [ ! -f "$DB_PATH" ]; then
  echo "missing progress database: $DB_PATH" >&2
  echo "run scripts/init-progress-db.sh first" >&2
  exit 1
fi

quoted_agent=$(sql_quote "$AGENT_NAME")

sqlite3 "$DB_PATH" <<SQL
PRAGMA foreign_keys = ON;
BEGIN IMMEDIATE;

INSERT INTO agents(name)
VALUES ('$quoted_agent')
ON CONFLICT(name) DO NOTHING;

DROP TABLE IF EXISTS selected_work;
CREATE TEMP TABLE selected_work AS
SELECT work_queue.id
FROM work_queue
JOIN subprojects ON subprojects.name = work_queue.subproject_name
JOIN layers ON layers.id = subprojects.layer_id
LEFT JOIN attempts ON attempts.work_queue_id = work_queue.id
WHERE work_queue.claimed_by_agent_id IS NULL
  AND work_queue.completed_at IS NULL
GROUP BY work_queue.id
ORDER BY layers.ordinal ASC, work_queue.priority DESC, COUNT(attempts.id) ASC, work_queue.id ASC
LIMIT 1;

UPDATE work_queue
SET
  claimed_by_agent_id = (SELECT id FROM agents WHERE name = '$quoted_agent'),
  claimed_at = CURRENT_TIMESTAMP
WHERE id IN (SELECT id FROM selected_work);

INSERT INTO attempts(
  work_queue_id,
  class_fqn,
  agent_id,
  role_id,
  started_at,
  compile_status_id,
  diff_status_id,
  verdict_id,
  notes
)
SELECT
  work_queue.id,
  work_queue.target_class_fqn,
  agents.id,
  work_queue.role_id,
  CURRENT_TIMESTAMP,
  compile_statuses.id,
  diff_statuses.id,
  verdicts.id,
  'claim created by scripts/claim-work.sh'
FROM selected_work
JOIN work_queue ON work_queue.id = selected_work.id
JOIN agents ON agents.name = '$quoted_agent'
JOIN compile_statuses ON compile_statuses.name = 'UNKNOWN'
JOIN diff_statuses ON diff_statuses.name = 'PENDING'
JOIN verdicts ON verdicts.name = 'PENDING';

COMMIT;

.headers on
.mode column
SELECT
  work_queue.id AS work_id,
  attempts.id AS attempt_id,
  roles.name AS role,
  work_queue.subproject_name,
  work_queue.target_class_fqn,
  agents.name AS agent,
  work_queue.claimed_at
FROM selected_work
JOIN work_queue ON work_queue.id = selected_work.id
JOIN roles ON roles.id = work_queue.role_id
JOIN agents ON agents.id = work_queue.claimed_by_agent_id
JOIN attempts ON attempts.work_queue_id = work_queue.id
ORDER BY attempts.id DESC
LIMIT 1;
SQL
