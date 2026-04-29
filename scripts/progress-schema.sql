PRAGMA foreign_keys = ON;

BEGIN;

CREATE TABLE IF NOT EXISTS roles (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS tiers (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS verdicts (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS compile_statuses (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS diff_statuses (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS diff_scopes (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS probe_sources (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS layers (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  ordinal INTEGER NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS subprojects (
  name TEXT PRIMARY KEY,
  layer_id INTEGER NOT NULL REFERENCES layers(id),
  gradle_path TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS classes (
  fqn TEXT PRIMARY KEY,
  subproject_name TEXT NOT NULL REFERENCES subprojects(name),
  target_tier_id INTEGER NOT NULL REFERENCES tiers(id)
);

CREATE TABLE IF NOT EXISTS agents (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS work_queue (
  id INTEGER PRIMARY KEY,
  role_id INTEGER NOT NULL REFERENCES roles(id),
  subproject_name TEXT NOT NULL REFERENCES subprojects(name),
  target_class_fqn TEXT REFERENCES classes(fqn),
  priority INTEGER NOT NULL DEFAULT 0,
  claimed_by_agent_id INTEGER REFERENCES agents(id),
  claimed_at TEXT,
  completed_at TEXT,
  CHECK (
    (claimed_by_agent_id IS NULL AND claimed_at IS NULL)
    OR (claimed_by_agent_id IS NOT NULL AND claimed_at IS NOT NULL)
  )
);

CREATE TABLE IF NOT EXISTS attempts (
  id INTEGER PRIMARY KEY,
  work_queue_id INTEGER REFERENCES work_queue(id),
  class_fqn TEXT REFERENCES classes(fqn),
  agent_id INTEGER NOT NULL REFERENCES agents(id),
  role_id INTEGER NOT NULL REFERENCES roles(id),
  started_at TEXT NOT NULL,
  finished_at TEXT,
  compile_status_id INTEGER NOT NULL REFERENCES compile_statuses(id),
  diff_status_id INTEGER NOT NULL REFERENCES diff_statuses(id),
  achieved_tier_id INTEGER REFERENCES tiers(id),
  verdict_id INTEGER NOT NULL REFERENCES verdicts(id),
  notes TEXT,
  CHECK (finished_at IS NULL OR finished_at >= started_at)
);

CREATE TABLE IF NOT EXISTS diff_entries (
  attempt_id INTEGER NOT NULL REFERENCES attempts(id) ON DELETE CASCADE,
  ordinal INTEGER NOT NULL,
  scope_id INTEGER NOT NULL REFERENCES diff_scopes(id),
  location TEXT NOT NULL,
  before_text TEXT,
  after_text TEXT,
  PRIMARY KEY (attempt_id, ordinal)
);

CREATE TABLE IF NOT EXISTS javap_reports (
  attempt_id INTEGER PRIMARY KEY REFERENCES attempts(id) ON DELETE CASCADE,
  path TEXT NOT NULL UNIQUE,
  generated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS toolchain_probes (
  id INTEGER PRIMARY KEY,
  vendor TEXT NOT NULL,
  major INTEGER NOT NULL,
  minor INTEGER NOT NULL,
  patch INTEGER NOT NULL,
  source_id INTEGER NOT NULL REFERENCES probe_sources(id),
  chosen INTEGER NOT NULL DEFAULT 0 CHECK (chosen IN (0, 1)),
  probed_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS toolchain (
  component TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  probe_id INTEGER REFERENCES toolchain_probes(id),
  set_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_classes_subproject ON classes(subproject_name);
CREATE INDEX IF NOT EXISTS idx_work_queue_claim ON work_queue(completed_at, claimed_by_agent_id, priority);
CREATE INDEX IF NOT EXISTS idx_attempts_class_started ON attempts(class_fqn, started_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_diff_entries_attempt ON diff_entries(attempt_id);

INSERT INTO roles(name)
VALUES
  ('decompiler'),
  ('compiler_fixer'),
  ('bytecode_aligner'),
  ('verifier'),
  ('librarian')
ON CONFLICT(name) DO NOTHING;

INSERT INTO tiers(name)
VALUES
  ('A'),
  ('B')
ON CONFLICT(name) DO NOTHING;

INSERT INTO verdicts(name)
VALUES
  ('PASS'),
  ('FAIL'),
  ('DEGRADED'),
  ('PENDING')
ON CONFLICT(name) DO NOTHING;

INSERT INTO compile_statuses(name)
VALUES
  ('GREEN'),
  ('RED'),
  ('UNKNOWN')
ON CONFLICT(name) DO NOTHING;

INSERT INTO diff_statuses(name)
VALUES
  ('IDENTICAL'),
  ('DIFFERENT'),
  ('PENDING')
ON CONFLICT(name) DO NOTHING;

INSERT INTO diff_scopes(name)
VALUES
  ('METHOD'),
  ('FIELD'),
  ('ATTRIBUTE'),
  ('CONSTANT_POOL'),
  ('INSTRUCTION'),
  ('ACCESS_FLAGS')
ON CONFLICT(name) DO NOTHING;

INSERT INTO probe_sources(name)
VALUES
  ('MANIFEST'),
  ('FINGERPRINT'),
  ('BRUTE_FORCE')
ON CONFLICT(name) DO NOTHING;

INSERT INTO layers(name, ordinal)
VALUES
  ('common', 0),
  ('datafix', 1),
  ('world', 2),
  ('network', 3),
  ('server', 4),
  ('client', 5)
ON CONFLICT(name) DO UPDATE SET ordinal = excluded.ordinal;

INSERT INTO subprojects(name, layer_id, gradle_path)
SELECT 'brigadier', id, ':brigadier'
FROM layers
WHERE name = 'common'
ON CONFLICT(name) DO UPDATE SET layer_id = excluded.layer_id, gradle_path = excluded.gradle_path;

INSERT INTO subprojects(name, layer_id, gradle_path)
SELECT 'datafixerupper', id, ':datafixerupper'
FROM layers
WHERE name = 'common'
ON CONFLICT(name) DO UPDATE SET layer_id = excluded.layer_id, gradle_path = excluded.gradle_path;

INSERT INTO subprojects(name, layer_id, gradle_path)
SELECT 'authlib', id, ':authlib'
FROM layers
WHERE name = 'common'
ON CONFLICT(name) DO UPDATE SET layer_id = excluded.layer_id, gradle_path = excluded.gradle_path;

INSERT INTO subprojects(name, layer_id, gradle_path)
SELECT 'minecraft-common', id, ':minecraft-common'
FROM layers
WHERE name = 'world'
ON CONFLICT(name) DO UPDATE SET layer_id = excluded.layer_id, gradle_path = excluded.gradle_path;

INSERT INTO subprojects(name, layer_id, gradle_path)
SELECT 'minecraft-server', id, ':minecraft-server'
FROM layers
WHERE name = 'server'
ON CONFLICT(name) DO UPDATE SET layer_id = excluded.layer_id, gradle_path = excluded.gradle_path;

INSERT INTO subprojects(name, layer_id, gradle_path)
SELECT 'minecraft-client', id, ':minecraft-client'
FROM layers
WHERE name = 'client'
ON CONFLICT(name) DO UPDATE SET layer_id = excluded.layer_id, gradle_path = excluded.gradle_path;

INSERT INTO subprojects(name, layer_id, gradle_path)
SELECT 'blaze3d', id, ':blaze3d'
FROM layers
WHERE name = 'client'
ON CONFLICT(name) DO UPDATE SET layer_id = excluded.layer_id, gradle_path = excluded.gradle_path;

COMMIT;

DROP VIEW IF EXISTS current_class_state;
CREATE VIEW current_class_state AS
WITH ranked_attempts AS (
  SELECT
    attempts.*,
    ROW_NUMBER() OVER (
      PARTITION BY attempts.class_fqn
      ORDER BY attempts.started_at DESC, attempts.id DESC
    ) AS attempt_rank
  FROM attempts
  WHERE attempts.class_fqn IS NOT NULL
),
latest_attempts AS (
  SELECT *
  FROM ranked_attempts
  WHERE attempt_rank = 1
)
SELECT
  classes.fqn AS class_fqn,
  classes.subproject_name,
  target_tiers.name AS target_tier,
  latest_attempts.id AS attempt_id,
  agents.name AS agent_name,
  roles.name AS role_name,
  latest_attempts.started_at,
  latest_attempts.finished_at,
  compile_statuses.name AS compile_status,
  diff_statuses.name AS diff_status,
  achieved_tiers.name AS achieved_tier,
  verdicts.name AS verdict,
  latest_attempts.notes
FROM classes
JOIN tiers AS target_tiers ON target_tiers.id = classes.target_tier_id
LEFT JOIN latest_attempts ON latest_attempts.class_fqn = classes.fqn
LEFT JOIN agents ON agents.id = latest_attempts.agent_id
LEFT JOIN roles ON roles.id = latest_attempts.role_id
LEFT JOIN compile_statuses ON compile_statuses.id = latest_attempts.compile_status_id
LEFT JOIN diff_statuses ON diff_statuses.id = latest_attempts.diff_status_id
LEFT JOIN tiers AS achieved_tiers ON achieved_tiers.id = latest_attempts.achieved_tier_id
LEFT JOIN verdicts ON verdicts.id = latest_attempts.verdict_id;

DROP VIEW IF EXISTS subproject_health;
CREATE VIEW subproject_health AS
SELECT
  subprojects.name,
  layers.name AS layer_name,
  layers.ordinal AS layer_ordinal,
  COUNT(classes.fqn) AS class_count,
  SUM(CASE WHEN current_class_state.verdict = 'PASS' THEN 1 ELSE 0 END) AS pass_count,
  SUM(CASE WHEN current_class_state.verdict = 'FAIL' THEN 1 ELSE 0 END) AS fail_count,
  SUM(CASE WHEN current_class_state.verdict IS NULL THEN 1 ELSE 0 END) AS unattempted_count,
  SUM(CASE WHEN current_class_state.compile_status = 'GREEN' THEN 1 ELSE 0 END) AS compile_green_count,
  SUM(CASE WHEN current_class_state.diff_status = 'IDENTICAL' THEN 1 ELSE 0 END) AS diff_identical_count
FROM subprojects
JOIN layers ON layers.id = subprojects.layer_id
LEFT JOIN classes ON classes.subproject_name = subprojects.name
LEFT JOIN current_class_state ON current_class_state.class_fqn = classes.fqn
GROUP BY subprojects.name, layers.name, layers.ordinal;

DROP VIEW IF EXISTS tier_a_coverage;
CREATE VIEW tier_a_coverage AS
SELECT
  COUNT(classes.fqn) AS total_classes,
  SUM(CASE WHEN target_tiers.name = 'A' THEN 1 ELSE 0 END) AS target_tier_a_classes,
  SUM(
    CASE
      WHEN current_class_state.verdict = 'PASS'
        AND current_class_state.achieved_tier = 'A'
      THEN 1
      ELSE 0
    END
  ) AS tier_a_pass_classes,
  ROUND(
    100.0
    * SUM(
      CASE
        WHEN current_class_state.verdict = 'PASS'
          AND current_class_state.achieved_tier = 'A'
        THEN 1
        ELSE 0
      END
    )
    / NULLIF(COUNT(classes.fqn), 0),
    2
  ) AS tier_a_pass_percent
FROM classes
JOIN tiers AS target_tiers ON target_tiers.id = classes.target_tier_id
LEFT JOIN current_class_state ON current_class_state.class_fqn = classes.fqn;
