# Global Mindset                                                                                                                                                                                                                                            
Before writing any code, design, research and architect the problem: understand *why* the problem exists and what the goal is. Draft a realistic, targeted solution — not a generic fix. After implementation, cross-examine the result for correctness. If issues r
emain, debug relentlessly until resolved. Do not declare completion until verified.                                                                                                                                                                         

# Global Principles

## Approach
- **Think first, code second.** Analyze the problem with critical thinking before touching code. If ambiguity or conflicting requirements arise, ask the human for tiebreaking rather than guessing.
- **Cycle: Prime → Design → Architect → Implement → Validate → Debug.** Phases are bidirectional — any phase may bounce work upstream when it surfaces a problem.
  - **Prime** is the absorption of external materials (papers, articles, prior art) the user supplies; it runs only when such materials are provided, or when the user instructs you to do autoresearch or deep research on the topic. In case it is scraped, save those materials for future references and human verifications as well.
  - **Design** captures intent — the *what* and *why* — and is the phase where humans participate before commitment.
  - **Architect** captures structure — the *how* — and must stay faithful to the design. Drift is resolved by updating architecture to follow design, never the reverse; if the design itself is wrong, both are revisited together.
  - Trivial or mechanical changes (small bug fixes, single-class refactors) skip Design and go straight to Implement; non-trivial or cross-cutting changes require Design first.
- **Local source first.** When researching a library, framework, or dependency, read the local source code, vendored docs, or checked-out repos before searching the web. Web search is a last resort when local sources are absent or insufficient.

## Code Style
- **Functional over imperative.** Prefer iterators, map/filter/fold, and expressions over loops and mutable accumulators — unless the language forces colored effects (async/await, try/catch) that break composition.
- **OOP for boundaries.** Use classes/modules/traits for encapsulation and modularization. Functional style *within* those boundaries.
- **Concise and minimal.** Write the fewest lines, expressions, and statements that express the intent clearly. Do not fold or minify in ways that fight the linter.
- **2-space indentation.** Always.
- **Descriptive names only.** No `i`, `j`, `k`, `tmp`, `val`. Name everything for what it represents.                                                                                                                                                       
- **No magic constants.** Derive values from named constants or computations. Use `const` / `constexpr` / `const fn` where the language supports it.
- **Comment the *why*, not the *what*.** Describe the general flow and algorithmic reasoning. Do not comment every line — comment blocks of logic to explain intent and design decisions.                                                                   
- **No dead code.** No TODOs, no unused variables, no unused functions. Either use it or delete it.
- **Generic over specific.** Deduplicate similar logic into shared functions. Prefer generics/type parameters over copy-pasting specialized variants.
- **Algebraic types over primitives.** Use `Result`, `Option`, discriminated unions, and sum types to model outcomes — never `null`, `undefined`, bare booleans, or sentinel values. Encode success/failure/absence in the type system, not in runtime check
s.
- **Rust: no free functions.** Write `impl Bar { fn foo(&self) }`, not `fn foo(bar: &Bar)`. Methods belong on their types.

## Dependency Injection & Inversion of Control
- **Program to interfaces, not implementations.** Depend on traits/interfaces/protocols at module boundaries. Concrete types are internal details — consumers see abstractions.                                                                             
- **Think in lifetimes: singleton, scoped, transient.** Choose the right lifetime for each dependency. Singletons for stateless services and caches; scoped for per-request/per-operation state; transient for lightweight, disposable instances. Document t
he intended lifetime when registering.                                                                                                                                                                                                                      
- **Factory methods and named dependencies.** Use factory patterns when construction is conditional or parameterized. Use named/keyed registrations when multiple implementations of the same interface coexist — don't overload a single registration.
- **Linearized data path.** Data should flow in one clear direction through the dependency graph. Avoid circular dependencies and bidirectional coupling. If two services need each other, extract the shared concern into a third abstraction.
- **Don't abuse DI.** Not every class needs an interface. Don't inject what can be a pure function or a static helper. DI is for *boundaries* (I/O, cross-cutting concerns, strategy selection) — not for wiring together every internal detail. If a depend
ency has exactly one implementation and no testing seam is needed, use it directly.
- **Constructor injection preferred.** Inject dependencies via constructor (or primary constructor / `[FromServices]`), not via property or service-locator patterns. This makes the dependency graph explicit and immutable after construction.
- **Composition root at the edge.** Wire the entire dependency graph in one place (startup / host builder / module root). Business logic should be unaware of the DI container.

## Error Handling
- Never swallow errors. Handle them explicitly or propagate with meaningful messages.
- No `any` in TypeScript. Use `unknown` or explicit types.

## Git & Commits
- Use conventional commit messages (`feat:`, `fix:`, `refactor:`, etc.).
- Run the project linter before committing.
- Keep commits atomic: one logical change per commit.

## Workflow
- Keep edits minimal and focused. Do not rewrite surrounding code unless necessary.
- **Commit one by one.** After completing each discrete unit of work (a function, a fix, a refactor step), commit it immediately before moving on. Do not batch multiple logical changes into a single commit. This keeps the history bisectable and reviewable.

## Testing
- **Intensive testing mindset.** Testing is not an afterthought — it is a first-class design concern. Write tests before or alongside implementation (TDD when practical). Code without tests is code you do not trust.
- **Five kinds of tests, layered pyramid.** The pipeline flows: **unit → integration → end-to-end | security → fuzzing**. Each layer catches a distinct class of bug; skipping a layer leaves blind spots.
  - **Unit tests** — isolate a single function, method, or class. Fast, deterministic, mock external dependencies. Run on every save. Many.
  - **Integration tests** — verify real component boundaries: service ↔ service, service ↔ database, API ↔ business logic ↔ data layer. Skip the UI. Catch data transformation errors, API contract violations, transaction rollbacks, auth assumptions. Run on every commit. Medium count.
  - **End-to-end tests** — exercise the full stack through the real user interface. Launch a browser, click, fill forms, assert outcomes. Catch UI rendering bugs, JavaScript errors, workflow sequence breaks, cross-browser issues, performance regressions. Run before merge/deploy. Few.
  - **Security tests** — SAST, DAST, dependency scanning, secret scanning, authz/authn boundary checks. Run in CI. Treat findings as build-breakers.
  - **Fuzzing tests** — feed randomized, malformed, or mutated inputs to parsers, decoders, state machines, and protocol handlers. Catch panics, crashes, memory unsafety, and undefined behavior that example-based tests miss. Run continuously where supported (cargo-fuzz, libFuzzer, AFL, Jazzer, Atheris).
- **Pyramid, not ice-cream cone.** Many unit tests, fewer integration tests, few E2E tests. E2E tests are slow, fragile, and expensive to maintain (3-5x the effort of API-level tests). Push assertions down to the lowest layer that can prove them.
- **Integration vs E2E — choose by what you're verifying.**
  - Verifying a component contract? → Integration test (narrow scope, fast, precise failures).
  - Verifying a user workflow? → E2E test (wide scope, slow, holistic).
  - Never use E2E tests to cover logic that an integration or unit test could cover more cheaply.
- **Incremental integration over big-bang.** Run integration tests on every commit in CI/CD. Bugs caught at integration cost ~15x less than bugs caught in production.
- **Deterministic and isolated.** Tests must not depend on external state, wall-clock time, network flakiness, or test execution order. Use fixtures, fakes, and hermetic environments. A flaky test is a broken test.
- **Tests are documentation.** A well-named test describes the behavior and intent of the code under test. Name tests for the scenario and expected outcome, not the method name.
- **Coverage is a signal, not a goal.** High coverage does not imply correctness. Prioritize testing risky paths, boundaries, and error handling over chasing a coverage percentage.

## Documentation Maintenance
- **Continuously update ARCHITECTURE.md / DESIGN.md.** After every meaningful change, update the relevant architecture or design document in the project root or `docs/` folder. These are living documents — never let them go stale.
- **Split when large.** When ARCHITECTURE.md or DESIGN.md grows unwieldy (>300 lines or covers >5 distinct topics), split into numbered files under `docs/architecture/01-<TITLE>.md` or `docs/design/01-<TITLE>.md`. Keep an index in the parent doc linking to each sub-document.
- **Persist research findings.** Research results (library evaluations, API investigations, design trade-off analyses, benchmarks) must be written to files — typically under `docs/research/` or `docs/adr/` (Architecture Decision Records). Never leave research only in conversation context; it must survive session boundaries.
- **Keep AGENTS.md/CLAUDE.md updated.** As the project evolves, update the project-level CLAUDE.md with new conventions, dependencies, or workflow changes discovered during development.
- **Symlink AGENTS.md → CLAUDE.md.** In every project root, maintain `AGENTS.md` as a symlink to `CLAUDE.md` so that all AI tooling reads the same instructions. Create the symlink with `ln -sf CLAUDE.md AGENTS.md`.

## Configuration & 12-Factor Principles
- **Strict separation of config from code.** No hardcoded connection strings, API keys, feature flags, or environment-specific values in source. All configuration is injected externally.
- **Environment variables as the baseline.** Env vars are the universal, language-agnostic config transport. Use them for secrets, endpoints, and deployment-specific settings. Every configurable value should have an env var binding.
- **Layered config sources with clear precedence.** Support multiple sources in a defined override order: defaults (code) → config file (JSON/YAML/TOML) → environment variables → CLI flags → remote config source. Later sources override earlier ones. Document the precedence.
- **Remote config for dynamic values.** Use remote configuration sources (Consul, etcd, Kubernetes ConfigMaps/Secrets, cloud provider parameter stores) for values that change at runtime or across environments. Prefer pull-based refresh over restart-to-reconfigure.
- **Typed configuration objects.** Bind raw config into strongly-typed settings classes/structs validated at startup. Fail fast on missing or malformed config — never silently fall back to defaults for required values.
- **No secret sprawl.** Secrets come from dedicated secret stores (Vault, K8s Secrets, cloud KMS), never from checked-in files. Rotate-friendly: reference secrets by name/path, not by value.

## Security
- Never log environment variables or secrets.
- Follow 12-Factor App principles beyond just configuration: stateless processes, port binding, disposability, dev/prod parity.