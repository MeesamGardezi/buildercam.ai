// Purpose: AI-driven PDF layout generation. Gemini emits a full elements[]
// array (coordinates, sizes, colours, content) ready to render or load into
// the PdfEditorWidget. When a PDF template is supplied, its structural
// elements (logos, images, shapes, dividers, containers, signature blocks)
// are handed to Gemini verbatim so branding is preserved while the AI lays
// out the SOW content around them.

const A4_WIDTH = 595;
const A4_HEIGHT = 842;

// Element types the template may contribute as "structural" — these carry
// branding/layout identity and are preserved as-is by the model.
const STRUCTURAL_TYPES = new Set([
  'logo',
  'image',
  'shape',
  'divider',
  'container',
  'signature_block',
]);

/**
 * Pulls the renderable element list + page size out of a PDF template object.
 * Accepts either the raw template ({ pdfJson: { elements, pageSize } }) or an
 * already-unwrapped { elements, pageSize } shape. Returns null when nothing
 * usable is present.
 */
function _extractTemplateLayout(pdfTemplate) {
  if (!pdfTemplate || typeof pdfTemplate !== 'object') return null;

  const json =
    pdfTemplate.pdfJson && typeof pdfTemplate.pdfJson === 'object'
      ? pdfTemplate.pdfJson
      : pdfTemplate;

  const elements = Array.isArray(json.elements) ? json.elements : [];
  const pageSize =
    json.pageSize && typeof json.pageSize === 'object'
      ? {
          width: Number(json.pageSize.width) || A4_WIDTH,
          height: Number(json.pageSize.height) || A4_HEIGHT,
        }
      : { width: A4_WIDTH, height: A4_HEIGHT };

  return { elements, pageSize, name: pdfTemplate.name ?? json.name ?? '' };
}

/**
 * Splits template elements into the structural set to preserve and a list of
 * the template's existing text elements (used only as styling reference for
 * the model — their content is replaced by SOW content).
 *
 * Structural elements have their `src` field stripped before being sent to
 * Gemini — base64 image data can be 40 k+ chars and causes output truncation.
 * The original src values are preserved in a lookup map (srcById) so they can
 * be re-attached to the AI's output after parsing.
 */
function _partitionTemplateElements(elements) {
  const structural = [];
  const textRefs = [];
  // id → original src string (only for elements that carried one)
  const srcById = {};

  for (const el of elements) {
    if (!el || typeof el !== 'object' || !el.type) continue;
    if (STRUCTURAL_TYPES.has(el.type)) {
      // Stash the original src before stripping it from the prompt copy.
      if (el.src) srcById[String(el.id)] = el.src;
      // Send a lightweight copy to Gemini — no base64 image data.
      const slimEl = Object.assign({}, el);
      delete slimEl.src;
      structural.push(slimEl);
    } else if (el.type === 'text') {
      textRefs.push(el);
    }
  }
  return { structural, textRefs, srcById };
}

/**
 * Builds the Gemini prompt instructing it to emit a full elements[] array.
 */
function _formatDate(d) {
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return `${d.getDate()} ${months[d.getMonth()]} ${d.getFullYear()}`;
}

function _buildLayoutPrompt({
  sowText,
  projectName,
  clientName,
  siteLocation,
  instructions,
  pageSize,
  templateLayout,
}) {
  const lines = [];
  const today = _formatDate(new Date());

  lines.push(
    'You are a professional document layout engine. You produce print-ready PDF',
    'layouts as a flat JSON array of absolutely-positioned elements for a',
    'construction "Scope of Work" (SOW) document.',
    '',
    `PAGE SIZE: ${pageSize.width} wide × ${pageSize.height} tall (points, A4 portrait).`,
    'COORDINATE SYSTEM: origin (0,0) is the TOP-LEFT corner. x increases right,',
    'y increases downward. Every element must fit fully inside the page:',
    `0 ≤ x and x + width ≤ ${pageSize.width}; 0 ≤ y and y + height ≤ ${pageSize.height}.`,
    'Use a 44pt left/right margin for body content (content width ≈',
    `${pageSize.width - 88}pt) unless a template element dictates otherwise.`,
    '',
    'PROJECT DETAILS:',
    `  Project : ${projectName || ''}`,
    `  Client  : ${clientName || ''}`,
  );
  if (siteLocation) lines.push(`  Site    : ${siteLocation}`);
  lines.push(`  Date    : ${today}`,
    '  (Use this exact date wherever a document date, issue date, or "Date:" field appears.)',
  );

  lines.push('', 'SOW CONTENT (lay this out in full — do not omit sections):', '', sowText.trim());

  if (instructions && instructions.trim()) {
    lines.push('', 'ADDITIONAL INSTRUCTIONS (follow carefully):', instructions.trim());
  }

  // ── Element schema ────────────────────────────────────────────────────────
  lines.push(
    '',
    'ELEMENT SCHEMA — every element is an object with these common fields:',
    '  "id": string (unique, e.g. "el-1")',
    '  "type": one of "text" | "divider" | "shape" | "table"',
    '  "x", "y", "width", "height": numbers (points, top-left origin)',
    '  "zIndex": integer (draw order, higher = on top)',
    '  "locked": boolean (use true for header/branding blocks)',
    '  "visible": true',
    '',
    'Type-specific fields:',
    '  text:    "content": string (use "\\n" for line breaks),',
    '           "style": { "fontSize": number, "fontWeight": 400|700,',
    '             "color": int ARGB, "textAlign": "left"|"center"|"right",',
    '             "lineHeight": number (~1.4), "letterSpacing": number,',
    '             "backgroundColor": int ARGB (optional, for banners) }',
    '  divider: "orientation": "horizontal"|"vertical", "thickness": number,',
    '           "color": int ARGB, "dashStyle": "solid"|"dashed"|"dotted"',
    '  shape:   "shapeKind": "rectangle"|"ellipse", "fillColor": int ARGB,',
    '           "borderColor": int ARGB, "borderWidth": number, "borderRadius": number',
    '  table:   "tableData": { "headers": [string...], "rows": [[string...]...] },',
    '           "tablestyle": { "headerBg": int ARGB, "borderColor": int ARGB,',
    '             "cellPadding": number, "alternateRows": boolean,',
    '             "alternateRowColor": int ARGB }',
    '',
    'COLOURS are 32-bit ARGB INTEGERS (alpha in the top byte). Examples:',
    '  white (0xFFFFFFFF) = 4294967295, near-black body (0xFF0F172A) = 4279179050,',
    '  brand blue (0xFF0284C7) = 4278355143, navy banner (0xFF0C1A3A) = 4278983226,',
    '  light border (0xFFCBD5E1) = 4291548641.',
    'Always include full opacity (0xFF) alpha. Never output hex strings — integers only.',
  );

  // ── Template handling ───────────────────────────────────────────────────
  if (templateLayout && templateLayout.structural.length > 0) {
    lines.push(
      '',
      '════════ TEMPLATE: PRESERVE BRANDING ════════',
      `A template named "${templateLayout.name || 'template'}" is provided. You MUST`,
      'include the following structural elements EXACTLY as given (same id, type,',
      'x, y, width, height, colours). Image src values are stripped here to save',
      'space — they will be restored automatically after you respond, so do NOT',
      'include a src field for logo/image elements. Copy all other fields verbatim',
      'into your output, then lay out the SOW text content around/below them',
      'without overlapping:',
      '',
      JSON.stringify(templateLayout.structural, null, 1),
    );
    if (templateLayout.textRefs.length > 0) {
      lines.push(
        '',
        'The template also contains these text blocks. Reuse their POSITION and',
        'STYLE as a guide for headings/labels, but REPLACE their content with the',
        'matching SOW content:',
        '',
        JSON.stringify(
          templateLayout.textRefs.map((t) => ({
            x: t.x, y: t.y, width: t.width, height: t.height,
            style: t.style ?? null,
            originalContent: t.content ?? '',
          })),
          null,
          1,
        ),
      );
    }
    lines.push('════════════════════════════════════════════', '');
  } else {
    lines.push(
      '',
      'No template provided. Design a clean, professional layout yourself: a',
      'header banner with the project/client name (locked), section headings in',
      'brand blue with a thin accent rule, body text in near-black, and a closing',
      'signature area. Keep generous spacing and never overlap elements.',
    );
  }

  lines.push(
    '',
    'OUTPUT RULES:',
    '- Stack content vertically in reading order; never overlap text blocks.',
    '- Estimate text height from content length so blocks do not collide',
    `  (≈ ${pageSize.width - 88}pt wide fits ~90 chars per line at fontSize 10;`,
    '  height ≈ lines × fontSize × lineHeight + 8).',
    '- If content exceeds one page height, continue stacking with increasing y;',
    `  the canvas scrolls (do not clamp at ${pageSize.height}).`,
    '- Return ONLY a JSON object, no markdown/code fences/explanations:',
    '{ "pageSize": { "width": number, "height": number }, "elements": [ ... ] }',
  );

  return lines.join('\n');
}

/**
 * Generates a complete PDF layout (elements + pageSize) from SOW text via
 * Gemini. Mix this into SowService.
 *
 * @param {object} opts
 * @param {string} opts.sowText        - The full SOW plain text.
 * @param {string} [opts.projectName]
 * @param {string} [opts.clientName]
 * @param {string} [opts.siteLocation]
 * @param {string} [opts.instructions] - Optional extra user instructions.
 * @param {object} [opts.pdfTemplate]  - Optional PDF template ({ pdfJson, name }).
 * @returns {Promise<{ pageSize: {width:number,height:number}, elements: object[] }>}
 */
export async function generatePdfLayout({
  sowText,
  projectName = '',
  clientName = '',
  siteLocation = '',
  instructions = '',
  pdfTemplate = null,
}) {
  if (!sowText || !String(sowText).trim()) {
    throw Object.assign(new Error('sowText is required.'), { status: 400 });
  }

  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) throw new Error('GEMINI_API_KEY is not configured on the server.');
  const model = process.env.GEMINI_MODEL || 'gemini-2.5-flash';

  const templateLayout = _extractTemplateLayout(pdfTemplate);
  const pageSize = templateLayout?.pageSize ?? { width: A4_WIDTH, height: A4_HEIGHT };

  // srcById maps element id → original src string so we can restore image
  // data after Gemini returns (it never sees the base64 payload).
  let srcById = {};
  if (templateLayout) {
    const partitioned = _partitionTemplateElements(templateLayout.elements);
    templateLayout.structural = partitioned.structural;
    templateLayout.textRefs = partitioned.textRefs;
    srcById = partitioned.srcById;
  }

  const prompt = _buildLayoutPrompt({
    sowText: String(sowText),
    projectName,
    clientName,
    siteLocation,
    instructions,
    pageSize,
    templateLayout,
  });

  const resp = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        // 65536 tokens gives ~50 k output chars — enough for a full SOW layout
        // even with many sections. 8192 caused truncation when templates with
        // large base64 images were included in the prompt.
        generationConfig: { temperature: 0.15, maxOutputTokens: 65536 },
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

  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error(`Gemini returned non-JSON layout. Raw: ${raw.slice(0, 200)}`);
  }

  const elements = Array.isArray(parsed.elements) ? parsed.elements : [];
  if (elements.length === 0) {
    throw new Error('Gemini returned a layout with no elements.');
  }

  // Re-attach original src values that were stripped before sending to Gemini.
  // Gemini copies the structural elements by id, so we match on id here.
  if (Object.keys(srcById).length > 0) {
    for (const el of elements) {
      if (el && el.id && srcById[String(el.id)]) {
        el.src = srcById[String(el.id)];
      }
    }
  }

  const outPageSize =
    parsed.pageSize && typeof parsed.pageSize === 'object'
      ? {
          width: Number(parsed.pageSize.width) || pageSize.width,
          height: Number(parsed.pageSize.height) || pageSize.height,
        }
      : pageSize;

  return { pageSize: outPageSize, elements };
}