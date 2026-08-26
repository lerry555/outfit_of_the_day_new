/// The clothing presentation the owner wants the product to style them in.
///
/// This is deliberately not a gender/identity field. It controls outfit
/// composition only and never gets inferred from wardrobe contents.
enum StylingPresentation {
  noPreference('no_preference'),
  menswear('menswear'),
  womenswear('womenswear'),
  mixed('mixed');

  const StylingPresentation(this.wireName);

  final String wireName;

  bool get filtersWardrobe =>
      this == StylingPresentation.menswear ||
      this == StylingPresentation.womenswear;

  static StylingPresentation parse(Object? raw) {
    final value = raw?.toString().trim().toLowerCase() ?? '';
    return StylingPresentation.values.firstWhere(
      (item) => item.wireName == value,
      orElse: () => StylingPresentation.noPreference,
    );
  }
}
