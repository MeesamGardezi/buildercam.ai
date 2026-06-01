// Purpose: Displays activity logs — owners see all users, members see their own.
// Supports project-wise filtering via a chip bar.
import 'package:buildercam/core/app_colors.dart';
import 'package:buildercam/core/app_spacing.dart';
import 'package:buildercam/features/sow_transcription/models/sow_transcript_model.dart';
import 'package:buildercam/features/sow_transcription/services/sow_firestore_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../models/activity_log_model.dart';

class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  bool _loading = true;
  bool _loadingMore = false;
  bool _loadingProjects = false;
  String? _error;
  bool _isOwner = false;
  List<ActivityLogEntry> _logs = const [];
  List<SowProjectModel> _projects = const [];

  /// null = "All Projects"
  SowProjectModel? _selectedProject;

  static const int _pageSize = 50;

  @override
  void initState() {
    super.initState();
    _load();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    setState(() => _loadingProjects = true);
    try {
      final auth = context.read<AuthController>();
      final svc = SowBackendService(tokenProvider: auth.getIdToken);
      final projects = await svc.fetchProjects();
      if (mounted) setState(() => _projects = projects);
    } catch (_) {
      // Non-fatal — filter bar stays empty.
    } finally {
      if (mounted) setState(() => _loadingProjects = false);
    }
  }

  Future<void> _load({bool reset = true}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _logs = const [];
      });
    } else {
      setState(() => _loadingMore = true);
    }

    try {
      final auth = context.read<AuthController>();
      _isOwner = auth.user?.isOwner == true;

      final before = (!reset && _logs.isNotEmpty) ? _logs.last.timestamp : null;
      final page = await auth.getActivityLogs(
        limit: _pageSize,
        before: before,
        projectId: _selectedProject?.id,
      );

      if (!mounted) return;
      setState(() {
        _logs = reset ? page : [..._logs, ...page];
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _selectProject(SowProjectModel? project) {
    if (_selectedProject?.id == project?.id) return;
    setState(() => _selectedProject = project);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(_isOwner ? 'Activity Logs — All Members' : 'My Activity Log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () => _load(),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Project filter bar ───────────────────────────────────────────
          if (_projects.isNotEmpty || _loadingProjects)
            _ProjectFilterBar(
              projects: _projects,
              selected: _selectedProject,
              loading: _loadingProjects,
              onSelected: _selectProject,
            ),

          // ── Log list ─────────────────────────────────────────────────────
          Expanded(
            child: () {
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
                        const Icon(
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
                          onPressed: () => _load(),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (_logs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: 48,
                        color: AppColors.bodySubtle,
                      ),
                      const SizedBox(height: AppSpacing.s3),
                      Text(
                        _selectedProject != null
                            ? 'No activity for "${_selectedProject!.name}" yet.'
                            : 'No activity recorded yet.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppColors.bodyMuted),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.s4),
                itemCount: _logs.length + 1, // +1 for load-more footer
                separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.s2),
                itemBuilder: (context, index) {
                  if (index == _logs.length) {
                    if (_loadingMore) {
                      return const Padding(
                        padding: EdgeInsets.all(AppSpacing.s4),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (_logs.length >= _pageSize) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.s4,
                        ),
                        child: Center(
                          child: OutlinedButton(
                            onPressed: () => _load(reset: false),
                            child: const Text('Load more'),
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  }
                  return _LogEntryTile(
                    entry: _logs[index],
                    showUser: _isOwner,
                  );
                },
              );
            }(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Horizontal chip bar for project filtering
// ─────────────────────────────────────────────────────────────────────────────

class _ProjectFilterBar extends StatelessWidget {
  const _ProjectFilterBar({
    required this.projects,
    required this.selected,
    required this.loading,
    required this.onSelected,
  });

  final List<SowProjectModel> projects;
  final SowProjectModel? selected;
  final bool loading;
  final void Function(SowProjectModel?) onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Filter by project',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: AppColors.bodySubtle),
          ),
          const SizedBox(height: AppSpacing.s2),
          if (loading)
            const SizedBox(
              height: 32,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  // "All" chip
                  _FilterChip(
                    label: 'All Projects',
                    selected: selected == null,
                    onTap: () => onSelected(null),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  ...projects.map((p) => Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.s2),
                        child: _FilterChip(
                          label: p.name,
                          selected: selected?.id == p.id,
                          onTap: () => onSelected(p),
                        ),
                      )),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.s2),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s3,
          vertical: AppSpacing.s1,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.blue100 : AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: selected ? AppColors.primary : AppColors.bodyMuted,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single activity log tile
// ─────────────────────────────────────────────────────────────────────────────

class _LogEntryTile extends StatelessWidget {
  const _LogEntryTile({
    required this.entry,
    required this.showUser,
  });

  final ActivityLogEntry entry;
  final bool showUser;

  static final _dateFormat = DateFormat('MMM d, yyyy');
  static final _timeFormat = DateFormat('h:mm a');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ts = entry.parsedTimestamp?.toLocal();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        side: const BorderSide(color: AppColors.border),
      ),
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _iconBg(entry.action),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Icon(
                _actionIcon(entry.action),
                size: 18,
                color: _iconColor(entry.action),
              ),
            ),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.actionLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.body,
                          ),
                        ),
                      ),
                      if (ts != null) ...[
                        const SizedBox(width: AppSpacing.s2),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _timeFormat.format(ts),
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: AppColors.bodyMuted),
                            ),
                            Text(
                              _dateFormat.format(ts),
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: AppColors.bodySubtle),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  if (showUser) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.userName.isNotEmpty
                          ? entry.userName
                          : entry.userEmail,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.primary),
                    ),
                  ],
                  if (entry.projectName != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.folder_outlined,
                          size: 12,
                          color: AppColors.bodySubtle,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          entry.projectName!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.bodySubtle),
                        ),
                      ],
                    ),
                  ],
                  if (entry.details != null && entry.details!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      entry.details!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.bodyMuted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _actionIcon(String action) => switch (action) {
    ActivityLogAction.login => Icons.login_rounded,
    ActivityLogAction.logout => Icons.logout_rounded,
    ActivityLogAction.createProject => Icons.create_new_folder_outlined,
    ActivityLogAction.updateProject => Icons.edit_outlined,
    ActivityLogAction.deleteProject => Icons.delete_outline_rounded,
    ActivityLogAction.startRecording => Icons.mic_none_rounded,
    ActivityLogAction.stopRecording => Icons.stop_circle_outlined,
    ActivityLogAction.transcriptionSaved => Icons.subtitles_outlined,
    ActivityLogAction.exportDocument => Icons.ios_share_outlined,
    ActivityLogAction.viewDocument => Icons.description_outlined,
    ActivityLogAction.teamMemberAdded => Icons.person_add_outlined,
    ActivityLogAction.teamMemberRemoved => Icons.person_remove_outlined,
    ActivityLogAction.permissionsUpdated => Icons.admin_panel_settings_outlined,
    _ => Icons.event_note_outlined,
  };

  Color _iconColor(String action) => switch (action) {
    ActivityLogAction.deleteProject ||
    ActivityLogAction.teamMemberRemoved => AppColors.danger,
    ActivityLogAction.login ||
    ActivityLogAction.createProject ||
    ActivityLogAction.teamMemberAdded => AppColors.success,
    ActivityLogAction.startRecording ||
    ActivityLogAction.stopRecording => AppColors.warning,
    _ => AppColors.primary,
  };

  Color _iconBg(String action) => switch (action) {
    ActivityLogAction.deleteProject ||
    ActivityLogAction.teamMemberRemoved => AppColors.dangerLight,
    ActivityLogAction.login ||
    ActivityLogAction.createProject ||
    ActivityLogAction.teamMemberAdded => AppColors.successLight,
    ActivityLogAction.startRecording ||
    ActivityLogAction.stopRecording => AppColors.warningLight,
    _ => AppColors.blue100,
  };
}


