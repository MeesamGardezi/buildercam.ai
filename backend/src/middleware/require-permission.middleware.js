// Purpose: Per-project, per-member permission guard. Owners always bypass.
//
// Usage:
//   import { requirePermission } from '../../middleware/require-permission.middleware.js';
//   router.post('/projects/:projectId/foo', requirePermission('canTranscribe'), handler);
//   router.post('/export', requirePermission('canExport', { projectIdFrom: 'body' }), handler);
//
// projectIdFrom: 'params' (default) | 'body' | 'query'
// Members without a resolvable projectId are denied (safer than the previous
// silent pass-through).
import { getMemberProjectPermissions } from '../features/team-settings/team-settings.service.js';

export function requirePermission(permissionKey, { projectIdFrom = 'params' } = {}) {
  return async (req, res, next) => {
    if (req.user?.role === 'owner') return next();

    const source =
      projectIdFrom === 'body' ? req.body
      : projectIdFrom === 'query' ? req.query
      : req.params;
    const projectId = source?.projectId;

    if (!projectId) {
      return res.status(403).json({
        success: false,
        message: 'Project context required for permission check.',
      });
    }

    try {
      const perms = await getMemberProjectPermissions({
        companyId: req.user.companyId,
        uid: req.user.uid,
        projectId,
      });
      if (!perms[permissionKey]) {
        return res.status(403).json({
          success: false,
          message: 'You do not have permission to perform this action.',
        });
      }
      return next();
    } catch (err) {
      return res
        .status(500)
        .json({ success: false, message: 'Failed to verify permissions.' });
    }
  };
}
