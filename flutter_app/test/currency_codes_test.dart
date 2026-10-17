import 'package:flutter_test/flutter_test.dart';
import 'package:hesabaty/finance/currency_codes.dart';

void main() {
  test('supported choices are the ten approved finance currencies', () {
    expect(FinanceCurrency.codes, [
      'EGP', 'USD', 'EUR', 'AED', 'SAR',
      'CAD', 'KWD', 'SEK', 'UAH', 'RUB',
    ]);
  });

  test('untrusted, unknown or blank currency labels cannot get into PDF', () {
    expect(FinanceCurrency.normalize(null), 'EGP');
    expect(FinanceCurrency.normalize('USD'), 'USD');
    expect(FinanceCurrency.normalize(' rub '), 'EGP');
    expect(FinanceCurrency.normalize('UNKNOWN'), 'EGP');
  });
}
