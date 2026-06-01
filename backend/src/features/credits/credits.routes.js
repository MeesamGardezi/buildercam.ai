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

export default router;
