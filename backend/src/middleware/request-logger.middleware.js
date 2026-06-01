import { randomUUID } from 'crypto';

const MAX_TEXT_LENGTH = 140;

export function requestLogger(req, res, next) {
  const requestId = randomUUID().slice(0, 8);
  const startedAt = Date.now();

  req.requestId = requestId;

  console.info(_formatRequestLog(requestId, req));

  res.on('finish', () => {
    const durationMs = Date.now() - startedAt;
    console.info(_formatResponseLog(requestId, req, res.statusCode, durationMs));
  });

  next();
}

function _formatRequestLog(requestId, req) {
  const summary = _summarizeRequest(req);
  const lines = [`[${requestId}] REQUEST ${req.method} ${req.originalUrl}`];

  if (Object.keys(summary).length > 0) {
    lines.push(`  details: ${JSON.stringify(summary)}`);
  }

  return lines.join('\n');
}

function _formatResponseLog(requestId, req, statusCode, durationMs) {
  const statusLabel = statusCode >= 400 ? 'ERROR' : 'OK';
  return `[${requestId}] RESPONSE ${statusLabel} ${req.method} ${req.originalUrl} ${statusCode} ${durationMs}ms`;
}

function _summarizeRequest(req) {
  const summary = {};

  if (req.params && Object.keys(req.params).length > 0) {
    summary.params = req.params;
  }

  if (req.query && Object.keys(req.query).length > 0) {
    summary.query = req.query;
  }

  if (req.body && Object.keys(req.body).length > 0) {
    summary.body = _summarizeValue(req.body);
  }

  return summary;
}

function _summarizeValue(value) {
  if (typeof value === 'string') {
    return value.length > MAX_TEXT_LENGTH
      ? `${value.slice(0, MAX_TEXT_LENGTH)}… (${value.length} chars)`
      : value;
  }

  if (Array.isArray(value)) {
    return value.map(_summarizeValue);
  }

  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([key, entryValue]) => [key, _summarizeValue(entryValue)]),
    );
  }

  return value;
}
