// Purpose: Adapts SOW HTTP requests into service calls and consistent JSON responses.
import { sowService } from './sow.service.js';
import { spendCredits, CREDIT_COSTS } from '../credits/credits.service.js';
import { resolveBillingUid } from '../credits/billing-uid.js';

class SowController {
  async createProject(req, res) {
    try {
      const { name, clientName, siteLocation, scopeSummary, notes, status } = req.body;
      if (!name || !clientName) {
        return res.status(400).json({
          success: false,
          message: 'name and clientName are required.',
        });
      }

      const project = await sowService.createProject({
        name,
        clientName,
        siteLocation,
        scopeSummary,
        notes,
        status,
        createdBy: req.user.uid,
        companyId: req.user.companyId,
      });
      return res.status(201).json({ success: true, project });
    } catch (error) {
      return this._handleError(req, res, error, 'createProject');
    }
  }

  async listProjects(req, res) {
    try {
      const projects = await sowService.listProjects(req.user.companyId);
      return res.json({ success: true, projects });
    } catch (error) {
      return this._handleError(req, res, error, 'listProjects');
    }
  }

  async getProject(req, res) {
    try {
      const project = await sowService.getProject(req.params.projectId, req.user.companyId);
      if (!project) {
        return res.status(404).json({
          success: false,
          message: 'Project not found.',
        });
      }

      return res.json({ success: true, project });
    } catch (error) {
      return this._handleError(req, res, error, 'getProject');
    }
  }

  async saveTranscript(req, res) {
    try {
      const { projectId } = req.params;
      const {
        id,
        rawTranscript,
        text,
        durationSeconds,
        duration,
        createdAt,
        status = 'completed',
        frameUrls,
        title,
      } = req.body;
      const normalizedText = String(rawTranscript || text || '').trim();
      if (!normalizedText) {
        return res.status(400).json({
          success: false,
          message: 'text is required.',
        });
      }
      const { transcript, created } = await sowService.saveTranscript({
        projectId,
        id,
        rawTranscript: normalizedText,
        durationSeconds: durationSeconds ?? duration,
        createdAt,
        createdBy: req.user.uid,
        companyId: req.user.companyId,
        status,
        frameUrls: Array.isArray(frameUrls) ? frameUrls : [],
        title: typeof title === 'string' && title.trim() ? title.trim() : null,
      });
      // Deduct credits only when a brand-new transcript is created.
      // Video transcripts (those with frameUrls) cost 2 credits; audio costs 1.
      if (created) {
        const isVideo = Array.isArray(frameUrls) && frameUrls.length > 0;
        const transcriptCost = isVideo ? CREDIT_COSTS.transcript_video : CREDIT_COSTS.transcript;
        const billingUid = await resolveBillingUid(req);
        spendCredits(billingUid, transcriptCost, {
          actionType: isVideo ? 'transcript_video' : 'transcript',
          projectId: req.params.projectId,
          companyId: req.user.companyId,
        }).catch((err) => console.error('[credits] transcript spend failed:', err));
      }
      return res.status(created ? 201 : 200).json({ success: true, transcript });
    } catch (error) {
      return this._handleError(req, res, error, 'saveTranscript');
    }
  }

  async listTranscripts(req, res) {
    try {
      const transcripts = await sowService.listTranscripts(
        req.params.projectId,
        req.user.companyId,
      );
      return res.json({ success: true, transcripts });
    } catch (error) {
      return this._handleError(req, res, error, 'listTranscripts');
    }
  }

  async deleteTranscript(req, res) {
    try {
      const { projectId, transcriptId } = req.params;
      await sowService.deleteTranscript(projectId, transcriptId, req.user.companyId);
      return res.json({ success: true });
    } catch (error) {
      return this._handleError(req, res, error, 'deleteTranscript');
    }
  }

  async deleteProject(req, res) {
    try {
      const { projectId } = req.params;
      await sowService.deleteProject(projectId, req.user.companyId);
      return res.json({ success: true });
    } catch (error) {
      return this._handleError(req, res, error, 'deleteProject');
    }
  }

  async generateSow(req, res) {
    try {
      const { projectId } = req.params;
      const {
        transcriptIds,
        specialInstructions,
        notes,
        includeMaterials,
        includeEstimate,
      } = req.body;
      if (!Array.isArray(transcriptIds) || transcriptIds.length === 0) {
        return res.status(400).json({
          success: false,
          message: 'transcriptIds must be a non-empty array of transcript IDs.',
        });
      }
      const sowSettings = {
        specialInstructions: typeof specialInstructions === 'string' ? specialInstructions.trim() : '',
        notes: typeof notes === 'string' ? notes.trim() : '',
        includeMaterials: includeMaterials !== false,
        includeEstimate: includeEstimate !== false,
      };
      const sow = await sowService.generateSow(
        projectId,
        transcriptIds,
        req.user.companyId,
        sowSettings,
      );
      // Deduct 3 credits for every AI SOW generation.
      const billingUid = await resolveBillingUid(req);
      spendCredits(billingUid, CREDIT_COSTS.sow_generation, {
        actionType: 'sow_generation',
        projectId,
        companyId: req.user.companyId,
      }).catch((err) => console.error('[credits] sow_generation spend failed:', err));
      return res.json({ success: true, sow });
    } catch (error) {
      return this._handleError(req, res, error, 'generateSow');
    }
  }

  async listSowDocuments(req, res) {
    try {
      const documents = await sowService.listSowDocuments(req.params.projectId, req.user.companyId);
      return res.json({ success: true, documents });
    } catch (error) {
      return this._handleError(req, res, error, 'listSowDocuments');
    }
  }

  async getSowDocument(req, res) {
    try {
      const { projectId, sowDocId } = req.params;
      const document = await sowService.getSowDocument(projectId, sowDocId, req.user.companyId);
      if (!document) {
        return res.status(404).json({ success: false, message: 'Document not found.' });
      }
      return res.json({ success: true, document });
    } catch (error) {
      return this._handleError(req, res, error, 'getSowDocument');
    }
  }

  async saveSowDocument(req, res) {
    try {
      const { projectId, sowDocId } = req.params;
      const { title, content, transcriptIds, frameUrls, pdfData } = req.body;
      if (!content || !String(content).trim()) {
        return res.status(400).json({ success: false, message: 'content is required.' });
      }
      const { document, created } = await sowService.saveSowDocument({
        projectId,
        id: sowDocId ?? null,
        title: String(title || '').trim() || 'Untitled SOW',
        content: String(content),
        transcriptIds: Array.isArray(transcriptIds) ? transcriptIds : [],
        frameUrls: Array.isArray(frameUrls) ? frameUrls : [],
        pdfData: pdfData && typeof pdfData === 'object' ? pdfData : null,
        createdBy: req.user.uid,
        companyId: req.user.companyId,
      });
      if (created) {
        const billingUid = await resolveBillingUid(req);
        spendCredits(billingUid, CREDIT_COSTS.sow_document, {
          actionType: 'sow_document',
          projectId,
          companyId: req.user.companyId,
        }).catch((err) => console.error('[credits] sow_document spend failed:', err));
      }
      return res.status(created ? 201 : 200).json({ success: true, document });
    } catch (error) {
      return this._handleError(req, res, error, 'saveSowDocument');
    }
  }

  async deleteSowDocument(req, res) {
    try {
      const { projectId, sowDocId } = req.params;
      await sowService.deleteSowDocument(projectId, sowDocId, req.user.companyId);
      return res.json({ success: true });
    } catch (error) {
      return this._handleError(req, res, error, 'deleteSowDocument');
    }
  }

  async listPdfDocuments(req, res) {
    try {
      const documents = await sowService.listPdfDocuments(req.params.projectId, req.user.companyId);
      return res.json({ success: true, documents });
    } catch (error) {
      return this._handleError(req, res, error, 'listPdfDocuments');
    }
  }

  async getPdfDocument(req, res) {
    try {
      const { projectId, pdfDocId } = req.params;
      const document = await sowService.getPdfDocument(projectId, pdfDocId, req.user.companyId);
      if (!document) {
        return res.status(404).json({ success: false, message: 'PDF document not found.' });
      }
      return res.json({ success: true, document });
    } catch (error) {
      return this._handleError(req, res, error, 'getPdfDocument');
    }
  }

  async savePdfDocument(req, res) {
    try {
      const { projectId, pdfDocId } = req.params;
      const { title, pdfData } = req.body;
      if (!pdfData || typeof pdfData !== 'object') {
        return res.status(400).json({ success: false, message: 'pdfData is required.' });
      }
      const { document, created } = await sowService.savePdfDocument({
        projectId,
        id: pdfDocId,
        title: title || 'Untitled PDF',
        pdfData,
        createdBy: req.user.uid,
        companyId: req.user.companyId,
      });
      if (created) {
        const billingUid = await resolveBillingUid(req);
        spendCredits(billingUid, CREDIT_COSTS.pdf_document, {
          actionType: 'pdf_document',
          projectId,
          companyId: req.user.companyId,
        }).catch((err) => console.error('[credits] pdf_document spend failed:', err));
      }
      return res.status(created ? 201 : 200).json({ success: true, document });
    } catch (error) {
      return this._handleError(req, res, error, 'savePdfDocument');
    }
  }

  async deletePdfDocument(req, res) {
    try {
      const { projectId, pdfDocId } = req.params;
      await sowService.deletePdfDocument(projectId, pdfDocId, req.user.companyId);
      return res.json({ success: true });
    } catch (error) {
      return this._handleError(req, res, error, 'deletePdfDocument');
    }
  }

  async listTemplates(req, res) {
    try {
      const templates = await sowService.listTemplates(req.user.companyId);
      return res.json({ success: true, templates });
    } catch (error) {
      return this._handleError(req, res, error, 'listTemplates');
    }
  }

  async saveTemplate(req, res) {
    try {
      const { name, content } = req.body;
      if (!content || !String(content).trim()) {
        return res.status(400).json({ success: false, message: 'content is required.' });
      }
      if (!name || !String(name).trim()) {
        return res.status(400).json({ success: false, message: 'name is required.' });
      }
      const { template, created } = await sowService.saveTemplate({
        companyId: req.user.companyId,
        name: String(name).trim(),
        content: String(content),
        createdBy: req.user.uid,
      });
      return res.status(created ? 201 : 200).json({ success: true, template });
    } catch (error) {
      return this._handleError(req, res, error, 'saveTemplate');
    }
  }

  async deleteTemplate(req, res) {
    try {
      const { templateId } = req.params;
      await sowService.deleteTemplate(templateId, req.user.companyId);
      return res.json({ success: true });
    } catch (error) {
      return this._handleError(req, res, error, 'deleteTemplate');
    }
  }

  async structureSow(req, res) {
    try {
      const { sowText, instructions = '' } = req.body;
      if (!sowText?.trim()) {
        return res.status(400).json({ success: false, message: 'sowText is required.' });
      }
      const result = await sowService.structureSow(sowText, instructions);
      return res.json({ success: true, ...result });
    } catch (error) {
      return this._handleError(req, res, error, 'structureSow');
    }
  }

  _handleError(req, res, error, action) {
    console.error([
      `[${req.requestId || 'no-request-id'}] ${action} failed`,
      `  message: ${error.message || 'Unknown error'}`,
      error.stack ? `  stack: ${error.stack}` : null,
    ].filter(Boolean).join('\n'));

    return res.status(error.status || 500).json({
      success: false,
      message: error.message || 'Something went wrong while handling SOW audio.',
    });
  }
}

export const sowController = new SowController();
