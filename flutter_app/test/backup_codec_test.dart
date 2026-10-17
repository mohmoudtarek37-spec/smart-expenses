import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hesabaty/finance/backup_codec.dart';
import 'package:hesabaty/finance/finance_models.dart';
import 'package:hesabaty/finance/installment_models.dart';

void main() {
  test('Flutter backup roundtrips linked payments, SMS, receipts and prefs', () {
    final start = InstallmentLedger(
      entries: [
        FinanceEntry(
          id: 'bank-tx', type: EntryType.withdrawal,
          amount: 150, date: DateTime(2026, 10, 17),
          category: 'أقساط', source: 'CIB', note: 'اختبار',
          originalMessage: 'Purchase EGP 150', sender: 'CIB',
          fingerprint: 'abc123', createdAt: '2026-10-17T10:00:00Z',
          receiptDataUrl: 'data:image/png;base64,aGVsbG8=',
          linkedInstallment: 'phone',
          extraFields: {'legacyCategoryHint': 'test'},
        ),
      ],
      installments: [
        InstallmentPlan(
          id: 'phone', name: 'موبايل', amount: 150, dueDay: 31,
          startMonth: DateTime(2026, 1), count: 12,
          payments: [
            InstallmentPayment(month: DateTime(2026, 10),
                transactionId: 'bank-tx', date: DateTime(2026, 10, 17)),
          ],
        ),
      ],
      customCategories: ['قهوة'],
      prefs: {'displayName': 'اسم تجريبي', 'dark': true},
      createdAt: '2026-10-01T00:00:00Z',
    );
    final encoded = BackupCodec.encode(start);
    final parsed = jsonDecode(encoded) as Map<String, dynamic>;
    expect(parsed['format'], 'hesabaty-backup');
    expect((parsed['data'] as Map<String, dynamic>)['schemaVersion'], 1);
    final preview = BackupCodec.decode(encoded);
    expect(preview.transactionCount, 1);
    expect(preview.installmentCount, 1);
    expect(preview.receiptCount, 1);
    expect(preview.smsCount, 1);
    expect(preview.ledger.entries.single.originalMessage, 'Purchase EGP 150');
    expect(preview.ledger.entries.single.receiptDataUrl,
        'data:image/png;base64,aGVsbG8=');
    expect(preview.ledger.entries.single.extraFields['legacyCategoryHint'],
        'test');
    expect(preview.ledger.installments.single.payments.single.transactionId,
        'bank-tx');
    expect(preview.ledger.customCategories, ['قهوة']);
    expect(preview.ledger.prefs['displayName'], 'اسم تجريبي');
  });

  test('imports exact HTML v1 backup envelope and source fields', () {
    final legacy = jsonEncode({
      'format': 'hesabaty-backup',
      'appVersion': '1.5.0',
      'data': {
        'schemaVersion': 1,
        'transactions': [
          {
            'id': 'old-withdrawal', 'type': 'withdrawal',
            'amount': 100, 'date': '2026-10-16',
            'category': 'مطاعم', 'source': 'CIB',
            'note': 'غداء', 'originalMessage': 'Purchase 100 EGP',
            'sender': 'CIB', 'receiptDataUrl': '',
            'fingerprint': 'older-fingerprint',
            'linkedInstallment': '', 'createdAt': '2026-10-16T00:00:00Z',
          },
        ],
        'installments': [
          {
            'id': 'installment-x', 'name': 'قسط', 'amount': 50,
            'dueDay': 31, 'startMonth': '2026-01',
            'count': 0, 'active': true, 'payments': [],
          },
        ],
        'customCategories': ['مطاعم خاصة'],
        'prefs': {'profileName': 'اختبار'},
        'createdAt': '2026-01-01T00:00:00Z',
      },
    });
    final preview = BackupCodec.decode(legacy);
    expect(preview.sourceVersion, '1.5.0');
    expect(preview.ledger.entries.single.fingerprint, 'older-fingerprint');
    expect(preview.ledger.installments.single.count, 0);
    expect(preview.ledger.prefs['profileName'], 'اختبار');
  });

  test('a backup with missing installment withdrawal must be rejected', () {
    final broken = jsonEncode({
      'format': 'hesabaty-backup',
      'data': {
        'schemaVersion': 1,
        'transactions': [],
        'installments': [
          {
            'id': 'due', 'name': 'قسط', 'amount': 100, 'dueDay': 5,
            'count': 0, 'startMonth': '2026-01', 'active': true,
            'payments': [
              {'month': '2026-10', 'txId': 'deleted-tx',
               'date': '2026-10-17'}
            ],
          },
        ],
      },
    });
    expect(() => BackupCodec.decode(broken), throwsFormatException);
  });

  test('duplicate transaction IDs are never silently merged', () {
    final transaction = {
      'id': 'same', 'type': 'deposit', 'amount': 100,
      'date': '2026-10-01', 'category': 'إيداع',
    };
    final broken = jsonEncode({
      'format': 'hesabaty-backup',
      'data': {'schemaVersion': 1,
        'transactions': [transaction, transaction],
        'installments': [],
      },
    });
    expect(() => BackupCodec.decode(broken), throwsFormatException);
  });

  test('future backup schema and random JSON are refused', () {
    final future = jsonEncode({
      'format': 'hesabaty-backup',
      'data': {'schemaVersion': 99,
        'transactions': [], 'installments': []},
    });
    expect(() => BackupCodec.decode(future), throwsFormatException);
    expect(() => BackupCodec.decode('{"hello":"world"}'),
        throwsFormatException);
  });

  test('bad receipt types cause a clear error rather than data loss', () {
    final broken = jsonEncode({
      'format': 'hesabaty-backup',
      'data': {'schemaVersion': 1, 'transactions': [
          {'id': 'a', 'type': 'deposit', 'amount': 1,
           'date': '2026-10-17', 'category': 'إيداع',
           'receiptDataUrl': 'file:///private/photo.jpeg'},
        ], 'installments': []},
    });
    expect(() => BackupCodec.decode(broken), throwsFormatException);
  });
}
