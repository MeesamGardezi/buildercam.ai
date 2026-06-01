/**
 * Validates and normalises an incoming template element object.
 * Throws if required fields are missing or malformed.
 */
export function validateElement(el) {
  const required = ['id', 'type', 'x', 'y', 'width', 'height', 'zIndex'];
  for (const key of required) {
    if (el[key] === undefined || el[key] === null) {
      throw new Error(`Element missing required field: ${key}`);
    }
  }

  const validTypes = ['text', 'image', 'table', 'logo', 'signature_block', 'divider'];
  if (!validTypes.includes(el.type)) {
    throw new Error(`Unknown element type: ${el.type}`);
  }

  return {
    id: String(el.id),
    type: el.type,
    x: Number(el.x),
    y: Number(el.y),
    width: Math.max(Number(el.width), 1),
    height: Math.max(Number(el.height), 1),
    zIndex: Number(el.zIndex) || 0,
    locked: Boolean(el.locked),
    visible: el.visible !== false,
    // type-specific
    ...(el.content !== undefined && { content: String(el.content) }),
    ...(el.style && { style: el.style }),
    ...(el.src !== undefined && { src: String(el.src) }),
    ...(el.opacity !== undefined && { opacity: Math.min(1, Math.max(0, Number(el.opacity))) }),
    ...(el.borderRadius !== undefined && { borderRadius: Number(el.borderRadius) }),
    ...(el.objectFit !== undefined && { objectFit: Number(el.objectFit) }),
    ...(el.tableData && { tableData: el.tableData }),
    ...(el.tablestyle && { tablestyle: el.tablestyle }),
    ...(el.orientation !== undefined && { orientation: el.orientation }),
    ...(el.thickness !== undefined && { thickness: Number(el.thickness) }),
    ...(el.color !== undefined && { color: Number(el.color) }),
    ...(el.dashStyle !== undefined && { dashStyle: el.dashStyle }),
  };
}

export function validateGenerateRequest(body) {
  if (!body?.elements || !Array.isArray(body.elements)) {
    throw new Error('Request body must include an elements array');
  }
  const pageSize = body.pageSize ?? { width: 595, height: 842 };
  const elements = body.elements.map(validateElement);
  return { elements, pageSize };
}
