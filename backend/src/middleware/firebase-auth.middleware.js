// Purpose: Verifies Firebase ID tokens for protected SOW transcription routes.
import { getFirebaseAdmin } from '../config/firebase-admin.js';

export async function verifyFirebaseToken(req, res, next) {
  try {
    const authorization = req.headers.authorization || '';
    if (!authorization.startsWith('Bearer ')) {
      return res.status(401).json({
        success: false,
        message: 'Missing Firebase ID token.',
      });
    }

    const idToken = authorization.replace('Bearer ', '').trim();
    const admin = getFirebaseAdmin();
    req.user = await admin.auth().verifyIdToken(idToken);
    return next();
  } catch (_) {
    return res.status(401).json({
      success: false,
      message: 'Invalid or expired Firebase ID token.',
    });
  }
}
