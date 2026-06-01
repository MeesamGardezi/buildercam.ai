// Purpose: HTTP handlers for activity log creation and retrieval.
import * as activityLogsService from './activity-logs.service.js';

class ActivityLogsController {
  /**
   * POST /api/activity-logs
   * Any authenticated company member can write a log entry.
   * Body: { action, projectId?, projectName?, details? }
   */
  async createLog(req, res) {
    try {
      const { companyId, uid, email, name } = req.user;
      const { action, projectId, projectName, details } = req.body;

      if (!action || !String(action).trim()) {
        return res.status(400).json({ success: false, message: 'action is required.' });
      }

      const log = await activityLogsService.createActivityLog({
        companyId,
        userId: uid,
        userEmail: email || '',
        userName: name || email || '',
        action: String(action).trim(),
        projectId: projectId || null,
        projectName: projectName || null,
        details: details || null,
      });

      return res.status(201).json({ success: true, log });
    } catch (error) {
      return this._handleError(req, res, error, 'createLog');
    }
  }

  /**
   * GET /api/activity-logs
   * Owner: returns logs for all company members.
   * Member: returns only their own logs.
   * Query params: limit (number), before (ISO timestamp for pagination)
   */
  async getLogs(req, res) {
    try {
      const { companyId, uid, role } = req.user;
      const isOwner = role === 'owner';
      const limit = req.query.limit ? parseInt(req.query.limit, 10) : 50;
      const before = req.query.before || null;
      const projectId = req.query.projectId || null;

      const logs = await activityLogsService.getActivityLogs({
        companyId,
        userId: uid,
        isOwner,
        projectId,
        limit,
        before,
      });

      return res.json({ success: true, logs, isOwner });
    } catch (error) {
      return this._handleError(req, res, error, 'getLogs');
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

export const activityLogsController = new ActivityLogsController();
