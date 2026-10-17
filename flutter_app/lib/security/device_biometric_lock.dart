import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../finance/transaction_store.dart';

/// A per-device, per-account privacy lock. It is NOT Supabase login.
class DeviceBiometricLock {
  DeviceBiometricLock._();
  static final DeviceBiometricLock instance = DeviceBiometricLock._();

  final LocalAuthentication _auth = LocalAuthentication();
  bool isAuthenticating = false;
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  String _key(String scope) => 'hesabaty_biometric_lock_$scope';

  Future<bool> isEnabled(String scope) async =>
      await const DevicePrivateStorage().read(_key(scope)) == 'true';

  Future<bool> available() async {
    try {
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> verify(String reason) async {
    if (isAuthenticating) return false;
    isAuthenticating = true;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    } finally {
      isAuthenticating = false;
    }
  }

  Future<bool> change(String scope, bool enable, String reason) async {
    if (enable && !await available()) return false;
    if (!await verify(reason)) return false;
    await const DevicePrivateStorage().write(_key(scope),
        enable ? 'true' : 'false');
    changes.value++;
    return true;
  }
}

/// Covers the entire signed-in/guest dashboard while an enabled local lock
/// needs device authentication. Never offers an insecure dismiss shortcut.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.scope, required this.isEnglish,
    required this.child});
  final String scope;
  final bool isEnglish;
  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate>
    with WidgetsBindingObserver {
  bool _checking = true;
  bool _locked = true;
  bool _wentBackground = false;
  bool _prompting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DeviceBiometricLock.instance.changes.addListener(_onPreferenceChange);
    _check(initial: true);
  }

  @override
  void didUpdateWidget(covariant AppLockGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope) {
      setState(() { _locked = true; _checking = true; });
      _check(initial: true);
    }
  }

  void _onPreferenceChange() {
    if (mounted) _check();
  }

  Future<void> _check({bool initial = false}) async {
    final scope = widget.scope;
    bool enabled;
    try {
      enabled = await DeviceBiometricLock.instance.isEnabled(scope);
    } catch (_) {
      enabled = false;
    }
    if (!mounted || widget.scope != scope) return;
    setState(() {
      _checking = false;
      if (!enabled) _locked = false;
      if (enabled && initial) _locked = true;
    });
    if (enabled && _locked && !_prompting) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
    }
  }

  Future<void> _unlock() async {
    if (!mounted || !_locked || _checking || _prompting) return;
    _prompting = true;
    final ok = await DeviceBiometricLock.instance.verify(widget.isEnglish
        ? 'Unlock Hesabaty with your phone security'
        : 'افتح حساباتي ببصمة أو وسيلة قفل الموبايل');
    _prompting = false;
    if (!mounted) return;
    if (ok) setState(() => _locked = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (DeviceBiometricLock.instance.isAuthenticating) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _wentBackground = true;
    }
    if (state == AppLifecycleState.resumed && _wentBackground) {
      _wentBackground = false;
      setState(() => _locked = true);
      _check(initial: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DeviceBiometricLock.instance.changes.removeListener(_onPreferenceChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
    widget.child,
    if (_checking || _locked)
      Positioned.fill(child: ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(child: Center(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 64),
            const SizedBox(height: 12),
            Text(widget.isEnglish ? 'Hesabaty is locked' : 'حساباتي مقفول',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 15),
            if (_checking) const CircularProgressIndicator()
            else FilledButton.icon(
              key: const Key('unlock-app'),
              onPressed: _prompting ? null : _unlock,
              icon: const Icon(Icons.fingerprint),
              label: Text(widget.isEnglish
                  ? 'Unlock' : 'فتح التطبيق'),
            ),
          ],
        ))),
      )),
  ]);
}
