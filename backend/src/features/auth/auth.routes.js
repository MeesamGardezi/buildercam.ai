// Purpose: Routes for company registration, user profile, and team member management.
import { Router } from 'express';

import { verifyFirebaseToken } from '../../middleware/firebase-auth.middleware.js';
import { authController } from './auth.controller.js';

const router = Router();

// requireCompany — caller must have completed company setup (has companyId claim).
const requireCompany = (req, res, next) => {
  if (!req.user?.companyId) {
    return res.status(403).json({ success: false, message: 'Company setup required.' });
  }
  return next();
};

// requireOwner — caller must be the company owner.
const requireOwner = (req, res, next) => {
  if (req.user?.role !== 'owner') {
    return res
      .status(403)
      .json({ success: false, message: 'Only company owners can perform this action.' });
  }
  return next();
};

// First-time setup: registers the company and sets the companyId custom claim.
// Only requires a valid Firebase ID token (no pre-existing company needed).
router.post('/setup-company', verifyFirebaseToken, (req, res) =>
  authController.setupCompany(req, res),
);

router.get('/me', verifyFirebaseToken, requireCompany, (req, res) =>
  authController.getMe(req, res),
);

router.post('/team-members', verifyFirebaseToken, requireCompany, requireOwner, (req, res) =>
  authController.createTeamMember(req, res),
);

router.get('/team-members', verifyFirebaseToken, requireCompany, (req, res) =>
  authController.listTeamMembers(req, res),
);

router.delete('/team-members/:uid', verifyFirebaseToken, requireCompany, requireOwner, (req, res) =>
  authController.removeTeamMember(req, res),
);

// Delete the caller's own account (and company + team data if owner).
router.delete('/account', verifyFirebaseToken, (req, res) =>
  authController.deleteAccount(req, res),
);

// Company-wide AI settings: categories and notes used during SOW/PDF generation.
router.get('/company-settings', verifyFirebaseToken, requireCompany, (req, res) =>
  authController.getCompanySettings(req, res),
);

router.put('/company-settings', verifyFirebaseToken, requireCompany, requireOwner, (req, res) =>
  authController.updateCompanySettings(req, res),
);

// Mark that the authenticated user has seen the welcome screen (stored in Firestore).
router.post('/mark-welcome-seen', verifyFirebaseToken, requireCompany, (req, res) =>
  authController.markWelcomeSeen(req, res),
);

export default router;
