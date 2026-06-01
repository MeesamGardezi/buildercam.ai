// Purpose: Billing screen — shows credit balance, plans, and transaction history.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:buildercam/core/app_colors.dart';
import '../../controllers/credits_controller.dart';
import '../../models/credit_model.dart';

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctrl = context.read<CreditsController>();
      ctrl.init();
      ctrl.loadTransactions();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ── Checkout ───────────────────────────────────────────────────────────────

  Future<void> _openCheckout(
    BuildContext context,
    String type,
    String planId,
  ) async {
    final ctrl = context.read<CreditsController>();
    final url = await ctrl.getCheckoutUrl(type: type, planId: planId);
    if (url == null) return;

    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open checkout page.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Credits & Billing'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.bodyMuted,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Buy Credits'),
            Tab(text: 'Subscriptions'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: Column(
        children: [
          _BalanceHeader(),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _CreditPacksTab(onBuy: _openCheckout),
                _SubscriptionsTab(onSubscribe: _openCheckout),
                _TransactionHistoryTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Balance header ────────────────────────────────────────────────────────────

class _BalanceHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CreditsController>();
    return Container(
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.warningLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.bolt_rounded,
              color: AppColors.warning,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Current Balance',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.bodyMuted,
                ),
              ),
              Text(
                '${ctrl.balance} credits',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.body,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (ctrl.subscription?.isActive == true)
            _SubscriptionChip(ctrl.subscription!),
        ],
      ),
    );
  }
}

class _SubscriptionChip extends StatelessWidget {
  const _SubscriptionChip(this.sub);

  final CreditSubscription sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.successLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, size: 14, color: AppColors.success),
              const SizedBox(width: 4),
              Text(
                sub.planId == 'plan_starter' ? 'Starter Plan' : 'Pro Plan',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          Text(
            '${sub.creditsPerCycle} credits / month',
            style: const TextStyle(fontSize: 11, color: AppColors.success),
          ),
        ],
      ),
    );
  }
}

// ── Credit packs tab ──────────────────────────────────────────────────────────

class _CreditPacksTab extends StatelessWidget {
  const _CreditPacksTab({required this.onBuy});

  final Future<void> Function(BuildContext, String type, String planId) onBuy;

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CreditsController>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.shopping_cart_outlined,
            title: 'One-time Credit Packs',
            subtitle: 'Credits never expire. Use them whenever you need.',
          ),
          const SizedBox(height: 16),
          _CostGuide(),
          const SizedBox(height: 20),
          if (ctrl.loading)
            const Center(child: CircularProgressIndicator())
          else if (ctrl.creditPacks.isEmpty)
            const _EmptyState(message: 'No credit packs available.')
          else
            ...ctrl.creditPacks.map(
              (pack) => _PackCard(
                pack: pack,
                onTap: () => onBuy(context, 'pack', pack.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _PackCard extends StatelessWidget {
  const _PackCard({required this.pack, required this.onTap});

  final CreditPack pack;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.blue50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.bolt_rounded, color: AppColors.primary, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pack.label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.body,
                    ),
                  ),
                  Text(
                    pack.description,
                    style: const TextStyle(fontSize: 13, color: AppColors.bodyMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$${pack.priceInDollars.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.body,
                  ),
                ),
                const SizedBox(height: 4),
                FilledButton(
                  onPressed: onTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Buy', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Subscriptions tab ─────────────────────────────────────────────────────────

class _SubscriptionsTab extends StatelessWidget {
  const _SubscriptionsTab({required this.onSubscribe});

  final Future<void> Function(BuildContext, String type, String planId)
      onSubscribe;

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CreditsController>();
    final activePlanId = ctrl.subscription?.isActive == true
        ? ctrl.subscription!.planId
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.repeat_rounded,
            title: 'Monthly Subscriptions',
            subtitle:
                'Save more per credit than buying packs directly. Credits refresh each billing cycle.',
          ),
          const SizedBox(height: 16),
          _CostGuide(),
          const SizedBox(height: 20),
          if (ctrl.loading)
            const Center(child: CircularProgressIndicator())
          else if (ctrl.subscriptionPlans.isEmpty)
            const _EmptyState(message: 'No subscription plans available.')
          else
            ...ctrl.subscriptionPlans.map(
              (plan) => _PlanCard(
                plan: plan,
                isActive: activePlanId == plan.id,
                onTap: activePlanId == plan.id
                    ? null
                    : () => onSubscribe(context, 'subscription', plan.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.isActive,
    required this.onTap,
  });

  final SubscriptionPlan plan;
  final bool isActive;
  final VoidCallback? onTap;

  bool get isPro => plan.id == 'plan_pro';

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isActive
              ? AppColors.success
              : isPro
                  ? AppColors.primary
                  : AppColors.border,
          width: isActive || isPro ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPro)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: const Text(
                'BEST VALUE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      plan.label,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.body,
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.successLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Active',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.success,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '\$${plan.priceInDollars.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: AppColors.body,
                          ),
                        ),
                        const Text(
                          '/ month',
                          style:
                              TextStyle(fontSize: 12, color: AppColors.bodyMuted),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  plan.description,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.bodyMuted,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onTap,
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          isActive ? AppColors.success : AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      isActive ? 'Current Plan' : 'Subscribe',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Transaction history tab ───────────────────────────────────────────────────

class _TransactionHistoryTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CreditsController>();

    if (ctrl.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (ctrl.transactions.isEmpty) {
      return const _EmptyState(
        message: 'No transactions yet.\nPurchase credits or a subscription to get started.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: ctrl.transactions.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => _TransactionRow(tx: ctrl.transactions[i]),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.tx});

  final CreditTransaction tx;

  @override
  Widget build(BuildContext context) {
    final isCredit = tx.isCredit;
    final color = isCredit ? AppColors.success : AppColors.danger;
    final icon = isCredit ? Icons.add_circle_outline : Icons.remove_circle_outline;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.description,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.body,
                  ),
                ),
                if (tx.createdAt != null)
                  Text(
                    _formatDate(tx.createdAt!),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.bodyMuted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isCredit ? '+' : ''}${tx.amount}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              Text(
                '${tx.balanceAfter} bal.',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.bodyMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return iso;
    }
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.body,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style:
              const TextStyle(fontSize: 13, color: AppColors.bodyMuted),
        ),
      ],
    );
  }
}

class _CostGuide extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.blue50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primaryLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Credit costs per action',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          ...[
            ('Audio transcript', 1),
            ('Video transcript', 2),
            ('Save SOW document', 1),
            ('Save PDF document', 1),
            ('SOW generation (AI)', 3),
            ('PDF export (render)', 3),
          ].map(
            (e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded,
                      size: 14, color: AppColors.warning),
                  const SizedBox(width: 4),
                  Text(
                    '${e.$2} credit${e.$2 != 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.body,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '— ${e.$1}',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.bodyMuted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.bodyMuted, fontSize: 14),
        ),
      ),
    );
  }
}
