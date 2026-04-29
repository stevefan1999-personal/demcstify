# Paradigm — Multi-Agent LLM-Driven Source Reconstruction

> Living research note. The conceptual frame for `demcstify`. Refines as the project teaches us what works.

## 0. Distribution Stance

This paradigm is delivered as **scaffolding**, never as reconstructed code. The repository ships design documents, agent guardrails, build glue, the bytecode-diff plugin, the progress-database schema, and orchestration scripts. It does not ship the original JAR (user-supplied, gitignored) and it does not ship any decompiled, repaired, or rebuilt Minecraft source (also gitignored). Each user runs the loop on their own machine, against their own legitimately-acquired JAR, and the output stays there.

The framework is therefore a recipe and a workforce specification — not a code drop. This is a deliberate stance to keep the project on the right side of IP law and to keep its contribution unambiguously methodological.

## 1. The Setting

A non-trivial Java codebase exists in two states: a complete JVM-bytecode artifact (the original JAR), and an incomplete, error-ridden text approximation produced by an off-the-shelf decompiler (Vineflower). The gap between the two is well-defined: the decompiler is mechanical and lossy; the JAR is the spec.

The question this project asks is: **can a fleet of LLM agents close that gap and produce buildable Java sources whose recompiled bytecode matches the original, byte for byte?**

That question generalizes. It's the same shape as a CTF reverse-engineering challenge — given a binary and a partial decompilation, recover the program — scaled up to real-world dimensions.

## 2. Why This Is a Useful Test Bed

Most LLM-driven software-engineering benchmarks share a fatal weakness: the oracle is human judgment, sometimes formalized as test cases. SWE-bench tasks pass when chosen tests pass; "looks reasonable, isn't right" failures are common, and human reviewers are needed to catch them.

Source reconstruction against a reference binary has a **mechanical, deterministic oracle**: ASM bytecode comparison. There is no ambiguity about correctness. A class either matches the original at the chosen tier or it doesn't. The signal is binary, fast, and not subject to LLM flattery loops.

That property is rare. It makes the project a clean substrate for studying multi-agent workflows under strict evaluator pressure.

## 3. The Pillars

### 3.1 Bytecode equality as ground truth

The original `.class` files are the spec. The build output is the test. No human grader, no fuzzy heuristic, no learned reward model — just `==` on byte arrays (tier A) or structural equivalence (tier B). The agent system never has to *guess* whether it's done; the verdict is always available on demand.

### 3.2 Decompiler as priming, not as truth

Vineflower output is a draft. Treating it as authoritative would propagate every decompilation error into the rebuilt source. Treating it as priming context for the LLM — "here is one plausible reading; reconstruct what actually fits" — turns the decompiler into a starting point rather than a destination. This mirrors how CTF reverse-engineers use IDA or Ghidra: the tool's output is one input among many, not the answer.

### 3.3 Multi-agent role separation

Five roles, each with a narrow charter and a hard non-overlap rule:

- **decompiler** runs Vineflower; never edits its output.
- **compiler_fixer** drives `gradle compileJava` to zero warn / zero err on one subproject.
- **bytecode_aligner** drives one class to verdict = PASS at the target tier.
- **verifier** independently re-runs build and diff. Must not be the same agent that wrote the change.
- **librarian** maintains documentation and schema; never touches source.

Role separation counters two well-known LLM failure modes: scope creep and self-confirmation. An agent that wrote the change cannot bless it; an agent fixing compile errors cannot quietly rewrite bytecode.

### 3.4 Strict evaluator contract

The bytecode-diff tool is the only entity that can issue PASS. Agents may not self-report. Every claim is a row in a write-only `attempts` table; PASS without an evaluator verdict is invalid. This pattern derives from the Autoresearch model — strict-evaluator loops with no agent override path — and prevents the convergence-toward-plausibility failure mode that plagues open-ended LLM agents.

### 3.5 Relational state, normalized to 3NF/BCNF

Shared state is a SQLite database, not a JSON blob, not a markdown notepad. Agents claim work via atomic SQL transactions, which lets a swarm of different LLMs run in parallel without competing for broad filesystem locks or stale status files. Progress is queryable. History is bisectable. The schema has lookup tables for every enum, no JSON columns, no denormalized lists. This trades some write-time complexity for a complete and auditable record of what was attempted, by whom, when, with what outcome.

### 3.6 Layered scheduling with dependency awareness

Subprojects are compiled in topological order (`common` → `datafix` → `world` → `network` → `server` → `client`). Within a layer, classes are pulled leaf-first — a class with no inbound dependencies from other classes in the same layer goes first. This mirrors how compilers themselves schedule work, and it avoids the pathological case where an aligner is asked to fix a class whose dependencies don't yet compile.

### 3.7 Tier ratchet for partial success

Some classes will resist strict tier-A equality because of compiler-emitted artifacts (line tables, constant-pool ordering, debug attributes) that javac chooses non-determ-istically. Tier B accepts these as cosmetic. The system tracks tier-A coverage as a metric that *only ratchets upward* — a downgrade requires an ADR. This lets the project make steady progress without abandoning the strict goal.

### 3.8 Driver hierarchy for orchestration

Three drivers, each with a clear charter:

- **Ralph** — convergence loop on one target until verdict = PASS. The boulder.
- **Ultrawork** — parallel fan-out across the work queue. Throughput.
- **Autoresearch** — stateful improvement loop with strict evaluator, used only for high-stakes one-shot decisions (toolchain pin, tier downgrades).

The drivers are orthogonal: Ralph operates on one item, Ultrawork operates on many, Autoresearch operates on critical decisions. Mixing them — invoking Autoresearch for routine fixes — would smother throughput in process. Roles are the actors; drivers are the stage.

### 3.9 Continuous priming

The user can hand the agent fleet new context — papers, articles, prior art — at any phase. Priming is not a one-shot before the run; it's a re-pointable channel. Knowledge that arrives mid-project is folded in, not deferred.

## 4. Connections to Adjacent Fields

| Field | Relation |
|-------|---------|
| **CTF reverse engineering** | Direct ancestor. LLM-assisted Ghidra / IDA workflows in rev challenges showed LLMs can reason about decompiler output meaningfully. This project applies the same idea to a real codebase. |
| **Program synthesis** | Bytecode equality is a near-perfect oracle for inductive synthesis — closer to test-driven synthesis than to free-form code generation. |
| **Distributed builds** (Bazel, Buck) | The work queue + role model echoes distributed build orchestration. The progress DB is the build-cache analogue. |
| **Agent benchmarks** (SWE-bench, AgentBench) | Most benchmarks are toy-scale and rely on human-graded test cases. Source reconstruction against a reference binary is larger, has a deterministic signal, and exercises long-horizon coordination. |
| **Clean-room reverse engineering** (Wine, ReactOS, OpenMW, emulator projects) | Procedural ancestor. Those projects use human teams; this project asks whether an LLM fleet can do the same kind of work under similar constraints (user-supplied originals, no redistribution). |

## 5. What Is Novel

- A **bytecode-level oracle** for an LLM agent project. Eliminates the dominant failure mode of "looks plausible, isn't right".
- **Strict role separation enforced by schema** — the database itself is the gatekeeper; an aligner literally cannot mark its own attempt as verified.
- **A three-driver orchestration hierarchy** with explicit charters for convergence, throughput, and high-stakes decisions.
- **Tier ratchet as a soft-goal mechanism**: lets the project make progress without abandoning a hard goal.
- **A relational, queryable, append-only history** instead of the markdown / JSON / scratchpad chaos typical of LLM agent projects.

## 6. Honest Limitations

- The oracle exists only because a reference binary exists. The technique does not generalize to greenfield work.
- The original JAR being shipped deobfuscated is a precondition. An obfuscated input would require a mapping layer, which is a far harder problem.
- Strict tier A may be unreachable for some classes. Tier B is a real release valve, but every B-tier class is a small mark against the project's claim of fidelity.
- Agent thrash on intractable classes can starve the queue. The attempt-count threshold mitigates but does not eliminate this.
- The project depends on the quality of Vineflower's output. If a future Java feature defeats Vineflower, the priming step degrades.
- LLM-driven work has variable cost; long-horizon convergence on hard classes can be expensive in tokens.

## 7. Success Criteria for the Paradigm (not just the project)

The Minecraft 26.1.2 reconstruction is the testbed. The paradigm is validated when:

1. The system reaches 100% tier-A or tier-B coverage with no human in the inner loop for routine fixes.
2. The role separation prevents at least one observable category of failure that an unconstrained single-agent baseline would commit.
3. The progress DB makes failures legible — a researcher can answer "which classes are stuck and why" with a single SQL query.
4. The drivers are reusable beyond this project — Ralph / Ultrawork / Autoresearch as a triple should be applicable to any task with a strict evaluator.

If those four hold, the paradigm earns generalization beyond Minecraft.

## 8. Closing Thesis: Code Is Cheap, Show Me the Talk

The LLM era is a reality check for software that relies on obscurity as its primary protection. Heavily obfuscated, mutated, or virtualized code can often be initially recovered with mechanical tooling: lifters such as [`remill`](https://github.com/lifting-bits/remill) translate binary instructions into analyzable representations, recompilers such as [`PS2Recomp`](https://github.com/ran-j/PS2Recomp) and [`XenonRecomp`](https://github.com/hedge-dev/XenonRecomp) preserve platform behavior through generated code, and emulators such as [`RPCS3`](https://github.com/RPCS3/rpcs3) show how complete machine states can be modeled and inspected.

Java brings the problem closer to source. Bytecode is already high-level compared with native machine code, and common obfuscators such as ProGuard or RetroGuard cannot remove the underlying semantics that the VM must execute. Once an LLM can combine bytecode evidence, decompiler output, traces, and an evaluator oracle, devirtualization and deobfuscation become workflows rather than isolated feats.

This does not erase intellectual property. It makes provenance, licensing, purpose, and explanation more important. Obfuscation can be a layer, but it cannot be the story. If software is now industrially generated and reconstructed, the differentiator is the reasoning that surrounds it: why it exists, how it is validated, what boundaries it respects, and who maintains it. The old maxim was "talk is cheap, show me the code." This paradigm reverses the burden: **code is cheap; show me the talk**.
