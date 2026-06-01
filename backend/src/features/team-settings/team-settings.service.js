// Purpose: Firestore operations for per-project, per-member permission management.
import { getFirestore } from '../../config/firebase-admin.js';

const COMPANIES_COLLECTION = 'companies';
const PERMISSIONS_SUBCOLLECTION = 'member_permissions';

function _docId(uid, projectId) {
  return `${uid}_${projectId}`;
}

/**
 * Upsert a full permission record for a member on a specific project.
 */
export async function setMemberProjectPermissions({
  companyId,
  uid,
  projectId,
  permissions,
}) {
  const firestore = getFirestore();
  const docId = _docId(uid, projectId);
  const now = new Date();
  const payload = {
    uid,
    projectId,
    companyId,
    canView: permissions.canView ?? true,
    canRecord: permissions.canRecord ?? false,
    canTranscribe: permissions.canTranscribe ?? false,
    canEditDocument: permissions.canEditDocument ?? false,
    canExport: permissions.canExport ?? false,
    canDeleteTranscript: permissions.canDeleteTranscript ?? false,
    canCreateProject: permissions.canCreateProject ?? false,
    canEditProject: permissions.canEditProject ?? false,
    canDeleteProject: permissions.canDeleteProject ?? false,
    canManageTemplates: permissions.canManageTemplates ?? false,
    canUploadFiles: permissions.canUploadFiles ?? false,
    canViewSow: permissions.canViewSow ?? true,
    canCreateSow: permissions.canCreateSow ?? false,
    canDeleteSow: permissions.canDeleteSow ?? false,
    canViewPdf: permissions.canViewPdf ?? true,
    canCreatePdf: permissions.canCreatePdf ?? false,
    canDeletePdf: permissions.canDeletePdf ?? false,
    updatedAt: now,
  };
  await firestore
    .collection(COMPANIES_COLLECTION)
    .doc(companyId)
    .collection(PERMISSIONS_SUBCOLLECTION)
    .doc(docId)
    .set(payload, { merge: true });
  return _serialize(payload);
}

/**
 * Get a single member's permissions for a specific project.
 * Returns default (view-only) if no record exists yet.
 */
export async function getMemberProjectPermissions({ companyId, uid, projectId }) {
  const firestore = getFirestore();
  const docId = _docId(uid, projectId);
  const doc = await firestore
    .collection(COMPANIES_COLLECTION)
    .doc(companyId)
    .collection(PERMISSIONS_SUBCOLLECTION)
    .doc(docId)
    .get();
  if (!doc.exists) return _defaultPermissions(uid, projectId, companyId);
  return _serialize(doc.data());
}

/**
 * Get all permission records for a specific member across all projects.
 */
export async function getMemberAllPermissions({ companyId, uid }) {
  const firestore = getFirestore();
  const snapshot = await firestore
    .collection(COMPANIES_COLLECTION)
    .doc(companyId)
    .collection(PERMISSIONS_SUBCOLLECTION)
    .where('uid', '==', uid)
    .get();
  return snapshot.docs.map((doc) => _serialize(doc.data()));
}

/**
 * Get all permission records for all members in a company (owner overview).
 */
export async function getAllCompanyPermissions({ companyId }) {
  const firestore = getFirestore();
  const snapshot = await firestore
    .collection(COMPANIES_COLLECTION)
    .doc(companyId)
    .collection(PERMISSIONS_SUBCOLLECTION)
    .get();
  return snapshot.docs.map((doc) => _serialize(doc.data()));
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function _defaultPermissions(uid, projectId, companyId) {
  return {
    uid,
    projectId,
    companyId,
    canView: true,
    canRecord: false,
    canTranscribe: false,
    canEditDocument: false,
    canExport: false,
    canDeleteTranscript: false,
    canCreateProject: false,
    canEditProject: false,
    canDeleteProject: false,
    canManageTemplates: false,
    canUploadFiles: false,
    canViewSow: true,
    canCreateSow: false,
    canDeleteSow: false,
    canViewPdf: true,
    canCreatePdf: false,
    canDeletePdf: false,
    updatedAt: null,
  };
}

function _serialize(data = {}) {
  return {
    uid: data.uid || '',
    projectId: data.projectId || '',
    companyId: data.companyId || '',
    canView: data.canView ?? true,
    canRecord: data.canRecord ?? false,
    canTranscribe: data.canTranscribe ?? false,
    canEditDocument: data.canEditDocument ?? false,
    canExport: data.canExport ?? false,
    canDeleteTranscript: data.canDeleteTranscript ?? false,
    canCreateProject: data.canCreateProject ?? false,
    canEditProject: data.canEditProject ?? false,
    canDeleteProject: data.canDeleteProject ?? false,
    canManageTemplates: data.canManageTemplates ?? false,
    canUploadFiles: data.canUploadFiles ?? false,
    canViewSow: data.canViewSow ?? true,
    canCreateSow: data.canCreateSow ?? false,
    canDeleteSow: data.canDeleteSow ?? false,
    canViewPdf: data.canViewPdf ?? true,
    canCreatePdf: data.canCreatePdf ?? false,
    canDeletePdf: data.canDeletePdf ?? false,
    updatedAt: _serializeDate(data.updatedAt),
  };
}

function _serializeDate(value) {
  if (!value) return null;
  if (value instanceof Date) return value.toISOString();
  if (typeof value.toDate === 'function') return value.toDate().toISOString();
  return null;
}
