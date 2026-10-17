import 'dart:async';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Google Play purchases are disabled until the verification backend reports
/// readiness. The app NEVER grants Premium from a device purchase callback.
class PremiumPage extends StatefulWidget {
  const PremiumPage({super.key});
  @override
  State<PremiumPage> createState() => _PremiumPageState();
}

class _PremiumPageState extends State<PremiumPage> {
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
          if (mounted) setState(() => _status =
              'تعذر الاتصال بمتجر Google Play. جرّب مرة تانية.');
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
          _status = 'الاشتراكات لسه مش متاحة: '
              'لازم نفعّل Google Play Developer API والتحقق على السيرفر.';
        });
        return;
      }
      final store = await _billing.isAvailable();
      if (!mounted) return;
      if (!store) {
        setState(() => _status = 'Google Play Billing مش متاح على الجهاز.');
        return;
      }
      final response = await _billing.queryProductDetails({productId});
      if (!mounted) return;
      if (response.productDetails.isEmpty) {
        setState(() => _status =
            'منتج Premium مش متاح على Google Play للحساب ده.');
        return;
      }
      setState(() {
        _backendReady = true;
        _storeReady = true;
        _product = response.productDetails.first;
        _status = 'الاشتراك متاح عبر Google Play.';
      });
    } catch (_) {
      if (mounted) setState(() => _status =
          'تعذر فحص المتجر والسيرفر. مش هنبدأ شراء غير قابل للتحقق.');
    } finally {
      if (mounted) setState(() => _loading = false);
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
      if (!started) setState(() => _status =
          'متجر Google Play ما بدأش عملية الاشتراك.');
    } catch (_) {
      if (mounted) setState(() => _status =
          'تعذر بدء الاشتراك. لم يتم تفعيل Premium.');
    }
  }

  Future<void> _restore() async {
    if (!_backendReady || !_storeReady) return;
    try {
      await _billing.restorePurchases();
      if (mounted) setState(() => _status =
          'هنراجع أي اشتراكات سابقة مع Google Play.');
    } catch (_) {
      if (mounted) setState(() => _status = 'تعذرت استعادة مشتريات Google Play.');
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    if (_processing) return;
    for (final purchase in purchases) {
      if (purchase.productID != productId) continue;
      if (purchase.status == PurchaseStatus.pending) {
        if (mounted) setState(() => _status =
            'العملية لسه تحت المعالجة في Google Play.');
        continue;
      }
      if (purchase.status == PurchaseStatus.canceled) {
        if (mounted) setState(() => _status = 'تم إلغاء عملية الشراء.');
        continue;
      }
      if (purchase.status == PurchaseStatus.error) {
        if (mounted) setState(() => _status =
            'فشل الشراء في Google Play. لم يتم تفعيل Premium.');
        continue;
      }
      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) continue;
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) continue;
      setState(() {
        _processing = true;
        _status = 'بنتحقق من الاشتراك على السيرفر...';
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
        if (mounted) setState(() => _status =
            _premium ? 'تم تأكيد اشتراك Premium على السيرفر.'
                : 'تم التحقق لكن الاشتراك مش نشط حاليًا.');
      } catch (_) {
        if (mounted) setState(() => _status =
            'تعذر التحقق من الشراء. مش هنفعّل Premium قبل تأكيد Google. '
            'راجع الاتصال أو جرّب استعادة المشتريات.');
      } finally {
        if (mounted) setState(() => _processing = false);
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
    appBar: AppBar(title: const Text('حساباتي Premium')),
    body: SafeArea(child: ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const Icon(Icons.workspace_premium_outlined, size: 72),
        const SizedBox(height: 12),
        Text(_premium ? 'اشتراكك نشط' : 'حساباتي Premium',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        const Text('الدفع والاشتراكات من خلال Google Play فقط. '
            'السعر النهائي بيظهر من Google Play بعملة حسابك '
            'قبل ما توافق على الدفع.',
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
          label: Text(_premium ? 'Premium مفعل' : 'اشترك عبر Google Play'),
        ),
        OutlinedButton(
          key: const Key('restore-premium'),
          onPressed: _loading || !_backendReady || !_storeReady
              ? null : _restore,
          child: const Text('استعادة مشتريات Google Play'),
        ),
        const Text('الاشتراك لا يتفعل إلا بعد التحقق من صلاحية '
            'المشتريات على السيرفر. لا نستخدم دفعًا خارج Google Play.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12)),
      ],
    )),
  );
}
