import 'dart:async';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Google Play purchases are disabled until the verification backend reports
/// readiness. The app NEVER grants Premium from a device purchase callback.
class PremiumPage extends StatefulWidget {
  const PremiumPage({super.key, this.isEnglish = false});
  final bool isEnglish;
  @override
  State<PremiumPage> createState() => _PremiumPageState();
}

class _PremiumPageState extends State<PremiumPage> {
  String _tr(String ar, String en) => widget.isEnglish ? en : ar;

  static const productId = 'hesabaty_premium_monthly';
  final _billing = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  ProductDetails? _product;
  bool _loading = true;
  bool _storeReady = false;
  bool _backendReady = false;
  bool _premium = false;
  bool _processing = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _purchaseSub = _billing.purchaseStream.listen(_onPurchases,
        onError: (_) {
          if (mounted) {
          setState(() => _status =
              _tr('تعذر الاتصال بمتجر Google Play. جرّب مرة تانية.', 'Cannot connect to Google Play. Try again.'));
        }
        });
    _initialize();
  }

  Future<void> _refreshEntitlement() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final data = await Supabase.instance.client.from('user_entitlements')
        .select('status,expires_at,product_id')
        .eq('user_id', user.id).maybeSingle();
    if (!mounted) return;
    final until = DateTime.tryParse(data?['expires_at']?.toString() ?? '');
    final permitted = data?['product_id'] == productId &&
        ['active', 'grace_period', 'canceled'].contains(data?['status']) &&
        until != null && until.isAfter(DateTime.now());
    setState(() => _premium = permitted);
  }

  Future<void> _initialize() async {
    try {
      await _refreshEntitlement();
      final response = await Supabase.instance.client.functions.invoke(
          'verify-play-subscription', body: {'action': 'status'});
      final ready = response.data is Map &&
          response.data['ready'] == true;
      if (!mounted) return;
      if (!ready) {
        setState(() {
          _status = _tr('الاشتراكات لسه مش متاحة: '
              'لازم نفعّل Google Play Developer API والتحقق على السيرفر.',
              'Subscriptions are not available yet: server verification is not configured.');
        });
        return;
      }
      final store = await _billing.isAvailable();
      if (!mounted) return;
      if (!store) {
        setState(() => _status = _tr('Google Play Billing مش متاح على الجهاز.', 'Google Play Billing is unavailable on this device.'));
        return;
      }
      final productsResponse = await _billing.queryProductDetails({productId});
      if (!mounted) return;
      if (productsResponse.productDetails.isEmpty) {
        setState(() => _status =
            _tr('منتج Premium مش متاح على Google Play للحساب ده.', 'Premium is not offered for this Google Play account.'));
        return;
      }
      setState(() {
        _backendReady = true;
        _storeReady = true;
        _product = productsResponse.productDetails.first;
        _status = _tr('الاشتراك متاح عبر Google Play.', 'Subscribe using Google Play.');
      });
    } catch (_) {
      if (mounted) {
          setState(() => _status =
          _tr('تعذر فحص المتجر والسيرفر. مش هنبدأ شراء غير قابل للتحقق.', 'Cannot verify the store and server. Purchase is disabled for your protection.'));
        }
    } finally {
      if (mounted) {
          setState(() => _loading = false);
        }
    }
  }

  Future<void> _buy() async {
    if (_loading || _processing || !_backendReady || !_storeReady ||
        _product == null || Supabase.instance.client.auth.currentUser == null) {
      return;
    }
    try {
      final started = await _billing.buyNonConsumable(
          purchaseParam: PurchaseParam(productDetails: _product!));
      if (!mounted) return;
      if (!started) {
          setState(() => _status =
          _tr('متجر Google Play ما بدأش عملية الاشتراك.', 'Google Play did not start the purchase.'));
        }
    } catch (_) {
      if (mounted) {
          setState(() => _status =
          _tr('تعذر بدء الاشتراك. لم يتم تفعيل Premium.', 'Could not start purchase. Premium is not active.'));
        }
    }
  }

  Future<void> _restore() async {
    if (!_backendReady || !_storeReady) return;
    try {
      await _billing.restorePurchases();
      if (mounted) {
          setState(() => _status =
          _tr('هنراجع أي اشتراكات سابقة مع Google Play.', 'Checking past subscriptions with Google Play.'));
        }
    } catch (_) {
      if (mounted) {
          setState(() => _status = _tr('تعذرت استعادة مشتريات Google Play.', 'Could not restore Google Play purchases.'));
        }
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    if (_processing) return;
    for (final purchase in purchases) {
      if (purchase.productID != productId) continue;
      if (purchase.status == PurchaseStatus.pending) {
        if (mounted) {
          setState(() => _status =
            _tr('العملية لسه تحت المعالجة في Google Play.', 'Purchase is pending in Google Play.'));
        }
        continue;
      }
      if (purchase.status == PurchaseStatus.canceled) {
        if (mounted) {
          setState(() => _status = _tr('تم إلغاء عملية الشراء.', 'Purchase was cancelled.'));
        }
        continue;
      }
      if (purchase.status == PurchaseStatus.error) {
        if (mounted) {
          setState(() => _status =
            _tr('فشل الشراء في Google Play. لم يتم تفعيل Premium.', 'Purchase failed. Premium was not activated.'));
        }
        continue;
      }
      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) {
        continue;
      }
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) continue;
      setState(() {
        _processing = true;
        _status = _tr('بنتحقق من الاشتراك على السيرفر...', 'Verifying purchase on the server...');
      });
      try {
        final response = await Supabase.instance.client.functions.invoke(
          'verify-play-subscription', body: {
            'action': 'verify',
            'productId': productId,
            'purchaseToken': purchase.verificationData.serverVerificationData,
          },
        );
        final verified = response.data is Map &&
            response.data['verified'] == true;
        if (!verified) {
          throw StateError('Google Play verification was not confirmed');
        }
        if (purchase.pendingCompletePurchase) {
          await _billing.completePurchase(purchase);
        }
        if (Supabase.instance.client.auth.currentUser?.id != userId) return;
        await _refreshEntitlement();
        if (mounted) {
          setState(() => _status =
            _premium ? _tr('تم تأكيد اشتراك Premium على السيرفر.', 'Premium subscription verified.')
                : _tr('تم التحقق لكن الاشتراك مش نشط حاليًا.', 'Subscription verified but currently inactive.'));
        }
      } catch (_) {
        if (mounted) {
          setState(() => _status =
            _tr('تعذر التحقق من الشراء. مش هنفعّل Premium قبل تأكيد Google. '
            'راجع الاتصال أو جرّب استعادة المشتريات.',
            'Purchase verification failed. Premium stays locked until Google confirms the purchase.'));
        }
      } finally {
        if (mounted) {
          setState(() => _processing = false);
        }
      }
    }
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_tr('حساباتي Premium', 'Hesabaty Premium'))),
    body: SafeArea(child: ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const Icon(Icons.workspace_premium_outlined, size: 72),
        const SizedBox(height: 12),
        Text(_premium ? _tr('اشتراكك نشط', 'Your subscription is active')
            : _tr('حساباتي Premium', 'Hesabaty Premium'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        Text(_tr('الدفع والاشتراكات من خلال Google Play فقط. '
            'السعر النهائي بيظهر من Google Play بعملة حسابك '
            'قبل ما توافق على الدفع.',
            'Subscriptions are billed by Google Play only. The final price '
            'and currency appear in the store before purchase.'),
            textAlign: TextAlign.center),
        const SizedBox(height: 20),
        if (_product != null)
          Text(_product!.price, textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall),
        if (_status.isNotEmpty)
          Padding(padding: const EdgeInsets.all(12),
              child: Text(_status, textAlign: TextAlign.center)),
        if (_loading || _processing) const LinearProgressIndicator(),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('buy-premium'),
          onPressed: _premium || _loading || _processing ||
              !_backendReady || !_storeReady ? null : _buy,
          icon: const Icon(Icons.shopping_bag_outlined),
          label: Text(_premium ? _tr('Premium مفعل', 'Premium active')
              : _tr('اشترك عبر Google Play', 'Subscribe with Google Play')),
        ),
        OutlinedButton(
          key: const Key('restore-premium'),
          onPressed: _loading || !_backendReady || !_storeReady
              ? null : _restore,
          child: Text(_tr('استعادة مشتريات Google Play', 'Restore Google Play purchases')),
        ),
        Text(_tr('الاشتراك لا يتفعل إلا بعد التحقق من صلاحية '
            'المشتريات على السيرفر. لا نستخدم دفعًا خارج Google Play.',
            'Premium unlocks only after server-side purchase verification. '
            'All billing uses Google Play.'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12)),
      ],
    )),
  );
}
