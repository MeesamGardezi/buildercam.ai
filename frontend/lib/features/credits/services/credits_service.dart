// Purpose: HTTP client for the credits & billing backend API.
import 'dart:convert';

import 'package:buildercam/core/core.dart';
import 'package:http/http.dart' as http;

import '../models/credit_model.dart';

class CreditsService {
  CreditsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Uri get _base => Uri.parse(ApiConfig.sowProxyBaseUrl);

  // ── Balance & history ──────────────────────────────────────────────────────

  Future<int> fetchBalance(String idToken) async {
    final res = await _client.get(
      _base.resolve('/api/credits/balance'),
      headers: _auth(idToken),
    );
    _assert(res, 'fetchBalance');
    final data = _decode(res);
    return (data['balance'] as num?)?.toInt() ?? 0;
  }

  Future<List<CreditTransaction>> fetchTransactions(String idToken) async {
    final res = await _client.get(
      _base.resolve('/api/credits/transactions'),
      headers: _auth(idToken),
    );
    _assert(res, 'fetchTransactions');
    final data = _decode(res);
    final raw = data['transactions'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(CreditTransaction.fromJson)
        .toList();
  }

  Future<CreditSubscription?> fetchSubscription(String idToken) async {
    final res = await _client.get(
      _base.resolve('/api/credits/subscription'),
      headers: _auth(idToken),
    );
    _assert(res, 'fetchSubscription');
    final data = _decode(res);
    final sub = data['subscription'];
    if (sub == null) return null;
    return CreditSubscription.fromJson(sub as Map<String, dynamic>);
  }

  // ── Plans ──────────────────────────────────────────────────────────────────

  Future<({List<CreditPack> packs, List<SubscriptionPlan> plans})>
      fetchPlans() async {
    final res = await _client.get(_base.resolve('/api/credits/plans'));
    _assert(res, 'fetchPlans');
    final data = _decode(res);

    final packs = (data['creditPacks'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(CreditPack.fromJson)
        .toList();

    final plans = (data['subscriptionPlans'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(SubscriptionPlan.fromJson)
        .toList();

    return (packs: packs, plans: plans);
  }

  // ── Checkout ───────────────────────────────────────────────────────────────

  /// Requests a Paddle checkout URL from the backend.
  /// [type] is either `'pack'` or `'subscription'`.
  /// [planId] is the item ID (e.g. `'pack_50'` or `'plan_starter'`).
  Future<String> createCheckout({
    required String idToken,
    required String type,
    required String planId,
    String? returnUrl,
  }) async {
    final body = <String, dynamic>{'type': type, 'planId': planId};
    if (returnUrl != null) body['returnUrl'] = returnUrl;

    final res = await _client.post(
      _base.resolve('/api/credits/checkout'),
      headers: _auth(idToken),
      body: jsonEncode(body),
    );
    _assert(res, 'createCheckout');
    final data = _decode(res);
    final url = data['checkoutUrl'] as String?;
    if (url == null) throw Exception('Backend did not return a checkout URL.');
    return url;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Map<String, String> _auth(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  Map<String, dynamic> _decode(http.Response res) =>
      jsonDecode(res.body) as Map<String, dynamic>;

  void _assert(http.Response res, String op) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    final body = _tryDecode(res.body);
    final msg = body?['message'] as String? ?? res.body;
    throw Exception('[$op] ${res.statusCode}: $msg');
  }

  Map<String, dynamic>? _tryDecode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }
}
