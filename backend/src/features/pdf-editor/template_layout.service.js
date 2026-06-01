const FLOW_GAP = 8;
const PAGE_MARGIN = 8;
const DEFAULT_PAGE_HEIGHT = 842;
const FLOW_LANE_TOLERANCE = 6;
const FLOW_MIN_OVERLAP_RATIO = 0.25;

function estimateWrappedLines(textValue, width, fontSize) {
  const text = String(textValue ?? '');
  const safeWidth = Math.max(1, width);
  const charsPerLine = Math.max(1, Math.floor(safeWidth / (fontSize * 0.52)));
  let lines = 0;

  for (const paragraph of text.split('\n')) {
    const words = paragraph.trim().split(/\s+/).filter(Boolean);
    if (words.length === 0) {
      lines += 1;
      continue;
    }

    let current = 0;
    for (const word of words) {
      const wordLength = word.length;
      if (current === 0) {
        lines += Math.floor(wordLength / charsPerLine);
        current = wordLength % charsPerLine;
      } else if (current + 1 + wordLength <= charsPerLine) {
        current += 1 + wordLength;
      } else {
        lines += 1;
        lines += Math.floor(wordLength / charsPerLine);
        current = wordLength % charsPerLine;
      }
    }
    if (current > 0) lines += 1;
  }

  return Math.max(1, lines);
}

function estimateTextHeight(el) {
  const style = el.style ?? {};
  const fontSize = style.fontSize ?? 11;
  const lineHeight = style.lineHeight ?? 1.5;
  const lines = estimateWrappedLines(el.content, el.width, fontSize);
  const preferredHeight = lines * fontSize * lineHeight + 4;
  return Math.max(el.height, preferredHeight);
}

function normalizeElementSize(el) {
  if (el.type === 'text') return { ...el, height: estimateTextHeight(el) };
  return { ...el };
}

function rectOf(el) {
  return {
    left: Number(el.x ?? 0),
    top: Number(el.y ?? 0),
    right: Number(el.x ?? 0) + Number(el.width ?? 0),
    bottom: Number(el.y ?? 0) + Number(el.height ?? 0),
    width: Number(el.width ?? 0),
  };
}

function horizontalOverlap(a, b) {
  return Math.max(0, Math.min(a.right, b.right) - Math.max(a.left, b.left));
}

function isInFlowLane(elementRect, anchorRect) {
  const expandedAnchor = {
    ...anchorRect,
    left: anchorRect.left - FLOW_LANE_TOLERANCE,
    right: anchorRect.right + FLOW_LANE_TOLERANCE,
    width: anchorRect.width + FLOW_LANE_TOLERANCE * 2,
  };
  const overlap = horizontalOverlap(elementRect, expandedAnchor);
  if (overlap <= 0) return false;

  const narrowerWidth = Math.min(elementRect.width, expandedAnchor.width);
  if (narrowerWidth <= 0) return false;
  return overlap / narrowerWidth >= FLOW_MIN_OVERLAP_RATIO;
}

function applyAutoFlow(elements, changedId, oldRect, newRect) {
  let next = [...elements];
  let changed = next.find(el => el.id === changedId);
  if (!changed) return next;

  const deltaBottom = newRect.bottom - oldRect.bottom;
  if (deltaBottom < -0.5) {
    next = next.map(el => {
      if (el.id === changedId || el.locked) return el;
      if (!isInFlowLane(rectOf(el), oldRect)) return el;
      if (el.y < oldRect.bottom - 1) return el;
      return {
        ...el,
        y: Math.max(newRect.bottom + FLOW_GAP, el.y + deltaBottom),
      };
    });
    changed = next.find(el => el.id === changedId);
    if (!changed) return next;
  }

  const flowAnchor = rectOf(changed);
  const minCandidateY = Math.min(oldRect.top, newRect.top);
  const candidates = next
    .filter(el =>
      el.id !== changedId &&
      !el.locked &&
      el.y >= minCandidateY - FLOW_GAP &&
      isInFlowLane(rectOf(el), flowAnchor))
    .sort((a, b) => (a.y - b.y) || (a.x - b.x));

  let cursor = changed.y + changed.height + FLOW_GAP;
  let i = 0;
  while (i < candidates.length) {
    const groupY = candidates[i].y;
    const group = [];
    while (i < candidates.length && Math.abs(candidates[i].y - groupY) < 2) {
      group.push(candidates[i]);
      i += 1;
    }

    if (groupY < cursor) {
      let maxBottom = 0;
      for (const groupEl of group) {
        const idx = next.findIndex(candidate => candidate.id === groupEl.id);
        if (idx === -1) continue;
        next[idx] = { ...next[idx], y: cursor };
        maxBottom = Math.max(maxBottom, next[idx].y + next[idx].height);
      }
      cursor = maxBottom + FLOW_GAP;
    } else {
      const maxBottom = group.reduce(
        (bottom, el) => Math.max(bottom, el.y + el.height),
        0,
      );
      cursor = maxBottom + FLOW_GAP;
    }
  }

  return next;
}

export function normalizeTemplateLayoutForRender(elements, pageSize) {
  let next = (elements ?? []).map(el => ({ ...el }));
  const ordered = [...next].sort((a, b) => (a.y - b.y) || (a.x - b.x));

  for (const original of ordered) {
    const idx = next.findIndex(el => el.id === original.id);
    if (idx === -1) continue;
    const before = next[idx];
    const after = normalizeElementSize(before);
    if (after.height === before.height) continue;
    next = [...next];
    next[idx] = after;
    // Auto-flow is intentionally omitted: the frontend already handles layout
    // positioning. Re-running it here would override the user's edits and
    // produce the same layout regardless of what the user changed.
  }

  const contentHeight = next.reduce((maxHeight, el) => {
    const bottom = Number(el.y ?? 0) + Number(el.height ?? 0) + PAGE_MARGIN;
    return Math.max(maxHeight, bottom);
  }, DEFAULT_PAGE_HEIGHT);

  return {
    elements: next,
    pageSize: {
      ...pageSize,
      height: Math.max(
        DEFAULT_PAGE_HEIGHT,
        pageSize?.height ?? 0,
        Math.ceil(contentHeight),
      ),
    },
  };
}
