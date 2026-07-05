// Purpose: Thin wrapper around StoreKit (via the official in_app_purchase
//          package) — queries products, drives purchases, and verifies each
//          completed purchase against our backend before finishing it.
import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

import '../models/credit_model.dart';
import 'credits_service.dart';

enum AppleIapOutcome { success, cancelled, error }

/// Result of a single purchase-stream event, after backend verification.
class AppleIapEvent {
  const AppleIapEvent({
    required this.outcome,
    this.message,
    this.balance,
    this.subscription,
  });

  final AppleIapOutcome outcome;
  final String? message;
  final int? balance;
  final CreditSubscription? subscription;
}

class AppleIapService {
  AppleIapService(this._creditsService, this._tokenProvider);

  final CreditsService _creditsService;
  final Future<String?> Function() _tokenProvider;

  final _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  final _eventsController = StreamController<AppleIapEvent>.broadcast();

  /// Emits one event per purchase-stream update, after backend verification
  /// and StoreKit completion. Listen to this to refresh wallet UI state.
  Stream<AppleIapEvent> get events => _eventsController.stream;

  /// Must be called once, as early as possible (e.g. app/screen init), so no
  /// purchase updates are missed — including ones left over from a previous
  /// session that never finished.
  void start() {
    _subscription ??= _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (Object error) {
        _eventsController.add(AppleIapEvent(outcome: AppleIapOutcome.error, message: '$error'));
      },
    );
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _eventsController.close();
  }

  Future<bool> isAvailable() => _iap.isAvailable();

  Future<ProductDetailsResponse> queryProducts(Set<String> productIds) =>
      _iap.queryProductDetails(productIds);

  /// Credit packs are consumable — each purchase is a distinct, repeatable buy.
  Future<bool> buyPack(ProductDetails product) =>
      _iap.buyConsumable(purchaseParam: PurchaseParam(productDetails: product));

  /// Subscriptions are non-consumable from StoreKit's point of view.
  Future<bool> buySubscription(ProductDetails product) =>
      _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));

  Future<void> restorePurchases() => _iap.restorePurchases();

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          break;
        case PurchaseStatus.canceled:
          _eventsController.add(const AppleIapEvent(outcome: AppleIapOutcome.cancelled));
          break;
        case PurchaseStatus.error:
          _eventsController.add(AppleIapEvent(
            outcome: AppleIapOutcome.error,
            message: purchase.error?.message ?? 'Purchase failed.',
          ));
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verifyAndComplete(purchase);
          break;
      }
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  Future<void> _verifyAndComplete(PurchaseDetails purchase) async {
    final transactionId = purchase.purchaseID;
    if (transactionId == null) {
      _eventsController.add(const AppleIapEvent(
        outcome: AppleIapOutcome.error,
        message: 'Apple did not return a transaction id.',
      ));
      return;
    }

    try {
      final token = await _tokenProvider();
      if (token == null) throw Exception('Not authenticated.');
      final result = await _creditsService.verifyApplePurchase(
        idToken: token,
        transactionId: transactionId,
      );
      _eventsController.add(AppleIapEvent(
        outcome: AppleIapOutcome.success,
        balance: result.balance,
        subscription: result.subscription,
      ));
    } catch (e) {
      _eventsController.add(AppleIapEvent(outcome: AppleIapOutcome.error, message: '$e'));
    }
  }
}
