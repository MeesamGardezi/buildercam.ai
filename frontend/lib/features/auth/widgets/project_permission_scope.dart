// Purpose: Inherited widget that exposes the current user's MemberPermission
// for the active project to the descendant widget tree. Lets feature screens
// hide / disable Save, Edit, Export, Delete buttons without plumbing the
// permission through every constructor.
//
// Usage:
//   ProjectPermissionScope.load(
//     projectId: project.id,
//     child: ...,
//   );
//
//   // anywhere in the subtree:
//   final perm = ProjectPermissionScope.of(context);
//   if (!perm.canEditDocument) return const SizedBox.shrink();

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/auth_controller.dart';
import '../models/member_permission_model.dart';

class ProjectPermissionScope extends InheritedWidget {
  const ProjectPermissionScope({
    super.key,
    required this.permission,
    required super.child,
  });

  final MemberPermission permission;

  /// Returns the permission record for the nearest enclosing scope. Falls back
  /// to a fully-allow record when no scope is in the tree — keeps the gating
  /// helpers safe to use in standalone / preview contexts.
  static MemberPermission of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<ProjectPermissionScope>();
    return scope?.permission ?? _allowAll;
  }

  @override
  bool updateShouldNotify(ProjectPermissionScope oldWidget) =>
      oldWidget.permission != permission;

  /// Convenience widget that asynchronously loads the current user's
  /// permission record for [projectId] and provides it to [child]. Renders
  /// [child] with a fully-permissive default while the lookup is in flight
  /// so the UI never flashes "denied" for owners (whose lookup is synchronous
  /// anyway).
  static Widget load({
    Key? key,
    required String projectId,
    required Widget child,
  }) {
    return _ProjectPermissionLoader(
      key: key,
      projectId: projectId,
      child: child,
    );
  }
}

class _ProjectPermissionLoader extends StatefulWidget {
  const _ProjectPermissionLoader({
    super.key,
    required this.projectId,
    required this.child,
  });

  final String projectId;
  final Widget child;

  @override
  State<_ProjectPermissionLoader> createState() =>
      _ProjectPermissionLoaderState();
}

class _ProjectPermissionLoaderState extends State<_ProjectPermissionLoader> {
  MemberPermission _permission = _allowAll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ProjectPermissionLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthController>();
    final result = await auth.permissionsForProject(widget.projectId);
    if (!mounted) return;
    setState(() => _permission = result);
  }

  @override
  Widget build(BuildContext context) {
    return ProjectPermissionScope(
      permission: _permission,
      child: widget.child,
    );
  }
}

final _allowAll = const MemberPermission(
  uid: '',
  projectId: '',
  companyId: '',
  canView: true,
  canRecord: true,
  canTranscribe: true,
  canEditDocument: true,
  canExport: true,
  canDeleteTranscript: true,
  canCreateProject: true,
  canEditProject: true,
  canDeleteProject: true,
  canManageTemplates: true,
  canUploadFiles: true,
  canViewSow: true,
  canCreateSow: true,
  canDeleteSow: true,
  canViewPdf: true,
  canCreatePdf: true,
  canDeletePdf: true,
);
