import 'package:flutter_test/flutter_test.dart';
import 'package:hesabaty/finance/finance_models.dart';
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
