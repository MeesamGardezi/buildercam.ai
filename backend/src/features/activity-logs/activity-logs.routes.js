// Purpose: Routes for activity log creation and retrieval.
import { Router } from 'express';

import { verifyFirebaseToken } from '../../middleware/firebase-auth.middleware.js';
import { activityLogsController } from './activity-logs.controller.js';

const router = Router();

const requireCompany = (req, res, next) => {
  if (!req.user?.companyId) {
    return res.status(403).json({ success: false, message: 'Company setup required.' });
  }
  return next();
};

// Create a new activity log entry (any authenticated company member).
router.post(
  '/',
  verifyFirebaseToken,
  requireCompany,
  (req, res) => activityLogsController.createLog(req, res),
);

// Retrieve logs — owner sees all, member sees own.
router.get(
  '/',
  verifyFirebaseToken,
  requireCompany,
  (req, res) => activityLogsController.getLogs(req, res),
);

export default router;
