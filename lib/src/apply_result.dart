/// Result returned by [InputParser.applyText].
class ApplyResult {
  /// Number of player records that had at least one attribute written.
  final int updated;

  /// Number of data lines that were skipped (player not found, team limit, etc.).
  final int skipped;

  /// Non-fatal errors encountered during apply (unknown field value, player not
  /// found, etc.).  The apply continues past each error.
  final List<String> errors;

  const ApplyResult({
    required this.updated,
    required this.skipped,
    required this.errors,
  });
}
