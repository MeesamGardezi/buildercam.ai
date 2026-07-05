// Purpose: HTTP handlers for credit balance, checkout creation, and Paddle webhooks.
import {
  getCreditBalance,
  getTransactionHistory,
  getSubscription,
  addCreditsIdempotent,
  upsertSubscription,
  recordPendingPurchase,
  listPendingPurchases,
  resolvePendingPurchase,
  findUidByPaddleSubscriptionId,
  findUidByAppleOriginalTransactionId,
  findUidByAppleTransactionId,
} from './credits.service.js';
import { resolveBillingUid } from './billing-uid.js';
import {
  CREDIT_PACKS,
  SUBSCRIPTION_PLANS,
  createPaddleCheckout,
  getPaddleTransaction,
  verifyPaddleWebhook,
  findPackByPriceId,
  findPlanByPriceId,
  findPackById,
  findPlanById,
} from './paddle.service.js';
import {
  APPLE_CREDIT_PACKS,
  APPLE_SUBSCRIPTION_PLANS,
  getVerifiedTransaction,
  decodeSignedTransaction,
  verifyNotification,
  findPackByAppleProductId,
  findPlanByAppleProductId,
} from './apple-iap.service.js';

const FRONTEND_URL = process.env.FRONTEND_URL ?? 'http://localhost';
const APPLE_PACK_PRODUCT_ID_BY_ID = new Map(APPLE_CREDIT_PACKS.map((p) => [p.id, p.appleProductId]));
const APPLE_PLAN_PRODUCT_ID_BY_ID = new Map(APPLE_SUBSCRIPTION_PLANS.map((p) => [p.id, p.appleProductId]));

// Return targets we allow checkout to redirect back to: the web app over
// http(s), or the mobile app via its custom deep-link scheme.
function _isAllowedReturnUrl(url) {
  return (
    typeof url === 'string' &&
    (url.startsWith('http://') ||
      url.startsWith('https://') ||
      url.startsWith('buildercam://'))
  );
}

class CreditsController {
  // GET /api/credits/balance
  async getBalance(req, res) {
    try {
      const uid = await resolveBillingUid(req);
      const balance = await getCreditBalance(uid);
      return res.json({ success: true, balance });
    } catch (err) {
      return res.status(500).json({ success: false, message: err.message });
    }
  }

  // GET /api/credits/transactions
  async getTransactions(req, res) {
    try {
      const uid = await resolveBillingUid(req);
      const transactions = await getTransactionHistory(uid, 50);
      return res.json({ success: true, transactions });
    } catch (err) {
      return res.status(500).json({ success: false, message: err.message });
    }
  }

  // GET /api/credits/subscription
  async getSubscription(req, res) {
    try {
      const uid = await resolveBillingUid(req);
      const subscription = await getSubscription(uid);
      return res.json({ success: true, subscription });
    } catch (err) {
      return res.status(500).json({ success: false, message: err.message });
    }
  }

  // GET /api/credits/plans  — public catalogue (no auth needed)
  async getPlans(_req, res) {
    return res.json({
      success: true,
      creditPacks: CREDIT_PACKS.map(({ id, credits, priceUsd, label, description }) => ({
        id,
        credits,
        priceUsd,
        label,
        description,
        appleProductId: APPLE_PACK_PRODUCT_ID_BY_ID.get(id) ?? null,
      })),
      subscriptionPlans: SUBSCRIPTION_PLANS.map(
        ({ id, credits, priceUsd, label, description }) => ({
          id,
          credits,
          priceUsd,
          label,
          description,
          appleProductId: APPLE_PLAN_PRODUCT_ID_BY_ID.get(id) ?? null,
        }),
      ),
    });
  }

  // POST /api/credits/checkout
  // Body: { type: 'pack'|'subscription', planId: string, returnUrl?: string }
  async createCheckout(req, res) {
    try {
      const { type, planId, returnUrl } = req.body;

      if (!type || !['pack', 'subscription'].includes(type)) {
        return res.status(400).json({
          success: false,
          message: 'type must be "pack" or "subscription".',
        });
      }
      if (!planId || typeof planId !== 'string') {
        return res.status(400).json({ success: false, message: 'planId is required.' });
      }

      const item =
        type === 'pack' ? findPackById(planId) : findPlanById(planId);

      if (!item) {
        return res.status(400).json({ success: false, message: 'Unknown plan ID.' });
      }
      if (!item.priceId) {
        return res.status(503).json({
          success: false,
          message: 'Paddle is not yet configured for this plan.',
        });
      }

      const destination = _isAllowedReturnUrl(returnUrl)
        ? returnUrl
        : `${FRONTEND_URL}/billing`;

      const billingUid = await resolveBillingUid(req);
      const { url: checkoutUrl, transactionId } = await createPaddleCheckout({
        priceId: item.priceId,
        uid: billingUid,
        email: req.user.email ?? '',
        returnUrl: destination,
      });

      if (!checkoutUrl) {
        // Almost always a Paddle dashboard misconfiguration: no default payment
        // link is set under Checkout settings, so Paddle returns no hosted URL.
        return res.status(502).json({
          success: false,
          message:
            'Paddle did not return a checkout URL. Set a default payment link in your Paddle checkout settings.',
        });
      }

      // Record the pending purchase so /sync can reconcile it against Paddle if
      // the webhook is delayed, dropped, or fails — the safety net.
      await recordPendingPurchase(transactionId, {
        uid: billingUid,
        type,
        planId,
        companyId: req.user.companyId ?? null,
      });

      return res.json({ success: true, checkoutUrl, transactionId });
    } catch (err) {
      return res.status(500).json({ success: false, message: err.message });
    }
  }

  // POST /api/credits/sync
  // Reconciles this user's pending purchases against Paddle and grants any
  // credits that are owed but not yet applied. Idempotent and safe to call
  // repeatedly — this is what the app hits when returning from checkout.
  async sync(req, res) {
    try {
      const uid = await resolveBillingUid(req);
      const pending = await listPendingPurchases(uid);

      let applied = false;
      for (const p of pending) {
        try {
          // Pass the company context from the pending purchase record.
          const result = await this._reconcileTransaction(p.transactionId, uid, p.companyId);
          applied = applied || result.applied;
        } catch (err) {
          // One bad transaction must not abort the rest; log and continue.
          console.error(
            `[credits] sync failed for tx ${p.transactionId}:`,
            err.message,
          );
        }
      }

      const [balance, subscription] = await Promise.all([
        getCreditBalance(uid),
        getSubscription(uid),
      ]);
      return res.json({ success: true, applied, balance, subscription });
    } catch (err) {
      return res.status(500).json({ success: false, message: err.message });
    }
  }

  // POST /api/credits/apple/verify
  // Body: { transactionId }. Called by the iOS app right after StoreKit
  // reports a successful purchase — verifies straight against Apple's own
  // servers (never trusts client-supplied product/credit data) and grants
  // credits idempotently, same as the Paddle paths.
  async verifyApplePurchase(req, res) {
    try {
      const { transactionId } = req.body;
      if (!transactionId || typeof transactionId !== 'string') {
        return res.status(400).json({ success: false, message: 'transactionId is required.' });
      }

      const decoded = await getVerifiedTransaction(transactionId);
      if (decoded.bundleId !== process.env.APPLE_BUNDLE_ID) {
        return res.status(400).json({ success: false, message: 'Transaction bundle id mismatch.' });
      }

      const pack = findPackByAppleProductId(decoded.productId);
      const plan = findPlanByAppleProductId(decoded.productId);
      if (!pack && !plan) {
        return res.status(400).json({ success: false, message: 'Unknown Apple product ID.' });
      }

      const uid = await resolveBillingUid(req);
      const companyId = req.user.companyId ?? null;
      const idempotencyKey = `apple:${decoded.transactionId}`;

      if (pack) {
        await addCreditsIdempotent(uid, pack.credits, {
          idempotencyKey,
          description: `Purchased ${pack.label}`,
          appleTransactionId: decoded.transactionId,
          type: 'purchase',
          companyId,
          source: 'apple',
        });
      } else {
        await addCreditsIdempotent(uid, plan.credits, {
          idempotencyKey,
          description: `${plan.label} plan — ${plan.credits} credits`,
          appleTransactionId: decoded.transactionId,
          appleOriginalTransactionId: decoded.originalTransactionId,
          type: 'subscription',
          companyId,
          source: 'apple',
        });
        await upsertSubscription(uid, {
          appleOriginalTransactionId: decoded.originalTransactionId,
          planId: plan.id,
          status: 'active',
          creditsPerCycle: plan.credits,
          nextBillDate: decoded.expiresDate ? new Date(decoded.expiresDate).toISOString() : null,
          companyId,
        });
      }

      const [balance, subscription] = await Promise.all([
        getCreditBalance(uid),
        getSubscription(uid),
      ]);
      return res.json({ success: true, applied: true, balance, subscription });
    } catch (err) {
      console.error('[credits] Apple verify error:', err);
      return res.status(500).json({ success: false, message: err.message });
    }
  }

  // POST /api/credits/apple/notifications  — App Store Server Notifications V2.
  // Public: Apple signs the payload itself, so there's no Firebase token to check.
  async appleNotifications(req, res) {
    try {
      const signedPayload = req.body?.signedPayload;
      if (!signedPayload) {
        return res.status(400).json({ success: false, message: 'Missing signedPayload.' });
      }
      const decoded = await verifyNotification(signedPayload);
      await this._handleAppleNotification(decoded);
      return res.json({ success: true });
    } catch (err) {
      console.error('[credits] Apple notification error:', err);
      return res.status(500).json({ success: false, message: 'Notification processing failed.' });
    }
  }

  // POST /api/credits/paddle/webhook  — Paddle sends signed events here
  async paddleWebhook(req, res) {
    try {
      const signature = req.headers['paddle-signature'];
      if (!signature) {
        return res
          .status(400)
          .json({ success: false, message: 'Missing Paddle-Signature header.' });
      }

      const rawBody = req.rawBody;
      if (!verifyPaddleWebhook(rawBody, signature)) {
        return res
          .status(401)
          .json({ success: false, message: 'Invalid webhook signature.' });
      }

      await this._handlePaddleEvent(req.body);
      return res.json({ success: true });
    } catch (err) {
      console.error('[credits] Paddle webhook error:', err);
      return res.status(500).json({ success: false, message: 'Webhook processing failed.' });
    }
  }

  // ── Private (Apple) ──────────────────────────────────────────────────────────

  /**
   * Handles a verified App Store Server Notification V2 payload. Renewals and
   * refunds don't carry our uid, so subscriptions are attributed via the
   * appleOriginalTransactionId stored at first-purchase time, and consumable
   * refunds via the appleTransactionId stored on the original credit grant.
   */
  async _handleAppleNotification(decoded) {
    const { notificationType, data } = decoded;
    if (!data?.signedTransactionInfo) return;

    const transaction = await decodeSignedTransaction(data.signedTransactionInfo);
    const plan = findPlanByAppleProductId(transaction.productId);
    const pack = findPackByAppleProductId(transaction.productId);

    if (notificationType === 'SUBSCRIBED' || notificationType === 'DID_RENEW') {
      if (!plan) return;
      const uid = await findUidByAppleOriginalTransactionId(transaction.originalTransactionId);
      if (!uid) {
        console.warn(
          `[credits] Apple ${notificationType} for ${transaction.originalTransactionId} has no resolvable uid; skipping.`,
        );
        return;
      }
      const companyId = await this._getCompanyIdForUid(uid);
      await addCreditsIdempotent(uid, plan.credits, {
        idempotencyKey: `apple:${transaction.transactionId}`,
        description: `${plan.label} plan — ${plan.credits} credits`,
        appleTransactionId: transaction.transactionId,
        appleOriginalTransactionId: transaction.originalTransactionId,
        type: 'subscription',
        companyId,
        source: 'apple-webhook',
      });
      await upsertSubscription(uid, {
        appleOriginalTransactionId: transaction.originalTransactionId,
        planId: plan.id,
        status: 'active',
        creditsPerCycle: plan.credits,
        nextBillDate: transaction.expiresDate
          ? new Date(transaction.expiresDate).toISOString()
          : null,
        companyId,
      });
      return;
    }

    if (['EXPIRED', 'GRACE_PERIOD_EXPIRED', 'REVOKE', 'DID_FAIL_TO_RENEW'].includes(notificationType)) {
      const uid = await findUidByAppleOriginalTransactionId(transaction.originalTransactionId);
      if (!uid) return;
      await upsertSubscription(uid, {
        appleOriginalTransactionId: transaction.originalTransactionId,
        planId: plan?.id ?? 'unknown',
        status: notificationType === 'DID_FAIL_TO_RENEW' ? 'past_due' : 'cancelled',
        creditsPerCycle: 0,
        nextBillDate: null,
        companyId: await this._getCompanyIdForUid(uid),
      });
      return;
    }

    if (notificationType === 'REFUND') {
      const credits = plan?.credits ?? pack?.credits;
      if (!credits) return;

      const uid = plan
        ? await findUidByAppleOriginalTransactionId(transaction.originalTransactionId)
        : await findUidByAppleTransactionId(transaction.transactionId);
      if (!uid) {
        console.warn(
          `[credits] Apple REFUND for ${transaction.transactionId} has no resolvable uid; skipping.`,
        );
        return;
      }

      const companyId = await this._getCompanyIdForUid(uid);
      await addCreditsIdempotent(uid, -credits, {
        idempotencyKey: `apple-refund:${transaction.transactionId}`,
        description: `Refunded ${plan?.label ?? pack?.label ?? 'purchase'}`,
        appleTransactionId: transaction.transactionId,
        appleOriginalTransactionId: transaction.originalTransactionId ?? null,
        type: 'refund',
        companyId,
        source: 'apple-webhook',
      });

      if (plan) {
        await upsertSubscription(uid, {
          appleOriginalTransactionId: transaction.originalTransactionId,
          planId: plan.id,
          status: 'cancelled',
          creditsPerCycle: 0,
          nextBillDate: null,
          companyId,
        });
      }
    }
  }

  // ── Private (Paddle) ─────────────────────────────────────────────────────────

  async _handlePaddleEvent(event) {
    const { event_type: eventType, data } = event;
    if (!data) return;

    // One-time purchases and subscription billing cycles both fire this event.
    if (eventType === 'transaction.completed') {
      // Renewal transactions may not echo custom_data, so fall back to the
      // subscription → uid mapping we stored when the sub was activated.
      let uid = data.custom_data?.uid;
      let companyId = data.custom_data?.companyId ?? null;

      if (!uid && data.subscription_id) {
        uid = await findUidByPaddleSubscriptionId(data.subscription_id);
      }

      // Fetch company context for the billing uid.
      if (uid && !companyId) {
        companyId = await this._getCompanyIdForUid(uid);
      }

      if (!uid) {
        console.warn(`[credits] transaction.completed ${data.id} has no uid; skipping.`);
        return;
      }

      await this._creditTransactionItems(uid, data, 'webhook', companyId);
      // Webhook beat reconciliation to it — stop /sync re-checking.
      await resolvePendingPurchase(data.id, 'completed');
      return;
    }

    // Record / update subscription metadata in Firestore.
    if (eventType === 'subscription.activated' || eventType === 'subscription.updated') {
      const { uid, companyId } = await this._resolveSubscriptionUidAndCompany(data);
      if (!uid) {
        console.warn(`[credits] subscription ${data.id} has no resolvable uid; skipping.`);
        return;
      }

      for (const item of data.items ?? []) {
        const priceId = item.price?.id;
        const plan = findPlanByPriceId(priceId);
        if (plan) {
          await upsertSubscription(uid, {
            paddleSubscriptionId: data.id,
            planId: plan.id,
            status: data.status,
            creditsPerCycle: plan.credits,
            nextBillDate: data.next_billed_at ?? null,
            companyId,
          });
        }
      }
      return;
    }

    // Handle pause and cancellation — both stop future billing.
    if (eventType === 'subscription.paused' || eventType === 'subscription.canceled') {
      const { uid, companyId } = await this._resolveSubscriptionUidAndCompany(data);
      if (!uid) return;

      const isCanceled = eventType === 'subscription.canceled';
      await upsertSubscription(uid, {
        paddleSubscriptionId: data.id,
        planId: 'unknown',
        status: isCanceled ? 'cancelled' : 'paused',
        creditsPerCycle: 0,
        nextBillDate: null,
        companyId,
      });

      // Record the status change in transaction history for audit trail.
      await this._recordSubscriptionStatusChange(uid, data.id, isCanceled ? 'cancelled' : 'paused', companyId);
      return;
    }

    // Past-due subscriptions still accrue credits on successful payment.
    if (eventType === 'subscription.past_due') {
      const { uid, companyId } = await this._resolveSubscriptionUidAndCompany(data);
      if (!uid) return;
      await upsertSubscription(uid, {
        paddleSubscriptionId: data.id,
        planId: this._extractPlanIdFromSubscription(data),
        status: 'past_due',
        creditsPerCycle: this._extractCreditsFromSubscription(data),
        nextBillDate: data.next_billed_at ?? null,
        companyId,
      });
      return;
    }
  }

  /**
   * Grants credits for every recognised line item on a completed transaction.
   * Idempotent: each (transaction, price) pair is granted at most once, so the
   * webhook and the reconciliation path can both run safely.
   * @returns {Promise<{applied: boolean}>}
   */
  async _creditTransactionItems(uid, data, source, companyId = null) {
    const subscriptionId = data.subscription_id ?? null;
    let applied = false;

    for (const item of data.items ?? []) {
      const priceId = item.price?.id ?? item.price_id;
      if (!priceId) continue;

      const pack = findPackByPriceId(priceId);
      if (pack) {
        const r = await addCreditsIdempotent(uid, pack.credits, {
          idempotencyKey: `${data.id}:${priceId}`,
          description: `Purchased ${pack.label}`,
          paddleTransactionId: data.id,
          type: 'purchase',
          companyId,
          source,
        });
        applied = applied || r.applied;
        continue;
      }

      const plan = findPlanByPriceId(priceId);
      if (plan) {
        const r = await addCreditsIdempotent(uid, plan.credits, {
          idempotencyKey: `${data.id}:${priceId}`,
          description: `${plan.label} plan — ${plan.credits} credits`,
          paddleTransactionId: data.id,
          paddleSubscriptionId: subscriptionId,
          type: 'subscription',
          companyId,
          source,
        });
        applied = applied || r.applied;
      }
    }

    return { applied };
  }

  /**
   * Verifies a transaction directly against Paddle and applies any owed credits.
   * Used by the /sync reconciliation endpoint — never trusts client input, only
   * Paddle's own record of the transaction's status.
   * @returns {Promise<{applied: boolean, status: string|null}>}
   */
  async _reconcileTransaction(transactionId, expectedUid, expectedCompanyId = null) {
    const data = await getPaddleTransaction(transactionId);
    if (!data) return { applied: false, status: null };

    if (data.status !== 'completed') {
      // Still pending/past_due/cancelled — leave it for a later check.
      if (data.status === 'canceled') {
        await resolvePendingPurchase(transactionId, 'canceled');
      }
      return { applied: false, status: data.status };
    }

    // Prefer Paddle's own custom_data; fall back to who initiated the checkout.
    const uid = data.custom_data?.uid || expectedUid;
    let companyId = data.custom_data?.companyId ?? expectedCompanyId;

    if (!uid) return { applied: false, status: data.status };

    // Fetch company context if not in Paddle data.
    if (!companyId) {
      companyId = await this._getCompanyIdForUid(uid);
    }

    const result = await this._creditTransactionItems(uid, data, 'sync', companyId);
    await resolvePendingPurchase(transactionId, 'completed');
    return { applied: result.applied, status: data.status };
  }

  /**
   * Resolves the Firebase uid for a subscription event. Paddle usually copies
   * custom_data from the originating transaction onto the subscription, but not
   * always — so we fall back to that transaction when needed.
   * @returns {Promise<{uid: string|null, companyId: string|null}>}
   */
  async _resolveSubscriptionUidAndCompany(data) {
    const uid = data.custom_data?.uid;
    const companyId = data.custom_data?.companyId;

    if (uid) {
      return { uid, companyId: companyId ?? null };
    }

    // Fall back to the originating transaction if custom_data is missing.
    const txnId = data.transaction_id ?? data.first_billing?.transaction_id;
    if (!txnId) {
      return { uid: null, companyId: null };
    }

    try {
      const txn = await getPaddleTransaction(txnId);
      const txnUid = txn?.custom_data?.uid ?? null;
      const txnCompanyId = txn?.custom_data?.companyId ?? null;
      return { uid: txnUid, companyId: txnCompanyId };
    } catch (err) {
      console.warn(`[credits] Failed to resolve subscription uid via transaction ${txnId}:`, err.message);
      return { uid: null, companyId: null };
    }
  }

  /**
   * Fetches the companyId for a given uid from the Firestore user doc.
   * Handles missing users gracefully by returning null.
   */
  async _getCompanyIdForUid(uid) {
    try {
      const { getFirestore } = await import('../../config/firebase-admin.js');
      const doc = await getFirestore().collection('users').doc(uid).get();
      return doc.exists ? (doc.data().companyId ?? null) : null;
    } catch (err) {
      console.warn(`[credits] Failed to fetch companyId for uid ${uid}:`, err.message);
      return null;
    }
  }

  /**
   * Records a subscription status change (pause/cancel) in the transaction history
   * so billing admins can see the audit trail.
   */
  async _recordSubscriptionStatusChange(uid, subscriptionId, status, companyId) {
    try {
      const { getFirestore } = await import('../../config/firebase-admin.js');
      const txRef = getFirestore().collection('credit_transactions').doc();
      await txRef.set({
        id: txRef.id,
        uid,
        companyId: companyId ?? null,
        type: 'subscription_status_change',
        amount: 0,
        balanceAfter: await getCreditBalance(uid),
        description: `Subscription ${subscriptionId} status changed to ${status}`,
        paddleSubscriptionId: subscriptionId,
        createdAt: new Date(),
      });
    } catch (err) {
      console.error(`[credits] Failed to record subscription status change for ${subscriptionId}:`, err.message);
    }
  }

  /**
   * Extracts the plan ID from a subscription's items (helper for status updates).
   */
  _extractPlanIdFromSubscription(data) {
    for (const item of data.items ?? []) {
      const priceId = item.price?.id;
      const plan = findPlanByPriceId(priceId);
      if (plan) return plan.id;
    }
    return 'unknown';
  }

  /**
   * Extracts the total credits from a subscription's items.
   */
  _extractCreditsFromSubscription(data) {
    let total = 0;
    for (const item of data.items ?? []) {
      const priceId = item.price?.id;
      const plan = findPlanByPriceId(priceId);
      if (plan) total += plan.credits;
    }
    return total;
  }
}

export const creditsController = new CreditsController();
