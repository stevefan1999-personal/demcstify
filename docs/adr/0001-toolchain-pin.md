# ADR 0001 - Toolchain Pin

## Status

Accepted for bootstrap; revisit with Autoresearch brute-force probing after Gradle compilation exists.

## Context

The 26.1.2 manifest declares Java runtime component `java-runtime-epsilon` with major version `25`. A classfile fingerprint of `ground_truth/26.1.2.jar` found major version `69`, minor version `0`, which corresponds to Java `25` across `10682` sampled-majority classes.

The currently active local Java reports `21.0.2`. That runtime is not treated as the target compiler unless it also satisfies Java 25.

## Decision

Pin the bootstrap target to `java-runtime-epsilon:25` and mirror it into:

- `state/progress.db.toolchain`
- `gradle.properties`
- `.tool-versions`
- `gradle.properties` also pins Gradle `9.5.0` for `scripts/gradle.sh`

## Consequences

Strict tier-A bytecode equality remains conditional on a later brute-force javac probe. Until Gradle build output exists, this project records the manifest and classfile fingerprint as the best available non-destructive evidence.
