// Purpose: HTTP handlers for credit balance, checkout creation, and Paddle webhooks.
import {
  getCreditBalance,
  getTransactionHistory,
  getSubscription,
  addCredits,
  upsertSubscription,
} from './credits.service.js';
import { resolveBillingUid } from './billing-uid.js';
import {
  CREDIT_PACKS,
  SUBSCRIPTION_PLANS,
  createPaddleCheckout,
  verifyPaddleWebhook,
  findPackByPriceId,
  findPlanByPriceId,
  findPackById,
  findPlanById,
} from './paddle.service.js';

const FRONTEND_URL = process.env.FRONTEND_URL ?? 'http://localhost';

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
      })),
      subscriptionPlans: SUBSCRIPTION_PLANS.map(
        ({ id, credits, priceUsd, label, description }) => ({
          id,
          credits,
          priceUsd,
          label,
          description,
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

      const destination =
        typeof returnUrl === 'string' && returnUrl.startsWith('http')
          ? returnUrl
          : `${FRONTEND_URL}/billing`;

      const billingUid = await resolveBillingUid(req);
      const checkoutUrl = await createPaddleCheckout({
        priceId: item.priceId,
        uid: billingUid,
        email: req.user.email ?? '',
        returnUrl: destination,
      });

      return res.json({ success: true, checkoutUrl });
    } catch (err) {
      return res.status(500).json({ success: false, message: err.message });
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

  // ── Private ────────────────────────────────────────────────────────────────

  async _handlePaddleEvent(event) {
    const { event_type: eventType, data } = event;
    if (!data) return;

    // One-time purchases and subscription billing cycles both fire this event.
    if (eventType === 'transaction.completed') {
      const uid = data.custom_data?.uid;
      if (!uid) return;

      const subscriptionId = data.subscription_id ?? null;

      for (const item of data.items ?? []) {
        const priceId = item.price?.id;
        if (!priceId) continue;

        const pack = findPackByPriceId(priceId);
        if (pack) {
          await addCredits(uid, pack.credits, {
            description: `Purchased ${pack.label}`,
            paddleTransactionId: data.id,
            type: 'purchase',
          });
          continue;
        }

        const plan = findPlanByPriceId(priceId);
        if (plan) {
          await addCredits(uid, plan.credits, {
            description: `${plan.label} plan — ${plan.credits} credits`,
            paddleTransactionId: data.id,
            paddleSubscriptionId: subscriptionId,
            type: 'subscription',
          });
        }
      }
    }

    // Record / update subscription metadata in Firestore.
    if (eventType === 'subscription.activated' || eventType === 'subscription.updated') {
      const uid = data.custom_data?.uid;
      if (!uid) return;

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
          });
        }
      }
    }

    if (eventType === 'subscription.canceled') {
      const uid = data.custom_data?.uid;
      if (!uid) return;
      await upsertSubscription(uid, {
        paddleSubscriptionId: data.id,
        planId: 'unknown',
        status: 'cancelled',
        creditsPerCycle: 0,
        nextBillDate: null,
      });
    }
  }
}

export const creditsController = new CreditsController();
