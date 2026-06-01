import 'dotenv/config';
import { createServer } from 'http';

import app from './app.js';
import { initSocketIO } from './socket.js';

const port = Number(process.env.PORT || 3001);
const httpServer = createServer(app);

initSocketIO(httpServer);

httpServer.listen(port, () => {
  console.log(`BuilderCam SOW API + Socket.IO listening on ${port}`);
});
