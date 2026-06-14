// Purpose: Protected REST routes for SOW transcription and transcript history.
import { Router } from 'express';

import { verifyFirebaseToken } from '../../middleware/firebase-auth.middleware.js';
import { requireCredits } from '../../middleware/require-credits.middleware.js';
import { requirePermission } from '../../middleware/require-permission.middleware.js';
import { CREDIT_COSTS } from '../credits/credits.service.js';
import { sowController } from './sow.controller.js';

const router = Router();

// All SOW routes require a valid Firebase ID token and a company affiliation.
const requireCompany = (req, res, next) => {
  if (!req.user?.companyId) {
    return res.status(403).json({ success: false, message: 'Company setup required.' });
  }
  return next();
};

// Owner-only guard.
const requireOwner = (req, res, next) => {
  if (req.user?.role !== 'owner') {
    return res.status(403).json({ success: false, message: 'Only company owners can perform this action.' });
  }
  return next();
};

router.use(verifyFirebaseToken, requireCompany);

router.get('/projects', (req, res) => sowController.listProjects(req, res));

router.post('/projects', (req, res) => sowController.createProject(req, res));

router.get(
  '/projects/:projectId',
  requirePermission('canView'),
  (req, res) => sowController.getProject(req, res),
);

router.get(
  '/projects/:projectId/transcripts',
  requirePermission('canView'),
  (req, res) => sowController.listTranscripts(req, res),
);

router.post(
  '/projects/:projectId/transcripts',
  requirePermission('canTranscribe'),
  requireCredits((req) =>
    Array.isArray(req.body?.frameUrls) && req.body.frameUrls.length > 0
      ? CREDIT_COSTS.transcript_video
      : CREDIT_COSTS.transcript,
  ),
  (req, res) => sowController.saveTranscript(req, res),
);

router.delete(
  '/projects/:projectId/transcripts/:transcriptId',
  requirePermission('canDeleteTranscript'),
  (req, res) => sowController.deleteTranscript(req, res),
);

router.delete('/projects/:projectId', requireOwner, (req, res) => sowController.deleteProject(req, res));

router.post('/structure-sow', (req, res) => sowController.structureSow(req, res));

router.post(
  '/projects/:projectId/generate-sow',
  requirePermission('canEditDocument'),
  requireCredits(CREDIT_COSTS.sow_generation),
  (req, res) => sowController.generateSow(req, res),
);

// AI-generated PDF layout from SOW text (optionally following a PDF template).
// Costs the same as a PDF generation (render) since it produces the final
// renderable layout. Gated by canExport like other PDF-producing actions.
router.post(
  '/projects/:projectId/generate-pdf-layout',
  requirePermission('canExport'),
  requireCredits(CREDIT_COSTS.pdf_generation),
  (req, res) => sowController.generatePdfLayout(req, res),
);

router.get(
  '/projects/:projectId/sow-documents',
  requirePermission('canView'),
  (req, res) => sowController.listSowDocuments(req, res),
);

router.get(
  '/projects/:projectId/sow-documents/:sowDocId',
  requirePermission('canView'),
  (req, res) => sowController.getSowDocument(req, res),
);

router.post(
  '/projects/:projectId/sow-documents',
  requirePermission('canEditDocument'),
  requireCredits(CREDIT_COSTS.sow_document),
  (req, res) => sowController.saveSowDocument(req, res),
);

router.put(
  '/projects/:projectId/sow-documents/:sowDocId',
  requirePermission('canEditDocument'),
  (req, res) => sowController.saveSowDocument(req, res),
);

router.delete(
  '/projects/:projectId/sow-documents/:sowDocId',
  requirePermission('canEditDocument'),
  (req, res) => sowController.deleteSowDocument(req, res),
);

router.get('/templates', (req, res) => sowController.listTemplates(req, res));

router.post('/templates', (req, res) => sowController.saveTemplate(req, res));

router.delete('/templates/:templateId', (req, res) => sowController.deleteTemplate(req, res));

// ── Standalone PDF documents ──────────────────────────────────────────────────
router.get(
  '/projects/:projectId/pdf-documents',
  requirePermission('canView'),
  (req, res) => sowController.listPdfDocuments(req, res),
);

router.post(
  '/projects/:projectId/pdf-documents',
  requirePermission('canEditDocument'),
  requireCredits(CREDIT_COSTS.pdf_document),
  (req, res) => sowController.savePdfDocument(req, res),
);

router.get(
  '/projects/:projectId/pdf-documents/:pdfDocId',
  requirePermission('canView'),
  (req, res) => sowController.getPdfDocument(req, res),
);

router.put(
  '/projects/:projectId/pdf-documents/:pdfDocId',
  requirePermission('canEditDocument'),
  (req, res) => sowController.savePdfDocument(req, res),
);

router.delete(
  '/projects/:projectId/pdf-documents/:pdfDocId',
  requirePermission('canDeleteTranscript'),
  (req, res) => sowController.deletePdfDocument(req, res),
);

export default router;