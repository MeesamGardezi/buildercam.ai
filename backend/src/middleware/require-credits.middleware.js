// Purpose: Guards routes that require a minimum credit balance.
//          Runs AFTER verifyFirebaseToken — req.user must be populated.
//          The controller is responsible for deducting credits after a
//          successful action; this middleware only prevents entry when the
//          user cannot afford the action.
import { getCreditBalance, isVipUser } from '../features/credits/credits.service.js';
import { resolveBillingUid } from '../features/credits/billing-uid.js';

/**
 * Returns a middleware that blocks the request with HTTP 402 if the
 * authenticated user's balance is below `cost`.
 *
 * @param {number | ((req: import('express').Request) => number)} costOrResolver
 *   Either a fixed credit cost or a function that computes the cost from the request.
 */
export function requireCredits(costOrResolver) {
  return async (req, res, next) => {
    try {
      const billingUid = await resolveBillingUid(req);

      if (await isVipUser(billingUid)) {
        req.creditCost = 0;
        return next();
      }

      const cost = typeof costOrResolver === 'function' ? costOrResolver(req) : costOrResolver;
      const balance = await getCreditBalance(billingUid);
      if (balance < cost) {
        return res.status(402).json({
          success: false,
          message: `Insufficient credits. This action costs ${cost} credit${cost !== 1 ? 's' : ''} and you have ${balance}.`,
          required: cost,
          balance,
        });
      }
      req.creditCost = cost; // resolved cost available to controller
      return next();
    } catch (err) {
      return res
        .status(500)
        .json({ success: false, message: 'Failed to verify credit balance.' });
    }
  };
}
