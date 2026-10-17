/// The app records nominal amounts in one chosen unit. Switching the unit
/// does not perform a foreign-exchange conversion of historical transactions.
abstract final class FinanceCurrency {
  static const codes = <String>[
    'EGP', 'USD', 'EUR', 'AED', 'SAR',
    'CAD', 'KWD', 'SEK', 'UAH', 'RUB',
  ];

  static String normalize(Object? raw) {
    final code = raw?.toString() ?? '';
    return codes.contains(code) ? code : 'EGP';
  }
}
