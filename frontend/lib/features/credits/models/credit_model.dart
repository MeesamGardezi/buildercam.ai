// Purpose: Data models for the credits & billing feature.

/// A user's current credit wallet state.
class CreditWallet {
  const CreditWallet({required this.balance});

  factory CreditWallet.fromJson(Map<String, dynamic> json) {
    return CreditWallet(balance: (json['balance'] as num?)?.toInt() ?? 0);
  }

  final int balance;
}

/// A single credit transaction record.
class CreditTransaction {
  const CreditTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    required this.description,
    required this.createdAt,
    this.actionType,
  });

  factory CreditTransaction.fromJson(Map<String, dynamic> json) {
    return CreditTransaction(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      balanceAfter: (json['balanceAfter'] as num?)?.toInt() ?? 0,
      description: json['description'] as String? ?? '',
      createdAt: json['createdAt'] as String?,
      actionType: json['actionType'] as String?,
    );
  }

  final String id;

  /// 'purchase', 'subscription', or 'spend'
  final String type;

  /// Positive = credits added, negative = credits spent.
  final int amount;
  final int balanceAfter;
  final String description;
  final String? createdAt;
  final String? actionType;

  bool get isCredit => amount > 0;
}

/// An active Paddle subscription.
class CreditSubscription {
  const CreditSubscription({
    required this.planId,
    required this.status,
    required this.creditsPerCycle,
    this.nextBillDate,
    this.paddleSubscriptionId,
  });

  factory CreditSubscription.fromJson(Map<String, dynamic> json) {
    return CreditSubscription(
      planId: json['planId'] as String? ?? '',
      status: json['status'] as String? ?? '',
      creditsPerCycle: (json['creditsPerCycle'] as num?)?.toInt() ?? 0,
      nextBillDate: json['nextBillDate'] as String?,
      paddleSubscriptionId: json['paddleSubscriptionId'] as String?,
    );
  }

  final String planId;
  final String status;
  final int creditsPerCycle;
  final String? nextBillDate;
  final String? paddleSubscriptionId;

  bool get isActive => status == 'active';
}

/// A purchasable credit pack (one-time payment).
class CreditPack {
  const CreditPack({
    required this.id,
    required this.credits,
    required this.priceUsd,
    required this.label,
    required this.description,
  });

  factory CreditPack.fromJson(Map<String, dynamic> json) {
    return CreditPack(
      id: json['id'] as String,
      credits: (json['credits'] as num).toInt(),
      priceUsd: (json['priceUsd'] as num).toInt(),
      label: json['label'] as String,
      description: json['description'] as String,
    );
  }

  final String id;
  final int credits;

  /// Price in cents (e.g. 4499 = $44.99).
  final int priceUsd;
  final String label;
  final String description;

  double get priceInDollars => priceUsd / 100.0;
}

/// A monthly subscription plan.
class SubscriptionPlan {
  const SubscriptionPlan({
    required this.id,
    required this.credits,
    required this.priceUsd,
    required this.label,
    required this.description,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      id: json['id'] as String,
      credits: (json['credits'] as num).toInt(),
      priceUsd: (json['priceUsd'] as num).toInt(),
      label: json['label'] as String,
      description: json['description'] as String,
    );
  }

  final String id;
  final int credits;
  final int priceUsd;
  final String label;
  final String description;

  double get priceInDollars => priceUsd / 100.0;
}
