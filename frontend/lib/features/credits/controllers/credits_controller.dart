// Purpose: Manages credit balance, plans, and checkout flow.
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
  Future<String?> getCheckoutUrl({
    required String type,
    required String planId,
  }) async {
    _clearError();
    try {
      final token = await _tokenProvider();
      if (token == null) throw Exception('Not authenticated.');
      final url = await _service.createCheckout(
        idToken: token,
        type: type,
        planId: planId,
      );
      return url;
    } catch (e) {
      _setError(e.toString());
      return null;
    }
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
