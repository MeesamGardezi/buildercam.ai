// Purpose: Lets the company owner manage per-project permissions for every team member.
import 'package:buildercam/core/app_colors.dart';
import 'package:buildercam/core/app_spacing.dart';
import 'package:buildercam/core/router/app_router.dart';
import 'package:buildercam/features/sow_transcription/models/sow_transcript_model.dart';
import 'package:buildercam/features/sow_transcription/services/sow_firestore_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../models/app_user_model.dart';
import '../../models/member_permission_model.dart';

/// Entry point — owner-only screen for managing team member permissions.
class TeamSettingsScreen extends StatefulWidget {
  const TeamSettingsScreen({super.key});

  @override
  State<TeamSettingsScreen> createState() => _TeamSettingsScreenState();
}

class _TeamSettingsScreenState extends State<TeamSettingsScreen> {
  bool _loading = true;
  String? _error;
  List<TeamMember> _members = const [];
  List<SowProjectModel> _projects = const [];

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
      _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthController>();
      final tokenProvider = auth.getIdToken;
      final backendService = SowBackendService(tokenProvider: tokenProvider);

      final results = await Future.wait([
        auth.listTeamMembers(),
        backendService.fetchProjects(),
      ]);

      if (!mounted) return;
      setState(() {
        _members =
            (results[0] as List<TeamMember>)
                .where((m) => !m.isOwner)
                .toList();
        _projects = results[1] as List<SowProjectModel>;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text('Team Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: AppColors.danger,
                size: 40,
              ),
              const SizedBox(height: AppSpacing.s3),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.danger),
              ),
              const SizedBox(height: AppSpacing.s4),
              ElevatedButton(
                onPressed: _load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_members.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.group_outlined,
                size: 48,
                color: AppColors.bodySubtle,
              ),
              const SizedBox(height: AppSpacing.s3),
              Text(
                'No team members yet.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.bodyMuted),
              ),
              const SizedBox(height: AppSpacing.s1),
              Text(
                'Add team members from the Invite Team menu.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.bodySubtle),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    if (_projects.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s5),
          child: Text(
            'No projects yet. Create a project first, then manage permissions here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: AppColors.bodyMuted),
          ),
        ),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.s4),
          itemCount: _members.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.s4),
          itemBuilder: (_, i) => _MemberPermissionsCard(
            member: _members[i],
            projects: _projects,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-member card: expandable list of projects with permission toggles
// ─────────────────────────────────────────────────────────────────────────────

class _MemberPermissionsCard extends StatefulWidget {
  const _MemberPermissionsCard({
    required this.member,
    required this.projects,
  });

  final TeamMember member;
  final List<SowProjectModel> projects;

  @override
  State<_MemberPermissionsCard> createState() => _MemberPermissionsCardState();
}

class _MemberPermissionsCardState extends State<_MemberPermissionsCard> {
  bool _expanded = false;
  bool _loadingPermissions = false;

  /// projectId → MemberPermission (mutable local state for optimistic updates)
  Map<String, MemberPermission> _permissions = {};

  Future<void> _ensureLoaded() async {
    if (_permissions.isNotEmpty) return;
    setState(() => _loadingPermissions = true);
    try {
      final auth = context.read<AuthController>();
      final list = await auth.getMemberPermissions(widget.member.uid);
      final byProject = <String, MemberPermission>{
        for (final p in list) p.projectId: p,
      };
      // Fill defaults for projects that have no stored record yet.
      for (final project in widget.projects) {
        byProject.putIfAbsent(
          project.id,
          () => MemberPermission.defaultFor(
            uid: widget.member.uid,
            projectId: project.id,
            companyId: widget.member.companyId,
          ),
        );
      }
      if (mounted) setState(() => _permissions = byProject);
    } catch (_) {
      // silently ignore — will retry on next expand
    } finally {
      if (mounted) setState(() => _loadingPermissions = false);
    }
  }

  Future<void> _toggle(
    String projectId,
    MemberPermission current,
    MemberPermission updated,
  ) async {
    // Optimistic update
    setState(() => _permissions[projectId] = updated);
    try {
      final auth = context.read<AuthController>();
      final saved = await auth.setMemberProjectPermissions(
        memberUid: widget.member.uid,
        projectId: projectId,
        permission: updated,
      );
      if (mounted) setState(() => _permissions[projectId] = saved);
      // Log the permission change
      await auth.logActivity(
        action: 'permissions_updated',
        details:
            'Updated permissions for ${widget.member.displayName} on project $projectId',
      );
    } catch (_) {
      // Rollback on failure
      if (mounted) setState(() => _permissions[projectId] = current);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update permissions.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        side: const BorderSide(color: AppColors.border),
      ),
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──────────────────────────────────────────────────────
          InkWell(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppSpacing.radiusSm),
              bottom: _expanded
                  ? Radius.zero
                  : Radius.circular(AppSpacing.radiusSm),
            ),
            onTap: () async {
              final willExpand = !_expanded;
              setState(() => _expanded = willExpand);
              if (willExpand) await _ensureLoaded();
            },
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.s4),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.blue100,
                    child: Text(
                      _initials(widget.member.displayName),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.member.displayName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          widget.member.email,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.bodyMuted),
                        ),
                      ],
                    ),
                  ),
                  if (_loadingPermissions)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: AppColors.bodyMuted,
                    ),
                ],
              ),
            ),
          ),

          // ── Expanded permission table ────────────────────────────────────
          if (_expanded) ...[
            const Divider(height: 1),
            if (_loadingPermissions)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.s5),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Column(
                children: widget.projects.map((project) {
                  final perm = _permissions[project.id] ??
                      MemberPermission.defaultFor(
                        uid: widget.member.uid,
                        projectId: project.id,
                        companyId: widget.member.companyId,
                      );
                  return _ProjectPermissionRow(
                    project: project,
                    permission: perm,
                    onChanged: (updated) =>
                        _toggle(project.id, perm, updated),
                  );
                }).toList(),
              ),
          ],
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single project row with inline toggle chips
// ─────────────────────────────────────────────────────────────────────────────

class _ProjectPermissionRow extends StatelessWidget {
  const _ProjectPermissionRow({
    required this.project,
    required this.permission,
    required this.onChanged,
  });

  final SowProjectModel project;
  final MemberPermission permission;
  final void Function(MemberPermission updated) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.folder_outlined,
                size: 16,
                color: AppColors.bodyMuted,
              ),
              const SizedBox(width: AppSpacing.s2),
              Expanded(
                child: Text(
                  project.name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.body,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          Wrap(
            spacing: AppSpacing.s2,
            runSpacing: AppSpacing.s2,
            children: [
              _PermChip(
                label: 'View',
                icon: Icons.visibility_outlined,
                value: permission.canView,
                onChanged: (v) => onChanged(permission.copyWith(canView: v)),
              ),
              _PermChip(
                label: 'Record',
                icon: Icons.mic_none_rounded,
                value: permission.canRecord,
                onChanged: (v) => onChanged(permission.copyWith(canRecord: v)),
              ),
              _PermChip(
                label: 'Transcribe',
                icon: Icons.subtitles_outlined,
                value: permission.canTranscribe,
                onChanged: (v) =>
                    onChanged(permission.copyWith(canTranscribe: v)),
              ),
              _PermChip(
                label: 'Edit Doc',
                icon: Icons.edit_outlined,
                value: permission.canEditDocument,
                onChanged: (v) =>
                    onChanged(permission.copyWith(canEditDocument: v)),
              ),
              _PermChip(
                label: 'Export',
                icon: Icons.ios_share_outlined,
                value: permission.canExport,
                onChanged: (v) =>
                    onChanged(permission.copyWith(canExport: v)),
              ),
              _PermChip(
                label: 'Delete',
                icon: Icons.delete_outline_rounded,
                value: permission.canDeleteTranscript,
                onChanged: (v) =>
                    onChanged(permission.copyWith(canDeleteTranscript: v)),
                dangerColor: true,
              ),
              _PermChip(
                label: 'Create Project',
                icon: Icons.create_new_folder_outlined,
                value: permission.canCreateProject,
                onChanged: (v) =>
                    onChanged(permission.copyWith(canCreateProject: v)),
              ),
              _PermChip(
                label: 'Edit Project',
                icon: Icons.drive_file_rename_outline,
                value: permission.canEditProject,
                onChanged: (v) =>
                    onChanged(permission.copyWith(canEditProject: v)),
              ),
              _PermChip(
                label: 'Delete Project',
                icon: Icons.folder_delete_outlined,
                value: permission.canDeleteProject,
                onChanged: (v) =>
                    onChanged(permission.copyWith(canDeleteProject: v)),
                dangerColor: true,
              ),
              _PermChip(
                label: 'Manage Templates',
                icon: Icons.dashboard_customize_outlined,
                value: permission.canManageTemplates,
                onChanged: (v) =>
                    onChanged(permission.copyWith(canManageTemplates: v)),
              ),
              _PermChip(
                label: 'Upload Files',
                icon: Icons.upload_file_outlined,
                value: permission.canUploadFiles,
                onChanged: (v) =>
                    onChanged(permission.copyWith(canUploadFiles: v)),
              ),
              _PermChip(
                label: 'View SOW',
                icon: Icons.description_outlined,
                value: permission.canViewSow,
                onChanged: (v) =>
                    onChanged(permission.copyWith(canViewSow: v)),
              ),
              _PermChip(
                label: 'Create SOW',
                icon: Icons.post_add_outlined,
                value: permission.canCreateSow,
                onChanged: (v) =>
                    onChanged(permission.copyWith(canCreateSow: v)),
              ),
              _PermChip(
                label: 'Delete SOW',
                icon: Icons.delete_sweep_outlined,
                value: permission.canDeleteSow,
                onChanged: (v) =>
                    onChanged(permission.copyWith(canDeleteSow: v)),
                dangerColor: true,
              ),
              _PermChip(
                label: 'View PDF',
                icon: Icons.picture_as_pdf_outlined,
                value: permission.canViewPdf,
                onChanged: (v) =>
                    onChanged(permission.copyWith(canViewPdf: v)),
              ),
              _PermChip(
                label: 'Create PDF',
                icon: Icons.note_add_outlined,
                value: permission.canCreatePdf,
                onChanged: (v) =>
                    onChanged(permission.copyWith(canCreatePdf: v)),
              ),
              _PermChip(
                label: 'Delete PDF',
                icon: Icons.delete_forever_outlined,
                value: permission.canDeletePdf,
                onChanged: (v) =>
                    onChanged(permission.copyWith(canDeletePdf: v)),
                dangerColor: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tappable permission toggle chip
// ─────────────────────────────────────────────────────────────────────────────

class _PermChip extends StatelessWidget {
  const _PermChip({
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
    this.dangerColor = false,
  });

  final String label;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool dangerColor;

  @override
  Widget build(BuildContext context) {
    final activeColor = dangerColor ? AppColors.danger : AppColors.primary;
    final activeBg = dangerColor ? AppColors.dangerLight : AppColors.blue100;

    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s3,
          vertical: AppSpacing.s1,
        ),
        decoration: BoxDecoration(
          color: value ? activeBg : AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          border: Border.all(
            color: value ? activeColor : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: value ? activeColor : AppColors.bodyMuted),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: value ? activeColor : AppColors.bodyMuted,
                fontWeight: value ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
