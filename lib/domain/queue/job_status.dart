/// Lifecycle of a single conversion job.
enum JobStatus {
  queued,
  preparing,
  processing,
  validating,
  completed,
  failed,
  cancelled,
  skipped;

  bool get isActive =>
      this == JobStatus.preparing ||
      this == JobStatus.processing ||
      this == JobStatus.validating;

  bool get isTerminal =>
      this == JobStatus.completed ||
      this == JobStatus.failed ||
      this == JobStatus.cancelled ||
      this == JobStatus.skipped;

  bool get isSuccessful => this == JobStatus.completed;

  String get label => switch (this) {
    JobStatus.queued => 'Queued',
    JobStatus.preparing => 'Preparing',
    JobStatus.processing => 'Converting',
    JobStatus.validating => 'Verifying output',
    JobStatus.completed => 'Done',
    JobStatus.failed => 'Failed',
    JobStatus.cancelled => 'Cancelled',
    JobStatus.skipped => 'Skipped',
  };
}
