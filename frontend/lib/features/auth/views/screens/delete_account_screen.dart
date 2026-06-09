// Purpose: Lets a user permanently delete their account.
// Owners also have their company and all team members deleted.
// Requires typing "DELETE" as a confirmation before proceeding.
import 'package:buildercam/core/app_colors.dart';
import 'package:buildercam/core/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _confirmController = TextEditingController();
  bool _deleting = false;
  String? _error;

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  bool get _confirmed =>
      _confirmController.text.trim().toUpperCase() == 'DELETE';

  Future<void> _deleteAccount() async {
    if (!_confirmed) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await context.read<AuthController>().deleteAccount();
      // Auth controller signs out after deletion — router handles redirect.
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _deleting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthController>();
    final isOwner = auth.user?.isOwner == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Delete Account'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.s6),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Warning banner ───────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(AppSpacing.s4),
                  decoration: BoxDecoration(
                    color: AppColors.dangerLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: AppColors.danger, size: 22),
                      const SizedBox(width: AppSpacing.s3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'This action is permanent and cannot be undone.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppColors.danger,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.s2),
                            Text(
                              isOwner
                                  ? 'Deleting your account will permanently remove your company, '
                                      'all team members, all projects, and all associated data.'
                                  : 'Deleting your account will permanently remove your profile '
                                      'and access to this workspace.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.danger,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.s8),

                // ── What will be deleted ─────────────────────────────────────
                Text(
                  'What will be deleted:',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppColors.body,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.s3),
                ..._buildDeleteList(isOwner, theme),

                const SizedBox(height: AppSpacing.s8),

                // ── Confirmation input ───────────────────────────────────────
                Text(
                  'To confirm, type DELETE in the field below:',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.body,
                  ),
                ),
                const SizedBox(height: AppSpacing.s3),
                ListenableBuilder(
                  listenable: _confirmController,
                  builder: (context, _) {
                    return TextField(
                      controller: _confirmController,
                      enabled: !_deleting,
                      autofocus: false,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'DELETE',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: _confirmed
                                ? AppColors.danger
                                : AppColors.border,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                              color: AppColors.danger, width: 1.5),
                        ),
                      ),
                    );
                  },
                ),

                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.s3),
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.danger),
                  ),
                ],

                const SizedBox(height: AppSpacing.s6),

                // ── Delete button ────────────────────────────────────────────
                ListenableBuilder(
                  listenable: _confirmController,
                  builder: (context, _) {
                    return FilledButton(
                      onPressed:
                          (_confirmed && !_deleting) ? _deleteAccount : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        disabledBackgroundColor:
                            AppColors.danger.withValues(alpha: 0.4),
                        padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.s4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _deleting
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Permanently Delete Account',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600),
                            ),
                    );
                  },
                ),

                const SizedBox(height: AppSpacing.s3),

                TextButton(
                  onPressed: _deleting ? null : () => context.pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDeleteList(bool isOwner, ThemeData theme) {
    final items = [
      'Your account and profile',
      if (isOwner) 'Your company and all its settings',
      if (isOwner) 'All team members',
      'All projects and recordings',
      'All generated SOW documents and PDFs',
    ];
    return items
        .map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s2),
            child: Row(
              children: [
                const Icon(Icons.remove_circle_outline_rounded,
                    size: 16, color: AppColors.danger),
                const SizedBox(width: AppSpacing.s3),
                Text(item,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.bodyMuted)),
              ],
            ),
          ),
        )
        .toList();
  }
}
