// Purpose: Manages credit balance, plans, and checkout flow.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/credit_model.dart';
import '../services/credits_service.dart';

class CreditsController extends ChangeNotifier {
  CreditsController(this._service, this._tokenProvider);

  final CreditsService _service;
  final Future<String?> Function() _tokenProvider;

  int _balance = 0;
  CreditSubscription? _subscription;
  List<CreditTransaction> _transactions = const [];
  List<CreditPack> _packs = const [];
  List<SubscriptionPlan> _plans = const [];

  bool _loading = false;
  String? _error;

  // ── Public state ───────────────────────────────────────────────────────────

  int get balance => _balance;
  CreditSubscription? get subscription => _subscription;
  List<CreditTransaction> get transactions => _transactions;
  List<CreditPack> get creditPacks => _packs;
  List<SubscriptionPlan> get subscriptionPlans => _plans;
  bool get loading => _loading;
  String? get error => _error;

  // ── Initialisation ─────────────────────────────────────────────────────────

  /// Load balance + subscription + plans in one shot.
  Future<void> init() async {
    _setLoading(true);
    _clearError();
    try {
      await Future.wait([_loadBalance(), _loadSubscription(), _loadPlans()]);
    } catch (e) {
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  Future<void> refreshBalance() async {
    try {
      await _loadBalance();
    } catch (e) {
      _setError(e.toString());
    }
  }

  Future<void> loadTransactions() async {
    _clearError();
    try {
      final token = await _tokenProvider();
      if (token == null) return;
      _transactions = await _service.fetchTransactions(token);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
    }
  }

  // ── Checkout ───────────────────────────────────────────────────────────────

  /// Returns the Paddle checkout URL for the given plan/pack.
  /// [type] is `'pack'` or `'subscription'`.
  /// [returnUrl] is where Paddle sends the user after payment (a web URL on
  /// web, the `buildercam://billing` deep link on mobile).
  Future<String?> getCheckoutUrl({
    required String type,
    required String planId,
    String? returnUrl,
  }) async {
    _clearError();
    try {
      final token = await _tokenProvider();
      if (token == null) throw Exception('Not authenticated.');
      final url = await _service.createCheckout(
        idToken: token,
        type: type,
        planId: planId,
        returnUrl: returnUrl,
      );
      return url;
    } catch (e) {
      _setError(e.toString());
      return null;
    }
  }

  /// Reconciles pending purchases after the user returns from checkout.
  ///
  /// This is the safety net for the classic "paid but no credits" bug: rather
  /// than trusting the webhook to have arrived, it polls the backend's /sync
  /// endpoint (which verifies the payment straight against Paddle) a few times
  /// with backoff, settling as soon as credits/subscription appear.
  ///
  /// Returns `true` if the wallet changed (credits granted or sub activated).
  Future<bool> syncAfterCheckout({int attempts = 6}) async {
    final token = await _tokenProvider();
    if (token == null) return false;

    final beforeBalance = _balance;
    final beforeSub = _subscription?.isActive == true;

    for (var i = 0; i < attempts; i++) {
      try {
        final r = await _service.syncPayments(token);
        _balance = r.balance;
        _subscription = r.subscription;
        notifyListeners();

        final gainedCredits = _balance > beforeBalance;
        final gainedSub = !beforeSub && _subscription?.isActive == true;
        if (r.applied || gainedCredits || gainedSub) {
          unawaited(loadTransactions());
          return true;
        }
      } catch (_) {
        // Transient — keep polling; the webhook may also still land.
      }
      // Backoff: 1s, 2s, 3s … giving Paddle time to finish processing.
      await Future<void>.delayed(Duration(seconds: i + 1));
    }

    // Final settle in case state changed without us catching the transition.
    return _balance > beforeBalance ||
        (!beforeSub && _subscription?.isActive == true);
  }

  // ── Private ────────────────────────────────────────────────────────────────

  Future<void> _loadBalance() async {
    final token = await _tokenProvider();
    if (token == null) return;
    _balance = await _service.fetchBalance(token);
    notifyListeners();
  }

  Future<void> _loadSubscription() async {
    final token = await _tokenProvider();
    if (token == null) return;
    _subscription = await _service.fetchSubscription(token);
    notifyListeners();
  }

  Future<void> _loadPlans() async {
    final result = await _service.fetchPlans();
    _packs = result.packs;
    _plans = result.plans;
    notifyListeners();
  }

  void _setLoading(bool v) {
    _loading = v;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
    notifyListeners();
  }

  void _setError(String msg) {
    _error = msg;
    notifyListeners();
  }
}
