// Purpose: Express routes for the credits & billing feature.
import { Router } from 'express';
import { verifyFirebaseToken } from '../../middleware/firebase-auth.middleware.js';
import { creditsController } from './credits.controller.js';

const router = Router();

// ── Public ───────────────────────────────────────────────────────────────────

// Paddle webhook — verified by HMAC signature, not by Firebase token.
router.post('/paddle/webhook', (req, res) =>
  creditsController.paddleWebhook(req, res),
);

// Apple App Store Server Notifications — verified by Apple's JWS signature.
router.post('/apple/notifications', (req, res) =>
  creditsController.appleNotifications(req, res),
);

// Plan catalogue — unauthenticated so the landing page can display pricing.
router.get('/plans', (req, res) => creditsController.getPlans(req, res));

// ── Authenticated ─────────────────────────────────────────────────────────────

router.use(verifyFirebaseToken);

router.get('/balance', (req, res) => creditsController.getBalance(req, res));
router.get('/transactions', (req, res) =>
  creditsController.getTransactions(req, res),
);
router.get('/subscription', (req, res) =>
  creditsController.getSubscription(req, res),
);
router.post('/checkout', (req, res) =>
  creditsController.createCheckout(req, res),
);
// Reconcile pending purchases against Paddle — the safety net the app calls
// when returning from checkout in case the webhook was delayed or missed.
router.post('/sync', (req, res) => creditsController.sync(req, res));

// Verify an Apple IAP purchase straight against Apple's servers and grant credits.
router.post('/apple/verify', (req, res) =>
  creditsController.verifyApplePurchase(req, res),
);

export default router;
