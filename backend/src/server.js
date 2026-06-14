import 'dotenv/config';
import { createServer } from 'http';

import app from './app.js';
import { initSocketIO } from './socket.js';
import { initVoiceProxy } from './voice-proxy.js';

const port = Number(process.env.PORT || 3001);
const httpServer = createServer(app);

initSocketIO(httpServer);
initVoiceProxy(httpServer);

httpServer.listen(port, () => {
  console.log(`BuilderCam SOW API + Socket.IO listening on ${port}`);
});
