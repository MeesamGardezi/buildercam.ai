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

  Future<void> _signInWithGoogle() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final outcome =
          await context.read<AuthController>().signInWithGoogle();
      if (!mounted) return;
      switch (outcome) {
        case GoogleSignInOutcome.cancelled:
          setState(() => _loading = false);
        case GoogleSignInOutcome.success:
          break; // AuthGate handles navigation automatically
        case GoogleSignInOutcome.newUser:
          setState(() => _loading = false);
          await _showSetPasswordSheet();
        case GoogleSignInOutcome.needsLinking:
          setState(() => _loading = false);
          await _showLinkAccountSheet();
      }
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

  Future<void> _showSetPasswordSheet() async {
    final auth = context.read<AuthController>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(),
      builder: (_) => _SetPasswordSheet(auth: auth),
    );
  }

  Future<void> _showLinkAccountSheet() async {
    final auth = context.read<AuthController>();
    final email = auth.pendingGoogleEmail ?? '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(),
      builder: (_) => _LinkAccountSheet(email: email, auth: auth),
    );
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

                // OR divider
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s3,
                      ),
                      child: Text(
                        'or',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.bodySubtle,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: AppSpacing.s4),

                // Google sign-in
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : _signInWithGoogle,
                    icon: const _GoogleIcon(),
                    label: const Text('Continue with Google'),
                  ),
                ),
                const SizedBox(height: AppSpacing.s3),

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

// ── Google icon ───────────────────────────────────────────────────────────────

class _GoogleIcon extends StatelessWidget {
  const _GoogleIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: const BoxDecoration(
        color: Color(0xFF4285F4),
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Text(
          'G',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            height: 1.0,
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

// ── Sheet error text ──────────────────────────────────────────────────────────

class _SheetErrorText extends StatelessWidget {
  const _SheetErrorText({required this.message});
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
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.danger,
            ),
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

// ── Link account sheet (email exists with password) ───────────────────────────

class _LinkAccountSheet extends StatefulWidget {
  const _LinkAccountSheet({required this.email, required this.auth});

  final String email;
  final AuthController auth;

  @override
  State<_LinkAccountSheet> createState() => _LinkAccountSheetState();
}

class _LinkAccountSheetState extends State<_LinkAccountSheet> {
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _error = 'Please enter your password.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.auth.linkWithPassword(password);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = widget.auth.errorMessage ?? 'Failed to link account.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.s5,
        AppSpacing.s5,
        AppSpacing.s5,
        AppSpacing.s5 + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius:
                    BorderRadius.circular(AppSpacing.radiusFull),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s5),
          Text('Link your Google account',
              style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.s2),
          Text(
            'An account with ${widget.email} already exists. Enter your password to connect Google Sign-In.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: AppColors.bodyMuted),
          ),
          const SizedBox(height: AppSpacing.s5),
          if (_error != null) ...[
            _SheetErrorText(message: _error!),
            const SizedBox(height: AppSpacing.s4),
          ],
          AuthTextField(
            controller: _passwordController,
            label: 'Password',
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _link(),
            autofocus: true,
          ),
          const SizedBox(height: AppSpacing.s5),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _loading ? null : _link,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Link Account'),
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          TextButton(
            onPressed: _loading ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

// ── Set password sheet (new Google user) ──────────────────────────────────────

class _SetPasswordSheet extends StatefulWidget {
  const _SetPasswordSheet({required this.auth});

  final AuthController auth;

  @override
  State<_SetPasswordSheet> createState() => _SetPasswordSheetState();
}

class _SetPasswordSheetState extends State<_SetPasswordSheet> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _setPassword() async {
    final password = _passwordController.text;
    final confirm = _confirmController.text;
    if (password.isEmpty || confirm.isEmpty) {
      setState(() => _error = 'Please fill in both fields.');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.auth.addPasswordToAccount(password);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = widget.auth.errorMessage ?? 'Failed to set password.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.s5,
        AppSpacing.s5,
        AppSpacing.s5,
        AppSpacing.s5 + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius:
                    BorderRadius.circular(AppSpacing.radiusFull),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s5),
          Text('Add a password (optional)',
              style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.s2),
          Text(
            'You can also sign in with email and password. Skip this to use Google only.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: AppColors.bodyMuted),
          ),
          const SizedBox(height: AppSpacing.s5),
          if (_error != null) ...[
            _SheetErrorText(message: _error!),
            const SizedBox(height: AppSpacing.s4),
          ],
          AuthTextField(
            controller: _passwordController,
            label: 'New Password',
            obscureText: true,
            textInputAction: TextInputAction.next,
            autofocus: true,
          ),
          const SizedBox(height: AppSpacing.s3),
          AuthTextField(
            controller: _confirmController,
            label: 'Confirm Password',
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _setPassword(),
          ),
          const SizedBox(height: AppSpacing.s5),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _loading ? null : _setPassword,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Set Password'),
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          SizedBox(
            height: 48,
            child: TextButton(
              onPressed: _loading ? null : () => Navigator.pop(context),
              child: const Text('Skip — use Google only'),
            ),
          ),
        ],
      ),
    );
  }
}

