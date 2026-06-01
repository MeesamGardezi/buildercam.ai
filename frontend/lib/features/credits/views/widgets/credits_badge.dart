// Purpose: Small widget that displays the user's current credit balance.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:buildercam/core/app_colors.dart';
import 'package:buildercam/core/router/app_router.dart';
import '../../controllers/credits_controller.dart';

class CreditsBadge extends StatelessWidget {
  const CreditsBadge({super.key, this.compact = false});

  /// When true, shows only the coin icon + number (no label).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final balance = context.watch<CreditsController>().balance;

    return GestureDetector(
      onTap: () => context.pushNamed(AppRoute.billing.name),
      child: Tooltip(
        message: 'Credits — tap to buy more',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.warningLight,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bolt_rounded, size: 16, color: AppColors.warning),
              const SizedBox(width: 4),
              Text(
                '$balance',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.warning,
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 4),
                const Text(
                  'credits',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.warning,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
