// Purpose: Allows company owners to add team members and manage the team roster.
import 'package:buildercam/core/app_colors.dart';
import 'package:buildercam/core/app_spacing.dart';
import 'package:buildercam/core/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../models/app_user_model.dart';
import '../widgets/auth_text_field.dart';

class InviteMemberScreen extends StatefulWidget {
  const InviteMemberScreen({super.key});

  @override
  State<InviteMemberScreen> createState() => _InviteMemberScreenState();
}

class _InviteMemberScreenState extends State<InviteMemberScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _creating = false;
  bool _loadingMembers = true;
  String? _createError;
  String? _createSuccess;
  List<TeamMember> _members = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthController>();
      if (auth.user?.isOwner != true) {
        context.go(AppRoute.home.path);
        return;
      }
      _loadMembers();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    setState(() => _loadingMembers = true);
    try {
      final members = await context.read<AuthController>().listTeamMembers();
      if (mounted) setState(() => _members = members);
    } catch (_) {
      // Non-fatal — list stays empty.
    } finally {
      if (mounted) setState(() => _loadingMembers = false);
    }
  }

  Future<void> _createMember() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() {
        _createError = 'Please fill in all fields.';
        _createSuccess = null;
      });
      return;
    }
    if (password.length < 6) {
      setState(() {
        _createError = 'Password must be at least 6 characters.';
        _createSuccess = null;
      });
      return;
    }

    setState(() {
      _creating = true;
      _createError = null;
      _createSuccess = null;
    });

    try {
      final member = await context.read<AuthController>().createTeamMember(
        email: email,
        password: password,
        displayName: name,
      );
      _nameController.clear();
      _emailController.clear();
      _passwordController.clear();
      if (mounted) {
        setState(() {
          _createSuccess = '${member.displayName} added successfully.';
          _creating = false;
        });
        await _loadMembers();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _createError = e is StateError ? e.message : 'Failed to create member.';
          _creating = false;
        });
      }
    }
  }

  Future<void> _removeMember(TeamMember member) async {
    final authController = context.read<AuthController>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Team Member'),
        content: Text(
          'Remove ${member.displayName} (${member.email}) from your company? '
          'They will no longer be able to sign in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await authController.removeTeamMember(member.uid);
      await _loadMembers();
    } catch (e) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(e is StateError ? e.message : 'Failed to remove member.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = context.watch<AuthController>().user;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text('Team Members'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.s5),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
          // ── Add member form ────────────────────────────────────────────────
          Text('Add Team Member', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.s1),
          Text(
            'Create a sign-in account for a field technician. They will use these credentials to log in.',
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.bodyMuted),
          ),
          const SizedBox(height: AppSpacing.s4),

          if (_createError != null) ...[
            _Banner(message: _createError!, isError: true),
            const SizedBox(height: AppSpacing.s3),
          ],
          if (_createSuccess != null) ...[
            _Banner(message: _createSuccess!, isError: false),
            const SizedBox(height: AppSpacing.s3),
          ],

          AuthTextField(
            controller: _nameController,
            label: 'Full Name',
            hint: 'John Smith',
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            enabled: !_creating,
          ),
          const SizedBox(height: AppSpacing.s3),
          AuthTextField(
            controller: _emailController,
            label: 'Email',
            hint: 'john@company.com',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            enabled: !_creating,
          ),
          const SizedBox(height: AppSpacing.s3),
          AuthTextField(
            controller: _passwordController,
            label: 'Temporary Password',
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _createMember(),
            enabled: !_creating,
          ),
          const SizedBox(height: AppSpacing.s4),

          SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              onPressed: _creating ? null : _createMember,
              icon: _creating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_add_rounded),
              label: Text(_creating ? 'Creating...' : 'Add Member'),
            ),
          ),

          const SizedBox(height: AppSpacing.s6),
          const Divider(),
          const SizedBox(height: AppSpacing.s4),

          // ── Member list ────────────────────────────────────────────────────
          Text(
            'Current Team',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.s3),

          if (_loadingMembers)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.s5),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_members.isEmpty)
            Text(
              'No team members yet.',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.bodyMuted),
            )
          else
            ...(_members.map(
              (m) => _MemberTile(
                member: m,
                isCurrentUser: m.uid == currentUser?.uid,
                onRemove: (currentUser?.isOwner == true && !m.isOwner)
                    ? () => _removeMember(m)
                    : null,
              ),
            )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.isCurrentUser,
    this.onRemove,
  });

  final TeamMember member;
  final bool isCurrentUser;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initials = member.displayName.isNotEmpty
        ? member.displayName.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0]).join().toUpperCase()
        : member.email[0].toUpperCase();

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.s2),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s1,
        ),
        leading: CircleAvatar(
          backgroundColor: AppColors.blue100,
          child: Text(
            initials,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        title: Text(
          member.displayName.isNotEmpty ? member.displayName : member.email,
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          member.email,
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.bodyMuted),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s2,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: member.isOwner ? AppColors.blue100 : AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              ),
              child: Text(
                member.isOwner ? 'Owner' : 'Member',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: member.isOwner ? AppColors.primary : AppColors.bodyMuted,
                ),
              ),
            ),
            if (onRemove != null) ...[
              const SizedBox(width: AppSpacing.s1),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.person_remove_outlined, size: 18),
                color: AppColors.danger,
                tooltip: 'Remove member',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.isError});
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s3),
      decoration: BoxDecoration(
        color: isError ? AppColors.dangerLight : AppColors.successLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: (isError ? AppColors.danger : AppColors.success).withAlpha(80),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            size: 16,
            color: isError ? AppColors.danger : AppColors.success,
          ),
          const SizedBox(width: AppSpacing.s2),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isError ? AppColors.danger : AppColors.success,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
