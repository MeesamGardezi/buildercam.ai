// Purpose: Paddle Billing API wrapper — checkout creation and webhook verification.
import crypto from 'node:crypto';

const IS_PRODUCTION = process.env.PADDLE_ENVIRONMENT === 'production';
const PADDLE_API_BASE = IS_PRODUCTION
  ? 'https://api.paddle.com'
  : 'https://sandbox-api.paddle.com';

const PADDLE_API_KEY = process.env.PADDLE_API_KEY ?? '';
const PADDLE_WEBHOOK_SECRET = process.env.PADDLE_WEBHOOK_SECRET ?? '';

// ── Product catalogue ─────────────────────────────────────────────────────────

/**
 * One-time credit packs.
 * Direct purchase: ~$0.45–$0.37 / credit.
 * Compare to subscriptions: ~$0.33–$0.28 / credit.
 */
export const CREDIT_PACKS = [
  {
    id: 'pack_50',
    priceId: process.env.PADDLE_PRICE_50_CREDITS ?? '',
    credits: 50,
    priceUsd: 1750,          // cents — $0.35 per credit
    label: '50 Credits',
    description: '$17.50 — $0.35 per credit',
  },
  {
    id: 'pack_150',
    priceId: process.env.PADDLE_PRICE_150_CREDITS ?? '',
    credits: 150,
    priceUsd: 4500,          // cents — $0.30 per credit
    label: '150 Credits',
    description: '$45.00 — $0.30 per credit',
  },
  {
    id: 'pack_300',
    priceId: process.env.PADDLE_PRICE_300_CREDITS ?? '',
    credits: 300,
    priceUsd: 7500,          // cents — $0.25 per credit
    label: '300 Credits',
    description: '$75.00 — $0.25 per credit',
  },
];

/**
 * Monthly subscription plans.
 * Starter $49/mo → 300 credits ($0.16/credit).
 * Pro     $99/mo → 700 credits ($0.14/credit).
 */
export const SUBSCRIPTION_PLANS = [
  {
    id: 'plan_starter',
    priceId: process.env.PADDLE_PRICE_STARTER_MONTHLY ?? '',
    credits: 300,
    priceUsd: 4900,
    label: 'Starter',
    description: '$49 / month — 300 credits ($0.16 each)',
  },
  {
    id: 'plan_pro',
    priceId: process.env.PADDLE_PRICE_PRO_MONTHLY ?? '',
    credits: 700,
    priceUsd: 9900,
    label: 'Pro',
    description: '$99 / month — 700 credits ($0.14 each)',
  },
];

// ── Lookup helpers ────────────────────────────────────────────────────────────

export function findPackByPriceId(priceId) {
  return CREDIT_PACKS.find((p) => p.priceId && p.priceId === priceId) ?? null;
}

export function findPlanByPriceId(priceId) {
  return SUBSCRIPTION_PLANS.find((p) => p.priceId && p.priceId === priceId) ?? null;
}

export function findPackById(id) {
  return CREDIT_PACKS.find((p) => p.id === id) ?? null;
}

export function findPlanById(id) {
  return SUBSCRIPTION_PLANS.find((p) => p.id === id) ?? null;
}

// ── API calls ─────────────────────────────────────────────────────────────────

async function _paddleFetch(method, path, body = null) {
  if (!PADDLE_API_KEY) {
    throw new Error('PADDLE_API_KEY is not configured.');
  }
  const url = `${PADDLE_API_BASE}${path}`;
  const options = {
    method,
    headers: {
      Authorization: `Bearer ${PADDLE_API_KEY}`,
      'Content-Type': 'application/json',
    },
  };
  if (body) options.body = JSON.stringify(body);

  const res = await fetch(url, options);
  const json = await res.json();
  if (!res.ok) {
    throw new Error(`Paddle API ${res.status}: ${JSON.stringify(json?.error ?? json)}`);
  }
  return json;
}

/**
 * Creates a Paddle transaction and returns the hosted checkout URL plus the
 * transaction id, so the caller can record a pending purchase for later
 * reconciliation (the safety net for missed/delayed webhooks).
 *
 * @param {object} opts
 * @param {string} opts.priceId   - Paddle price ID for the item
 * @param {string} opts.uid       - Firebase UID stored as custom_data
 * @param {string} opts.email     - Customer email pre-filled in checkout
 * @param {string} opts.returnUrl - Page/app deep-link to return to after payment
 * @returns {Promise<{url: string|null, transactionId: string|null, customerId: string|null}>}
 */
export async function createPaddleCheckout({ priceId, uid, email, returnUrl }) {
  const body = {
    items: [{ price_id: priceId, quantity: 1 }],
    // uid travels with the transaction AND any subscription Paddle spawns from
    // it, so webhooks and reconciliation can always attribute the payment.
    custom_data: { uid },
    checkout: { url: returnUrl },
  };
  // Only attach a customer when we actually have an email; Paddle rejects
  // an empty-string email.
  if (email) body.customer = { email };

  const data = await _paddleFetch('POST', '/transactions', body);
  return {
    url: data.data?.checkout?.url ?? null,
    transactionId: data.data?.id ?? null,
    customerId: data.data?.customer_id ?? null,
  };
}

/**
 * Fetches a single transaction straight from the Paddle API. Used by the
 * reconciliation endpoint to confirm a payment really completed before
 * granting credits — never trust the client, only Paddle's own record.
 * @param {string} transactionId
 * @returns {Promise<object|null>} The Paddle transaction `data` object.
 */
export async function getPaddleTransaction(transactionId) {
  if (!transactionId) return null;
  const data = await _paddleFetch('GET', `/transactions/${transactionId}`);
  return data.data ?? null;
}

// ── Webhook verification ──────────────────────────────────────────────────────

/**
 * Verifies a Paddle webhook signature.
 * Paddle-Signature header format: "ts=<timestamp>;h1=<hmac-sha256>"
 *
 * @param {string} rawBody  - Raw request body string (must not be JSON.parsed yet)
 * @param {string} signature - Value of the Paddle-Signature header
 * @returns {boolean}
 */
export function verifyPaddleWebhook(rawBody, signature) {
  if (!PADDLE_WEBHOOK_SECRET) return false;
  if (!signature || !rawBody) return false;

  const parts = Object.fromEntries(
    signature.split(';').map((part) => {
      const idx = part.indexOf('=');
      return [part.slice(0, idx), part.slice(idx + 1)];
    }),
  );
  const ts = parts['ts'];
  const h1 = parts['h1'];
  if (!ts || !h1) return false;

  const signedPayload = `${ts}:${rawBody}`;
  const expected = crypto
    .createHmac('sha256', PADDLE_WEBHOOK_SECRET)
    .update(signedPayload)
    .digest('hex');

  try {
    // timingSafeEqual prevents timing-attack probing of the secret.
    return crypto.timingSafeEqual(Buffer.from(h1, 'hex'), Buffer.from(expected, 'hex'));
  } catch {
    return false;
  }
}
