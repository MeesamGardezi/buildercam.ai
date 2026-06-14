// Purpose: WebSocket proxy for the voice assistant — the client connects here
// with its Firebase ID token and the server pipes frames to/from the Gemini
// Live API using the server-side GEMINI_API_KEY, which never leaves the box.
import { WebSocketServer, WebSocket } from 'ws';

import { getFirebaseAdmin } from './config/firebase-admin.js';

const VOICE_PROXY_PATH = '/voice-agent';

const GEMINI_LIVE_URL = (apiKey) =>
  'wss://generativelanguage.googleapis.com/ws/' +
  'google.ai.generativelanguage.v1beta.GenerativeService.' +
  `BidiGenerateContent?key=${apiKey}`;

export function initVoiceProxy(httpServer) {
  const wss = new WebSocketServer({ noServer: true });

  httpServer.on('upgrade', async (req, socket, head) => {
    let url;
    try {
      url = new URL(req.url, 'http://localhost');
    } catch {
      socket.destroy();
      return;
    }
    // Leave non-matching upgrades (i.e. /socket.io/) to their own handlers.
    if (url.pathname !== VOICE_PROXY_PATH) return;

    const idToken = url.searchParams.get('token') || '';
    let user;
    try {
      user = await getFirebaseAdmin().auth().verifyIdToken(idToken);
    } catch {
      socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
      socket.destroy();
      return;
    }
    if (!user?.companyId) {
      socket.write('HTTP/1.1 403 Forbidden\r\n\r\n');
      socket.destroy();
      return;
    }

    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) {
      socket.write('HTTP/1.1 500 Internal Server Error\r\n\r\n');
      socket.destroy();
      return;
    }

    wss.handleUpgrade(req, socket, head, (client) => {
      console.log(`[VoiceProxy] session opened for uid=${user.uid}`);
      pipeToGemini(client, apiKey, user.uid);
    });
  });

  console.log(`[VoiceProxy] listening on ${VOICE_PROXY_PATH}`);
}

function pipeToGemini(client, apiKey, uid) {
  const upstream = new WebSocket(GEMINI_LIVE_URL(apiKey));

  // Frames the client sends before the Gemini socket is open (typically the
  // setup message) are buffered and flushed on open.
  const pending = [];

  upstream.on('open', () => {
    for (const [data, isBinary] of pending) upstream.send(data, { binary: isBinary });
    pending.length = 0;
  });

  client.on('message', (data, isBinary) => {
    if (upstream.readyState === WebSocket.OPEN) {
      upstream.send(data, { binary: isBinary });
    } else if (upstream.readyState === WebSocket.CONNECTING) {
      pending.push([data, isBinary]);
    }
  });

  upstream.on('message', (data, isBinary) => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(data, { binary: isBinary });
    }
  });

  upstream.on('close', (code, reason) => {
    console.log(`[VoiceProxy] gemini closed (${code}) for uid=${uid}`);
    client.close(sanitizeCloseCode(code), reason.toString().slice(0, 120));
  });
  client.on('close', () => {
    console.log(`[VoiceProxy] client closed for uid=${uid}`);
    if (upstream.readyState === WebSocket.OPEN || upstream.readyState === WebSocket.CONNECTING) {
      upstream.close();
    }
  });

  upstream.on('error', (err) => {
    console.error(`[VoiceProxy] gemini error for uid=${uid}:`, err.message);
    client.close(1011, 'Upstream error');
  });
  client.on('error', () => {
    if (upstream.readyState === WebSocket.OPEN) upstream.close();
  });
}

/** ws.close() rejects reserved codes (1005/1006/1015) — map them to 1011. */
function sanitizeCloseCode(code) {
  if (code === 1000 || (code >= 3000 && code <= 4999)) return code;
  if (code >= 1001 && code <= 1013 && code !== 1005 && code !== 1006) return code;
  return 1011;
}
