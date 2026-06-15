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
        'Open a project and tap Record. Walk through the site talking naturally — BuilderCam transcribes everything in real time.',
    items: [
      'Audio transcript — 1 credit',
      'Video transcript — 2 credits',
      'All recordings saved per project',
    ],
  ),
  _Step(
    icon: Icons.record_voice_over_rounded,
    title: 'Talk to your\nAI assistant',
    subtitle:
        'Open any project and tap Talk. Speak naturally — the AI reads your SOW documents and can answer questions or edit them on command.',
    items: [
      'Voice session — 1 credit / 5 min',
      'Understands all your project SOWs',
      'Can edit documents hands-free',
    ],
  ),
  _Step(
    icon: Icons.description_outlined,
    title: 'Generate SOW\nand PDF reports',
    subtitle:
        'One tap converts your transcript into a professional Scope of Work or PDF report, ready to share with clients.',
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
    final cardW = (size.width - 48).clamp(0.0, 560.0);
    final cardH = (size.height - 48).clamp(0.0, 740.0);

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
                  color: AppColors.blue900.withValues(alpha: 0.14),
                  blurRadius: 40,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 4,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 340),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.04),
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
                Expanded(
                  flex: 6,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
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

// ─── Hero panel ───────────────────────────────────────────────────────────────

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
    final isLast = index == total - 1;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.blue900, AppColors.primary],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      child: Stack(
        children: [
          // Decorative circle — subtle brand watermark
          Positioned(
            top: -40,
            right: -40,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: -20,
            left: -30,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: logo + skip
              Row(
                children: [
                  Image.asset(
                    'assets/logos/buildercam-icon-64-transparent.png',
                    width: 20,
                    height: 20,
                  ),
                  const SizedBox(width: 7),
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
                      child: Text(
                        'Skip',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.55),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),

              const Spacer(),

              // Icon in a translucent circle
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.15),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                child: Icon(
                  step.icon,
                  size: 26,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                step.title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.18,
                  letterSpacing: -0.5,
                ),
              ),

              const SizedBox(height: 24),

              // Progress dots
              Row(
                children: List.generate(total, (i) {
                  final active = i == index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeInOut,
                    width: active ? 20 : 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 5),
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.3),
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

// ─── Content panel ────────────────────────────────────────────────────────────

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
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Credits badge (step 0 only)
          if (step.badge != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.warningLight,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.25),
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
            const SizedBox(height: 14),
          ],

          // Subtitle
          Text(
            step.subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.bodyMuted,
              height: 1.6,
            ),
          ),

          const SizedBox(height: 18),

          // Items
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(step.items.length, (i) {
                final isLastItem = i == step.items.length - 1;
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      child: Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: AppColors.blue50,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              size: 14,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              step.items[i],
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.body,
                                fontWeight: FontWeight.w500,
                                height: 1.4,
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

          const SizedBox(height: 18),

          // Step counter + navigation
          Row(
            children: [
              // Step counter
              Text(
                '${index + 1} of $total',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.bodySubtle,
                ),
              ),
              const Spacer(),
              if (index > 0) ...[
                SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: onBack,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.body,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusSm),
                      ),
                    ),
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              SizedBox(
                height: 44,
                child: FilledButton(
                  onPressed: onNext,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isLast ? 'Go to dashboard' : 'Continue',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Icon(Icons.arrow_forward_rounded, size: 15),
                    ],
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
