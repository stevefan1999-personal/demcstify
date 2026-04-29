# Research Note 02 - LLM Decompilation Workflow

> Research framing for publication. This note explains why the workflow is interesting beyond this repository.

## Research Question

Can LLM agents reconstruct a large Java program from a lossy decompiler draft when every step is judged by a deterministic bytecode oracle?

This project is a practical experiment in evaluator-grounded reverse engineering. The original JAR supplies a complete behavioral and structural reference. Vineflower supplies an imperfect draft. The LLM supplies search, repair, and source-level reconstruction. The bytecode diff supplies the grade.

## Why Decompilation Is a Good Agent Benchmark

LLM coding benchmarks often use hidden tests, public tests, or human review. Those signals are useful but incomplete: a change can pass tests and still be structurally wrong. JVM source reconstruction gives a stronger oracle:

- Raw class bytes can be compared exactly.
- Debug attributes and constant-pool differences are visible.
- Every class is an independent work item with a bounded artifact.
- Attempts produce durable evidence that can be audited later.

The benchmark therefore stresses long-horizon coordination without requiring subjective grading.

## Hypothesis

A role-scoped LLM workflow should outperform a single unconstrained agent because the roles prevent common failure modes:

- Decompilers are not allowed to "repair" output while routing it.
- Compile fixers are not allowed to silently optimize bytecode shape.
- Bytecode aligners are not allowed to fix neighboring classes while chasing one class.
- Verifiers cannot be the same agent that wrote the change.
- Librarians preserve the method and constraints while implementation agents move fast.

The strict database and evaluator contracts turn these social rules into operational rules.

## Observed Repair Patterns

Early bytecode-alignment work has exposed several repeatable classes of Vineflower drift:

| Pattern | Symptom | Repair strategy |
| --- | --- | --- |
| Decompiler-added broad `@SuppressWarnings` | Line tables shifted by one or more source lines | Remove only inside the claimed class when compile remains warning-free |
| Ternary reconstruction where original used branch returns | Extra `goto`, different stack-map frames | Restore explicit early-return or branch-return shape |
| Compound assignment drift | Same semantics but different bytecode operations | Restore original compound operator shape when javap shows opcode drift |
| Static initializer layout drift | `<clinit>` line table or lambda bootstrap line mismatch | Reconstruct declaration order and source-line spacing |
| Boolean condition flattening | Fewer/more branch targets than original | Reconstruct guard clauses or `continue` structure from javap evidence |
| Debug line-table mismatch only | Raw bytes differ while instructions match | Use narrow source spacing inside the claimed class |

These patterns are well-suited to AST-aware search. `ast-grep` is useful for locating repeated syntactic shapes such as decompiler-added annotations or identical ternary/guard patterns, while per-class bytecode alignment still needs javap-guided local reasoning.

## Why SQLite Matters

Markdown status files are easy for agents to write but hard to trust. Filesystem lockfiles are also the wrong bottleneck for a swarm of different LLMs: they force agents to coordinate through broad file ownership while the real shared resource is the work queue. The reconstruction workflow needs atomic claims, queryable history, and normalized status. SQLite provides:

- a single source of truth for queue ownership;
- an append-only attempt history;
- stable coverage metrics through views;
- SQL queries for stuck classes and repeated failures;
- transaction boundaries that prevent two agents from claiming the same class;
- short database locks instead of long filesystem locks, so many agents can compile, diff, and edit independently after claiming disjoint work;
- compatibility across heterogeneous LLM runners because every worker can speak SQL without sharing process memory.

The database is not bookkeeping; it is part of the experiment design.

## Evaluation Metrics

| Metric | Meaning |
| --- | --- |
| Tier-A coverage | Fraction of inventoried classes with raw byte-identical rebuilt output |
| Compile health | Per-subproject zero-error and zero-warning status |
| Attempt count per class | Search cost and stuck-class signal |
| Diff-entry distribution | Common mismatch families across classes |
| Queue latency by layer | Whether lower-layer classes are blocking downstream reconstruction |
| Runnable-jar guard failures | Evidence that packaging boundaries are working |

A future publishable analysis can compare these metrics against a baseline single-agent workflow or a decompiler-only workflow.

## Generalization

The method should transfer to projects that have:

1. a legally obtainable reference binary;
2. a compiler toolchain that can be pinned closely enough;
3. a deterministic or near-deterministic artifact comparison;
4. a decomposition into independently claimable units;
5. a legal publication boundary that permits tools and notes without redistributing code.

It does not transfer cleanly to greenfield feature work, where no byte-identical oracle exists.

## Publication Risks

| Risk | Mitigation |
| --- | --- |
| Readers mistake the project for a source redistribution | Put the publication boundary in README, DESIGN, and docs/design/01-publication-contract.md |
| Runnable jars accidentally include original classes | Keep `verifyNoGroundTruthCodeInRunnableJars` mandatory |
| Agents overfit to line tables instead of semantics | Require compile-green plus raw diff evidence; use Tier B only with ADRs |
| Toolchain mismatch makes Tier A impossible for many classes | Record JDK probes and run Autoresearch before downgrades |
| Multi-agent state becomes opaque | Keep all work claims and attempts in SQLite, not transient chat state |

## Open Research Tasks

- Quantify which Vineflower drift patterns dominate Tier-A failures.
- Compare ast-grep-assisted pattern sweeps against manual per-class edits.
- Measure queue throughput with one agent versus multiple independent bytecode aligners.
- Define a Tier-B structural comparator that is strict enough for release claims.
- Build a reproducible report generator from `state/progress.db` for publication snapshots.
