// Purpose: Resolve the uid whose credit wallet should be charged for a request.
//          Team members share their company owner's wallet, so all credit
//          checks and spends must route through the owner's uid.
import { getFirestore } from '../../config/firebase-admin.js';

const COMPANIES_COLLECTION = 'companies';

/**
 * Core resolver — accepts a plain user object `{uid, role, companyId}`.
 * Owners (or users without a companyId) bill to themselves; members resolve
 * to their company's `ownerUid`.
 */
export async function resolveBillingUidForUser({ uid, role, companyId }) {
  if (role === 'owner' || !companyId) return uid;
  try {
    const doc = await getFirestore()
      .collection(COMPANIES_COLLECTION)
      .doc(companyId)
      .get();
    return (doc.exists ? doc.data().ownerUid : null) || uid;
  } catch {
    return uid;
  }
}

/**
 * HTTP-request wrapper around resolveBillingUidForUser. Memoises the result
 * on the request object so repeated calls within the same request are free.
 */
export async function resolveBillingUid(req) {
  if (!req?.user) return null;
  if (req.billingUid) return req.billingUid;
  req.billingUid = await resolveBillingUidForUser(req.user);
  return req.billingUid;
}
