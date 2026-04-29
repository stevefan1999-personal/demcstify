# Research Note 03 - Compile Diagnostics and AST Repairs

## Context

`minecraft-common` has many decompiler-repair errors and warnings. The default javac diagnostic cap hides most of the queue after roughly 100 errors or warnings, which blocks parallel triage because agents cannot see the full failure surface from one compile run.

## Evidence

Before the diagnostic-cap change, `.omx/logs/compile-minecraft-common.log` exposed about 99 error-location lines and 100 warning-location lines. After adding explicit javac caps, the same compile task reported the full diagnostic surface:

- Command: `scripts/gradle.sh :minecraft-common:compileJava > .omx/logs/compile-minecraft-common.log 2>&1`
- Result: compile failed as expected while reconstruction remains incomplete
- Reported summary: `416 errors`, `2,063 warnings`
- Parsed diagnostic location lines: 415 errors, 2,063 warnings

The one-line mismatch between summary errors and parsed `: error:` locations is expected when javac emits an aggregate `-Werror` diagnostic without a normal source-location prefix.

## Decision

`build.gradle.kts` configures every `JavaCompile` task with:

- `-Xlint:all`
- `-Werror`
- `-Xmaxerrs 1000000`
- `-Xmaxwarns 1000000`

The high caps preserve the project's zero-warning gate while making all current diagnostics available for scheduling and parallel repair.

## Operational Note

Full diagnostic output is larger and can stress the default Gradle daemon heap while thousands of warnings are still present. `gradle.properties` now raises daemon memory to keep full-log compiles usable during the compile-fixer phase.

The diagnostic-heavy `minecraft-common` compile also needs a larger forked javac heap because Gradle's default worker launched with `-Xmx512m` while trying to serialize thousands of diagnostics. The build therefore forks javac with `javacWorker.heapSize` and raises the Gradle daemon heap separately.

## Follow-up: Brain Self-Type Repair

The full diagnostic list exposed a repeated entity pattern: subclass overrides such as `Brain<Frog> getBrain()` returned `super.getBrain()`, while `LivingEntity.getBrain()` exposed only `Brain<? extends LivingEntity>`. That wildcard is safe for generic callers but cannot satisfy covariant subclass return types.

Local source inspection showed each affected subclass installs its typed brain through `makeBrain(...)` during `LivingEntity` construction. The repair centralizes the unavoidable erased storage boundary in `LivingEntity.typedBrain()` and lets each subclass return that typed view instead of repeating unchecked casts in twenty entity classes.

## 2026-04-29 Compile-Fixer Progress

After raising both Gradle daemon memory and forked javac memory, a fresh full diagnostic run completed without daemon OOM or diagnostic-cap messages.

- Command: `GRADLE_OPTS='-Xmx8g -XX:MaxMetaspaceSize=1g -Dfile.encoding=UTF-8' scripts/gradle.sh --no-daemon :minecraft-common:compileJava`
- Result: expected compile failure while reconstruction remains incomplete
- Current full surface: `396 errors`, `2,054 warnings`
- Removed repeated cluster: `Brain<CAP#1> cannot be converted to Brain<SpecificEntity>` is now zero occurrences
- Removed repeated cluster: explicit `<Entity>getEntitiesOfClass(...)` class-token errors are now zero occurrences
- Current log: `.omx/logs/compile-minecraft-common.log`

Next focus is small decompiler generic repairs near the top of the full diagnostic list before returning to the large loot/provider clusters.

## Generic Codec Repair Notes

The next local pass targets small generic inference failures near the top of the full log:

- `ExtraCodecs.intervalCodec` now preserves `Pair<P, P>` instead of using raw `Pair` in the object-form codec.
- `FontDescription.CODEC` maps `Identifier` directly to the `FontDescription` interface type instead of assigning a `Codec<Resource>` to `Codec<FontDescription>`.
- `DataComponentPatch.CODEC` pins the dispatched-map value type to `Object`, matching the heterogeneous component-value map it builds.
- `StreamCodec.dispatch` accepts subtype codecs for decode and narrows only at the encode boundary, which matches registry-dispatched packet/stat/recipe codec usage.
- `MetadataSectionType.WithValue.unwrapToType` centralizes the type-token equality cast required after checking that both metadata section keys are the same object.

Verification after the generic codec pass:

- Command: `GRADLE_OPTS='-Xmx8g -XX:MaxMetaspaceSize=1g -Dfile.encoding=UTF-8' scripts/gradle.sh --no-daemon :minecraft-common:compileJava`
- Result: expected compile failure
- Full surface: `379 errors`, `2,047 warnings`
- OOM: no
- Targeted error checks now at zero: `ExtraCodecs.java:312`, `MetadataSectionType.java:13`, `DataComponentPatch.java:56`, `FontDescription.java:10`, `Stat.java:15`, `Recipe.java:23`

Verification after the top-of-log small generic pass:

- Command: `GRADLE_OPTS='-Xmx8g -XX:MaxMetaspaceSize=1g -Dfile.encoding=UTF-8' scripts/gradle.sh --no-daemon :minecraft-common:compileJava`
- Result: expected compile failure
- Full surface: `374 errors`, `2,039 warnings`
- OOM: no
- Targeted error checks now at zero: `ServerStatsCounter.java:45`, `TextFilter.java:16`, `DebugSubscription.java:72`, `Timeline.java:104`, `EntityDataSerializer.java:16`, `SlotDisplay.java:426`

## Structural Editing Discipline

The living design now records that code-structure modifications should prefer `ast-grep` or equivalent AST-aware tooling when the repair follows a syntactic pattern. Text replacement remains acceptable for trivial literals, but decompiler-repair sweeps should avoid broad regex rewrites when AST matching can preserve structure more safely.

## 2026-04-29 AST-Aware Note

Per design update, future structural decompiler repairs should prefer `ast-grep` where the pattern is syntactic. The current small local edits remain manual because each one repairs a local generic inference issue with different type constraints.

Verification after the world/chunk small generic pass:

- Command: `GRADLE_OPTS='-Xmx8g -XX:MaxMetaspaceSize=1g -Dfile.encoding=UTF-8' scripts/gradle.sh --no-daemon :minecraft-common:compileJava`
- Result: expected compile failure
- Full surface: `365 errors`, `2,024 warnings`
- OOM: no
- Targeted error checks now at zero: `ServerStatsCounter.java:46`, `BiomeGenerationSettings.java:61`, `StructureManager.java:121`, `RecipeMap.java:39`, `LootItemCondition.java:18`, `GameEvent.java:88`, `PalettedContainerFactory.java:34`, `PalettedContainer.java:61`

## Tooling Update: ast-grep Skill

Installed the `ast-grep` skill from `https://github.com/ast-grep/agent-skill` into `/home/steve/.codex/skills/ast-grep`. Codex needs a restart to auto-discover it in the skill list, but the workflow guidance is already being applied manually in this session.

## ast-grep Tooling Repair

The `ast-grep` Codex skill was installed from `https://github.com/ast-grep/agent-skill` to `/home/steve/.codex/skills/ast-grep`. Codex should be restarted to auto-discover the new skill in the session skill registry.

During validation, `omx code-intel ast_grep_search` failed because OMX's code-intel wrapper preferred `sg` before `ast-grep`; on this machine `/usr/bin/sg` is the Linux switch-group command. The installed OMX wrapper was patched to prefer `ast-grep` and validate `--version` before selecting a binary.

Validation:

- `ast-grep --version` -> `ast-grep 0.42.0`
- `omx code-intel ast_grep_search` now emits command `ast-grep run ...` and returns Java matches.
- The in-session MCP transport remains closed; use `omx code-intel ...` or direct `ast-grep` until Codex is restarted.
