// Purpose: HTTP handlers for per-project, per-member permissions management.
import * as teamSettingsService from './team-settings.service.js';

class TeamSettingsController {
  /**
   * GET /api/team-settings/permissions
   * Owner: returns all permission records for the company.
   * Member: returns their own permission records only.
   */
  async listPermissions(req, res) {
    try {
      const { companyId, uid, role } = req.user;
      const isOwner = role === 'owner';

      const permissions = isOwner
        ? await teamSettingsService.getAllCompanyPermissions({ companyId })
        : await teamSettingsService.getMemberAllPermissions({ companyId, uid });

      return res.json({ success: true, permissions });
    } catch (error) {
      return this._handleError(req, res, error, 'listPermissions');
    }
  }

  /**
   * GET /api/team-settings/permissions/:uid
   * Owner only: returns all project permissions for a specific member.
   */
  async getMemberPermissions(req, res) {
    try {
      const { companyId } = req.user;
      const targetUid = req.params.uid;

      const permissions = await teamSettingsService.getMemberAllPermissions({
        companyId,
        uid: targetUid,
      });

      return res.json({ success: true, permissions });
    } catch (error) {
      return this._handleError(req, res, error, 'getMemberPermissions');
    }
  }

  /**
   * PUT /api/team-settings/permissions/:uid/:projectId
   * Owner only: set a member's permissions for a specific project.
   * Body: { canView, canRecord, canTranscribe, canEditDocument, canExport, canDeleteTranscript,
   *         canCreateProject, canEditProject, canDeleteProject, canManageTemplates, canUploadFiles,
   *         canViewSow, canCreateSow, canDeleteSow, canViewPdf, canCreatePdf, canDeletePdf }
   */
  async setMemberProjectPermissions(req, res) {
    try {
      const { companyId } = req.user;
      const { uid, projectId } = req.params;

      const {
        canView,
        canRecord,
        canTranscribe,
        canEditDocument,
        canExport,
        canDeleteTranscript,
        canCreateProject,
        canEditProject,
        canDeleteProject,
        canManageTemplates,
        canUploadFiles,
        canViewSow,
        canCreateSow,
        canDeleteSow,
        canViewPdf,
        canCreatePdf,
        canDeletePdf,
      } = req.body;

      const permission = await teamSettingsService.setMemberProjectPermissions({
        companyId,
        uid,
        projectId,
        permissions: {
          canView: canView ?? true,
          canRecord: canRecord ?? false,
          canTranscribe: canTranscribe ?? false,
          canEditDocument: canEditDocument ?? false,
          canExport: canExport ?? false,
          canDeleteTranscript: canDeleteTranscript ?? false,
          canCreateProject: canCreateProject ?? false,
          canEditProject: canEditProject ?? false,
          canDeleteProject: canDeleteProject ?? false,
          canManageTemplates: canManageTemplates ?? false,
          canUploadFiles: canUploadFiles ?? false,
          canViewSow: canViewSow ?? true,
          canCreateSow: canCreateSow ?? false,
          canDeleteSow: canDeleteSow ?? false,
          canViewPdf: canViewPdf ?? true,
          canCreatePdf: canCreatePdf ?? false,
          canDeletePdf: canDeletePdf ?? false,
        },
      });

      return res.json({ success: true, permission });
    } catch (error) {
      return this._handleError(req, res, error, 'setMemberProjectPermissions');
    }
  }

  /**
   * GET /api/team-settings/permissions/:uid/:projectId
   * Owner only: get a single member's permissions for a specific project.
   */
  async getMemberSingleProjectPermissions(req, res) {
    try {
      const { companyId } = req.user;
      const { uid, projectId } = req.params;

      const permission = await teamSettingsService.getMemberProjectPermissions({
        companyId,
        uid,
        projectId,
      });

      return res.json({ success: true, permission });
    } catch (error) {
      return this._handleError(req, res, error, 'getMemberSingleProjectPermissions');
    }
  }

  _handleError(req, res, error, action) {
    console.error(
      `[${req.requestId || 'no-request-id'}] ${action} failed: ${error.message || 'Unknown error'}`,
    );
    return res.status(error.status || 500).json({
      success: false,
      message: error.message || 'Something went wrong.',
    });
  }
}

export const teamSettingsController = new TeamSettingsController();
