// Purpose: Apple App Store Server API wrapper — transaction verification and
//          signed-notification decoding, using Apple's official server library.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  AppStoreServerAPIClient,
  SignedDataVerifier,
  Environment,
} from '@apple/app-store-server-library';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const APPLE_ENVIRONMENT =
  process.env.APPLE_ENVIRONMENT === 'Production' ? Environment.PRODUCTION : Environment.SANDBOX;
const APPLE_BUNDLE_ID = process.env.APPLE_BUNDLE_ID ?? '';
const APPLE_APP_ID = process.env.APPLE_APP_ID ? Number(process.env.APPLE_APP_ID) : undefined;
const APPLE_ISSUER_ID = process.env.APPLE_ISSUER_ID ?? '';
const APPLE_KEY_ID = process.env.APPLE_KEY_ID ?? '';
// .env stores literal "\n" sequences inside a quoted value; restore real newlines.
const APPLE_PRIVATE_KEY = (process.env.APPLE_PRIVATE_KEY ?? '').replace(/\\n/g, '\n');

// ── Product catalogue ─────────────────────────────────────────────────────────
// `id` matches the shared plan/pack id used by paddle.service.js so credits and
// subscription bookkeeping stay provider-agnostic downstream.

export const APPLE_CREDIT_PACKS = [
  { id: 'pack_50', appleProductId: 'ai.buildercam.credits.pack50', credits: 50, label: '50 Credits' },
  { id: 'pack_150', appleProductId: 'ai.buildercam.credits.pack150', credits: 150, label: '150 Credits' },
  { id: 'pack_300', appleProductId: 'ai.buildercam.credits.pack300', credits: 300, label: '300 Credits' },
];

export const APPLE_SUBSCRIPTION_PLANS = [
  { id: 'plan_starter', appleProductId: 'ai.buildercam.sub.starter', credits: 300, label: 'Starter' },
  { id: 'plan_pro', appleProductId: 'ai.buildercam.sub.pro', credits: 700, label: 'Pro' },
];

export function findPackByAppleProductId(productId) {
  return APPLE_CREDIT_PACKS.find((p) => p.appleProductId === productId) ?? null;
}

export function findPlanByAppleProductId(productId) {
  return APPLE_SUBSCRIPTION_PLANS.find((p) => p.appleProductId === productId) ?? null;
}

// ── Apple client / verifier setup ─────────────────────────────────────────────

let _client = null;
function getClient() {
  if (_client) return _client;
  if (!APPLE_PRIVATE_KEY || !APPLE_KEY_ID || !APPLE_ISSUER_ID || !APPLE_BUNDLE_ID) {
    throw new Error('Apple IAP is not configured (missing APPLE_* env vars).');
  }
  _client = new AppStoreServerAPIClient(
    APPLE_PRIVATE_KEY,
    APPLE_KEY_ID,
    APPLE_ISSUER_ID,
    APPLE_BUNDLE_ID,
    APPLE_ENVIRONMENT,
  );
  return _client;
}

let _verifier = null;
function getVerifier() {
  if (_verifier) return _verifier;
  if (!APPLE_BUNDLE_ID) {
    throw new Error('Apple IAP is not configured (missing APPLE_BUNDLE_ID).');
  }
  const rootCert = fs.readFileSync(path.join(__dirname, 'apple-certs', 'AppleRootCA-G3.cer'));
  _verifier = new SignedDataVerifier(
    [rootCert],
    true, // enableOnlineChecks — revocation/expiry checks against the current date
    APPLE_ENVIRONMENT,
    APPLE_BUNDLE_ID,
    APPLE_APP_ID,
  );
  return _verifier;
}

// ── Verification ──────────────────────────────────────────────────────────────

/**
 * Decodes+verifies a signedTransactionInfo JWS — whether it came fresh from
 * getTransactionInfo or embedded in a notification's `data.signedTransactionInfo`.
 * @returns {Promise<import('@apple/app-store-server-library').JWSTransactionDecodedPayload>}
 */
export async function decodeSignedTransaction(signedTransactionInfo) {
  return getVerifier().verifyAndDecodeTransaction(signedTransactionInfo);
}

/**
 * Fetches a single transaction from Apple's own servers by id and decodes+
 * verifies its signed JWS. Never trusts client-supplied product/credit data —
 * only what Apple's signed response says.
 * @returns {Promise<import('@apple/app-store-server-library').JWSTransactionDecodedPayload>}
 */
export async function getVerifiedTransaction(transactionId) {
  const response = await getClient().getTransactionInfo(transactionId);
  if (!response.signedTransactionInfo) {
    throw new Error(`Apple returned no signedTransactionInfo for transaction ${transactionId}.`);
  }
  return decodeSignedTransaction(response.signedTransactionInfo);
}

/**
 * Decodes+verifies an App Store Server Notification V2 `signedPayload`.
 * @returns {Promise<import('@apple/app-store-server-library').ResponseBodyV2DecodedPayload>}
 */
export async function verifyNotification(signedPayload) {
  return getVerifier().verifyAndDecodeNotification(signedPayload);
}
