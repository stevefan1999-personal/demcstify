# Design Note 01 - Publication Contract

> Audience: maintainers, contributors, and readers evaluating the project before running it locally.

## Purpose

`demcstify` is published as a reconstruction system, not as a redistributed copy of Minecraft. The repository contains the process, schema, build glue, and evaluator that let a user reconstruct sources on their own machine from their own legitimate `ground_truth/26.1.2.jar`. Minecraft, Mojang, Mojang Studios, and related game code, assets, names, and marks are property of Mojang Studios and Microsoft; all rights are reserved by Mojang Studios and Microsoft.

The publication claim is methodological: a deterministic bytecode oracle can steer LLM agents from lossy decompiler output toward buildable, runnable, bytecode-matching Java source. The published artifact should make that method inspectable without publishing Mojang's code.

## Non-Goals

- Ship original Minecraft classes, decompiled source, repaired source, or rebuilt class files.
- Hide bytecode provenance by copying entries from `ground_truth/26.1.2.jar` into runnable artifacts.
- Treat LLM output as authoritative without evaluator evidence.
- Collapse client and server ownership into one monolith. `minecraft-server` owns server code; `minecraft-client` owns client code; shared non-server runtime code belongs in `minecraft-common`.

## Publication Boundary

| Category | Published | Local only |
| --- | --- | --- |
| Orchestration and workflow docs | yes | no |
| Gradle build logic and runnable-jar guards | yes | no |
| SQLite schema and queue scripts | yes | no |
| Original JAR / manifest | no | `ground_truth/26.1.2.jar`, `ground_truth/26.1.2.json` |
| Raw Vineflower output | no | `ground_truth/src-vineflower/` |
| Reconstructed Java source | no | `subprojects/*/src/` |
| Recompiled class files and runnable jars | no | `subprojects/*/build/`, `build/runnable/` |

The repository therefore remains a tool and a lab notebook. The user supplies the copyrighted artifact; the user's machine produces the reconstructed output.

The lab scaffolding itself is MIT licensed. That grant covers this repository's original scripts, Gradle build logic, schema, evaluator tooling, agent instructions, ADRs, and documentation. It does not license Minecraft, user-supplied ground-truth files, raw decompiler output, local reconstructed source, rebuilt class files, runnable jars, assets, names, or marks.

## Correctness Contract

Correctness is not defined by style, readability, or LLM confidence. It is defined by the evaluator pipeline:

1. Compile the assigned subproject with the pinned toolchain and zero warnings.
2. Compare the rebuilt class to `ground_truth/26.1.2.jar` with `scripts/bytecode-diff.mjs` or the Gradle `bytecodeDiff` task.
3. Persist the attempt, diff status, and javap evidence in `state/progress.db` and `state/javap/`.
4. Accept `PASS` only from `scripts/verdict-shim.mjs`.
5. Mark `work_queue.completed_at` only for evaluator-backed `PASS` rows.

Tier A is raw byte equality. Tier B is an explicit downgrade path that requires an ADR and evaluator approval. Publication should present Tier A as the default and Tier B as an exception mechanism, not as a hidden relaxation.

## Safety and Reproducibility

- The pinned JDK, Gradle, and Vineflower versions are recorded in docs and mirrored into the progress database.
- The runnable jars include reconstructed code and declared dependencies only; ground-truth resources are whitelisted separately from bytecode.
- `verifyNoGroundTruthCodeInRunnableJars` fails if original `.class` entries leak into runnable artifacts.
- Every queue item has a role, attempt history, and verdict trail in SQLite.
- Generated local source remains gitignored to avoid accidental publication.

## Reader-Facing Narrative

A concise public description should use this shape:

1. **Input:** a user-supplied legal copy of Minecraft 26.1.2.
2. **Primer:** Vineflower generates an imperfect source draft.
3. **Agents:** role-scoped LLM agents repair compile errors and bytecode mismatches one queue item at a time.
4. **Oracle:** bytecode comparison, not human preference, decides completion.
5. **Output:** local-only reconstructed sources and runnable jars, with no copied ground-truth code.

This keeps the project understandable to readers while preserving the clean publication boundary.
