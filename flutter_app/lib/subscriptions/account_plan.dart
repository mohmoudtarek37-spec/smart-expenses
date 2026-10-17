/// Read-only account plan derived from trusted session claims and
/// server-side Google Play entitlements. Clients must never write entitlements.
enum HesabatyPlan { guest, free, premium, owner }

abstract final class AccountPlan {
  static const productId = 'hesabaty_premium_monthly';

  static bool isOwner(Map<String, dynamic> claims) =>
      claims['role'] == 'owner';

  static bool verifiedPremium(Map<String, dynamic>? data, DateTime now) {
    if (data == null || data['product_id'] != productId) return false;
    if (!const {'active', 'grace_period', 'canceled'}
        .contains(data['status'])) return false;
    final expiresAt =
        DateTime.tryParse(data['expires_at']?.toString() ?? '');
    return expiresAt != null && expiresAt.isAfter(now);
  }

  static HesabatyPlan fromServer({
    required bool signedIn,
    Map<String, dynamic> appMetadata = const {},
    Map<String, dynamic>? entitlement,
    required DateTime now,
  }) {
    if (!signedIn) return HesabatyPlan.guest;
    if (isOwner(appMetadata)) return HesabatyPlan.owner;
    return verifiedPremium(entitlement, now)
        ? HesabatyPlan.premium : HesabatyPlan.free;
  }
}
