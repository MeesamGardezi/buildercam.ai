// Purpose: Routes for per-project, per-member team permission management.
import { Router } from 'express';

import { verifyFirebaseToken } from '../../middleware/firebase-auth.middleware.js';
import { teamSettingsController } from './team-settings.controller.js';

const router = Router();

const requireCompany = (req, res, next) => {
  if (!req.user?.companyId) {
    return res.status(403).json({ success: false, message: 'Company setup required.' });
  }
  return next();
};

const requireOwner = (req, res, next) => {
  if (req.user?.role !== 'owner') {
    return res
      .status(403)
      .json({ success: false, message: 'Only company owners can perform this action.' });
  }
  return next();
};

// List permissions: owner sees all, member sees own.
router.get(
  '/permissions',
  verifyFirebaseToken,
  requireCompany,
  (req, res) => teamSettingsController.listPermissions(req, res),
);

// Get all permissions for a specific member (owner only).
router.get(
  '/permissions/:uid',
  verifyFirebaseToken,
  requireCompany,
  requireOwner,
  (req, res) => teamSettingsController.getMemberPermissions(req, res),
);

// Get a member's permissions for a specific project (owner only).
router.get(
  '/permissions/:uid/:projectId',
  verifyFirebaseToken,
  requireCompany,
  requireOwner,
  (req, res) => teamSettingsController.getMemberSingleProjectPermissions(req, res),
);

// Set a member's permissions for a specific project (owner only).
router.put(
  '/permissions/:uid/:projectId',
  verifyFirebaseToken,
  requireCompany,
  requireOwner,
  (req, res) => teamSettingsController.setMemberProjectPermissions(req, res),
);

export default router;
