// Purpose: Billing screen — shows credit balance, plans, and transaction history.
import 'dart:async';

import 'package:flutter/foundation.dart';
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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabs;

  /// True from the moment we hand the user off to Paddle until we've confirmed
  /// the outcome. Drives the "verify on return" flow.
  bool _awaitingPayment = false;

  /// True while a reconciliation /sync round is in flight (shows the banner).
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctrl = context.read<CreditsController>();
      ctrl.init();
      ctrl.loadTransactions();
      // Reconcile any straggler purchases on entry — covers the case where the
      // app was reopened (cold start / deep link) after paying. Idempotent.
      _reconcile(silent: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabs.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the user comes back from the external Paddle checkout, verify the
    // payment regardless of how they returned (deep link or manual switch).
    if (state == AppLifecycleState.resumed && _awaitingPayment) {
      _reconcile(silent: false);
    }
  }

  // ── Checkout ───────────────────────────────────────────────────────────────

  /// Where Paddle returns the user after payment. On web we round-trip through
  /// the web app; on mobile we use the `buildercam://` deep link so the OS
  /// re-foregrounds the app.
  String get _returnUrl => kIsWeb
      ? '${Uri.base.origin}/billing?paid=1'
      : 'buildercam://billing?paid=1';

  Future<void> _openCheckout(
    BuildContext context,
    String type,
    String planId,
  ) async {
    final ctrl = context.read<CreditsController>();
    final url = await ctrl.getCheckoutUrl(
      type: type,
      planId: planId,
      returnUrl: _returnUrl,
    );
    if (url == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ctrl.error ?? 'Could not start checkout.')),
        );
      }
      return;
    }

    final uri = Uri.parse(url);
    final launched =
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open checkout page.')),
        );
      }
      return;
    }
    // Handed off successfully — arm the return-verification flow.
    if (mounted) setState(() => _awaitingPayment = true);
  }

  /// Reconciles the payment with the backend (which checks Paddle directly).
  /// [silent] suppresses the banner/snackbars for the on-entry straggler check.
  Future<void> _reconcile({required bool silent}) async {
    if (_verifying) return;
    final ctrl = context.read<CreditsController>();
    if (!silent && mounted) setState(() => _verifying = true);

    final changed = await ctrl.syncAfterCheckout(attempts: silent ? 1 : 6);

    if (!mounted) return;
    if (silent) {
      if (changed) setState(() => _awaitingPayment = false);
      return;
    }

    setState(() {
      _verifying = false;
      if (changed) _awaitingPayment = false;
    });

    final messenger = ScaffoldMessenger.of(context);
    if (changed) {
      messenger.showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.success,
          content: Text('Payment confirmed — your credits are updated.'),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 6),
          content: const Text(
            'Still confirming your payment. This can take a moment — tap "Refresh" if it doesn\'t update.',
          ),
          action: SnackBarAction(
            label: 'Refresh',
            textColor: Colors.white,
            onPressed: () => _reconcile(silent: false),
          ),
        ),
      );
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
        actions: [
          if (_awaitingPayment && !_verifying)
            TextButton.icon(
              onPressed: () => _reconcile(silent: false),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.bodyMuted,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Plans & Credits'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_verifying) const _VerifyingBanner(),
          _BalanceHeader(),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _PlansTab(onBuy: _openCheckout, onSubscribe: _openCheckout),
                _TransactionHistoryTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Thin progress banner shown while we confirm a payment with the backend.
class _VerifyingBanner extends StatelessWidget {
  const _VerifyingBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.blue50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: const [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Confirming your payment…',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
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
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.warningLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.bolt_rounded,
              color: AppColors.warning,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Current Balance',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.bodyMuted,
                ),
              ),
              Text(
                '${ctrl.balance} credits',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.successLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, size: 12, color: AppColors.success),
              const SizedBox(width: 4),
              Text(
                sub.planId == 'plan_starter' ? 'Starter Plan' : 'Pro Plan',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          Text(
            '${sub.creditsPerCycle} credits / month',
            style: const TextStyle(fontSize: 10, color: AppColors.success),
          ),
        ],
      ),
    );
  }
}

// ── Plans + credits tab (combined) ──────────────────────────────────────────────

class _PlansTab extends StatelessWidget {
  const _PlansTab({required this.onBuy, required this.onSubscribe});

  final Future<void> Function(BuildContext, String type, String planId) onBuy;
  final Future<void> Function(BuildContext, String type, String planId) onSubscribe;

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CreditsController>();
    final activePlanId = ctrl.subscription?.isActive == true
        ? ctrl.subscription!.planId
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.repeat_rounded,
            title: 'Monthly Plans',
            subtitle: 'Credits refresh each billing cycle. Better value than packs.',
          ),
          const SizedBox(height: 10),
          if (ctrl.loading)
            const Center(child: CircularProgressIndicator())
          else if (ctrl.subscriptionPlans.isEmpty)
            const _EmptyState(message: 'No plans available.')
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
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 10),
          _SectionHeader(
            icon: Icons.shopping_cart_outlined,
            title: 'One-time Credit Packs',
            subtitle: 'Credits never expire. Use them whenever you need.',
          ),
          const SizedBox(height: 10),
          _CostGuide(),
          const SizedBox(height: 10),
          if (!ctrl.loading && ctrl.creditPacks.isEmpty)
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
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.blue50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.bolt_rounded, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pack.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.body,
                    ),
                  ),
                  Text(
                    pack.description,
                    style: const TextStyle(fontSize: 12, color: AppColors.bodyMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$${pack.priceInDollars.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.body,
                  ),
                ),
                const SizedBox(height: 3),
                FilledButton(
                  onPressed: onTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Buy', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
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
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
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
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
              ),
              child: const Text(
                'BEST VALUE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      plan.label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.body,
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.successLight,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Active',
                          style: TextStyle(
                            fontSize: 10,
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
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: AppColors.body,
                          ),
                        ),
                        const Text(
                          '/ month',
                          style:
                              TextStyle(fontSize: 11, color: AppColors.bodyMuted),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  plan.description,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.bodyMuted,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onTap,
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          isActive ? AppColors.success : AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Text(
                      isActive ? 'Current Plan' : 'Subscribe',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
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
      padding: const EdgeInsets.all(14),
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
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
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
                  fontSize: 14,
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
            Icon(icon, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.body,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: AppColors.bodyMuted),
        ),
      ],
    );
  }
}

class _CostGuide extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.blue50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primaryLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Credit costs per action',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 6),
          ...[
            ('Audio transcript', 1),
            ('Video transcript', 2),
            ('Voice session (per 5 min)', 1),
            ('SOW generation (AI)', 3),
            ('PDF generation (AI)', 3),
            ('Save SOW document', 1),
            ('Save PDF document', 1),
          ].map(
            (e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded,
                      size: 12, color: AppColors.warning),
                  const SizedBox(width: 3),
                  Text(
                    '${e.$2} credit${e.$2 != 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.body,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '— ${e.$1}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.bodyMuted),
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
        padding: const EdgeInsets.all(28),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.bodyMuted, fontSize: 13),
        ),
      ),
    );
  }
}
