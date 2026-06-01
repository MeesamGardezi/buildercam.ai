// Purpose: Encapsulates Firestore project and transcript persistence for the SOW backend.
import admin from 'firebase-admin';

import { getFirestore, getStorage } from '../config/firebase-admin.js';

// Top-level (global) Firestore collections. Each document carries a
// `projectId` field that acts as the foreign key linking it back to the
// parent project document. This replaces the previous sub-collection model.
const PROJECTS_COLLECTION = 'projects';
const TRANSCRIPTS_COLLECTION = 'sow_transcripts';
const SOW_DOCUMENTS_COLLECTION = 'sow_documents';
const PDF_DOCUMENTS_COLLECTION = 'pdf_documents';
const SOW_TEMPLATES_COLLECTION = 'sow_templates';
const PDF_TEMPLATES_COLLECTION = 'pdf_templates';
const DEFAULT_PROJECT_STATUS = 'planning';

export async function saveProjectTranscript(projectId, transcript, companyId = null) {
  await _assertProjectExists(projectId, companyId);

  const collection = getFirestore().collection(TRANSCRIPTS_COLLECTION);
  const document = transcript.id ? collection.doc(transcript.id) : collection.doc();
  const existingSnapshot = await document.get();
  const created = !existingSnapshot.exists;
  const existingTranscript = existingSnapshot.exists ? existingSnapshot.data() : null;
  const createdAt = existingTranscript?.createdAt
    ? _toDate(existingTranscript.createdAt)
    : transcript.createdAt
    ? new Date(transcript.createdAt)
    : new Date();
  const durationSeconds = Number(transcript.durationSeconds || 0);
  const rawTranscript = String(transcript.rawTranscript || '').trim();
  const payload = {
    ...existingTranscript,
    ...transcript,
    id: existingTranscript?.id || transcript.id || document.id,
    projectId,
    rawTranscript,
    durationSeconds,
    createdAt,
    updatedAt: new Date(),
  };

  // Never wipe existing frame URLs through a text-only edit — only overwrite
  // when the incoming update explicitly provides at least one URL.
  if ((!transcript.frameUrls || transcript.frameUrls.length === 0) && existingTranscript?.frameUrls?.length) {
    payload.frameUrls = existingTranscript.frameUrls;
  }

  await document.set(payload);
  await _touchProject(projectId, payload, existingTranscript);
  return {
    transcript: _serializeTranscript(payload),
    created,
  };
}

export async function listProjectTranscripts(projectId, limit = 25, companyId = null) {
  await _assertProjectExists(projectId, companyId);

  // Sort in-memory to avoid requiring a composite index on (projectId, updatedAt).
  const snapshot = await getFirestore()
    .collection(TRANSCRIPTS_COLLECTION)
    .where('projectId', '==', projectId)
    .get();

  const items = snapshot.docs.map((document) =>
    _serializeTranscript(document.data(), document.id),
  );
  items.sort((a, b) => (b.updatedAt ?? '').localeCompare(a.updatedAt ?? ''));
  return items.slice(0, limit);
}

export async function deleteProjectTranscript(projectId, transcriptId, companyId = null) {
  await _assertProjectExists(projectId, companyId);

  const docRef = getFirestore().collection(TRANSCRIPTS_COLLECTION).doc(transcriptId);

  const snapshot = await docRef.get();
  if (!snapshot.exists) {
    return;
  }

  const data = snapshot.data();
  if (data.projectId && data.projectId !== projectId) {
    return;
  }
  const durationSeconds = Number(data.durationSeconds || 0);
  await docRef.delete();

  const projectRef = getFirestore().collection(PROJECTS_COLLECTION).doc(projectId);
  await projectRef.set(
    {
      updatedAt: new Date(),
      totalTranscriptSeconds: admin.firestore.FieldValue.increment(-durationSeconds),
      transcriptCount: admin.firestore.FieldValue.increment(-1),
    },
    { merge: true },
  );
}

// ─── SOW document CRUD (global collection, projectId FK) ────────────────────

export async function saveSowDocument(projectId, { id, title, content, transcriptIds, frameUrls, pdfData, createdBy, companyId }) {
  await _assertProjectExists(projectId, companyId);
  const col = getFirestore().collection(SOW_DOCUMENTS_COLLECTION);
  const doc = id ? col.doc(id) : col.doc();
  const existing = await doc.get();
  // If the doc exists but belongs to another project, refuse silently and
  // create a new one — never overwrite cross-project.
  if (existing.exists && existing.data().projectId && existing.data().projectId !== projectId) {
    const fresh = col.doc();
    return saveSowDocument(projectId, { id: fresh.id, title, content, transcriptIds, frameUrls, pdfData, createdBy, companyId });
  }
  const now = new Date();
  const payload = {
    id: doc.id,
    projectId,
    title: String(title || '').trim() || 'Untitled SOW',
    content: String(content || ''),
    transcriptIds: Array.isArray(transcriptIds) ? transcriptIds : [],
    frameUrls: Array.isArray(frameUrls) ? frameUrls : [],
    pdfData: pdfData && typeof pdfData === 'object' ? pdfData : null,
    createdBy: String(createdBy || ''),
    companyId: String(companyId || ''),
    createdAt: existing.exists ? existing.data().createdAt : now,
    updatedAt: now,
  };
  await doc.set(payload);
  return { document: _serializeSowDocument(payload), created: !existing.exists };
}

export async function listSowDocuments(projectId, companyId = null) {
  await _assertProjectExists(projectId, companyId);
  const snapshot = await getFirestore()
    .collection(SOW_DOCUMENTS_COLLECTION)
    .where('projectId', '==', projectId)
    .get();
  const items = snapshot.docs.map((d) => _serializeSowDocument(d.data(), d.id));
  items.sort((a, b) => (b.updatedAt ?? '').localeCompare(a.updatedAt ?? ''));
  return items.slice(0, 50);
}

export async function getSowDocument(projectId, sowDocId, companyId = null) {
  await _assertProjectExists(projectId, companyId);
  const snap = await getFirestore().collection(SOW_DOCUMENTS_COLLECTION).doc(sowDocId).get();
  if (!snap.exists) return null;
  const data = snap.data();
  if (data.projectId && data.projectId !== projectId) return null;
  return _serializeSowDocument(data, snap.id);
}

export async function deleteSowDocument(projectId, sowDocId, companyId = null) {
  await _assertProjectExists(projectId, companyId);
  const docRef = getFirestore().collection(SOW_DOCUMENTS_COLLECTION).doc(sowDocId);
  const snap = await docRef.get();
  if (!snap.exists) return;
  if (snap.data().projectId && snap.data().projectId !== projectId) return;
  await docRef.delete();
}

// ─── Standalone PDF document CRUD (global collection, projectId FK) ─────────

export async function savePdfDocument(projectId, { id, title, pdfData, createdBy, companyId }) {
  await _assertProjectExists(projectId, companyId);
  const col = getFirestore().collection(PDF_DOCUMENTS_COLLECTION);
  const doc = id ? col.doc(id) : col.doc();
  const existing = await doc.get();
  if (existing.exists && existing.data().projectId && existing.data().projectId !== projectId) {
    const fresh = col.doc();
    return savePdfDocument(projectId, { id: fresh.id, title, pdfData, createdBy, companyId });
  }
  const now = new Date();
  const payload = {
    id: doc.id,
    projectId,
    title: String(title || '').trim() || 'Untitled PDF',
    pdfData: pdfData && typeof pdfData === 'object' ? pdfData : {},
    createdBy: String(createdBy || ''),
    companyId: String(companyId || ''),
    createdAt: existing.exists ? existing.data().createdAt : now,
    updatedAt: now,
  };
  await doc.set(payload);
  return { document: _serializePdfDocument(payload), created: !existing.exists };
}

export async function listPdfDocuments(projectId, companyId = null) {
  await _assertProjectExists(projectId, companyId);
  const snapshot = await getFirestore()
    .collection(PDF_DOCUMENTS_COLLECTION)
    .where('projectId', '==', projectId)
    .get();
  const items = snapshot.docs.map((d) => _serializePdfDocument(d.data(), d.id));
  items.sort((a, b) => (b.updatedAt ?? '').localeCompare(a.updatedAt ?? ''));
  return items.slice(0, 50);
}

export async function getPdfDocument(projectId, pdfDocId, companyId = null) {
  await _assertProjectExists(projectId, companyId);
  const snap = await getFirestore().collection(PDF_DOCUMENTS_COLLECTION).doc(pdfDocId).get();
  if (!snap.exists) return null;
  const data = snap.data();
  if (data.projectId && data.projectId !== projectId) return null;
  return _serializePdfDocument(data, snap.id);
}

export async function deletePdfDocument(projectId, pdfDocId, companyId = null) {
  await _assertProjectExists(projectId, companyId);
  const docRef = getFirestore().collection(PDF_DOCUMENTS_COLLECTION).doc(pdfDocId);
  const snap = await docRef.get();
  if (!snap.exists) return;
  if (snap.data().projectId && snap.data().projectId !== projectId) return;
  await docRef.delete();
}

// ─── SOW template CRUD (company-level) ──────────────────────────────────────────

export async function saveTemplate(companyId, { id, name, content, createdBy }) {
  const col = getFirestore().collection(SOW_TEMPLATES_COLLECTION);
  const doc = id ? col.doc(id) : col.doc();
  const existing = await doc.get();
  const now = new Date();
  const payload = {
    id: doc.id,
    companyId: String(companyId || ''),
    name: String(name || '').trim() || 'Untitled Template',
    content: String(content || ''),
    createdBy: String(createdBy || ''),
    createdAt: existing.exists ? existing.data().createdAt : now,
    updatedAt: now,
  };
  await doc.set(payload);
  return { template: _serializeTemplate(payload), created: !existing.exists };
}

export async function listTemplates(companyId) {
  const snapshot = await getFirestore()
    .collection(SOW_TEMPLATES_COLLECTION)
    .where('companyId', '==', companyId)
    .orderBy('updatedAt', 'desc')
    .limit(100)
    .get();
  return snapshot.docs.map((d) => _serializeTemplate(d.data()));
}

export async function deleteTemplate(templateId, companyId) {
  const doc = getFirestore().collection(SOW_TEMPLATES_COLLECTION).doc(templateId);
  const snap = await doc.get();
  if (snap.exists && snap.data().companyId === companyId) {
    await doc.delete();
  }
}

function _serializeTemplate(data) {
  return {
    id: data.id,
    name: data.name,
    content: data.content,
    createdBy: data.createdBy,
    companyId: data.companyId,
    createdAt: _toDate(data.createdAt)?.toISOString() ?? null,
    updatedAt: _toDate(data.updatedAt)?.toISOString() ?? null,
  };
}

// ─── PDF template CRUD (company-level) ──────────────────────────────────────────

export async function savePdfTemplate(companyId, { name, pdfJson, createdBy }) {
  const col = getFirestore().collection(PDF_TEMPLATES_COLLECTION);
  const doc = col.doc();
  const now = new Date();
  const payload = {
    id: doc.id,
    companyId: String(companyId || ''),
    name: String(name || '').trim() || 'Untitled PDF Template',
    pdfJson: pdfJson || {},
    createdBy: String(createdBy || ''),
    createdAt: now,
    updatedAt: now,
  };
  await doc.set(payload);
  return _serializePdfTemplate(payload);
}

export async function listPdfTemplates(companyId) {
  // NOTE: avoid orderBy here — the where+orderBy combo requires a composite
  // index on the pdf_templates collection. Sort in memory instead so newly
  // saved templates show up immediately without needing index provisioning.
  const snapshot = await getFirestore()
    .collection(PDF_TEMPLATES_COLLECTION)
    .where('companyId', '==', companyId)
    .limit(100)
    .get();
  const items = snapshot.docs.map((d) => _serializePdfTemplate(d.data()));
  items.sort((a, b) => (b.updatedAt ?? '').localeCompare(a.updatedAt ?? ''));
  return items;
}

export async function deletePdfTemplate(templateId, companyId) {
  const doc = getFirestore().collection(PDF_TEMPLATES_COLLECTION).doc(templateId);
  const snap = await doc.get();
  if (snap.exists && snap.data().companyId === companyId) {
    await doc.delete();
  }
}

function _serializePdfTemplate(data) {
  return {
    id: data.id,
    name: data.name,
    pdfJson: data.pdfJson,
    createdBy: data.createdBy,
    companyId: data.companyId,
    createdAt: _toDate(data.createdAt)?.toISOString() ?? null,
    updatedAt: _toDate(data.updatedAt)?.toISOString() ?? null,
  };
}

// ─────────────────────────────────────────────────────────────────────────────

export async function deleteProject(projectId, companyId = null) {
  await _assertProjectExists(projectId, companyId);

  // 1. Delete all Storage files under projects/{projectId}/frames/
  try {
    const bucket = getStorage();
    const [files] = await bucket.getFiles({ prefix: `projects/${projectId}/frames/` });
    if (files.length > 0) {
      await Promise.all(files.map((file) => file.delete().catch(() => null)));
    }
  } catch (storageError) {
    console.warn(
      `[deleteProject] Storage cleanup failed for ${projectId}:`,
      storageError.message,
    );
  }

  // 2. Batch delete every document in the global collections that references
  //    this project via its `projectId` foreign key.
  await _deleteByProjectId(TRANSCRIPTS_COLLECTION, projectId);
  await _deleteByProjectId(SOW_DOCUMENTS_COLLECTION, projectId);
  await _deleteByProjectId(PDF_DOCUMENTS_COLLECTION, projectId);

  // 3. Delete the project document.
  await getFirestore().collection(PROJECTS_COLLECTION).doc(projectId).delete();
}

async function _deleteByProjectId(collectionName, projectId) {
  const snap = await getFirestore()
    .collection(collectionName)
    .where('projectId', '==', projectId)
    .get();
  if (snap.empty) return;
  // Firestore batch limit is 500; chunk to stay safe.
  const docs = snap.docs;
  for (let i = 0; i < docs.length; i += 400) {
    const batch = getFirestore().batch();
    docs.slice(i, i + 400).forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }
}

export async function listProjects(companyId) {
  // NOTE: This query requires a Firestore composite index on `projects`:
  //   companyId ASC + updatedAt DESC
  // Firebase will print an error with a direct link to create it on first run.
  let query = getFirestore()
    .collection(PROJECTS_COLLECTION)
    .where('companyId', '==', companyId)
    .orderBy('updatedAt', 'desc');

  const snapshot = await query.get();
  return snapshot.docs.map((document) => _serializeProject(document.data(), document.id));
}

export async function createProject(project) {
  const collection = getFirestore().collection(PROJECTS_COLLECTION);
  const document = collection.doc();
  const now = new Date();
  const payload = {
    id: document.id,
    name: String(project.name || '').trim(),
    clientName: String(project.clientName || '').trim(),
    siteLocation: String(project.siteLocation || '').trim(),
    scopeSummary: String(project.scopeSummary || '').trim(),
    notes: String(project.notes || '').trim(),
    status: String(project.status || DEFAULT_PROJECT_STATUS).trim() || DEFAULT_PROJECT_STATUS,
    createdBy: String(project.createdBy || '').trim(),
    companyId: String(project.companyId || '').trim(),
    createdAt: now,
    updatedAt: now,
    transcriptCount: 0,
    totalTranscriptSeconds: 0,
    lastTranscriptAt: null,
    latestTranscriptExcerpt: '',
  };

  await document.set(payload);
  return _serializeProject(payload);
}

export async function getProject(projectId, companyId = null) {
  const document = await getFirestore()
    .collection(PROJECTS_COLLECTION)
    .doc(projectId)
    .get();

  if (!document.exists) {
    return null;
  }

  const data = document.data();
  // Verify company ownership when a companyId is provided.
  if (companyId && data.companyId && data.companyId !== companyId) {
    return null;
  }

  return _serializeProject(data, document.id);
}

export async function getProjectWorkspace(projectId, transcriptLimit = 8) {
  const [project, transcripts] = await Promise.all([
    getProject(projectId),
    listProjectTranscripts(projectId, transcriptLimit),
  ]);

  if (!project) {
    return null;
  }

  return {
    ...project,
    transcripts,
  };
}

async function _touchProject(projectId, transcript, existingTranscript = null) {
  const projectRef = getFirestore().collection(PROJECTS_COLLECTION).doc(projectId);
  const durationDelta =
    Number(transcript.durationSeconds || 0) - Number(existingTranscript?.durationSeconds || 0);
  await projectRef.set(
    {
      id: projectId,
      updatedAt: new Date(),
      lastTranscriptAt: transcript.updatedAt || transcript.createdAt,
      latestTranscriptExcerpt: transcript.rawTranscript.slice(0, 180),
      totalTranscriptSeconds: admin.firestore.FieldValue.increment(durationDelta),
      ...(existingTranscript
        ? {}
        : { transcriptCount: admin.firestore.FieldValue.increment(1) }),
    },
    { merge: true },
  );
}

function _serializeSowDocument(data = {}, fallbackId = '') {
  return {
    id: data.id || fallbackId,
    projectId: data.projectId || '',
    title: data.title || 'Untitled SOW',
    content: data.content || '',
    transcriptIds: Array.isArray(data.transcriptIds) ? data.transcriptIds : [],
    frameUrls: Array.isArray(data.frameUrls) ? data.frameUrls : [],
    pdfData: data.pdfData && typeof data.pdfData === 'object' ? data.pdfData : null,
    createdBy: data.createdBy || '',
    createdAt: _serializeDate(data.createdAt),
    updatedAt: _serializeDate(data.updatedAt),
  };
}

function _serializePdfDocument(data = {}, fallbackId = '') {
  return {
    id: data.id || fallbackId,
    projectId: data.projectId || '',
    title: data.title || 'Untitled PDF',
    pdfData: data.pdfData && typeof data.pdfData === 'object' ? data.pdfData : {},
    createdBy: data.createdBy || '',
    createdAt: _serializeDate(data.createdAt),
    updatedAt: _serializeDate(data.updatedAt),
  };
}

function _serializeProject(data = {}, fallbackId = '') {
  return {
    id: data.id || fallbackId,
    name: data.name || '',
    clientName: data.clientName || '',
    siteLocation: data.siteLocation || '',
    scopeSummary: data.scopeSummary || '',
    notes: data.notes || '',
    status: data.status || DEFAULT_PROJECT_STATUS,
    createdBy: data.createdBy || '',
    companyId: data.companyId || '',
    createdAt: _serializeDate(data.createdAt),
    updatedAt: _serializeDate(data.updatedAt),
    transcriptCount: Number(data.transcriptCount || 0),
    totalTranscriptSeconds: Number(data.totalTranscriptSeconds || 0),
    lastTranscriptAt: _serializeDate(data.lastTranscriptAt),
    latestTranscriptExcerpt: data.latestTranscriptExcerpt || '',
  };
}

function _serializeTranscript(data = {}, fallbackId = '') {
  return {
    id: data.id || fallbackId,
    projectId: data.projectId || '',
    rawTranscript: data.rawTranscript || '',
    durationSeconds: Number(data.durationSeconds || 0),
    createdAt: _serializeDate(data.createdAt),
    updatedAt: _serializeDate(data.updatedAt),
    createdBy: data.createdBy || '',
    status: data.status || 'completed',
    frameUrls: Array.isArray(data.frameUrls) ? data.frameUrls : [],
    ...(data.title ? { title: data.title } : {}),
  };
}

async function _assertProjectExists(projectId, companyId = null) {
  const projectSnapshot = await getFirestore().collection(PROJECTS_COLLECTION).doc(projectId).get();

  if (!projectSnapshot.exists) {
    const error = new Error('Project not found.');
    error.status = 404;
    throw error;
  }

  // Verify company ownership when a companyId is provided.
  const data = projectSnapshot.data();
  if (companyId && data.companyId && data.companyId !== companyId) {
    const error = new Error('Project not found.');
    error.status = 404;
    throw error;
  }
}

function _serializeDate(value) {
  if (!value) {
    return null;
  }

  if (value instanceof Date) {
    return value.toISOString();
  }

  if (typeof value.toDate === 'function') {
    return value.toDate().toISOString();
  }

  if (typeof value === 'number') {
    return new Date(value).toISOString();
  }

  if (typeof value === 'string') {
    return value;
  }

  return null;
}

function _toDate(value) {
  if (!value) {
    return new Date();
  }

  if (value instanceof Date) {
    return value;
  }

  if (typeof value.toDate === 'function') {
    return value.toDate();
  }

  return new Date(value);
}
