// Purpose: Resolve the uid whose credit wallet should be charged for a request.
//          Team members share their company owner's wallet, so all credit
//          checks and spends must route through the owner's uid.
import { getFirestore } from '../../config/firebase-admin.js';

const COMPANIES_COLLECTION = 'companies';

/**
 * Returns the wallet uid for the authenticated request. Owners use their own
 * uid; members resolve to their company's `ownerUid`. The result is memoised
 * on the request as `req.billingUid`.
 */
export async function resolveBillingUid(req) {
  if (!req?.user) return null;
  if (req.billingUid) return req.billingUid;

  const { uid, role, companyId } = req.user;
  if (role === 'owner' || !companyId) {
    req.billingUid = uid;
    return uid;
  }

  try {
    const doc = await getFirestore()
      .collection(COMPANIES_COLLECTION)
      .doc(companyId)
      .get();
    const ownerUid = doc.exists ? doc.data().ownerUid : null;
    req.billingUid = ownerUid || uid;
  } catch {
    req.billingUid = uid;
  }
  return req.billingUid;
}
