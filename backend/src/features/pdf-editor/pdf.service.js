import {
  PDFDocument,
  StandardFonts,
  rgb,
  pushGraphicsState,
  popGraphicsState,
  concatTransformationMatrix,
} from 'pdf-lib';
import axios from 'axios';
import { normalizeTemplateLayoutForRender } from './template_layout.service.js';

// ── Font cache ────────────────────────────────────────────────────────────────
// Fonts are fetched once at startup and held in memory.

const FONT_URLS = {
  Roboto: 'https://fonts.gstatic.com/s/roboto/v32/KFOmCnqEu92Fr1Mu4mxK.woff2',
  RobotoBold: 'https://fonts.gstatic.com/s/roboto/v32/KFOlCnqEu92Fr1MmEU9fBBc4.woff2',
  RobotoMono: 'https://fonts.gstatic.com/s/robotomono/v23/L0xuDF4xlVMF-BfR8bXMIhJHg45mwgGEFl0_3vq_ROW4.woff2',
};

const fontCache = {};

async function loadFonts(pdfDoc) {
  const embedded = {};

  for (const [name, url] of Object.entries(FONT_URLS)) {
    try {
      if (!fontCache[name]) {
        const res = await axios.get(url, { responseType: 'arraybuffer', timeout: 5000 });
        fontCache[name] = new Uint8Array(res.data);
      }
      embedded[name] = await pdfDoc.embedFont(fontCache[name]);
    } catch {
      // Fall back to Helvetica if network fetch fails
    }
  }

  // Guaranteeed fallback fonts (built into pdf-lib)
  if (!embedded.Helvetica) {
    embedded.Helvetica = await pdfDoc.embedFont(StandardFonts.Helvetica);
    embedded.HelveticaBold = await pdfDoc.embedFont(StandardFonts.HelveticaBold);
    embedded.Courier = await pdfDoc.embedFont(StandardFonts.Courier);
  }

  return embedded;
}

// ── Y-axis coordinate flip ────────────────────────────────────────────────────
// Canvas origin: top-left.  PDF origin: bottom-left.
function pdfY(canvasY, elementHeight, pageHeight) {
  return pageHeight - canvasY - elementHeight;
}

// ── Colour helpers ────────────────────────────────────────────────────────────
function argbToRgb(argb) {
  const r = ((argb >> 16) & 0xff) / 255;
  const g = ((argb >> 8) & 0xff) / 255;
  const b = (argb & 0xff) / 255;
  return rgb(r, g, b);
}

function safePdfText(textValue) {
  return String(textValue ?? '')
    .replace(/\u2610/g, '[ ]')
    .replace(/[\u2611\u2612]/g, '[x]')
    .replace(/[✓✔]/g, 'x')
    .replace(/[–—]/g, '-')
    .replace(/[‘’]/g, "'")
    .replace(/[“”]/g, '"')
    .replace(/•/g, '-')
    .replace(/×/g, 'x')
    .replace(/²/g, '2')
    .replace(/\u00a0/g, ' ')
    .replace(/[^\n\r\t\x20-\x7e]/g, '?');
}

function isBoldFont(weightValue) {
  const raw = Number(weightValue);
  if (!Number.isFinite(raw)) return false;
  if (raw >= 100) return raw >= 600; // CSS weight
  return raw >= 5; // Flutter FontWeight index (w600+)
}

function parseTextAlign(alignValue) {
  if (typeof alignValue === 'string') {
    const normalized = alignValue.toLowerCase();
    if (normalized === 'center') return 'center';
    if (normalized === 'right' || normalized === 'end') return 'right';
    if (normalized === 'justify') return 'justify';
    return 'left';
  }
  const raw = Number(alignValue);
  if (!Number.isFinite(raw)) return 'left';
  if (raw === 1) return 'right';
  if (raw === 2) return 'center';
  if (raw === 3) return 'justify';
  return 'left';
}

function resolveFont(style, fonts) {
  const family = String(style?.fontFamily ?? '').toLowerCase();
  const wantsMono = family.includes('mono');
  const bold = isBoldFont(style?.fontWeight);

  if (wantsMono) {
    return fonts.RobotoMono ?? fonts.Courier ?? fonts.Helvetica;
  }

  if (bold) {
    return fonts.RobotoBold ?? fonts.HelveticaBold ?? fonts.Helvetica;
  }
  return fonts.Roboto ?? fonts.Helvetica;
}

function wrapText(textValue, font, fontSize, maxWidth) {
  const text = safePdfText(textValue);
  const lines = [];

  for (const paragraph of text.split('\n')) {
    const words = paragraph.trim().split(/\s+/).filter(Boolean);
    if (words.length === 0) {
      lines.push('');
      continue;
    }

    let current = '';
    for (const word of words) {
      const candidate = current ? `${current} ${word}` : word;
      if (font.widthOfTextAtSize(candidate, fontSize) <= maxWidth) {
        current = candidate;
        continue;
      }

      if (current) lines.push(current);
      if (font.widthOfTextAtSize(word, fontSize) <= maxWidth) {
        current = word;
        continue;
      }

      let chunk = '';
      for (const char of word) {
        const nextChunk = `${chunk}${char}`;
        if (font.widthOfTextAtSize(nextChunk, fontSize) <= maxWidth) {
          chunk = nextChunk;
        } else {
          if (chunk) lines.push(chunk);
          chunk = char;
        }
      }
      current = chunk;
    }

    if (current) lines.push(current);
  }

  return lines.length ? lines : [''];
}

// ── Main generator ────────────────────────────────────────────────────────────

/**
 * Generates a PDF from an array of canvas elements and returns the PDF bytes.
 * @param {Object[]} elements — sorted by zIndex ascending before calling
 * @param {{ width: number, height: number }} pageSize
 * @returns {Promise<Uint8Array>}
 */
export async function generatePdf(elements, pageSize) {
  const normalized = normalizeTemplateLayoutForRender(elements, pageSize);
  elements = normalized.elements;
  pageSize = normalized.pageSize;

  const pdfDoc = await PDFDocument.create();
  const page = pdfDoc.addPage([pageSize.width, pageSize.height]);
  const fonts = await loadFonts(pdfDoc);
  const pageH = pageSize.height;

  const sorted = [...elements].sort((a, b) => (a.zIndex ?? 0) - (b.zIndex ?? 0));

  for (const el of sorted) {
    if (el.visible === false) continue;

    const y = pdfY(el.y, el.height, pageH);
    const rotation = ((el.rotation ?? 0) % 360 + 360) % 360;
    const rotated = rotation !== 0;

    // Rotate around the element's centre by pushing a transformation matrix
    // onto the graphics state for the duration of the draw.
    if (rotated) {
      const cx = el.x + el.width / 2;
      const cy = y + el.height / 2;
      const rad = (rotation * Math.PI) / 180;
      const cos = Math.cos(rad);
      const sin = Math.sin(rad);
      page.pushOperators(
        pushGraphicsState(),
        // Translate to centre, rotate, translate back — composed inline.
        // Equivalent to:  T(cx,cy) · R(rad) · T(-cx,-cy)
        concatTransformationMatrix(
          cos,
          sin,
          -sin,
          cos,
          cx - cx * cos + cy * sin,
          cy - cx * sin - cy * cos,
        ),
      );
    }

    switch (el.type) {
      case 'text':
        await drawText(page, el, y, fonts);
        break;
      case 'image':
      case 'logo':
        await drawImage(pdfDoc, page, el, y);
        break;
      case 'table':
        await drawTable(page, el, y, fonts, pageH);
        break;
      case 'signature_block':
        drawSignatureBlock(page, el, y, fonts);
        break;
      case 'divider':
        drawDivider(page, el, y);
        break;
      case 'shape':
        drawShape(page, el, y);
        break;
      case 'container':
        drawContainer(page, el, y);
        break;
    }

    if (rotated) {
      page.pushOperators(popGraphicsState());
    }
  }

  return pdfDoc.save();
}

// ── Element renderers ─────────────────────────────────────────────────────────

async function drawText(page, el, y, fonts) {
  const style = el.style ?? {};
  const font = resolveFont(style, fonts);

  const fontSize = style.fontSize ?? 12;
  const color = style.color ? argbToRgb(style.color) : rgb(0, 0, 0);
  const content = el.content ?? '';
  const textAlign = parseTextAlign(style.textAlign);

  if (style.backgroundColor) {
    page.drawRectangle({
      x: el.x,
      y,
      width: el.width,
      height: el.height,
      color: argbToRgb(style.backgroundColor),
    });
  }

  const lines = wrapText(content, font, fontSize, el.width);
  const lineH = fontSize * (style.lineHeight ?? 1.4);
  const blockHeight = lineH * lines.length;
  let currentY = y + (el.height + blockHeight) / 2 - fontSize;

  for (const line of lines) {
    if (currentY < y) break;
    const lineWidth = font.widthOfTextAtSize(line, fontSize);
    let lineX = el.x;
    if (textAlign === 'center') {
      lineX = el.x + (el.width - lineWidth) / 2;
    } else if (textAlign === 'right') {
      lineX = el.x + el.width - lineWidth;
    }
    if (lineX < el.x) lineX = el.x;
    try {
      page.drawText(line, {
        x: lineX,
        y: currentY,
        size: fontSize,
        font,
        color,
      });
    } catch { /* skip if font doesn't support the char */ }
    currentY -= lineH;
  }
}

async function drawImage(pdfDoc, page, el, y) {
  if (!el.src || el.src === '') return;

  try {
    let bytes;
    let isPng = false;

    if (el.src.startsWith('data:')) {
      // data:image/png;base64,<data>  or  data:image/jpeg;base64,<data>
      const [header, b64] = el.src.split(',');
      isPng = header.includes('png');
      bytes = new Uint8Array(Buffer.from(b64, 'base64'));
    } else {
      const res = await axios.get(el.src, { responseType: 'arraybuffer', timeout: 8000 });
      bytes = new Uint8Array(res.data);
      isPng = (res.headers['content-type'] ?? '').includes('png');
    }

    const img = isPng
      ? await pdfDoc.embedPng(bytes)
      : await pdfDoc.embedJpg(bytes);

    const opacity = el.opacity ?? 1;
    page.drawImage(img, {
      x: el.x,
      y,
      width: el.width,
      height: el.height,
      opacity,
    });
  } catch {
    // Image unavailable — draw placeholder rectangle
    page.drawRectangle({
      x: el.x,
      y,
      width: el.width,
      height: el.height,
      color: rgb(0.95, 0.95, 0.95),
      borderColor: rgb(0.8, 0.8, 0.8),
      borderWidth: 0.5,
    });
  }
}

async function drawTable(page, el, topY, fonts, pageH) {
  const td = el.tableData ?? { headers: [], rows: [] };
  const ts = el.tablestyle ?? {};
  const font = fonts.Roboto ?? fonts.Helvetica;
  const boldFont = fonts.RobotoBold ?? fonts.HelveticaBold ?? fonts.Helvetica;
  const headers = td.headers ?? [];
  const rows = td.rows ?? [];

  const colCount = headers.length;
  if (colCount === 0) return;

  const colWidth = el.width / colCount;
  const rowCount = rows.length + 1;
  const rowHeight = el.height / rowCount;
  const maxPad = rowHeight * 0.18;
  const cellPad = maxPad < 2
    ? Math.max(0.5, maxPad)
    : Math.min(Math.max(ts.cellPadding ?? 6, 2), maxPad);
  const headerFontSize = Math.min(12, Math.max(8, rowHeight - cellPad * 2));
  const bodyFontSize = Math.min(11, Math.max(7, rowHeight - cellPad * 2));
  const lineHeight = 1.0;
  const headerBg = ts.headerBg ? argbToRgb(ts.headerBg) : rgb(0.01, 0.52, 0.78);
  const borderColor = ts.borderColor ? argbToRgb(ts.borderColor) : rgb(0.8, 0.8, 0.8);
  const altColor = ts.alternateRowColor ? argbToRgb(ts.alternateRowColor) : rgb(0.97, 0.98, 0.98);

  const drawCellText = (text, cx, rowY, rowHeight, fontToUse, fontSize, color) => {
    const lines = wrapText(text ?? '', fontToUse, fontSize, colWidth - cellPad * 2);
    let textY = rowY + rowHeight - cellPad - fontSize;
    for (const line of lines) {
      if (textY < rowY + cellPad - fontSize * 0.2) break;
      try {
        page.drawText(line, {
          x: cx + cellPad,
          y: textY,
          size: fontSize,
          font: fontToUse,
          color,
        });
      } catch { /* skip unsupported glyphs */ }
      textY -= fontSize * lineHeight;
    }
  };

  let currentTop = topY + el.height;

  // Header row
  const headerHeight = rowHeight;
  const headerY = currentTop - headerHeight;
  for (let col = 0; col < colCount; col++) {
    const cx = el.x + col * colWidth;
    page.drawRectangle({
      x: cx, y: headerY, width: colWidth, height: headerHeight,
      color: headerBg, borderColor, borderWidth: 0.75,
    });
    drawCellText(headers[col], cx, headerY, headerHeight, boldFont, headerFontSize, rgb(1, 1, 1));
  }
  currentTop = headerY;

  // Data rows
  for (let row = 0; row < rows.length; row++) {
    const rowBg = ts.alternateRows && row % 2 === 1 ? altColor : null;
    const rowCells = rows[row] ?? [];
    const rowY = currentTop - rowHeight;
    if (rowY < topY - 0.5) break;

    for (let col = 0; col < colCount; col++) {
      const cx = el.x + col * colWidth;
      page.drawRectangle({
        x: cx, y: rowY, width: colWidth, height: rowHeight,
        ...(rowBg ? { color: rowBg } : {}),
        borderColor, borderWidth: 0.75,
      });
      drawCellText(rowCells[col], cx, rowY, rowHeight, font, bodyFontSize, rgb(0.06, 0.09, 0.16));
    }
    currentTop = rowY;
    if (currentTop < 0) break;
  }
}

function drawSignatureBlock(page, el, y, fonts) {
  const font = fonts.Roboto ?? fonts.Helvetica;
  const labelColor = rgb(0.28, 0.33, 0.40);
  const lineColor = rgb(0.40, 0.44, 0.50);
  const textColor = rgb(0.06, 0.09, 0.16);

  const drawField = ({ label, value, baselineY, maxLineWidth }) => {
    const safeLabel = safePdfText(label || 'Signature');
    const safeValue = safePdfText(value || '');
    const labelText = `${safeLabel}:`;
    const labelWidth = font.widthOfTextAtSize(labelText, 9);
    const lineStart = el.x + labelWidth + 8;
    const lineEnd = Math.min(el.x + el.width, lineStart + maxLineWidth);

    page.drawText(labelText, {
      x: el.x,
      y: baselineY - 2,
      size: 9,
      font,
      color: labelColor,
    });

    if (safeValue.trim()) {
      page.drawText(safeValue, {
        x: lineStart,
        y: baselineY - 2,
        size: 9,
        font,
        color: textColor,
        maxWidth: Math.max(12, lineEnd - lineStart),
      });
    } else {
      page.drawLine({
        start: { x: lineStart, y: baselineY },
        end: { x: lineEnd, y: baselineY },
        thickness: 0.75,
        color: lineColor,
      });
    }
  };

  drawField({
    label: el.signatureLabel,
    value: el.signatureValue,
    baselineY: y + 26,
    maxLineWidth: el.width,
  });
  drawField({
    label: el.dateLabel || 'Date',
    value: el.dateValue,
    baselineY: y + 8,
    maxLineWidth: el.width * 0.6,
  });
}

function drawDivider(page, el, y) {
  const color = el.color ? argbToRgb(el.color) : rgb(0.8, 0.84, 0.88);
  const thickness = el.thickness ?? 1;
  const isH = el.orientation !== 'vertical';

  if (isH) {
    const midY = y + el.height / 2;
    if (el.dashStyle === 'dashed' || el.dashStyle === 'dotted') {
      const dashLen = el.dashStyle === 'dashed' ? 8 : 2;
      const gap = 4;
      let x = el.x;
      while (x < el.x + el.width) {
        page.drawLine({
          start: { x, y: midY },
          end: { x: Math.min(x + dashLen, el.x + el.width), y: midY },
          thickness, color,
        });
        x += dashLen + gap;
      }
    } else {
      page.drawLine({
        start: { x: el.x, y: midY },
        end: { x: el.x + el.width, y: midY },
        thickness, color,
      });
    }
  } else {
    const midX = el.x + el.width / 2;
    page.drawLine({
      start: { x: midX, y },
      end: { x: midX, y: y + el.height },
      thickness, color,
    });
  }
}

function drawShape(page, el, y) {
  const fillColor = el.fillColor != null ? argbToRgb(el.fillColor) : rgb(0.86, 0.92, 0.99);
  const borderColor = el.borderColor != null ? argbToRgb(el.borderColor) : rgb(0.23, 0.51, 0.96);
  const borderWidth = el.borderWidth ?? 2;
  const opacity = el.opacity ?? 1;
  const kind = el.shapeKind ?? 'rectangle';

  if (kind === 'ellipse') {
    page.drawEllipse({
      x: el.x + el.width / 2,
      y: y + el.height / 2,
      xScale: el.width / 2,
      yScale: el.height / 2,
      color: fillColor,
      borderColor,
      borderWidth,
      opacity,
    });
  } else {
    // rectangle and triangle both fall back to a rectangle in pdf-lib
    // (pdf-lib has no built-in triangle primitive).
    page.drawRectangle({
      x: el.x,
      y,
      width: el.width,
      height: el.height,
      color: fillColor,
      borderColor,
      borderWidth,
      opacity,
    });
  }
}

function drawContainer(page, el, y) {
  const fillColor = el.fillColor != null ? argbToRgb(el.fillColor) : null;
  const borderColor = el.borderColor != null ? argbToRgb(el.borderColor) : rgb(0.58, 0.64, 0.72);
  const borderWidth = el.borderWidth ?? 1;
  const opacity = el.opacity ?? 1;

  page.drawRectangle({
    x: el.x,
    y,
    width: el.width,
    height: el.height,
    ...(fillColor ? { color: fillColor } : {}),
    borderColor,
    borderWidth,
    opacity,
  });
}
