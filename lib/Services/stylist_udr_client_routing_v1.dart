/// Client-side interpretation for the production U/D/R Stylist seam.
///
/// The context response is authoritative for semantic clarification. This
/// adapter only normalizes the deployed contract's established action aliases;
/// it never derives a clarification from local conversation heuristics.
abstract final class StylistUdrClientRoutingV1 {
  static String normalizeContextAction(Object? rawAction) {
    final action = rawAction?.toString().trim() ?? '';
    return switch (action) {
      'ask_clarification' || 'clarify' => 'clarify',
      'proceed' || 'generate_outfit' => 'generate_outfit',
      'stop' => 'stop',
      _ => action.isEmpty ? 'chat' : action,
    };
  }

  /// Returns the immutable server explanation exactly as supplied, or null
  /// when the frozen authority did not provide one. Callers must surface the
  /// latter transparently rather than manufacture legacy Stylist prose.
  static String? frozenExplanationForDisplay(String? explanation) {
    if (explanation == null || explanation.trim().isEmpty) return null;
    return explanation;
  }
}
