// One-time setup: configures Firebase Storage CORS so the Flutter web app
// (running on localhost or any origin) can load frame thumbnails via XHR.
// Run once from the backend directory: node scripts/set-storage-cors.js

import { getStorage } from '../src/config/firebase-admin.js';

const bucket = getStorage();

await bucket.setCorsConfiguration([
  {
    origin: ['*'],
    method: ['GET'],
    responseHeader: ['Content-Type', 'Content-Disposition'],
    maxAgeSeconds: 3600,
  },
]);

console.log(`CORS configured on bucket: ${bucket.name}`);
