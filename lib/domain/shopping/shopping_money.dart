/// Currency amount represented exclusively in integer minor units.
///
/// This is intentionally separate from UI formatting and payment concerns.
class ShoppingMoney implements Comparable<ShoppingMoney> {
  const ShoppingMoney({required this.amountMinor, required this.currency})
    : assert(amountMinor >= 0),
      assert(currency.length == 3);

  final int amountMinor;
  final String currency;

  @override
  int compareTo(ShoppingMoney other) {
    _requireSameCurrency(other);
    return amountMinor.compareTo(other.amountMinor);
  }

  bool operator <(ShoppingMoney other) => compareTo(other) < 0;
  bool operator <=(ShoppingMoney other) => compareTo(other) <= 0;
  bool operator >(ShoppingMoney other) => compareTo(other) > 0;
  bool operator >=(ShoppingMoney other) => compareTo(other) >= 0;

  void _requireSameCurrency(ShoppingMoney other) {
    if (currency != other.currency) {
      throw ArgumentError(
        'Cannot compare different currencies: $currency and ${other.currency}.',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ShoppingMoney &&
      other.amountMinor == amountMinor &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(amountMinor, currency);

  @override
  String toString() => '$currency $amountMinor minor';
}
