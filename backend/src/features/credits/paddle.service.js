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
    priceUsd: 2249,          // cents
    label: '50 Credits',
    description: '$22.49 — $0.45 per credit',
  },
  {
    id: 'pack_150',
    priceId: process.env.PADDLE_PRICE_150_CREDITS ?? '',
    credits: 150,
    priceUsd: 5999,
    label: '150 Credits',
    description: '$59.99 — $0.40 per credit',
  },
  {
    id: 'pack_300',
    priceId: process.env.PADDLE_PRICE_300_CREDITS ?? '',
    credits: 300,
    priceUsd: 11249,
    label: '300 Credits',
    description: '$112.49 — $0.37 per credit',
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
 * Creates a Paddle transaction and returns the hosted checkout URL.
 * @param {object} opts
 * @param {string} opts.priceId   - Paddle price ID for the item
 * @param {string} opts.uid       - Firebase UID stored as custom_data
 * @param {string} opts.email     - Customer email pre-filled in checkout
 * @param {string} opts.returnUrl - Page to redirect to after payment
 */
export async function createPaddleCheckout({ priceId, uid, email, returnUrl }) {
  const body = {
    items: [{ price_id: priceId, quantity: 1 }],
    customer: { email },
    custom_data: { uid },
    checkout: { url: returnUrl },
  };
  const data = await _paddleFetch('POST', '/transactions', body);
  return data.data?.checkout?.url ?? null;
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
