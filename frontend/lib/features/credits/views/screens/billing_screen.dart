// Purpose: Billing screen — shows credit balance, plans, and transaction history.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:buildercam/core/app_colors.dart';
import '../../../auth/controllers/auth_controller.dart';
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
  bool _awaitingPayment = false;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctrl = context.read<CreditsController>();
      ctrl.init();
      ctrl.loadTransactions();
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
    if (state == AppLifecycleState.resumed && _awaitingPayment) {
      _reconcile(silent: false);
    }
  }

  String get _returnUrl => kIsWeb
      ? '${Uri.base.origin}/billing?paid=1'
      : 'buildercam://billing?paid=1';

  Future<void> _openCheckout(BuildContext context, String type, String planId) async {
    final ctrl = context.read<CreditsController>();
    final url = await ctrl.getCheckoutUrl(type: type, planId: planId, returnUrl: _returnUrl);
    if (url == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ctrl.error ?? 'Could not start checkout.')),
        );
      }
      return;
    }
    final launched = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!launched) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open checkout page.')),
        );
      }
      return;
    }
    if (mounted) setState(() => _awaitingPayment = true);
  }

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
      messenger.showSnackBar(const SnackBar(
        backgroundColor: AppColors.success,
        content: Text('Payment confirmed — your credits are updated.'),
      ));
    } else {
      messenger.showSnackBar(SnackBar(
        backgroundColor: AppColors.warning,
        duration: const Duration(seconds: 6),
        content: const Text(
          "Still confirming your payment. Tap Refresh if it doesn't update.",
        ),
        action: SnackBarAction(
          label: 'Refresh',
          textColor: Colors.white,
          onPressed: () => _reconcile(silent: false),
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVip = context.watch<AuthController>().user?.isVip == true;

    if (isVip) {
      return Scaffold(
        backgroundColor: AppColors.pageBackground,
        appBar: _appBar(showTabs: false),
        body: const _VipScreen(),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: _appBar(showTabs: true),
      body: Column(
        children: [
          if (_verifying) const _VerifyingBanner(),
          const _BalanceHeader(),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _PlansTab(onCheckout: _openCheckout),
                const _UsageTab(),
                const _HistoryTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  AppBar _appBar({required bool showTabs}) {
    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
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
      bottom: showTabs
          ? TabBar(
              controller: _tabs,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.bodyMuted,
              indicatorColor: AppColors.primary,
              indicatorSize: TabBarIndicatorSize.tab,
              tabs: const [
                Tab(text: 'Plans & Credits'),
                Tab(text: 'Usage'),
                Tab(text: 'History'),
              ],
            )
          : null,
    );
  }
}

// ── VIP screen ────────────────────────────────────────────────────────────────

class _VipScreen extends StatelessWidget {
  const _VipScreen();

  static const _actions = [
    ('Audio transcript', 1),
    ('Video transcript', 2),
    ('Voice session (per 5 min)', 1),
    ('SOW generation (AI)', 3),
    ('PDF generation (AI)', 3),
    ('Save SOW document', 1),
    ('Save PDF document', 1),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: [
              const SizedBox(height: 8),
              // Hero
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A3057), Color(0xFF0C1D38)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.35),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(Icons.workspace_premium_rounded,
                          color: Color(0xFFFFD700), size: 34),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'VIP Access',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'All features are unlocked.\nNo credits are ever charged.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.all_inclusive_rounded,
                              size: 16, color: Color(0xFFFFD700)),
                          SizedBox(width: 7),
                          Text(
                            'Unlimited Usage',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFFFD700),
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Reference table
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Standard credit costs',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.body,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'None of these are charged to VIP accounts.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.bodyMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    ..._actions.map((e) => _VipActionRow(label: e.$1, credits: e.$2)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VipActionRow extends StatelessWidget {
  const _VipActionRow({required this.label, required this.credits});
  final String label;
  final int credits;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: AppColors.body)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.warningLight,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bolt_rounded,
                    size: 11, color: AppColors.warning),
                const SizedBox(width: 2),
                Text(
                  '$credits cr.',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.warning,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.check_circle_rounded,
              size: 16, color: AppColors.success),
        ],
      ),
    );
  }
}

// ── Verifying banner ──────────────────────────────────────────────────────────

class _VerifyingBanner extends StatelessWidget {
  const _VerifyingBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.blue50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: const Row(
        children: [
          SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text(
            'Confirming your payment…',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Balance header ────────────────────────────────────────────────────────────

class _BalanceHeader extends StatelessWidget {
  const _BalanceHeader();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CreditsController>();
    final sub = ctrl.subscription;
    final active = sub?.isActive == true;

    return Container(
      color: AppColors.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Row(
                  children: [
                    // Balance
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Current Balance',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppColors.bodyMuted,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${ctrl.balance}',
                                style: const TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.body,
                                  height: 1,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Padding(
                                padding: EdgeInsets.only(bottom: 4),
                                child: Text(
                                  'credits',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.bodyMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Active plan badge
                    if (active)
                      _PlanBadge(
                        planName: sub!.planId == 'plan_starter' ? 'Starter' : 'Pro',
                      ),
                  ],
                ),
              ),
              // Active subscription bar
              if (active) _ActiveSubBar(sub: sub!),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanBadge extends StatelessWidget {
  const _PlanBadge({required this.planName});
  final String planName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.verified_rounded,
                  size: 13, color: AppColors.success),
              const SizedBox(width: 5),
              Text(
                '$planName Plan',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Text(
            'Active subscription',
            style: TextStyle(fontSize: 10, color: AppColors.success),
          ),
        ],
      ),
    );
  }
}

class _ActiveSubBar extends StatelessWidget {
  const _ActiveSubBar({required this.sub});
  final CreditSubscription sub;

  String get _planName => sub.planId == 'plan_starter' ? 'Starter' : 'Pro';

  String _renewal() {
    if (sub.nextBillDate == null) return '';
    try {
      final dt = DateTime.parse(sub.nextBillDate!).toLocal();
      const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return 'Renews ${m[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final renewal = _renewal();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        border: const Border(
          top: BorderSide(color: Color(0xFFBBF7D0)),
          bottom: BorderSide(color: Color(0xFFBBF7D0)),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.repeat_rounded, size: 14, color: AppColors.success),
          const SizedBox(width: 7),
          Text(
            '$_planName · ${sub.creditsPerCycle} credits refresh each month',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF15803D),
            ),
          ),
          if (renewal.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              '· $renewal',
              style: const TextStyle(fontSize: 12, color: Color(0xFF16A34A)),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Plans + credits tab ───────────────────────────────────────────────────────

class _PlansTab extends StatelessWidget {
  const _PlansTab({required this.onCheckout});
  final Future<void> Function(BuildContext, String type, String planId) onCheckout;

  @override
  Widget build(BuildContext context) {
    // iOS buys real Apple IAP products (Guideline 3.1.1); Android still
    // points to the web checkout for now.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return const _IosPlansTab();
    }

    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (isAndroid) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: const Column(
              children: [
                _WebOnlyMessage(),
                SizedBox(height: 24),
                _CostTable(),
              ],
            ),
          ),
        ),
      );
    }

    final ctrl = context.watch<CreditsController>();
    final activePlanId =
        ctrl.subscription?.isActive == true ? ctrl.subscription!.planId : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Monthly plans ──────────────────────────────────────────────
              const _SectionTitle(
                title: 'Monthly Plans',
                subtitle: 'Credits refresh every billing cycle.',
              ),
              const SizedBox(height: 12),
              if (ctrl.loading)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ))
              else if (ctrl.subscriptionPlans.isEmpty)
                const _EmptyState(message: 'No plans available.')
              else
                _PlanGrid(
                  plans: ctrl.subscriptionPlans,
                  activePlanId: activePlanId,
                  onSubscribe: (planId) =>
                      onCheckout(context, 'subscription', planId),
                ),

              const SizedBox(height: 28),
              const Divider(),
              const SizedBox(height: 24),

              // ── One-time packs ─────────────────────────────────────────────
              const _SectionTitle(
                title: 'One-time Credit Packs',
                subtitle: 'Never expire — use them whenever you need.',
              ),
              const SizedBox(height: 12),
              if (!ctrl.loading && ctrl.creditPacks.isEmpty)
                const _EmptyState(message: 'No credit packs available.')
              else
                ...ctrl.creditPacks.map(
                  (pack) => _PackCard(
                    pack: pack,
                    onTap: () => onCheckout(context, 'pack', pack.id),
                  ),
                ),

              const SizedBox(height: 16),
              const _CostTable(),
            ],
          ),
        ),
      ),
    );
  }
}

// ── iOS plans tab (Apple In-App Purchase) ──────────────────────────────────────

class _IosPlansTab extends StatefulWidget {
  const _IosPlansTab();

  @override
  State<_IosPlansTab> createState() => _IosPlansTabState();
}

class _IosPlansTabState extends State<_IosPlansTab> {
  Set<String> _lastIds = const {};
  Map<String, ProductDetails> _products = {};
  bool _loadingProducts = false;
  // False until the first query completes — distinguishes "still fetching"
  // from "fetched, but the App Store doesn't have this product" so a missing
  // product shows as unavailable instead of spinning forever.
  bool _productsLoaded = false;
  String? _productsError;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    context.read<CreditsController>().initAppleIap();
  }

  Future<void> _loadProducts(Set<String> ids) async {
    setState(() => _loadingProducts = true);
    try {
      final details = await context.read<CreditsController>().queryAppleProducts(ids);
      if (!mounted) return;
      final found = {for (final p in details) p.id: p};
      setState(() {
        _products = found;
        _productsError = found.length < ids.length
            ? 'Some plans aren\'t available from the App Store yet.'
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _productsError = 'Could not load pricing from the App Store.');
    } finally {
      if (mounted) {
        setState(() {
          _loadingProducts = false;
          _productsLoaded = true;
        });
      }
    }
  }

  Future<void> _restore() async {
    setState(() => _restoring = true);
    try {
      await context.read<CreditsController>().restoreApplePurchases();
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CreditsController>();
    final ids = <String>{
      for (final p in ctrl.creditPacks)
        if (p.appleProductId != null) p.appleProductId!,
      for (final p in ctrl.subscriptionPlans)
        if (p.appleProductId != null) p.appleProductId!,
    };

    if (ids.isNotEmpty && !setEquals(ids, _lastIds) && !_loadingProducts) {
      _lastIds = ids;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadProducts(ids));
    }

    final activePlanId =
        ctrl.subscription?.isActive == true ? ctrl.subscription!.planId : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(
                title: 'Monthly Plans',
                subtitle: 'Credits refresh every billing cycle.',
              ),
              const SizedBox(height: 12),
              if (ctrl.loading)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ))
              else if (ctrl.subscriptionPlans.isEmpty)
                const _EmptyState(message: 'No plans available.')
              else
                ...ctrl.subscriptionPlans.map((plan) {
                  final product =
                      plan.appleProductId != null ? _products[plan.appleProductId] : null;
                  final isActive = activePlanId == plan.id;
                  return _IosPlanCard(
                    plan: plan,
                    product: product,
                    isActive: isActive,
                    loading: _loadingProducts || !_productsLoaded,
                    onTap: (isActive || product == null)
                        ? null
                        : () => ctrl.buyAppleSubscription(product),
                  );
                }),

              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _restoring ? null : _restore,
                  icon: const Icon(Icons.restore_rounded, size: 16),
                  label: Text(_restoring ? 'Restoring…' : 'Restore Purchases'),
                ),
              ),

              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 20),

              const _SectionTitle(
                title: 'One-time Credit Packs',
                subtitle: 'Never expire — use them whenever you need.',
              ),
              const SizedBox(height: 12),
              if (!ctrl.loading && ctrl.creditPacks.isEmpty)
                const _EmptyState(message: 'No credit packs available.')
              else
                ...ctrl.creditPacks.map((pack) {
                  final product =
                      pack.appleProductId != null ? _products[pack.appleProductId] : null;
                  return _IosPackCard(
                    pack: pack,
                    product: product,
                    loading: _loadingProducts || !_productsLoaded,
                    onTap: product == null ? null : () => ctrl.buyApplePack(product),
                  );
                }),

              if (_productsError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _productsError!,
                  style: const TextStyle(fontSize: 12, color: AppColors.danger),
                ),
              ],
              if (ctrl.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  ctrl.error!,
                  style: const TextStyle(fontSize: 12, color: AppColors.danger),
                ),
              ],

              const SizedBox(height: 16),
              const _CostTable(),
            ],
          ),
        ),
      ),
    );
  }
}

class _IosPlanCard extends StatelessWidget {
  const _IosPlanCard({
    required this.plan,
    required this.product,
    required this.isActive,
    required this.loading,
    required this.onTap,
  });
  final SubscriptionPlan plan;
  final ProductDetails? product;
  final bool isActive;
  final bool loading;
  final VoidCallback? onTap;

  bool get _isPro => plan.id == 'plan_pro';

  @override
  Widget build(BuildContext context) {
    final borderColor =
        isActive ? AppColors.success : (_isPro ? AppColors.primary : AppColors.border);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: isActive || _isPro ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan.label,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.body),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${plan.credits} credits every month',
                    style: const TextStyle(fontSize: 12, color: AppColors.bodyMuted),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    product?.price ?? '—',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.body),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (isActive)
              const Icon(Icons.check_circle_rounded, color: AppColors.success)
            else
              FilledButton(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  backgroundColor: _isPro ? AppColors.primary : AppColors.charcoal700,
                ),
                child: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(product == null ? 'Unavailable' : 'Subscribe',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
          ],
        ),
      ),
    );
  }
}

class _IosPackCard extends StatelessWidget {
  const _IosPackCard({
    required this.pack,
    required this.product,
    required this.loading,
    required this.onTap,
  });
  final CreditPack pack;
  final ProductDetails? product;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final product = this.product;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.blue50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${pack.credits}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                      height: 1,
                    ),
                  ),
                  const Text(
                    'cr.',
                    style: TextStyle(
                        fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                pack.label,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.body),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: loading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(product == null ? 'Unavailable' : product.price,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.body,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 13, color: AppColors.bodyMuted),
        ),
      ],
    );
  }
}

// ── Plan grid (side-by-side on wide, stacked on narrow) ───────────────────────

class _PlanGrid extends StatelessWidget {
  const _PlanGrid({
    required this.plans,
    required this.activePlanId,
    required this.onSubscribe,
  });
  final List<SubscriptionPlan> plans;
  final String? activePlanId;
  final void Function(String planId) onSubscribe;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    // Side-by-side when enough room
    if (width > 520) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: plans.map((p) {
            final isActive = activePlanId == p.id;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: p == plans.last ? 0 : 10,
                ),
                child: _PlanCard(
                  plan: p,
                  isActive: isActive,
                  onTap: isActive ? null : () => onSubscribe(p.id),
                ),
              ),
            );
          }).toList(),
        ),
      );
    }
    return Column(
      children: plans.map((p) {
        final isActive = activePlanId == p.id;
        return _PlanCard(
          plan: p,
          isActive: isActive,
          onTap: isActive ? null : () => onSubscribe(p.id),
        );
      }).toList(),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.isActive, required this.onTap});
  final SubscriptionPlan plan;
  final bool isActive;
  final VoidCallback? onTap;

  bool get _isPro => plan.id == 'plan_pro';

  @override
  Widget build(BuildContext context) {
    final borderColor = isActive
        ? AppColors.success
        : _isPro
            ? AppColors.primary
            : AppColors.border;

    final double perCredit = plan.priceInDollars / plan.credits;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor,
          width: isActive || _isPro ? 2 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top badge
            if (isActive)
              _CardBadge(
                color: AppColors.success,
                icon: Icons.check_circle_rounded,
                label: 'YOUR PLAN',
              )
            else if (_isPro)
              _CardBadge(
                color: AppColors.primary,
                icon: Icons.star_rounded,
                label: 'MOST POPULAR',
              ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Plan name + price
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          plan.label,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.body,
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '\$${plan.priceInDollars.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: AppColors.body,
                              height: 1,
                            ),
                          ),
                          const Text(
                            'per month',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.bodyMuted),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Highlights
                  _PlanFeature(
                    icon: Icons.bolt_rounded,
                    color: AppColors.warning,
                    text: '${plan.credits} credits every month',
                  ),
                  const SizedBox(height: 6),
                  _PlanFeature(
                    icon: Icons.savings_outlined,
                    color: AppColors.primary,
                    text:
                        '\$${perCredit.toStringAsFixed(2)} per credit — '
                        '${_isPro ? 'best value' : 'good value'}',
                  ),
                  const SizedBox(height: 16),

                  // CTA
                  SizedBox(
                    width: double.infinity,
                    child: isActive
                        ? OutlinedButton.icon(
                            onPressed: null,
                            icon: const Icon(Icons.check_rounded,
                                size: 15, color: AppColors.success),
                            label: const Text(
                              'Current Plan',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: AppColors.success,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                  color: AppColors.success.withValues(alpha: 0.5)),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 11),
                              backgroundColor: const Color(0xFFF0FDF4),
                            ),
                          )
                        : FilledButton(
                            onPressed: onTap,
                            style: FilledButton.styleFrom(
                              backgroundColor: _isPro
                                  ? AppColors.primary
                                  : AppColors.charcoal700,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 11),
                            ),
                            child: const Text(
                              'Subscribe',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanFeature extends StatelessWidget {
  const _PlanFeature(
      {required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: AppColors.bodyMuted),
          ),
        ),
      ],
    );
  }
}

class _CardBadge extends StatelessWidget {
  const _CardBadge(
      {required this.color, required this.icon, required this.label});
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 7),
      color: color,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 12, color: Colors.white.withValues(alpha: 0.85)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Credit pack card ──────────────────────────────────────────────────────────

class _PackCard extends StatelessWidget {
  const _PackCard({required this.pack, required this.onTap});
  final CreditPack pack;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final perCredit = pack.priceInDollars / pack.credits;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Credits amount
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.blue50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${pack.credits}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                      height: 1,
                    ),
                  ),
                  const Text(
                    'cr.',
                    style: TextStyle(
                        fontSize: 10,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            // Name + value
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pack.label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.body,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '\$${perCredit.toStringAsFixed(2)} per credit',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.bodyMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Price + button
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$${pack.priceInDollars.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.body,
                  ),
                ),
                const SizedBox(height: 6),
                FilledButton(
                  onPressed: onTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Buy',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Cost reference table ──────────────────────────────────────────────────────

class _CostTable extends StatelessWidget {
  const _CostTable();

  static const _rows = [
    ('Audio transcript', 1),
    ('Video transcript', 2),
    ('Voice session (per 5 min)', 1),
    ('SOW generation (AI)', 3),
    ('PDF generation (AI)', 3),
    ('Save SOW document', 1),
    ('Save PDF document', 1),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.bolt_rounded,
                    size: 15, color: AppColors.warning),
                const SizedBox(width: 6),
                const Text(
                  'Credit costs per action',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.body,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ..._rows.map(
            (e) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(e.$1,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.bodyMuted)),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.warningLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${e.$2} cr.',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.warning,
                      ),
                    ),
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

// ── Web-only message ──────────────────────────────────────────────────────────

class _WebOnlyMessage extends StatelessWidget {
  const _WebOnlyMessage();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.blue50,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.language_rounded,
                  color: AppColors.primary, size: 30),
            ),
            const SizedBox(height: 20),
            const Text(
              'Manage your plan on the web',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Visit buildercam.ai from your browser to purchase credits or subscribe.',
              style: TextStyle(fontSize: 13, color: AppColors.bodyMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            const Text(
              'buildercam.ai',
              style: TextStyle(
                  fontSize: 13,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Usage history tab ─────────────────────────────────────────────────────────

class _UsageTab extends StatelessWidget {
  const _UsageTab();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CreditsController>();

    if (ctrl.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final spends =
        ctrl.transactions.where((t) => t.type == 'spend').toList();

    if (spends.isEmpty) {
      return const _EmptyState(
        message:
            'No usage yet.\nCredits are spent when you generate SOWs, PDFs, and transcripts.',
      );
    }

    final totalSpent = spends.fold(0, (sum, t) => sum + t.amount.abs());

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          itemCount: spends.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return _UsageSummary(
                totalSpent: totalSpent,
                count: spends.length,
              );
            }
            return _UsageRow(tx: spends[i - 1]);
          },
        ),
      ),
    );
  }
}

class _UsageSummary extends StatelessWidget {
  const _UsageSummary({required this.totalSpent, required this.count});
  final int totalSpent;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.warningLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.bolt_rounded,
                color: AppColors.warning, size: 20),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$totalSpent credits used',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.body,
                ),
              ),
              Text(
                'across $count action${count != 1 ? 's' : ''}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.bodyMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UsageRow extends StatelessWidget {
  const _UsageRow({required this.tx});
  final CreditTransaction tx;

  static const _actionInfo = <String, (String, IconData)>{
    'transcript': ('Audio Transcript', Icons.mic_rounded),
    'transcript_video': ('Video Transcript', Icons.videocam_rounded),
    'sow_generation': ('SOW Generation', Icons.auto_awesome_rounded),
    'pdf_generation': ('PDF Generation', Icons.picture_as_pdf_outlined),
    'sow_document': ('SOW Document', Icons.description_rounded),
    'pdf_document': ('PDF Document', Icons.save_rounded),
    'voice_session': ('Voice Session', Icons.record_voice_over_rounded),
  };

  String get _label {
    if (tx.actionType == null) return tx.description;
    return _actionInfo[tx.actionType]?.$1 ?? tx.actionType!;
  }

  IconData get _icon {
    if (tx.actionType == null) return Icons.bolt_rounded;
    return _actionInfo[tx.actionType]?.$2 ?? Icons.bolt_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final creditsUsed = tx.amount.abs();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Action icon
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.blue50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_icon, size: 16, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          // Action label + project
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.body,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (tx.projectName != null) ...[
                      const Icon(Icons.folder_outlined,
                          size: 11, color: AppColors.bodySubtle),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          tx.projectName!,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.bodyMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ] else if (tx.createdAt != null)
                      Text(
                        _date(tx.createdAt!),
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.bodyMuted),
                      ),
                    if (tx.projectName != null && tx.createdAt != null) ...[
                      const Text(' · ',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.bodySubtle)),
                      Text(
                        _date(tx.createdAt!),
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.bodyMuted),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Credits used badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.warningLight,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bolt_rounded,
                    size: 11, color: AppColors.warning),
                const SizedBox(width: 3),
                Text(
                  '$creditsUsed cr.',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.warning,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _date(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      const m = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${m[dt.month - 1]} ${dt.day}';
    } catch (_) {
      return iso;
    }
  }
}

// ── Transaction history tab ───────────────────────────────────────────────────

class _HistoryTab extends StatelessWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CreditsController>();

    if (ctrl.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (ctrl.transactions.isEmpty) {
      return const _EmptyState(
          message:
              'No transactions yet.\nPurchase credits or a plan to get started.');
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          itemCount: ctrl.transactions.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, indent: 46),
          itemBuilder: (_, i) => _TxRow(tx: ctrl.transactions[i]),
        ),
      ),
    );
  }
}

class _TxRow extends StatelessWidget {
  const _TxRow({required this.tx});
  final CreditTransaction tx;

  @override
  Widget build(BuildContext context) {
    final isCredit = tx.isCredit;
    final color = isCredit ? AppColors.success : AppColors.danger;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isCredit
                  ? AppColors.successLight
                  : AppColors.dangerLight,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCredit
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded,
              color: color,
              size: 15,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.description,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.body),
                ),
                if (tx.createdAt != null)
                  Text(
                    _date(tx.createdAt!),
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.bodyMuted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isCredit ? '+' : ''}${tx.amount} cr.',
                style: TextStyle(
                  fontSize: 13,
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

  String _date(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      const m = ['Jan','Feb','Mar','Apr','May','Jun',
                  'Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${m[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return iso;
    }
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppColors.bodyMuted),
        ),
      ),
    );
  }
}
