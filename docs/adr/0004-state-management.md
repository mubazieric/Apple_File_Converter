# ADR 0004 — State management: `provider` + `ChangeNotifier`, no code generation

* Status: Accepted
* Date: 2026-10-13

## Context

We need app-wide state for settings, theme, the conversion queue, gallery selection and ad
consent. Candidate approaches: Riverpod, BLoC, provider, or hand-rolled `InheritedWidget`.

## Decision

Use **`provider` with `ChangeNotifier`** controllers, exposed through a single root
`MultiProvider`. Controllers are thin: they hold presentation state and delegate business rules
to the pure `domain` layer. No build_runner, no code generation.

## Rationale

* The domain layer already holds the complex logic; a heavy state framework would add
  indirection without value.
* `provider` has no codegen step, keeping CI fast and the build reproducible.
* `ChangeNotifier` + `Selector`/`Consumer` is enough for the update granularity this app needs.

## Consequences

* Controllers must be disposed and must not perform I/O in `build`.
* Queue state is a `ChangeNotifier` wrapping the domain `ConversionQueue` so widget tests can
  drive it without the real engines.
