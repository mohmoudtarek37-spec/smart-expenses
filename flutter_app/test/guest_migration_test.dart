import 'package:flutter_test/flutter_test.dart';
import 'package:hesabaty/finance/finance_models.dart';
import 'package:hesabaty/finance/guest_migration.dart';
import 'package:hesabaty/finance/installment_models.dart';

void main() {
  final guest = InstallmentLedger(
    entries: [FinanceEntry(
      id: 'income', type: EntryType.deposit, amount: 1200,
      date: DateTime(2026, 10, 17), category: 'راتب',
    )], installments: const [], customCategories: const ['مخصص'],
  );
  const empty = InstallmentLedger(entries: [], installments: []);

  test('allows copy only into an empty account without mutating guest', () {
    final data = GuestMigration.prepare(guest: guest, account: empty);
    expect(data.entries.single.amount, 1200);
    expect(guest.entries.single.id, 'income');
    expect(data.customCategories, ['مخصص']);
  });

  test('refuses to replace transactions already in the account', () {
    final account = InstallmentLedger(
      entries: guest.entries, installments: const []);
    expect(() => GuestMigration.prepare(guest: guest, account: account),
        throwsStateError);
  });

  test('refuses accounts with existing settings', () {
    const account = InstallmentLedger(
      entries: [], installments: [], prefs: {'currency': 'EGP'});
    expect(() => GuestMigration.prepare(guest: guest, account: account),
        throwsStateError);
  });

  test('empty guest cannot reset even an empty account', () {
    expect(() => GuestMigration.prepare(guest: empty, account: empty),
        throwsStateError);
  });
}
