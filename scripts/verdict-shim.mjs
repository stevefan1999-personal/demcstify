#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const scriptPath = fileURLToPath(import.meta.url);
const scriptDir = dirname(scriptPath);

function parseArgs(argv) {
  const options = {};
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
      case "--attempt-id":
        options.attemptId = argv.at(argumentIndex + 1);
        argumentIndex += 1;
        break;
      case "-h":
      case "--help":
        console.error("usage: scripts/verdict-shim.mjs --class fqn [--db path] [--attempt-id id]");
        process.exit(0);
        break;
      default:
        if (!options.classFqn && !argument.startsWith("-")) {
          options.classFqn = argument;
        } else {
          throw new Error(`unknown argument: ${argument}`);
        }
    }
  }
  if (!options.classFqn) {
    throw new Error("missing required class fqn");
  }
  return options;
}

try {
  const options = parseArgs(process.argv.slice(2));
  const bytecodeDiffArgs = [
    join(scriptDir, "bytecode-diff.mjs"),
    "--class",
    options.classFqn,
    "--allow-different",
  ];

  if (options.dbPath) {
    bytecodeDiffArgs.push("--db", options.dbPath);
  }
  if (options.attemptId) {
    bytecodeDiffArgs.push("--attempt-id", options.attemptId);
  }

  const diffResult = JSON.parse(execFileSync(process.execPath, bytecodeDiffArgs, { encoding: "utf8" }));
  console.log(JSON.stringify({
    class: diffResult.class,
    tier: diffResult.tier,
    verdict: diffResult.verdict,
  }));
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
