// Purpose: Firestore credit-wallet operations — balance, spend, add, history.
import admin from 'firebase-admin';
import { getFirestore } from '../../config/firebase-admin.js';

const USERS_COLLECTION = 'users';
const CREDIT_TRANSACTIONS_COLLECTION = 'credit_transactions';
const SUBSCRIPTIONS_COLLECTION = 'credit_subscriptions';
// Guard docs that make credit grants exactly-once across webhook + reconciliation.
const IDEMPOTENCY_COLLECTION = 'credit_idempotency';
// Purchases we initiated; reconciliation reads these to verify against Paddle.
const PENDING_PURCHASES_COLLECTION = 'pending_purchases';

/** Credits required per action type. */
export const CREDIT_COSTS = {
  transcript: 1,         // audio-only transcript
  transcript_video: 2,   // video transcript (has frameUrls)
  sow_generation: 3,
  pdf_generation: 3,
  sow_document: 1,       // new SOW document save
  pdf_document: 1,       // new PDF document save
  voice_session: 1,      // per VOICE_SESSION_MINUTES_PER_CREDIT minutes of voice chat
};

/** One credit covers this many minutes of voice conversation. */
export const VOICE_SESSION_MINUTES_PER_CREDIT = 5;

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
  // No orderBy — Firestore needs a composite index for where+orderBy on
  // different fields and none is created yet. Sort in JS after fetch instead.
  const snapshot = await getFirestore()
    .collection(CREDIT_TRANSACTIONS_COLLECTION)
    .where('uid', '==', uid)
    .get();

  return snapshot.docs
    .map((doc) => _serializeTx(doc.data()))
    .filter(Boolean)
    .sort((a, b) => {
      const tA = a.createdAt ? new Date(a.createdAt).getTime() : 0;
      const tB = b.createdAt ? new Date(b.createdAt).getTime() : 0;
      return tB - tA;
    })
    .slice(0, limit);
}

export async function getSubscription(uid) {
  const doc = await getFirestore().collection(SUBSCRIPTIONS_COLLECTION).doc(uid).get();
  if (!doc.exists) return null;
  return _serializeSub(doc.data());
}

/**
 * Reverse lookup: which uid owns a given Paddle subscription. Lets renewal
 * transactions be attributed even if Paddle doesn't echo custom_data on them.
 */
export async function findUidByPaddleSubscriptionId(paddleSubscriptionId) {
  if (!paddleSubscriptionId) return null;
  const snapshot = await getFirestore()
    .collection(SUBSCRIPTIONS_COLLECTION)
    .where('paddleSubscriptionId', '==', paddleSubscriptionId)
    .limit(1)
    .get();
  return snapshot.empty ? null : (snapshot.docs[0].data().uid ?? null);
}

/**
 * Reverse lookup: which uid owns a given Apple subscription. Apple server
 * notifications (renewals, cancellations) don't carry our uid, so this is how
 * they get attributed after the original purchase was verified once.
 */
export async function findUidByAppleOriginalTransactionId(appleOriginalTransactionId) {
  if (!appleOriginalTransactionId) return null;
  const snapshot = await getFirestore()
    .collection(SUBSCRIPTIONS_COLLECTION)
    .where('appleOriginalTransactionId', '==', appleOriginalTransactionId)
    .limit(1)
    .get();
  return snapshot.empty ? null : (snapshot.docs[0].data().uid ?? null);
}

/**
 * Reverse lookup for consumable (credit pack) refunds: which uid was granted
 * credits for a given Apple transaction. Consumables have no subscription doc
 * to look the uid up from, so this reads the original credit_transactions entry.
 */
export async function findUidByAppleTransactionId(appleTransactionId) {
  if (!appleTransactionId) return null;
  const snapshot = await getFirestore()
    .collection(CREDIT_TRANSACTIONS_COLLECTION)
    .where('appleTransactionId', '==', appleTransactionId)
    .limit(1)
    .get();
  return snapshot.empty ? null : (snapshot.docs[0].data().uid ?? null);
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
 * Exactly-once version of {@link addCredits}. The `idempotencyKey` (typically
 * `<paddleTransactionId>:<priceId>`) is written as a guard doc inside the SAME
 * Firestore transaction as the balance increment. If the guard already exists
 * the grant is skipped. This is what makes it safe for the webhook AND the
 * reconciliation endpoint to both process the same payment — and for Paddle to
 * retry webhooks — without ever double-crediting.
 *
 * @returns {Promise<{applied: boolean, balance: number}>}
 */
export async function addCreditsIdempotent(
  uid,
  amount,
  {
    idempotencyKey,
    description,
    paddleTransactionId,
    paddleSubscriptionId,
    appleTransactionId,
    appleOriginalTransactionId,
    type = 'purchase',
    companyId,
    source,
  } = {},
) {
  if (!uid) throw new Error('addCreditsIdempotent: uid is required.');
  if (!idempotencyKey) throw new Error('addCreditsIdempotent: idempotencyKey is required.');

  const firestore = getFirestore();
  const userRef = firestore.collection(USERS_COLLECTION).doc(uid);
  const idemRef = firestore.collection(IDEMPOTENCY_COLLECTION).doc(idempotencyKey);
  const txRef = firestore.collection(CREDIT_TRANSACTIONS_COLLECTION).doc();
  const now = new Date();

  return firestore.runTransaction(async (t) => {
    // All reads must precede all writes in a Firestore transaction.
    const idemDoc = await t.get(idemRef);
    const userDoc = await t.get(userRef);
    const current = userDoc.exists ? Number(userDoc.data().creditBalance ?? 0) : 0;

    if (idemDoc.exists) {
      // Already granted by an earlier webhook / sync / retry — no-op.
      return { applied: false, balance: current };
    }

    const next = current + amount;

    t.set(userRef, { creditBalance: next, creditUpdatedAt: now }, { merge: true });

    t.set(txRef, {
      id: txRef.id,
      uid,
      companyId: companyId ?? null,
      type,
      amount,
      balanceAfter: next,
      description: description ?? `Added ${amount} credits`,
      paddleTransactionId: paddleTransactionId ?? null,
      paddleSubscriptionId: paddleSubscriptionId ?? null,
      appleTransactionId: appleTransactionId ?? null,
      appleOriginalTransactionId: appleOriginalTransactionId ?? null,
      createdAt: now,
    });

    t.set(idemRef, {
      key: idemRef.id,
      uid,
      amount,
      type,
      paddleTransactionId: paddleTransactionId ?? null,
      creditTransactionId: txRef.id,
      source: source ?? null, // 'webhook' | 'sync' — for debugging which path won
      createdAt: now,
    });

    return { applied: true, balance: next };
  });
}

/**
 * Atomically deducts `cost` credits and records the spend transaction.
 * Returns `true` if credits were deducted, `false` if the user is VIP (no deduction).
 * Throws if the user has insufficient credits (race-condition safe).
 */
export async function spendCredits(
  uid,
  cost,
  { actionType, projectId, projectName, companyId } = {},
) {
  if (await isVipUser(uid)) return false; // VIP users spend no credits

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
      projectName: projectName ?? null,
      createdAt: now,
    });
  });

  return true; // credits were actually deducted
}

// ── Subscription ─────────────────────────────────────────────────────────────

export async function upsertSubscription(
  uid,
  {
    paddleSubscriptionId,
    appleOriginalTransactionId,
    planId,
    status,
    creditsPerCycle,
    nextBillDate,
    companyId,
  },
) {
  const ref = getFirestore().collection(SUBSCRIPTIONS_COLLECTION).doc(uid);
  const now = new Date();

  const data = {
    uid,
    companyId: companyId ?? null,
    planId,
    status,
    creditsPerCycle,
    nextBillDate: nextBillDate ? new Date(nextBillDate) : null,
    updatedAt: now,
  };
  if (paddleSubscriptionId !== undefined) data.paddleSubscriptionId = paddleSubscriptionId;
  if (appleOriginalTransactionId !== undefined) {
    data.appleOriginalTransactionId = appleOriginalTransactionId;
  }

  await ref.set(data, { merge: true });
}

// ── Pending purchases (reconciliation) ─────────────────────────────────────────

/**
 * Records a purchase we just initiated so the reconciliation endpoint can later
 * verify it against Paddle even if the webhook never arrives. Keyed by the
 * Paddle transaction id so it maps 1:1 to the eventual webhook/transaction.
 * Stores companyId so reconciliation can properly attribute credits.
 */
export async function recordPendingPurchase(
  transactionId,
  { uid, type, planId, companyId } = {},
) {
  if (!transactionId || !uid) return;
  await getFirestore()
    .collection(PENDING_PURCHASES_COLLECTION)
    .doc(transactionId)
    .set(
      {
        transactionId,
        uid,
        type: type ?? null,
        planId: planId ?? null,
        companyId: companyId ?? null,
        status: 'pending',
        createdAt: new Date(),
      },
      { merge: true },
    );
}

/**
 * Returns this user's not-yet-reconciled purchases (most recent first).
 * Equality-only filters need no composite index.
 */
export async function listPendingPurchases(uid, limit = 10) {
  if (!uid) return [];
  const snapshot = await getFirestore()
    .collection(PENDING_PURCHASES_COLLECTION)
    .where('uid', '==', uid)
    .where('status', '==', 'pending')
    .limit(limit)
    .get();
  return snapshot.docs.map((d) => d.data());
}

/** Marks a pending purchase as resolved so we stop re-checking it. */
export async function resolvePendingPurchase(transactionId, status = 'completed') {
  if (!transactionId) return;
  await getFirestore()
    .collection(PENDING_PURCHASES_COLLECTION)
    .doc(transactionId)
    .set({ status, resolvedAt: new Date() }, { merge: true });
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
