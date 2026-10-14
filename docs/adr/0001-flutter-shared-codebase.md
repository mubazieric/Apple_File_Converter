# ADR 0001 — Use a single Flutter/Dart codebase for Android and iOS

* Status: Accepted
* Date: 2026-10-13

## Context

The product must ship equivalent gallery, conversion, compression and editing capabilities on
Android and iOS. The repository was empty, so there was no incumbent framework to preserve.

The hard parts are inherently platform-specific (media library access, HEIC decode, hardware
video codecs), but the surface area that is *not* platform-specific is large: navigation,
gallery UX, conversion configuration, batch queue, presets, settings, history, storage maths.

## Decision

Build the application as a **single Flutter application** targeting `android` and `ios`, with
Kotlin and Swift used only where a platform API has no Flutter equivalent. Platform-only logic
sits behind Dart interfaces (`services/**`) and is implemented with `MethodChannel`s.

## Alternatives considered

* **Two native codebases.** Rejected: doubles UI, state, queue and testing work for no user
  benefit, and the prompt asks for equivalent behaviour on both platforms.
* **Kotlin Multiplatform / Compose Multiplatform.** Rejected: iOS maturity and the multimedia
  package ecosystem are weaker than Flutter's for this problem space.

## Consequences

* One design system, one queue implementation, one test suite.
* Platform divergence is contained in `android/**`, `ios/**` and the `services` interfaces.
* We must be explicit about per-platform capability differences; the capability matrix is a
  first-class, tested artefact rather than an assumption of parity.
