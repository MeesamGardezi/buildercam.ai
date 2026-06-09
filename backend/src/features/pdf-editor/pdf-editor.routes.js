// Purpose: Express routes for the PdfEditorWidget — generates PDF bytes from canvas elements
//          and manages user-saved PDF layout templates.
import { Router } from 'express';
import { validateGenerateRequest } from './template.schema.js';
import { generatePdf } from './pdf.service.js';
import { verifyFirebaseToken } from '../../middleware/firebase-auth.middleware.js';
import { requireCredits } from '../../middleware/require-credits.middleware.js';
import { requirePermission } from '../../middleware/require-permission.middleware.js';
import { CREDIT_COSTS, spendCredits } from '../credits/credits.service.js';
import { resolveBillingUid } from '../credits/billing-uid.js';
import {
  savePdfTemplate,
  listPdfTemplates,
  deletePdfTemplate,
  updatePdfTemplate,
} from '../../services/firestore.service.js';

const router = Router();

// POST /api/templates/:templateId/generate
// Body: { elements: [...], pageSize: { width, height }, projectId? }
// Returns: application/pdf bytes
router.post(
  '/templates/:templateId/generate',
  verifyFirebaseToken,
  requirePermission('canExport', { projectIdFrom: 'body' }),
  requireCredits(CREDIT_COSTS.pdf_generation),
  async (req, res) => {
    try {
      const { elements, pageSize } = validateGenerateRequest(req.body);
      const sorted = [...elements].sort((a, b) => (a.zIndex ?? 0) - (b.zIndex ?? 0));
      const bytes = await generatePdf(sorted, pageSize);
      // Deduct credits after successful PDF generation.
      const billingUid = req.billingUid ?? (await resolveBillingUid(req));
      spendCredits(billingUid, CREDIT_COSTS.pdf_generation, {
        actionType: 'pdf_generation',
      }).catch((err) => console.error('[credits] pdf_generation spend failed:', err));
      res.setHeader('Content-Type', 'application/pdf');
      res.setHeader('Content-Disposition', 'inline; filename="document.pdf"');
      res.send(Buffer.from(bytes));
    } catch (err) {
      const status = err.message?.startsWith('Element missing') ? 400 : 500;
      res.status(status).json({ error: err.message });
    }
  },
);

// ── PDF template endpoints (authenticated) ────────────────────────────────────

// GET /api/pdf-templates — list saved PDF templates for the company
router.get('/pdf-templates', verifyFirebaseToken, async (req, res) => {
  try {
    const companyId = req.user.companyId || req.user.uid;
    const templates = await listPdfTemplates(companyId);
    return res.json({ success: true, templates });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// POST /api/pdf-templates — save current PDF canvas as a named template
// Body: { name: string, pdfJson: { name?, pageSize, elements } }
router.post('/pdf-templates', verifyFirebaseToken, async (req, res) => {
  try {
    const companyId = req.user.companyId || req.user.uid;
    const { name, pdfJson } = req.body;
    if (!name || !String(name).trim()) {
      return res.status(400).json({ success: false, message: 'name is required.' });
    }
    if (!pdfJson || typeof pdfJson !== 'object' || Array.isArray(pdfJson)) {
      return res.status(400).json({ success: false, message: 'pdfJson must be an object.' });
    }
    const template = await savePdfTemplate(companyId, {
      name: String(name).trim(),
      pdfJson,
      createdBy: req.user.uid,
    });
    return res.status(201).json({ success: true, template });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// DELETE /api/pdf-templates/:id — delete a saved PDF template
router.delete('/pdf-templates/:id', verifyFirebaseToken, async (req, res) => {
  try {
    const companyId = req.user.companyId || req.user.uid;
    await deletePdfTemplate(req.params.id, companyId);
    return res.json({ success: true });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// PUT /api/pdf-templates/:id — update name and/or content of a saved PDF template
// Body: { name?: string, pdfJson?: object }
router.put('/pdf-templates/:id', verifyFirebaseToken, async (req, res) => {
  try {
    const companyId = req.user.companyId || req.user.uid;
    const { name, pdfJson } = req.body;
    const template = await updatePdfTemplate(req.params.id, companyId, { name, pdfJson });
    return res.json({ success: true, template });
  } catch (err) {
    const status = err.message === 'Template not found' ? 404 : 500;
    return res.status(status).json({ success: false, message: err.message });
  }
});

export default router;
