import 'package:flutter_test/flutter_test.dart';
import 'package:hesabaty/finance/finance_models.dart';
import 'package:hesabaty/finance/installment_models.dart';
import 'package:hesabaty/finance/transaction_store.dart';

class _MemorySecureStorage implements PrivateStringStorage {
  final data = <String, String>{};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }
}

void main() {
  test('persists and restores transaction fields, dates, and exclusions', () async {
    final storage = _MemorySecureStorage();
    final store = EncryptedTransactionStore(accountScope: 'guest', storage: storage);
    final original = FinanceEntry(
      id: 'test-id', type: EntryType.withdrawal, amount: 253.75,
      date: DateTime(2026, 10, 17), category: 'مطاعم',
      source: 'CIB', note: 'الغداء', excluded: true,
    );
    await store.save([original]);
    final restored = await store.load();
    expect(restored, hasLength(1));
    final entry = restored.single;
    expect(entry.id, original.id);
    expect(entry.amount, 253.75);
    expect(entry.date, DateTime(2026, 10, 17));
    expect(entry.category, 'مطاعم');
    expect(entry.source, 'CIB');
    expect(entry.note, 'الغداء');
    expect(entry.excluded, isTrue);
    expect(storage.data.values.single, contains('"schemaVersion":2'));
  });

  test('guest and account data never share a storage namespace', () async {
    final secure = _MemorySecureStorage();
    final guest = EncryptedTransactionStore(accountScope: 'guest', storage: secure);
    final userA = EncryptedTransactionStore(accountScope: 'user-a', storage: secure);
    final userB = EncryptedTransactionStore(accountScope: 'user-b', storage: secure);
    await guest.save([FinanceEntry(id: 'guest-txn', type: EntryType.deposit,
        amount: 12, date: DateTime(2026, 10), category: 'إيداع')]);
    await userA.save([FinanceEntry(id: 'user-txn', type: EntryType.withdrawal,
        amount: 33, date: DateTime(2026, 10), category: 'أخرى')]);
    expect((await guest.load()).single.id, 'guest-txn');
    expect((await userA.load()).single.id, 'user-txn');
    expect(await userB.load(), isEmpty);
  });

  test('corrupt snapshot fails visibly; no silent empty-list fallback', () async {
    final secure = _MemorySecureStorage();
    final store = EncryptedTransactionStore(accountScope: 'guest', storage: secure);
    await store.save([]);
    final key = secure.data.keys.single;
    secure.data[key] = '{"schemaVersion":999,"entries":[]}';
    await expectLater(store.load(), throwsFormatException);
    expect(secure.data[key], contains('999'));
  });

  test('duplicate transaction IDs cannot be persisted', () async {
    final secure = _MemorySecureStorage();
    final store = EncryptedTransactionStore(accountScope: 'guest', storage: secure);
    final item = FinanceEntry(id: 'duplicate', type: EntryType.deposit,
        amount: 5, date: DateTime(2026, 10), category: 'راتب');
    await expectLater(store.save([item, item]), throwsFormatException);
    expect(secure.data, isEmpty);
  });

  test('v1 transaction snapshots upgrade to v2 without lost transactions', () async {
    final secure = _MemorySecureStorage();
    final store = EncryptedTransactionStore(accountScope: 'guest', storage: secure);
    const raw = '{"schemaVersion":1,"entries":[{"id":"old","type":"deposit",'
        '"amount":500.0,"date":"2026-10-01","category":"راتب"}]}';
    // Save the legacy bytes at the expected key without modifying them.
    await store.save([]);
    final key = secure.data.keys.single;
    secure.data[key] = raw;
    final old = await store.loadLedger();
    expect(old.entries.single.id, 'old');
    expect(old.installments, isEmpty);
    await store.save(old.entries);
    final upgraded = await store.loadLedger();
    expect(upgraded.entries.single.amount, 500);
    expect(secure.data[key], contains('"schemaVersion":2'));
  });

  test('entries and installments are saved together and survive reload', () async {
    final secure = _MemorySecureStorage();
    final store = EncryptedTransactionStore(accountScope: 'owner', storage: secure);
    final plan = InstallmentPlan(
      id: 'phone', name: 'قسط الموبايل', amount: 1200,
      dueDay: 31, startMonth: DateTime(2026, 1), count: 12,
    );
    final paid = InstallmentLedger(
      entries: const [], installments: [plan],
    ).recordPayment(
      installmentId: 'phone', month: DateTime(2026, 4),
      paidOn: DateTime(2026, 4, 15), newTransactionId: 'tx-id',
    );
    await store.saveLedger(paid);
    final restored = await store.loadLedger();
    expect(restored.entries.single.id, 'tx-id');
    expect(restored.installments.single.paymentFor(DateTime(2026, 4))
        ?.transactionId, 'tx-id');
    expect(secure.data.values.single, contains('"installments":'));
  });

  test('reject broken payment pointers before encrypted write', () async {
    final secure = _MemorySecureStorage();
    final store = EncryptedTransactionStore(accountScope: 'owner', storage: secure);
    final plan = InstallmentPlan(
      id: 'phone', name: 'قسط', amount: 100, dueDay: 1,
      startMonth: DateTime(2026, 1), count: 0,
      payments: [InstallmentPayment(month: DateTime(2026, 4),
          transactionId: 'missing', date: DateTime(2026, 4, 1))],
    );
    await expectLater(
      store.saveLedger(InstallmentLedger(
          entries: const [], installments: [plan])), throwsFormatException);
    expect(secure.data, isEmpty);
  });

  test('invalid dates cannot be silently normalized when reloaded', () {
    final item = FinanceEntry(
      id: 'id', type: EntryType.deposit, amount: 12,
      date: DateTime(2026, 10, 17), category: 'راتب',
    );
    final json = item.toJson();
    json['date'] = '2026-02-30';
    expect(() => FinanceEntry.fromJson(json), throwsFormatException);
  });
}
