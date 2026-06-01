// Purpose: Recovery screen for users who are authenticated but have not set up a company.
import 'package:buildercam/core/app_colors.dart';
import 'package:buildercam/core/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../widgets/auth_text_field.dart';

class SetupCompanyScreen extends StatefulWidget {
  const SetupCompanyScreen({super.key});

  @override
  State<SetupCompanyScreen> createState() => _SetupCompanyScreenState();
}

class _SetupCompanyScreenState extends State<SetupCompanyScreen> {
  final _companyController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _companyController.dispose();
    super.dispose();
  }

  Future<void> _setup() async {
    final name = _companyController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a company name.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await context.read<AuthController>().setupCompany(name);
      // AuthGate detects 'authenticated' and navigates automatically.
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is StateError ? e.message : 'Setup failed. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.s6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.blue100,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  ),
                  child: const Icon(
                    Icons.business_rounded,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(height: AppSpacing.s4),
                Text('Name your company', style: theme.textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.s1),
                Text(
                  'One last step — give your company a name to complete setup.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.bodyMuted),
                ),
                const SizedBox(height: AppSpacing.s6),

                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.s3),
                    decoration: BoxDecoration(
                      color: AppColors.dangerLight,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(color: AppColors.danger.withAlpha(80)),
                    ),
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.danger),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                ],

                AuthTextField(
                  controller: _companyController,
                  label: 'Company Name',
                  hint: 'Acme Contractors',
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _setup(),
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: AppSpacing.s5),

                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _setup,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Finish Setup'),
                  ),
                ),
                const SizedBox(height: AppSpacing.s4),
                TextButton(
                  onPressed: () => context.read<AuthController>().signOut(),
                  child: Text(
                    'Sign out',
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.bodyMuted),
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
