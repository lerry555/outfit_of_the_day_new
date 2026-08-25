bool stylistMessageNeedsWardrobeContext(String text) {
  final lower = text.toLowerCase();
  return lower.contains('ukáž') ||
      lower.contains('ukaz') ||
      lower.contains('zobraz') ||
      lower.contains('šatník') ||
      lower.contains('satnik') ||
      lower.contains('ktoré') ||
      lower.contains('ktore') ||
      lower.contains('mám v') ||
      lower.contains('mam v') ||
      lower.contains('ukážeš') ||
      lower.contains('ukazes') ||
      lower.contains('outfit') ||
      lower.contains('košel') ||
      lower.contains('kosel') ||
      lower.contains('set partner') ||
      lower.contains('matching');
}
