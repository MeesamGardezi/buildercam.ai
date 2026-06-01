// Purpose: Configures the Express app for the BuilderCam SOW transcription API.
import cors from 'cors';
import express from 'express';

import authRoutes from './features/auth/auth.routes.js';
import sowRoutes from './features/sow-transcription/sow.routes.js';
import teamSettingsRoutes from './features/team-settings/team-settings.routes.js';
import activityLogsRoutes from './features/activity-logs/activity-logs.routes.js';
import pdfEditorRoutes from './features/pdf-editor/pdf-editor.routes.js';
import creditsRoutes from './features/credits/credits.routes.js';
import { requestLogger } from './middleware/request-logger.middleware.js';

const app = express();

const corsOptions = {
  origin: [
    'https://app.buildercam.ai',
    /^http:\/\/localhost(:\d+)?$/,
  ],
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true,
};

// Explicitly handle OPTIONS pre-flight for all routes before any auth middleware.
app.options('*', cors(corsOptions));
app.use(cors(corsOptions));
// Capture raw body string so Paddle webhook signatures can be verified.
app.use(
  express.json({
    limit: '10mb',
    verify: (req, _res, buf) => {
      req.rawBody = buf.toString('utf8');
    },
  }),
);
app.use(requestLogger);

app.get('/health', (_, res) => {
  res.json({
    success: true,
    message: 'BuilderCam SOW transcription API is healthy.',
  });
});

app.use('/api/auth', authRoutes);
app.use('/api/sow-transcription', sowRoutes);
app.use('/api/team-settings', teamSettingsRoutes);
app.use('/api/activity-logs', activityLogsRoutes);
app.use('/api', pdfEditorRoutes);
app.use('/api/credits', creditsRoutes);

export default app;
