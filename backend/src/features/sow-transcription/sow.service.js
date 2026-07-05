// Purpose: Handles project and final transcript operations.
import {
  createProject,
  deleteProject as deleteFirestoreProject,
  getProject as getFirestoreProject,
  listProjectTranscripts,
  listProjects,
  saveProjectTranscript,
  deleteProjectTranscript,
  saveSowDocument,
  listSowDocuments,
  getSowDocument,
  deleteSowDocument,
  savePdfDocument,
  listPdfDocuments,
  getPdfDocument,
  deletePdfDocument,
  saveTemplate,
  listTemplates,
  deleteTemplate,
} from '../../services/firestore.service.js';
import { getCompanySettings } from '../auth/auth.service.js';
import { generatePdfLayout } from './generate-pdf-layout.service.js';

class SowService {
  async createProject(project) {
    return createProject(project);
  }

  async listProjects(companyId) {
    return listProjects(companyId);
  }

  async getProject(projectId, companyId) {
    return getFirestoreProject(projectId, companyId);
  }

  async saveTranscript({
    projectId,
    id,
    rawTranscript,
    durationSeconds,
    createdAt,
    createdBy,
    companyId,
    status,
    frameUrls,
    title,
  }) {
    return saveProjectTranscript(
      projectId,
      { id, rawTranscript, durationSeconds, createdAt, createdBy, status, frameUrls, title },
      companyId,
    );
  }

  async listTranscripts(projectId, companyId) {
    return listProjectTranscripts(projectId, 25, companyId);
  }

  async deleteTranscript(projectId, transcriptId, companyId) {
    return deleteProjectTranscript(projectId, transcriptId, companyId);
  }

  async deleteProject(projectId, companyId) {
    return deleteFirestoreProject(projectId, companyId);
  }

  async saveSowDocument({ projectId, id, title, content, transcriptIds, frameUrls, pdfData, createdBy, companyId }) {
    return saveSowDocument(projectId, { id, title, content, transcriptIds, frameUrls, pdfData, createdBy, companyId });
  }

  async getSowDocument(projectId, sowDocId, companyId) {
    return getSowDocument(projectId, sowDocId, companyId);
  }

  async listSowDocuments(projectId, companyId) {
    return listSowDocuments(projectId, companyId);
  }

  async deleteSowDocument(projectId, sowDocId, companyId) {
    return deleteSowDocument(projectId, sowDocId, companyId);
  }

  async savePdfDocument({ projectId, id, title, pdfData, createdBy, companyId }) {
    return savePdfDocument(projectId, { id, title, pdfData, createdBy, companyId });
  }

  async listPdfDocuments(projectId, companyId) {
    return listPdfDocuments(projectId, companyId);
  }

  async getPdfDocument(projectId, pdfDocId, companyId) {
    return getPdfDocument(projectId, pdfDocId, companyId);
  }

  async deletePdfDocument(projectId, pdfDocId, companyId) {
    return deletePdfDocument(projectId, pdfDocId, companyId);
  }

  async saveTemplate({ companyId, name, content, createdBy }) {
    return saveTemplate(companyId, { name, content, createdBy });
  }

  async listTemplates(companyId) {
    return listTemplates(companyId);
  }

  async deleteTemplate(templateId, companyId) {
    return deleteTemplate(templateId, companyId);
  }

  async structureSow(sowText, instructions = '') {
    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) throw new Error('GEMINI_API_KEY is not configured on the server.');
    const model = process.env.GEMINI_MODEL || 'gemini-2.5-flash';

    const instructionBlock = instructions.trim()
      ? `\nSPECIAL INSTRUCTIONS FROM THE USER (apply when structuring):\n${instructions.trim()}\n`
      : '';

    const prompt = `You are a professional document formatter. Convert this Scope of Work plain-text document into a structured JSON representation.${instructionBlock}

SOW TEXT:
${sowText}

Return ONLY a valid JSON object with this exact structure (no markdown, no code fences, no explanations):
{
  "sections": [
    {
      "heading": "1. Project Overview",
      "items": [
        {"type": "paragraph", "text": "paragraph text here"},
        {"type": "bullet",    "text": "bullet item text without leading dash"},
        {"type": "numbered",  "text": "1. full numbered item text"}
      ]
    }
  ]
}

Rules:
- type values must be exactly "paragraph", "bullet", or "numbered"
- Preserve all content verbatim
- Each distinct bullet or numbered item must be a separate item object
- Return ONLY the JSON object`;

    const resp = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
          generationConfig: { temperature: 0.05, maxOutputTokens: 8192 },
        }),
      },
    );

    if (!resp.ok) {
      const body = await resp.text();
      throw new Error(`Gemini error ${resp.status}: ${body}`);
    }

    const data = await resp.json();
    let raw = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? '';
    raw = raw.trim();

    // Strip markdown code fences — Gemini often wraps output in ```json ... ```
    if (raw.startsWith('```')) {
      const nl = raw.indexOf('\n');
      if (nl !== -1) raw = raw.substring(nl + 1);
      const closeIdx = raw.lastIndexOf('```');
      if (closeIdx !== -1) raw = raw.substring(0, closeIdx).trim();
    }

    try {
      return JSON.parse(raw);
    } catch {
      throw new Error(`Gemini returned non-JSON response. Raw: ${raw.slice(0, 200)}`);
    }
  }

  /**
   * Generates a complete, render-ready PDF layout (elements + pageSize) from
   * SOW text using Gemini. When [pdfTemplate] is supplied, its structural
   * branding elements (logos, banners, dividers, signature blocks) are
   * preserved and the AI lays SOW content around them.
   *
   * @param {object} opts
   * @param {string} opts.sowText
   * @param {string} [opts.projectName]
   * @param {string} [opts.clientName]
   * @param {string} [opts.siteLocation]
   * @param {string} [opts.instructions]
   * @param {object} [opts.pdfTemplate]   // { pdfJson, name } or { elements, pageSize }
   * @returns {Promise<{ pageSize: {width:number,height:number}, elements: object[] }>}
   */
  async generatePdfLayout(opts) {
    return generatePdfLayout(opts);
  }

  async generateSow(projectId, transcriptIds, companyId, settings = {}) {
    const [project, allTranscripts, companySettings] = await Promise.all([
      getFirestoreProject(projectId, companyId),
      listProjectTranscripts(projectId, 100, companyId),
      companyId ? getCompanySettings(companyId).catch(() => ({ categories: [], notes: '' })) : Promise.resolve({ categories: [], notes: '' }),
    ]);

    if (!project) {
      throw Object.assign(new Error('Project not found.'), { status: 404 });
    }

    const selected = allTranscripts.filter((t) => transcriptIds.includes(t.id));
    if (selected.length === 0) {
      throw Object.assign(
        new Error('None of the requested transcripts were found for this project.'),
        { status: 400 },
      );
    }

    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) {
      throw new Error('GEMINI_API_KEY is not configured on the server.');
    }

    const model = process.env.GEMINI_MODEL || 'gemini-2.5-flash';
    const mergedSettings = { ...settings, categories: companySettings.categories, categoryNotes: companySettings.notes };
    const prompt = _buildSowPrompt(project, selected, mergedSettings);

    // Collect all unique frame URLs across the selected transcripts.
    const allFrameUrls = [];
    const seenFrameUrls = new Set();
    for (const t of selected) {
      if (Array.isArray(t.frameUrls)) {
        for (const url of t.frameUrls) {
          if (url && !seenFrameUrls.has(url)) {
            seenFrameUrls.add(url);
            allFrameUrls.push(url);
          }
        }
      }
    }

    // Fetch images and encode as base64 for Gemini's multimodal API.
    const imageParts = await _fetchImageParts(allFrameUrls);

    const parts = [{ text: prompt }, ...imageParts];

    const geminiResponse = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: [{ parts }],
          generationConfig: { temperature: 0.2, maxOutputTokens: 8192 },
        }),
      },
    );

    if (!geminiResponse.ok) {
      const body = await geminiResponse.text();
      throw new Error(`Gemini API error ${geminiResponse.status}: ${body}`);
    }

    const data = await geminiResponse.json();
    const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
    if (!text) throw new Error('Gemini returned an empty response.');

    return text;
  }
}

function _formatDate(d) {
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return `${d.getDate()} ${months[d.getMonth()]} ${d.getFullYear()}`;
}

function _buildSowPrompt(project, transcripts, settings = {}) {
  const {
    specialInstructions = '',
    notes = '',
    includeMaterials = true,
    includeEstimate = true,
    categories = [],
    categoryNotes = '',
  } = settings;

  const today = _formatDate(new Date());

  const lines = [
    'You are a professional construction estimator. Generate a detailed, professional Scope of Work (SOW) document based on the following voice recordings captured during a site visit.',
    '',
    'PROJECT DETAILS:',
    `  Project name : ${project.name}`,
    `  Client       : ${project.clientName}`,
  ];
  if (project.siteLocation) lines.push(`  Site         : ${project.siteLocation}`);
  if (project.scopeSummary) lines.push(`  Scope note   : ${project.scopeSummary}`);
  if (project.notes) lines.push(`  Notes        : ${project.notes}`);
  lines.push(
    `  Date         : ${today}`,
    '  (Use this exact date wherever a document date, issue date, or "Date:" field appears. Do not invent or guess a date.)',
  );

  // Company trade categories.
  if (Array.isArray(categories) && categories.length > 0) {
    lines.push('', 'TRADE CATEGORIES (organise the SOW under these trades where applicable):');
    categories.forEach((cat) => lines.push(`  • ${cat}`));
  }
  if (categoryNotes) {
    lines.push('', 'CATEGORY NOTES:', `  ${categoryNotes}`);
  }

  if (specialInstructions) {
    lines.push('', 'SPECIAL INSTRUCTIONS (follow these carefully when generating the SOW):', `  ${specialInstructions}`);
  }
  if (notes) {
    lines.push('', 'ADDITIONAL NOTES:', `  ${notes}`);
  }

  lines.push('', `VOICE RECORDINGS (${transcripts.length}):`);
  transcripts.forEach((t, i) => {
    const label = t.title?.trim() || `Recording ${i + 1}`;
    lines.push('', `── ${label} ──`, t.rawTranscript.trim());
  });

  const sections = [
    '1. Project Overview',
    '2. Scope of Work  (numbered line items, be specific)',
  ];
  let sectionNum = 3;
  if (includeMaterials) {
    sections.push(`${sectionNum++}. Materials Required  (list items with estimated quantities)`);
  }
  if (includeEstimate) {
    sections.push(`${sectionNum++}. Labour Estimate  (tasks and estimated hours)`);
  }
  sections.push(`${sectionNum++}. Exclusions`);
  sections.push(`${sectionNum}. Notes & Assumptions`);

  lines.push(
    '',
    'Generate a structured SOW document with these sections:',
    ...sections,
    '',
    'Be specific and professional. Extract all actionable items from the recordings. Do NOT invent pricing unless explicitly mentioned. Use plain text — no markdown symbols.',
  );

  return lines.join('\n');
}

/**
 * Fetches image URLs and converts them to Gemini inline_data parts.
 * Silently skips any URL that fails to download.
 */
async function _fetchImageParts(urls) {
  if (!urls || urls.length === 0) return [];
  const parts = [];
  for (const url of urls) {
    try {
      const resp = await fetch(url);
      if (!resp.ok) continue;
      const contentType = resp.headers.get('content-type') || 'image/jpeg';
      const mimeType = contentType.split(';')[0].trim();
      // Only include image types supported by Gemini.
      if (!mimeType.startsWith('image/')) continue;
      const buffer = await resp.arrayBuffer();
      const base64 = Buffer.from(buffer).toString('base64');
      parts.push({ inline_data: { mime_type: mimeType, data: base64 } });
    } catch {
      // Skip images that fail to download.
    }
  }
  return parts;
}


export const sowService = new SowService();