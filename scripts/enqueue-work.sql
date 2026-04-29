PRAGMA foreign_keys = ON;

BEGIN;

INSERT INTO work_queue(role_id, subproject_name, target_class_fqn, priority)
SELECT
  roles.id,
  subprojects.name,
  NULL,
  COUNT(classes.fqn)
FROM subprojects
JOIN roles ON roles.name = 'decompiler'
JOIN classes ON classes.subproject_name = subprojects.name
WHERE NOT EXISTS (
  SELECT 1
  FROM work_queue
  WHERE work_queue.role_id = roles.id
    AND work_queue.subproject_name = subprojects.name
    AND work_queue.target_class_fqn IS NULL
)
GROUP BY roles.id, subprojects.name;

INSERT INTO work_queue(role_id, subproject_name, target_class_fqn, priority)
SELECT
  compiler_role.id,
  subprojects.name,
  NULL,
  COUNT(classes.fqn)
FROM subprojects
JOIN roles AS compiler_role ON compiler_role.name = 'compiler_fixer'
JOIN roles AS decompiler_role ON decompiler_role.name = 'decompiler'
JOIN classes ON classes.subproject_name = subprojects.name
WHERE EXISTS (
  SELECT 1
  FROM work_queue AS decompile_work
  JOIN attempts ON attempts.work_queue_id = decompile_work.id
  JOIN verdicts ON verdicts.id = attempts.verdict_id
  WHERE decompile_work.subproject_name = subprojects.name
    AND decompile_work.role_id = decompiler_role.id
    AND decompile_work.completed_at IS NOT NULL
    AND verdicts.name = 'PASS'
)
AND NOT EXISTS (
  SELECT 1
  FROM work_queue AS compile_work
  WHERE compile_work.role_id = compiler_role.id
    AND compile_work.subproject_name = subprojects.name
    AND compile_work.target_class_fqn IS NULL
)
GROUP BY compiler_role.id, subprojects.name;

COMMIT;
