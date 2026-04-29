#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE_PATH=${VINEFLOWER_OUTPUT_DIR:-"$PROJECT_ROOT/ground_truth/src-vineflower"}
SUBPROJECT=""
MODE="copy"
CLEAN_OUTPUT=0

usage() {
  cat >&2 <<'USAGE'
usage: scripts/route-vineflower-output.sh --subproject name [--source path] [--dry-run] [--clean]

Mechanically copies Vineflower .java output into one subproject's gitignored
src/main/java tree. The package-to-subproject mapping matches the inventory
logic in scripts/init-progress-db.sh.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --subproject)
      SUBPROJECT=$2
      shift 2
      ;;
    --source)
      SOURCE_PATH=$2
      shift 2
      ;;
    --dry-run)
      MODE="dry-run"
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

if [ -z "$SUBPROJECT" ]; then
  usage
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "missing required command: python3" >&2
  exit 1
fi

python3 - "$PROJECT_ROOT" "$SOURCE_PATH" "$SUBPROJECT" "$MODE" "$CLEAN_OUTPUT" <<'PY'
from __future__ import annotations

import pathlib
import shutil
import sys
import zipfile

project_root = pathlib.Path(sys.argv[1])
source_path = pathlib.Path(sys.argv[2])
subproject = sys.argv[3]
mode = sys.argv[4]
clean_output = sys.argv[5] == "1"
target_root = project_root / "subprojects" / subproject / "src" / "main" / "java"

known_subprojects = {
  "brigadier",
  "datafixerupper",
  "authlib",
  "blaze3d",
  "minecraft-common",
  "minecraft-server",
  "minecraft-client",
}

def mapped_subproject(java_path: str) -> str:
  if java_path.startswith("com/mojang/brigadier/"):
    return "brigadier"
  if java_path.startswith(("com/mojang/datafixers/", "com/mojang/serialization/")):
    return "datafixerupper"
  if java_path.startswith("com/mojang/authlib/"):
    return "authlib"
  if java_path.startswith("com/mojang/blaze3d/"):
    return "blaze3d"
  if java_path.startswith(("net/minecraft/server/", "net/minecraft/gametest/")):
    return "minecraft-server"
  if java_path.startswith(("net/minecraft/client/", "net/minecraft/realms/", "com/mojang/realmsclient/")):
    return "minecraft-client"
  return "minecraft-common"

def source_archive(path: pathlib.Path) -> pathlib.Path | None:
  if path.is_file() and path.suffix in {".jar", ".zip"}:
    return path
  if not path.is_dir():
    return None

  archives = sorted(path.glob("*.jar")) + sorted(path.glob("*.zip"))
  preferred = [archive for archive in archives if archive.name.startswith("26.1.2")]
  return (preferred or archives or [None])[0]

def iter_java_files(path: pathlib.Path):
  archive = source_archive(path)
  if archive is not None:
    with zipfile.ZipFile(archive) as decompiled:
      for member in decompiled.namelist():
        if member.endswith(".java") and mapped_subproject(member) == subproject:
          yield member, decompiled.read(member)
    return

  if not path.is_dir():
    raise SystemExit(f"missing Vineflower output: {path}")

  for java_file in path.rglob("*.java"):
    relative_path = java_file.relative_to(path).as_posix()
    if mapped_subproject(relative_path) == subproject:
      yield relative_path, java_file.read_bytes()

if subproject not in known_subprojects:
  raise SystemExit(f"unknown subproject: {subproject}")

files = list(iter_java_files(source_path))

if mode == "dry-run":
  print(f"subproject={subproject}")
  print(f"source={source_path}")
  print(f"target={target_root}")
  print(f"java_files={len(files)}")
  for java_path, _ in files[:10]:
    print(java_path)
  raise SystemExit(0)

if clean_output and target_root.exists():
  shutil.rmtree(target_root)

if not files:
  print(f"routed 0 Java files to {target_root}")
  raise SystemExit(0)

target_root.mkdir(parents=True, exist_ok=True)

for java_path, contents in files:
  target_path = target_root / java_path
  target_path.parent.mkdir(parents=True, exist_ok=True)
  target_path.write_bytes(contents)

print(f"routed {len(files)} Java files to {target_root}")
PY
