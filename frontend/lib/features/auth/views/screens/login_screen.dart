// Purpose: Email/password sign-in screen.
import 'package:buildercam/core/app_colors.dart';
import 'package:buildercam/core/app_spacing.dart';
import 'package:buildercam/core/app_theme.dart';
import 'package:buildercam/core/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../widgets/auth_text_field.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await context.read<AuthController>().signIn(email, password);
      TextInput.finishAutofillContext(shouldSave: true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = context.read<AuthController>().errorMessage;
          _loading = false;
        });
      }
    }
  }

  Future<void> _forgotPassword() async {
    final ctrl = TextEditingController(text: _emailController.text.trim());
    await showDialog<void>(
      context: context,
      builder: (ctx) => _ForgotPasswordDialog(
        emailController: ctrl,
        auth: context.read<AuthController>(),
      ),
    );
    ctrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWide = MediaQuery.sizeOf(context).width >= 600;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.s5,
              AppSpacing.s6,
              AppSpacing.s5,
              AppSpacing.s6 + bottomInset,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo
                Image.asset(
                  'assets/logos/buildercam-icon-128-transparent.png',
                  width: 56,
                  height: 56,
                ),
                const SizedBox(height: AppSpacing.s4),
                Text('Sign in', style: theme.textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.s1),
                Text(
                  'Access your company\'s scope-of-work workspace.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.bodyMuted,
                  ),
                ),
                const SizedBox(height: AppSpacing.s6),

                // Error banner
                if (_error != null) ...[
                  _ErrorBanner(message: _error!),
                  const SizedBox(height: AppSpacing.s4),
                ],

                // Fields
                AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      AuthTextField(
                        controller: _emailController,
                        label: 'Email',
                        hint: 'you@company.com',
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        autofocus: isWide,
                      ),
                      const SizedBox(height: AppSpacing.s3),
                      AuthTextField(
                        controller: _passwordController,
                        label: 'Password',
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _signIn(),
                        autofillHints: const [AutofillHints.password],
                      ),
                      TextButton(
                        onPressed: _loading ? null : _forgotPassword,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.s2,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Forgot password?',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.s3),

                // Sign-in button
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _signIn,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Sign In'),
                  ),
                ),
                const SizedBox(height: AppSpacing.s4),

                // Guest access
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _loading
                        ? null
                        : () async {
                            setState(() {
                              _loading = true;
                              _error = null;
                            });
                            try {
                              await context
                                  .read<AuthController>()
                                  .continueAsGuest();
                            } catch (_) {
                              if (mounted) {
                                setState(() {
                                  _error = context
                                      .read<AuthController>()
                                      .errorMessage;
                                  _loading = false;
                                });
                              }
                            }
                          },
                    icon: const Icon(Icons.person_outline_rounded, size: 18),
                    label: const Text('Continue as Guest'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.bodyMuted,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s5),

                // Register link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'New to BuilderCam? ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.bodyMuted,
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          context.pushNamed(AppRoute.register.name),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Create a company account',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  }
}

// ── Error banner ──────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s3),
      decoration: BoxDecoration(
        color: AppColors.dangerLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.danger.withAlpha(80)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 16, color: AppColors.danger),
          const SizedBox(width: AppSpacing.s2),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.danger,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Forgot password dialog ────────────────────────────────────────────────────

class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog({
    required this.emailController,
    required this.auth,
  });

  final TextEditingController emailController;
  final AuthController auth;

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  bool _loading = false;
  bool _sent = false;
  String? _error;

  Future<void> _send() async {
    final email = widget.emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Please enter your email address.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.auth.sendPasswordResetEmail(email);
      if (mounted) setState(() { _loading = false; _sent = true; });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = widget.auth.errorMessage ?? 'Failed to send reset email.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Reset Password'),
      content: _sent
          ? Text(
              'A reset link has been sent to ${widget.emailController.text.trim()}. Check your inbox.',
              style: theme.textTheme.bodyMedium,
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Enter your email and we'll send you a password reset link.",
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.bodyMuted),
                ),
                const SizedBox(height: AppSpacing.s4),
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.danger),
                  ),
                  const SizedBox(height: AppSpacing.s3),
                ],
                TextField(
                  controller: widget.emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _send(),
                  autofocus: widget.emailController.text.isEmpty,
                  decoration: AppInputs.standard(
                    labelText: 'Email',
                    hintText: 'you@company.com',
                  ),
                ),
              ],
            ),
      actions: _sent
          ? [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ]
          : [
              TextButton(
                onPressed: _loading ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: _loading ? null : _send,
                child: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send Link'),
              ),
            ],
    );
  }
}


