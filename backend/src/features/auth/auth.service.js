// Purpose: Firestore and Firebase Admin operations for company setup and team member management.
import { getFirebaseAdmin, getFirestore } from '../../config/firebase-admin.js';

const USERS_COLLECTION = 'users';
const COMPANIES_COLLECTION = 'companies';

export async function createCompany({ uid, email, displayName, companyName }) {
  const firestore = getFirestore();
  const companyRef = firestore.collection(COMPANIES_COLLECTION).doc();
  const companyId = companyRef.id;
  const now = new Date();

  const companyPayload = {
    id: companyId,
    name: String(companyName || '').trim(),
    ownerUid: uid,
    createdAt: now,
    updatedAt: now,
  };

  const userPayload = {
    uid,
    email: String(email || '').trim(),
    displayName: String(displayName || '').trim(),
    companyId,
    role: 'owner',
    createdAt: now,
  };

  const batch = firestore.batch();
  batch.set(companyRef, companyPayload);
  batch.set(firestore.collection(USERS_COLLECTION).doc(uid), userPayload);
  await batch.commit();

  await getFirebaseAdmin().auth().setCustomUserClaims(uid, {
    companyId,
    role: 'owner',
  });

  return {
    company: _serializeCompany(companyPayload),
    user: _serializeUser(userPayload),
  };
}

export async function getUserProfile(uid) {
  const firestore = getFirestore();
  const userRef = firestore.collection(USERS_COLLECTION).doc(uid);
  const doc = await userRef.get();
  if (!doc.exists) {
    return null;
  }
  let data = doc.data();

  // ── Self-heal legacy data ─────────────────────────────────────────────────
  // VIP used to be stored as role === 'vip', which clobbered the owner role.
  // Migrate to a boolean `isVip` field and restore the proper role.
  const patch = {};
  if (data.role === 'vip') {
    patch.isVip = true;
    patch.role = 'member';
  }
  if (data.companyId) {
    const companyDoc = await firestore
      .collection(COMPANIES_COLLECTION)
      .doc(data.companyId)
      .get();
    if (companyDoc.exists && companyDoc.data().ownerUid === uid && (patch.role || data.role) !== 'owner') {
      patch.role = 'owner';
    }
  }
  if (Object.keys(patch).length > 0) {
    await userRef.set(patch, { merge: true });
    data = { ...data, ...patch };
    // Keep custom claims in sync so middleware sees the correct role.
    try {
      await getFirebaseAdmin().auth().setCustomUserClaims(uid, {
        companyId: data.companyId || null,
        role: data.role,
      });
    } catch {
      // Non-fatal — claims will refresh on next sign-in.
    }
  }

  return _serializeUser(data);
}

export async function createTeamMember({ companyId, email, password, displayName }) {
  const firebaseAdmin = getFirebaseAdmin();
  const firestore = getFirestore();

  const firebaseUser = await firebaseAdmin.auth().createUser({
    email: String(email || '').trim(),
    password: String(password || ''),
    displayName: String(displayName || '').trim(),
  });

  const now = new Date();
  const userPayload = {
    uid: firebaseUser.uid,
    email: firebaseUser.email || String(email || '').trim(),
    displayName: firebaseUser.displayName || String(displayName || '').trim(),
    companyId,
    role: 'member',
    createdAt: now,
  };

  await firestore.collection(USERS_COLLECTION).doc(firebaseUser.uid).set(userPayload);

  // Set custom claims so the member's ID token will carry companyId on first sign-in.
  await firebaseAdmin.auth().setCustomUserClaims(firebaseUser.uid, {
    companyId,
    role: 'member',
  });

  return _serializeUser(userPayload);
}

export async function listTeamMembers(companyId) {
  const firestore = getFirestore();
  const [companyDoc, snapshot] = await Promise.all([
    firestore.collection(COMPANIES_COLLECTION).doc(companyId).get(),
    firestore
      .collection(USERS_COLLECTION)
      .where('companyId', '==', companyId)
      .orderBy('createdAt', 'asc')
      .get(),
  ]);

  const ownerUid = companyDoc.exists ? companyDoc.data().ownerUid : null;

  return snapshot.docs
    .map((doc) => _serializeUser(doc.data()))
    // Exclude the company owner from team listings (they manage, not appear).
    .filter((m) => m.uid !== ownerUid && m.role !== 'owner');
}

export async function removeTeamMember(companyId, uid) {
  const firebaseAdmin = getFirebaseAdmin();
  const firestore = getFirestore();

  const userDoc = await firestore.collection(USERS_COLLECTION).doc(uid).get();
  if (!userDoc.exists || userDoc.data().companyId !== companyId) {
    const err = new Error('Team member not found.');
    err.status = 404;
    throw err;
  }

  if (userDoc.data().role === 'owner') {
    const err = new Error('Cannot remove the company owner.');
    err.status = 403;
    throw err;
  }

  await firestore.collection(USERS_COLLECTION).doc(uid).delete();

  // Clean up all per-project permission records for this member.
  const permSnapshot = await firestore
    .collection(COMPANIES_COLLECTION)
    .doc(companyId)
    .collection('member_permissions')
    .where('uid', '==', uid)
    .get();
  if (!permSnapshot.empty) {
    const permBatch = firestore.batch();
    permSnapshot.docs.forEach((doc) => permBatch.delete(doc.ref));
    await permBatch.commit();
  }

  try {
    await firebaseAdmin.auth().deleteUser(uid);
  } catch {
    // Ignore — the Firebase Auth user may have already been deleted.
  }
}

export async function getCompanySettings(companyId) {
  const doc = await getFirestore().collection(COMPANIES_COLLECTION).doc(companyId).get();
  if (!doc.exists) return { categories: [], notes: '' };
  const data = doc.data();
  return {
    categories: Array.isArray(data.settings?.categories) ? data.settings.categories : [],
    notes: typeof data.settings?.notes === 'string' ? data.settings.notes : '',
  };
}

export async function updateCompanySettings(companyId, { categories, notes }) {
  const sanitizedCategories = Array.isArray(categories)
    ? categories.map((c) => String(c).trim()).filter(Boolean)
    : [];
  const sanitizedNotes = typeof notes === 'string' ? notes.trim() : '';
  await getFirestore()
    .collection(COMPANIES_COLLECTION)
    .doc(companyId)
    .set(
      { settings: { categories: sanitizedCategories, notes: sanitizedNotes }, updatedAt: new Date() },
      { merge: true },
    );
  return { categories: sanitizedCategories, notes: sanitizedNotes };
}

function _serializeCompany(data = {}) {
  return {
    id: data.id || '',
    name: data.name || '',
    ownerUid: data.ownerUid || '',
    createdAt: _serializeDate(data.createdAt),
    updatedAt: _serializeDate(data.updatedAt),
  };
}

function _serializeUser(data = {}) {
  return {
    uid: data.uid || '',
    email: data.email || '',
    displayName: data.displayName || '',
    companyId: data.companyId || '',
    role: data.role || 'member',
    isVip: data.isVip === true,
    createdAt: _serializeDate(data.createdAt),
  };
}

function _serializeDate(value) {
  if (!value) return null;
  if (value instanceof Date) return value.toISOString();
  if (typeof value.toDate === 'function') return value.toDate().toISOString();
  return null;
}
