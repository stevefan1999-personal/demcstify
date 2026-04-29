#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const scriptPath = fileURLToPath(import.meta.url);
const projectRoot = join(dirname(scriptPath), "..");
const defaultDbPath = join(projectRoot, "state/progress.db");
const defaultGroundTruthJar = join(projectRoot, "ground_truth/26.1.2.jar");
const defaultMaxEntries = 80;
const maxCommandBuffer = 128 * 1024 * 1024;

function usage() {
  console.error(`usage: scripts/bytecode-diff.mjs --class fqn [--db path] [--attempt-id id] [--allow-different]

Compares one rebuilt class against ground_truth/26.1.2.jar at Tier A.
When --attempt-id is present, javap/diff evidence is persisted in state/progress.db.`);
}

function parseArgs(argv) {
  const options = {
    dbPath: defaultDbPath,
    groundTruthJar: defaultGroundTruthJar,
    maxEntries: defaultMaxEntries,
    allowDifferent: false,
  };

  for (let argumentIndex = 0; argumentIndex < argv.length; argumentIndex += 1) {
    const argument = argv[argumentIndex];
    switch (argument) {
      case "--class":
        options.classFqn = argv.at(argumentIndex + 1);
        argumentIndex += 1;
        break;
      case "--db":
        options.dbPath = argv.at(argumentIndex + 1);
        argumentIndex += 1;
        break;
      case "--jar":
        options.groundTruthJar = argv.at(argumentIndex + 1);
        argumentIndex += 1;
        break;
      case "--attempt-id":
        options.attemptId = Number.parseInt(argv.at(argumentIndex + 1) ?? "", 10);
        argumentIndex += 1;
        break;
      case "--max-entries":
        options.maxEntries = Number.parseInt(argv.at(argumentIndex + 1) ?? "", 10);
        argumentIndex += 1;
        break;
      case "--allow-different":
        options.allowDifferent = true;
        break;
      case "--json":
        break;
      case "-h":
      case "--help":
        usage();
        process.exit(0);
        break;
      default:
        throw new Error(`unknown argument: ${argument}`);
    }
  }

  if (!options.classFqn) {
    throw new Error("missing required --class fqn");
  }
  if (options.attemptId !== undefined && !Number.isSafeInteger(options.attemptId)) {
    throw new Error("--attempt-id must be an integer");
  }
  if (!Number.isSafeInteger(options.maxEntries) || options.maxEntries < 1) {
    throw new Error("--max-entries must be a positive integer");
  }

  return options;
}

function sqlLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function sqlMaybe(value) {
  return value === undefined ? "NULL" : sqlLiteral(value);
}

function sqliteJson(dbPath, query) {
  const stdout = execFileSync("sqlite3", ["-json", dbPath, query], {
    encoding: "utf8",
    maxBuffer: maxCommandBuffer,
  }).trim();
  return stdout === "" ? [] : JSON.parse(stdout);
}

function sqliteExec(dbPath, query) {
  execFileSync("sqlite3", [dbPath, query], {
    encoding: "utf8",
    maxBuffer: maxCommandBuffer,
  });
}

function requireClassRow(dbPath, classFqn) {
  const rows = sqliteJson(
    dbPath,
    `SELECT
       classes.fqn AS classFqn,
       classes.subproject_name AS subprojectName,
       tiers.name AS targetTier
     FROM classes
     JOIN tiers ON tiers.id = classes.target_tier_id
     WHERE classes.fqn = ${sqlLiteral(classFqn)}
     LIMIT 1;`,
  );
  if (rows.length !== 1) {
    throw new Error(`class is not inventoried in state/progress.db: ${classFqn}`);
  }
  return rows[0];
}

function toClassEntry(classFqn) {
  return `${classFqn.replaceAll(".", "/")}.class`;
}

function sha256(buffer) {
  return createHash("sha256").update(buffer).digest("hex");
}

function readOriginalBytes(groundTruthJar, classEntry) {
  return execFileSync("unzip", ["-p", groundTruthJar, classEntry], {
    encoding: "buffer",
    maxBuffer: maxCommandBuffer,
    stdio: ["ignore", "pipe", "pipe"],
  });
}

function runJavap(args) {
  try {
    return execFileSync("javap", args, {
      encoding: "utf8",
      maxBuffer: maxCommandBuffer,
      stdio: ["ignore", "pipe", "pipe"],
    });
  } catch (error) {
    const stdout = Buffer.isBuffer(error.stdout) ? error.stdout.toString("utf8") : String(error.stdout ?? "");
    const stderr = Buffer.isBuffer(error.stderr) ? error.stderr.toString("utf8") : String(error.stderr ?? "");
    return `${stdout}${stderr}`;
  }
}

function runDiff(originalPath, rebuiltPath) {
  try {
    return execFileSync(
      "diff",
      ["-u", "--label", "original", "--label", "recompiled", originalPath, rebuiltPath],
      {
        encoding: "utf8",
        maxBuffer: maxCommandBuffer,
        stdio: ["ignore", "pipe", "pipe"],
      },
    );
  } catch (error) {
    if (error.status === 1) {
      return error.stdout.toString("utf8");
    }
    throw error;
  }
}

function javapEvidencePaths(classFqn) {
  const javapDir = join(projectRoot, "state/javap");
  mkdirSync(javapDir, { recursive: true });
  return {
    originalPath: join(javapDir, `${classFqn}.original.javap.txt`),
    rebuiltPath: join(javapDir, `${classFqn}.recompiled.javap.txt`),
    diffPath: join(javapDir, `${classFqn}.diff.txt`),
  };
}

function writeJavapEvidence({ classFqn, compiledClassPath, groundTruthJar, originalSha256, rebuiltSha256 }) {
  const evidencePaths = javapEvidencePaths(classFqn);
  const originalJavap = runJavap(["-v", "-p", "-classpath", groundTruthJar, classFqn]);
  const rebuiltJavap = runJavap(["-v", "-p", compiledClassPath]);

  writeFileSync(evidencePaths.originalPath, originalJavap);
  writeFileSync(evidencePaths.rebuiltPath, rebuiltJavap);

  const diffOutput = runDiff(evidencePaths.originalPath, evidencePaths.rebuiltPath);
  const output = diffOutput === ""
    ? `Binary class bytes differ but javap output is identical.
original_sha256=${originalSha256}
recompiled_sha256=${rebuiltSha256}
`
    : diffOutput;
  writeFileSync(evidencePaths.diffPath, output);
  return {
    ...evidencePaths,
    diffOutput: output,
  };
}

function classifyScope(line) {
  if (line.includes("flags:") || line.includes("ACC_")) {
    return "ACCESS_FLAGS";
  }
  if (line.includes("Constant pool:") || /^[-+]?\s*#\d+/.test(line)) {
    return "CONSTANT_POOL";
  }
  if (line.includes("Code:") || /^[-+]?\s*\d+:\s/.test(line)) {
    return "INSTRUCTION";
  }
  if (line.includes("descriptor:") || line.includes("Method") || line.includes("(")) {
    return "METHOD";
  }
  if (line.includes("Field") || line.includes(";")) {
    return "FIELD";
  }
  return "ATTRIBUTE";
}

function diffEntries(diffOutput, maxEntries) {
  const entries = [];
  let location = "binary";
  const lines = diffOutput.split(/\r?\n/u);

  for (const line of lines) {
    if (line.startsWith("@@")) {
      location = line;
      continue;
    }
    if (line.startsWith("---") || line.startsWith("+++") || line === "") {
      continue;
    }
    if (!line.startsWith("-") && !line.startsWith("+")) {
      continue;
    }
    const diffText = line.slice(1).trimStart();
    if (
      diffText.startsWith("Classfile ")
      || diffText.startsWith("Last modified ")
      || diffText.startsWith("SHA-256 checksum ")
    ) {
      continue;
    }
    entries.push({
      scopeName: classifyScope(line),
      location,
      beforeText: line.startsWith("-") ? line.slice(1) : undefined,
      afterText: line.startsWith("+") ? line.slice(1) : undefined,
    });
    if (entries.length >= maxEntries) {
      break;
    }
  }

  if (entries.length === 0 && diffOutput.trim() !== "") {
    entries.push({
      scopeName: "ATTRIBUTE",
      location: "binary",
      beforeText: diffOutput.trim(),
    });
  }

  return entries;
}

function recordEvidence(dbPath, attemptId, evidencePath, entries) {
  const insertEntries = entries.map((entry, entryIndex) => `
INSERT INTO diff_entries(attempt_id, ordinal, scope_id, location, before_text, after_text)
VALUES (
  ${attemptId},
  ${entryIndex + 1},
  (SELECT id FROM diff_scopes WHERE name = ${sqlLiteral(entry.scopeName)}),
  ${sqlLiteral(entry.location)},
  ${sqlMaybe(entry.beforeText)},
  ${sqlMaybe(entry.afterText)}
);`).join("\n");

  sqliteExec(dbPath, `
PRAGMA foreign_keys = ON;
BEGIN IMMEDIATE;
DELETE FROM diff_entries WHERE attempt_id = ${attemptId};
${insertEntries}
INSERT INTO javap_reports(attempt_id, path, generated_at)
VALUES (${attemptId}, ${sqlLiteral(relative(projectRoot, evidencePath))}, CURRENT_TIMESTAMP)
ON CONFLICT(attempt_id) DO UPDATE SET
  path = excluded.path,
  generated_at = excluded.generated_at;
COMMIT;`);
}

function recordIdentical(dbPath, attemptId) {
  sqliteExec(dbPath, `
PRAGMA foreign_keys = ON;
BEGIN IMMEDIATE;
DELETE FROM diff_entries WHERE attempt_id = ${attemptId};
DELETE FROM javap_reports WHERE attempt_id = ${attemptId};
COMMIT;`);
}

function buildResult(options) {
  const classRow = requireClassRow(options.dbPath, options.classFqn);
  const classEntry = toClassEntry(classRow.classFqn);
  const compiledClassPath = join(
    projectRoot,
    "subprojects",
    classRow.subprojectName,
    "build/classes/java/main",
    ...classEntry.split("/"),
  );

  if (!existsSync(compiledClassPath)) {
    return {
      class: classRow.classFqn,
      subproject: classRow.subprojectName,
      tier: classRow.targetTier,
      verdict: "FAIL",
      compileStatus: "RED",
      diffStatus: "PENDING",
      classEntry,
      compiledClassPath: relative(projectRoot, compiledClassPath),
      notes: "compiled class is missing; run the owning subproject compile first",
    };
  }

  const originalBytes = readOriginalBytes(options.groundTruthJar, classEntry);
  const rebuiltBytes = readFileSync(compiledClassPath);
  const originalSha256 = sha256(originalBytes);
  const rebuiltSha256 = sha256(rebuiltBytes);
  const identical = originalBytes.equals(rebuiltBytes);

  if (identical) {
    if (options.attemptId !== undefined) {
      recordIdentical(options.dbPath, options.attemptId);
    }
    return {
      class: classRow.classFqn,
      subproject: classRow.subprojectName,
      tier: classRow.targetTier,
      verdict: "PASS",
      compileStatus: "GREEN",
      diffStatus: "IDENTICAL",
      classEntry,
      compiledClassPath: relative(projectRoot, compiledClassPath),
      originalSize: originalBytes.length,
      recompiledSize: rebuiltBytes.length,
      originalSha256,
      recompiledSha256: rebuiltSha256,
    };
  }

  const evidence = writeJavapEvidence({
    classFqn: classRow.classFqn,
    compiledClassPath,
    groundTruthJar: options.groundTruthJar,
    originalSha256,
    rebuiltSha256,
  });
  const entries = diffEntries(evidence.diffOutput, options.maxEntries);

  if (options.attemptId !== undefined) {
    recordEvidence(options.dbPath, options.attemptId, evidence.diffPath, entries);
  }

  return {
    class: classRow.classFqn,
    subproject: classRow.subprojectName,
    tier: classRow.targetTier,
    verdict: "FAIL",
    compileStatus: "GREEN",
    diffStatus: "DIFFERENT",
    classEntry,
    compiledClassPath: relative(projectRoot, compiledClassPath),
    originalSize: originalBytes.length,
    recompiledSize: rebuiltBytes.length,
    originalSha256,
    recompiledSha256: rebuiltSha256,
    javapDiffPath: relative(projectRoot, evidence.diffPath),
    diffEntryCount: entries.length,
  };
}

try {
  const options = parseArgs(process.argv.slice(2));
  const result = buildResult(options);
  console.log(JSON.stringify(result, undefined, 2));
  if (!options.allowDifferent && result.verdict !== "PASS") {
    process.exitCode = 2;
  }
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
