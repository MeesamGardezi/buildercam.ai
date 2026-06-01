// Purpose: Firestore credit-wallet operations — balance, spend, add, history.
import admin from 'firebase-admin';
import { getFirestore } from '../../config/firebase-admin.js';

const USERS_COLLECTION = 'users';
const CREDIT_TRANSACTIONS_COLLECTION = 'credit_transactions';
const SUBSCRIPTIONS_COLLECTION = 'credit_subscriptions';

/** Credits required per action type. */
export const CREDIT_COSTS = {
  transcript: 1,         // audio-only transcript
  transcript_video: 2,   // video transcript (has frameUrls)
  sow_generation: 3,
  pdf_generation: 3,
  sow_document: 1,       // new SOW document save
  pdf_document: 1,       // new PDF document save
};

// ── Read ────────────────────────────────────────────────────────────────────

export async function getCreditBalance(uid) {
  const doc = await getFirestore().collection(USERS_COLLECTION).doc(uid).get();
  if (!doc.exists) return 0;
  return Number(doc.data().creditBalance ?? 0);
}

export async function hasSufficientCredits(uid, cost) {
  const balance = await getCreditBalance(uid);
  return balance >= cost;
}

export async function isVipUser(uid) {
  const doc = await getFirestore().collection(USERS_COLLECTION).doc(uid).get();
  if (!doc.exists) return false;
  const data = doc.data();
  // VIP is now a boolean field independent of role. Legacy: role === 'vip'.
  return data.isVip === true || data.role === 'vip';
}

export async function getTransactionHistory(uid, limit = 50) {
  const snapshot = await getFirestore()
    .collection(CREDIT_TRANSACTIONS_COLLECTION)
    .where('uid', '==', uid)
    .orderBy('createdAt', 'desc')
    .limit(limit)
    .get();

  return snapshot.docs.map((doc) => _serializeTx(doc.data()));
}

export async function getSubscription(uid) {
  const doc = await getFirestore().collection(SUBSCRIPTIONS_COLLECTION).doc(uid).get();
  if (!doc.exists) return null;
  return _serializeSub(doc.data());
}

// ── Write ────────────────────────────────────────────────────────────────────

/**
 * Atomically adds `amount` credits to the user's balance and records the
 * transaction. Safe to call from Paddle webhook handlers.
 */
export async function addCredits(
  uid,
  amount,
  {
    description,
    paddleTransactionId,
    paddleSubscriptionId,
    type = 'purchase',
    companyId,
  } = {},
) {
  const firestore = getFirestore();
  const userRef = firestore.collection(USERS_COLLECTION).doc(uid);
  const txRef = firestore.collection(CREDIT_TRANSACTIONS_COLLECTION).doc();
  const now = new Date();

  await firestore.runTransaction(async (t) => {
    const userDoc = await t.get(userRef);
    const current = userDoc.exists ? Number(userDoc.data().creditBalance ?? 0) : 0;

    t.set(
      userRef,
      { creditBalance: current + amount, creditUpdatedAt: now },
      { merge: true },
    );

    t.set(txRef, {
      id: txRef.id,
      uid,
      companyId: companyId ?? null,
      type,
      amount,
      balanceAfter: current + amount,
      description: description ?? `Added ${amount} credits`,
      paddleTransactionId: paddleTransactionId ?? null,
      paddleSubscriptionId: paddleSubscriptionId ?? null,
      createdAt: now,
    });
  });
}

/**
 * Atomically deducts `cost` credits and records the spend transaction.
 * Throws if the user has insufficient credits (race-condition safe).
 */
export async function spendCredits(
  uid,
  cost,
  { actionType, projectId, companyId } = {},
) {
  if (await isVipUser(uid)) return; // VIP users spend no credits

  const firestore = getFirestore();
  const userRef = firestore.collection(USERS_COLLECTION).doc(uid);
  const txRef = firestore.collection(CREDIT_TRANSACTIONS_COLLECTION).doc();
  const now = new Date();

  await firestore.runTransaction(async (t) => {
    const userDoc = await t.get(userRef);
    if (!userDoc.exists) throw new Error('User record not found.');
    const current = Number(userDoc.data().creditBalance ?? 0);
    if (current < cost) throw new Error('Insufficient credits.');

    t.set(
      userRef,
      { creditBalance: current - cost, creditUpdatedAt: now },
      { merge: true },
    );

    t.set(txRef, {
      id: txRef.id,
      uid,
      companyId: companyId ?? null,
      type: 'spend',
      amount: -cost,
      balanceAfter: current - cost,
      description: `${actionType ?? 'action'} (${cost} credit${cost !== 1 ? 's' : ''})`,
      actionType: actionType ?? null,
      projectId: projectId ?? null,
      createdAt: now,
    });
  });
}

// ── Subscription ─────────────────────────────────────────────────────────────

export async function upsertSubscription(
  uid,
  { paddleSubscriptionId, planId, status, creditsPerCycle, nextBillDate, companyId },
) {
  const ref = getFirestore().collection(SUBSCRIPTIONS_COLLECTION).doc(uid);
  const now = new Date();

  await ref.set(
    {
      uid,
      companyId: companyId ?? null,
      paddleSubscriptionId,
      planId,
      status,
      creditsPerCycle,
      nextBillDate: nextBillDate ? new Date(nextBillDate) : null,
      updatedAt: now,
    },
    { merge: true },
  );
}

// ── Serialisers ──────────────────────────────────────────────────────────────

function _serializeTx(data) {
  if (!data) return null;
  return {
    ...data,
    createdAt: data.createdAt?.toDate?.()?.toISOString() ?? null,
  };
}

function _serializeSub(data) {
  if (!data) return null;
  return {
    ...data,
    nextBillDate: data.nextBillDate?.toDate?.()?.toISOString() ?? null,
    updatedAt: data.updatedAt?.toDate?.()?.toISOString() ?? null,
  };
}
