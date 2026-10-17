import 'package:flutter_test/flutter_test.dart';
import 'package:hesabaty/subscriptions/account_plan.dart';

void main() {
  final now = DateTime.utc(2026, 10, 18);
  Map<String, dynamic> entitlement(String status, String date) => {
    'product_id': AccountPlan.productId,
    'status': status,
    'expires_at': date,
  };

  test('guest never gets paid features from a row', () {
    expect(AccountPlan.fromServer(
      signedIn: false, now: now,
      entitlement: entitlement('active', '2026-11-18T00:00:00Z')),
      HesabatyPlan.guest);
  });

  test('unverified user metadata cannot self-grant owner status', () {
    expect(AccountPlan.fromServer(
      signedIn: true, now: now,
      appMetadata: const {'role': 'user'},
      entitlement: null), HesabatyPlan.free);
  });

  test('only privileged owner app claim creates owner state', () {
    expect(AccountPlan.fromServer(
      signedIn: true, now: now,
      appMetadata: const {'role': 'owner'},
      entitlement: null), HesabatyPlan.owner);
  });

  test('active, grace and canceled remain premium through expiry', () {
    for (final status in ['active', 'grace_period', 'canceled']) {
      expect(AccountPlan.fromServer(
        signedIn: true, now: now,
        entitlement: entitlement(status, '2026-11-18T00:00:00Z')),
        HesabatyPlan.premium);
    }
  });

  test('expiration, wrong product or pending never unlock', () {
    expect(AccountPlan.fromServer(
      signedIn: true, now: now,
      entitlement: entitlement('active', '2026-09-18T00:00:00Z')),
      HesabatyPlan.free);
    expect(AccountPlan.fromServer(
      signedIn: true, now: now,
      entitlement: entitlement('pending', '2026-11-18T00:00:00Z')),
      HesabatyPlan.free);
    expect(AccountPlan.fromServer(
      signedIn: true, now: now,
      entitlement: {'status': 'active',
        'product_id': 'other', 'expires_at': '2026-11-18T00:00:00Z'}),
      HesabatyPlan.free);
  });
}
