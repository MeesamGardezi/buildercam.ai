// Purpose: Handles HTTP requests for company setup, team member management, and company settings.
import * as authService from './auth.service.js';

class AuthController {
  async setupCompany(req, res) {
    try {
      const { companyName } = req.body;
      if (!companyName || !String(companyName).trim()) {
        return res.status(400).json({ success: false, message: 'companyName is required.' });
      }

      if (req.user.companyId) {
        return res.status(409).json({
          success: false,
          message: 'This account already belongs to a company.',
        });
      }

      const result = await authService.createCompany({
        uid: req.user.uid,
        email: req.user.email || '',
        displayName: req.user.name || req.user.email || '',
        companyName: String(companyName).trim(),
      });

      return res.status(201).json({ success: true, ...result });
    } catch (error) {
      return this._handleError(req, res, error, 'setupCompany');
    }
  }

  async getMe(req, res) {
    try {
      const profile = await authService.getUserProfile(req.user.uid);
      return res.json({
        success: true,
        user: profile || { uid: req.user.uid, email: req.user.email || '' },
      });
    } catch (error) {
      return this._handleError(req, res, error, 'getMe');
    }
  }

  async createTeamMember(req, res) {
    try {
      const { email, password, displayName } = req.body;
      if (!email || !password || !displayName) {
        return res.status(400).json({
          success: false,
          message: 'email, password, and displayName are required.',
        });
      }

      const member = await authService.createTeamMember({
        companyId: req.user.companyId,
        email: String(email).trim(),
        password,
        displayName: String(displayName).trim(),
      });
      return res.status(201).json({ success: true, member });
    } catch (error) {
      return this._handleError(req, res, error, 'createTeamMember');
    }
  }

  async listTeamMembers(req, res) {
    try {
      const members = await authService.listTeamMembers(req.user.companyId);
      return res.json({ success: true, members });
    } catch (error) {
      return this._handleError(req, res, error, 'listTeamMembers');
    }
  }

  async getCompanySettings(req, res) {
    try {
      const settings = await authService.getCompanySettings(req.user.companyId);
      return res.json({ success: true, settings });
    } catch (error) {
      return this._handleError(req, res, error, 'getCompanySettings');
    }
  }

  async updateCompanySettings(req, res) {
    try {
      const { categories, notes } = req.body;
      const settings = await authService.updateCompanySettings(req.user.companyId, {
        categories,
        notes,
      });
      return res.json({ success: true, settings });
    } catch (error) {
      return this._handleError(req, res, error, 'updateCompanySettings');
    }
  }

  async removeTeamMember(req, res) {
    try {
      const { uid } = req.params;
      if (uid === req.user.uid) {
        return res.status(400).json({
          success: false,
          message: 'You cannot remove yourself.',
        });
      }
      await authService.removeTeamMember(req.user.companyId, uid);
      return res.json({ success: true });
    } catch (error) {
      return this._handleError(req, res, error, 'removeTeamMember');
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

export const authController = new AuthController();
