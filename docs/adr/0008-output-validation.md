# ADR 0008 — Output validation is mandatory, not cosmetic

* Status: Accepted
* Date: 2026-10-13

## Context

A common failure mode in converter apps is producing a file that only *looks* converted: the
extension changed but the bytes are wrong, truncated, or the container is invalid. The prompt
forbids this ("a successful conversion must produce a valid output file, not merely a file with
a new extension").

## Decision

Every job passes through `OutputValidator` before being reported as successful:

* **Order of checks** — the output must exist → be non-empty → have a recognised file
  signature matching the requested format → decode/probe successfully → match expected
  dimensions/duration within tolerance → contain the expected streams.
* **Images** — decode the output header (and optionally full decode at reduced size) and compare
  width/height with the expected dimensions.
* **Video** — `FFprobeKit` must report a valid container with the expected video stream, and the
  audio stream must be present when `keepAudio` was requested.
* On any failure the job becomes `failed` with a typed `ConversionError` (`outputCorrupt`,
  `outputMissingStreams`, `outputWrongDimensions`, …) and the temp output is deleted.

## Consequences

* Success is honest and testable; the integration tests assert validation, not just "file
  exists".
* Validation adds a small fixed cost per job, which is acceptable and is skipped for
  pure remux only where the container itself proves integrity.
