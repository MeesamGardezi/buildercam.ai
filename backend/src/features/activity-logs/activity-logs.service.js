// Purpose: Firestore operations for company-wide activity log management.
import { getFirestore } from '../../config/firebase-admin.js';

const COMPANIES_COLLECTION = 'companies';
const ACTIVITY_LOGS_SUBCOLLECTION = 'activity_logs';
const MAX_PAGE_SIZE = 200;
const DEFAULT_PAGE_SIZE = 50;

/**
 * Write a new activity log entry for a user action.
 */
export async function createActivityLog({
  companyId,
  userId,
  userEmail,
  userName,
  action,
  projectId,
  projectName,
  details,
}) {
  const firestore = getFirestore();
  const ref = firestore
    .collection(COMPANIES_COLLECTION)
    .doc(companyId)
    .collection(ACTIVITY_LOGS_SUBCOLLECTION)
    .doc();

  const now = new Date();
  const payload = {
    id: ref.id,
    companyId,
    userId: String(userId || ''),
    userEmail: String(userEmail || '').trim(),
    userName: String(userName || '').trim(),
    action: String(action || '').trim(),
    projectId: projectId || null,
    projectName: projectName || null,
    details: details || null,
    timestamp: now,
  };

  await ref.set(payload);
  return _serialize(payload);
}

/**
 * Fetch activity logs.
 * - Owner: all logs for the company (optionally filtered by projectId).
 * - Member: only their own logs (optionally filtered by projectId).
 * Supports pagination via `before` (ISO timestamp of last seen record).
 */
export async function getActivityLogs({
  companyId,
  userId,
  isOwner,
  projectId,
  limit = DEFAULT_PAGE_SIZE,
  before,
}) {
  const firestore = getFirestore();
  const safeLimit = Math.min(Number(limit) || DEFAULT_PAGE_SIZE, MAX_PAGE_SIZE);

  let query = firestore
    .collection(COMPANIES_COLLECTION)
    .doc(companyId)
    .collection(ACTIVITY_LOGS_SUBCOLLECTION)
    .orderBy('timestamp', 'desc')
    .limit(safeLimit);

  if (!isOwner) {
    query = query.where('userId', '==', userId);
  }

  if (projectId) {
    query = query.where('projectId', '==', projectId);
  }

  if (before) {
    const beforeDate = new Date(before);
    if (!isNaN(beforeDate.getTime())) {
      query = query.startAfter(beforeDate);
    }
  }

  const snapshot = await query.get();
  return snapshot.docs.map((doc) => _serialize(doc.data()));
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function _serialize(data = {}) {
  return {
    id: data.id || '',
    companyId: data.companyId || '',
    userId: data.userId || '',
    userEmail: data.userEmail || '',
    userName: data.userName || '',
    action: data.action || '',
    projectId: data.projectId || null,
    projectName: data.projectName || null,
    details: data.details || null,
    timestamp: _serializeDate(data.timestamp),
  };
}

function _serializeDate(value) {
  if (!value) return null;
  if (value instanceof Date) return value.toISOString();
  if (typeof value.toDate === 'function') return value.toDate().toISOString();
  return null;
}
