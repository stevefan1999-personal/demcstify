# Documentation Index

This directory contains publishable notes for the reconstruction system. None of these documents include reconstructed Minecraft source or original game files.

## Core Project Documents

- [`../DESIGN.md`](../DESIGN.md) — mission, acceptance criteria, state model, equality tiers, and driver charters.
- [`../ARCHITECTURE.md`](../ARCHITECTURE.md) — repository layout, subproject layering, build outputs, and CI topology.
- [`../AGENTS.md`](../AGENTS.md) — agent roles, queue discipline, evaluator contract, and hard constraints.
- [`../README.md`](../README.md) — public-facing introduction and legal stance.
- [`../NOTICE.md`](../NOTICE.md) — rights-holder notice for Mojang Studios and Microsoft.
- [`../LICENSE`](../LICENSE) — MIT license for the lab scaffolding itself.

## Design Notes

- [`design/01-publication-contract.md`](design/01-publication-contract.md) — what may be published, what stays local, and how to describe the project safely.

## Architecture Notes

- [`architecture/01-llm-decompilation-workflow.md`](architecture/01-llm-decompilation-workflow.md) — end-to-end LLM decompilation workflow with Mermaid diagrams.

## Research Notes

- [`research/01-llm-reconstruction-paradigm.md`](research/01-llm-reconstruction-paradigm.md) — conceptual framing for multi-agent LLM source reconstruction against a bytecode oracle.
- [`research/02-llm-decompilation-workflow.md`](research/02-llm-decompilation-workflow.md) — research framing for the workflow, evaluator, metrics, and publication risks.
- [`research/03-compile-diagnostics-and-ast-repairs.md`](research/03-compile-diagnostics-and-ast-repairs.md) — compile diagnostics and AST-aware repair notes.

## ADRs

- [`adr/0001-toolchain-pin.md`](adr/0001-toolchain-pin.md) — bootstrap toolchain pin decision.
