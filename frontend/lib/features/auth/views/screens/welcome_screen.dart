// Purpose: Welcome screen — shown once to new accounts after company setup.
import 'package:buildercam/core/app_colors.dart';
import 'package:buildercam/core/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/router/app_router.dart';
import '../../controllers/auth_controller.dart';

// ─── Data ─────────────────────────────────────────────────────────────────────

class _Step {
  const _Step({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.items,
    this.badge,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> items;
  final String? badge;
}

const _steps = [
  _Step(
    icon: Icons.bolt_rounded,
    title: 'Welcome to\nBuilderCam',
    subtitle:
        "Your account is live. We've added 25 free credits so you can explore every feature right now — no payment needed.",
    badge: '25 free credits added to your account',
    items: [
      'No credit card required to get started',
      'Works on phone, tablet and desktop',
      'Your data is always synced and secure',
    ],
  ),
  _Step(
    icon: Icons.mic_none_rounded,
    title: 'Record any\njob-site walkthrough',
    subtitle:
        'Open a project and hit Record. Walk through the site talking naturally — BuilderCam transcribes everything for you.',
    items: [
      'Audio transcript — 1 credit',
      'Video transcript — 2 credits',
      'All recordings saved per project',
    ],
  ),
  _Step(
    icon: Icons.description_outlined,
    title: 'Generate SOW\nand PDF reports',
    subtitle:
        'One tap converts your transcript into a professional Scope of Work or PDF report, ready to send to clients.',
    items: [
      'Scope of Work (AI) — 3 credits',
      'PDF report (AI) — 3 credits',
      'Save any document — 1 credit',
    ],
  ),
  _Step(
    icon: Icons.group_outlined,
    title: 'Invite your team,\nscale your plan',
    subtitle:
        'Add team members from Settings. Upgrade to a monthly plan whenever you are ready for more.',
    items: [
      'Starter — \$49 / month · 300 credits',
      'Pro — \$99 / month · 700 credits',
      'One-time credit packs, no commitment',
    ],
  ),
];

// ─── Screen ───────────────────────────────────────────────────────────────────

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  int _index = 0;

  void _next() {
    if (_index < _steps.length - 1) {
      setState(() => _index++);
    } else {
      _finish();
    }
  }

  void _back() {
    if (_index > 0) setState(() => _index--);
  }

  Future<void> _finish() async {
    await context.read<AuthController>().markWelcomeSeen();
    if (mounted) context.go(AppRoute.home.path);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Give the card a comfortable width — fills small screens, centered on large ones.
    final cardW = (size.width - 48).clamp(0.0, 600.0);
    // Card always fills most of the viewport height.
    final cardH = (size.height - 48).clamp(0.0, 700.0);

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: Center(
          child: Container(
            width: cardW,
            height: cardH,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radius2xl),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: AppColors.charcoal900.withValues(alpha: 0.12),
                  blurRadius: 48,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Dark hero — fixed height ──────────────────────────────
                Expanded(
                  flex: 4,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 360),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.03),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: _HeroPanel(
                      key: ValueKey(_index),
                      step: _steps[_index],
                      index: _index,
                      total: _steps.length,
                      onSkip: _finish,
                    ),
                  ),
                ),

                // ── White content ─────────────────────────────────────────
                Expanded(
                  flex: 6,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeOut,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: child,
                    ),
                    child: _ContentPanel(
                      key: ValueKey('c$_index'),
                      step: _steps[_index],
                      index: _index,
                      total: _steps.length,
                      onNext: _next,
                      onBack: _back,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Dark hero ────────────────────────────────────────────────────────────────

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    super.key,
    required this.step,
    required this.index,
    required this.total,
    required this.onSkip,
  });

  final _Step step;
  final int index;
  final int total;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final numStr = (index + 1).toString().padLeft(2, '0');
    final isLast = index == total - 1;

    return Container(
      color: AppColors.charcoal900,
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
      child: Stack(
        children: [
          // ── Ghost step number ───────────────────────────────────────────
          Positioned(
            top: -14,
            right: -8,
            child: Text(
              numStr,
              style: const TextStyle(
                fontSize: 110,
                fontWeight: FontWeight.w900,
                color: AppColors.charcoal700,
                height: 1,
              ),
            ),
          ),

          // ── Foreground content ──────────────────────────────────────────
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo row + skip
              Row(
                children: [
                  Image.asset(
                    'assets/logos/buildercam-icon-64-transparent.png',
                    width: 22,
                    height: 22,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'BuilderCam',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.1,
                    ),
                  ),
                  const Spacer(),
                  if (!isLast)
                    GestureDetector(
                      onTap: onSkip,
                      child: const Text(
                        'Skip',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.charcoal400,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),

              const Spacer(),

              // Feature icon
              Icon(
                step.icon,
                size: 32,
                color: AppColors.blue600,
              ),
              const SizedBox(height: 14),

              // Title
              Text(
                step.title,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.17,
                  letterSpacing: -0.4,
                ),
              ),

              const SizedBox(height: 28),

              // Step dots
              Row(
                children: List.generate(total, (i) {
                  final active = i == index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeInOut,
                    width: active ? 22 : 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 5),
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.blue600
                          : AppColors.charcoal600,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── White content panel ─────────────────────────────────────────────────────

class _ContentPanel extends StatelessWidget {
  const _ContentPanel({
    super.key,
    required this.step,
    required this.index,
    required this.total,
    required this.onNext,
    required this.onBack,
  });

  final _Step step;
  final int index;
  final int total;
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLast = index == total - 1;

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Credits badge (step 0 only)
          if (step.badge != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.warningLight,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.28),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bolt_rounded,
                      size: 13, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Text(
                    step.badge!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Subtitle
          Text(
            step.subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.bodyMuted,
              height: 1.6,
            ),
          ),

          const SizedBox(height: 20),

          // Items
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: List.generate(step.items.length, (i) {
                final isLastItem = i == step.items.length - 1;
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              step.items[i],
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.body,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isLastItem)
                      const Divider(height: 1, color: AppColors.border),
                  ],
                );
              }),
            ),
          ),

          const SizedBox(height: 20),

          // Navigation buttons
          Row(
            children: [
              if (index > 0) ...[
                SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: onBack,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.body,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusSm),
                      ),
                    ),
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: FilledButton(
                    onPressed: onNext,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusSm),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          isLast ? 'Go to dashboard' : 'Continue',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.arrow_forward_rounded, size: 15),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
