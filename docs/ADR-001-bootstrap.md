# ADR-001: Bootstrap boundaries

## Status

Accepted — 2026-08-13.

## Decision

The repository follows the monorepo layout from `CONCEPT.md`. The iOS client is the local source of UI data. REST and realtime schemas are stored in `contracts` before server and client implementation.

## Consequences

The first deliverable is the local iOS core. Further endpoints require an OpenAPI change and tests.
