// Purpose: Lazily initializes Firebase Admin for protected transcript APIs.
import admin from 'firebase-admin';
import fs from 'node:fs';

let firebaseApp;

function getLocalServiceAccount() {
  const serviceAccountPath = new URL('../../config/firebase-key.json', import.meta.url);

  if (!fs.existsSync(serviceAccountPath)) {
    return null;
  }

  try {
    return JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));
  } catch {
    return null;
  }
}

export function getFirebaseAdmin() {
  if (firebaseApp) {
    return admin;
  }

  const envServiceAccount = process.env.FIREBASE_SERVICE_ACCOUNT_JSON
    ? JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON)
    : null;
  const serviceAccount = envServiceAccount ?? getLocalServiceAccount();
  const projectId = process.env.FIREBASE_PROJECT_ID ?? serviceAccount?.project_id;

  firebaseApp = admin.apps.length
    ? admin.app()
    : admin.initializeApp({
        credential: serviceAccount
          ? admin.credential.cert(serviceAccount)
          : admin.credential.applicationDefault(),
        projectId,
      });

  return admin;
}

let firestoreSettingsApplied = false;
export function getFirestore() {
  getFirebaseAdmin();
  const db = admin.firestore();
  if (!firestoreSettingsApplied) {
    try {
      db.settings({ ignoreUndefinedProperties: true });
    } catch (_) {
      // settings() throws if already initialized — safe to ignore.
    }
    firestoreSettingsApplied = true;
  }
  return db;
}

export function getStorage() {
  getFirebaseAdmin();
  const bucket =
    process.env.FIREBASE_STORAGE_BUCKET ||
    `${admin.app().options.projectId}.firebasestorage.app`;
  return admin.storage().bucket(bucket);
}
