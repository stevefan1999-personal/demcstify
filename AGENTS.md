@LLM_CODESTYLES.md

# Introduction

You are going to help in a project that is going to completely reconstruct the partial source code of Minecraft back into a fully functional and playable game client and server.

Read `DESIGN.md` and `ARCHITECTURE.md` before any work. Both are living documents — keep them current as the project evolves.

# Project-Specific Guardrails

## Roles

When acting as an agent in this project, declare and stay in one role per pulled task. Do not cross roles silently.

| Role | Charter |
|------|---------|
| `decompiler` | Run pinned Vineflower; route output into the assigned subproject. Never edit decompiled output beyond mechanical splitting. |
| `compiler_fixer` | Drive `gradle :sub:compileJava` to zero errors AND zero warnings. Do not touch other subprojects. |
| `bytecode_aligner` | Pull one class; drive the `bytecode-diff` task to verdict = PASS at the class's target tier. May read but not modify other classes. |
| `verifier` | Independently confirm a claim of PASS by re-running build + diff. MUST NOT be the same agent that wrote the change. |
| `librarian` | Update `DESIGN.md`, `ARCHITECTURE.md`, ADRs, schema migrations. Never touches `subprojects/*/src`. |

## Drivers

This project uses three orchestration drivers. Pick by purpose:

- **Ralph** — convergence loop on one target until evaluator returns PASS.
- **Ultrawork** — parallel fan-out across independent queue items.
- **Autoresearch** — stateful improvement loop with strict evaluator contract. Use ONLY for high-stakes decisions (toolchain pin, tier-A → tier-B downgrade). Not for routine compile fixes.

## Work-Claim Protocol

1. Query `work_queue` for unclaimed items in the lowest layer with outstanding work, leaf-first within that layer.
2. Atomically claim by setting `claimed_by_agent_id` and `claimed_at` in a single transaction.
3. Insert an `attempts` row with `started_at` set and `verdict = PENDING`.
4. Do work.
5. Update the `attempts` row with `finished_at`, `verdict`, `compile_status`, `diff_status`, `achieved_tier`, plus any `diff_entries`.
6. Mark `work_queue.completed_at` only on `verdict = PASS`.
7. Release the claim on failure (`claimed_by_agent_id = NULL`) so another agent may retry.

## Evaluator Contract

`scripts/verdict-shim.mjs` produces the canonical Autoresearch verdict for a class:

```json
{ "class": "net.minecraft.…", "tier": "A", "verdict": "PASS" }
```

Treat this as the only source of truth for completion. Never self-report PASS without running the shim.

## Tier Downgrade Discipline

A → B downgrade requires:

1. At least N failed `attempts` rows for the class (N defined in `gradle.properties` as `bytecode.tierDowngradeAttempts`).
2. An ADR under `docs/adr/` documenting why tier A is unreachable for this class, with reference to the failing diff entries.
3. Autoresearch evaluator approval. Manual claims are rejected.

## Toolchain Probe Discipline

Never invoke `gradle build` without a pinned toolchain. If `toolchain.jdk` is empty, run `scripts/probe-toolchain.sh` first. Cascade order: manifest → fingerprint → brute-force probe.

## Commit Protocol

- Conventional commits. Types: `feat`, `fix`, `refactor`, `docs`, `chore`, `test`, `build`.
- Subject prefix encodes the affected subproject: `fix(network): align packet codec descriptors`.
- One logical change per commit. Commit immediately after each discrete unit of work.
- Pre-commit MUST pass: `gradle :affected:build` green, `bytecode-diff` non-regressing for affected classes.
- `state/progress.db` is committed only via Git LFS.
- `ground_truth/src-vineflower/` is gitignored — never commit raw decompile output.

## Hard Constraints

- Zero errors AND zero warnings on `gradle build`. `-Xlint:all` is on; do not silence it.
- No `null` returns or sentinel values. Use `Optional` or `Result`-style sum types where possible.
- No magic constants. Derive from named constants.
- Comment WHY, never WHAT. `LLM_CODESTYLES.md` is authoritative.
- Never modify code outside the claimed work item. If a fix requires changing another class, file a separate `work_queue` entry first.
- Never silently widen scope: a `compiler_fixer` does not also align bytecode in the same attempt.
- **Never commit reconstructed Minecraft sources.** `subprojects/*/src/` is gitignored. The reconstruction is performed locally on the user's machine; no decompiled, repaired, or rebuilt Minecraft code is to be pushed to any remote. Committing such code would be both an IP redistribution and a violation of this project's legal stance (see README.md).

## Where State Lives

| Artifact | Location | Tracked |
|----------|----------|---------|
| Source (reconstructed Minecraft code) | `subprojects/<name>/src/` | gitignored — user-local only, never committed |
| Subproject build glue (`build.gradle.kts`, etc.) | `subprojects/<name>/` (excluding `src/`) | yes |
| Build outputs | `subprojects/<name>/build/` | gitignored |
| Vineflower raw | `ground_truth/src-vineflower/` | gitignored |
| Progress DB | `state/progress.db` | yes (LFS) |
| Javap reports | `state/javap/<fqn>.txt` | gitignored (regenerated on demand) |
| ADRs | `docs/adr/` | yes |
| Research notes | `docs/research/` | yes |

## Documentation Maintenance

`DESIGN.md` and `ARCHITECTURE.md` are living. After every meaningful change, update them. When `DESIGN.md` exceeds 300 lines or 5 distinct topics, split into `docs/design/0N-<TITLE>.md` and keep an index in `DESIGN.md`. The same rule applies to `ARCHITECTURE.md` → `docs/architecture/`.
