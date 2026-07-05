# Complete Payment Flow Documentation

## Overview
This document outlines the complete payment flow from checkout initiation through subscription renewal and status updates. All stages are now properly connected with company context and audit trails.

---

## Stage 1: Checkout Creation
**Endpoint:** `POST /api/credits/checkout`

### Flow:
```
User Request
  ↓
Validate type (pack|subscription) & planId
  ↓
Resolve billing UID (team members → company owner)
  ↓
Create Paddle transaction (with uid in custom_data)
  ↓
Record pending purchase (including companyId) ← NEW: companyId tracking
  ↓
Return checkout URL to client
```

### Data Stored:
- **pending_purchases** collection:
  - `transactionId` (Paddle ID)
  - `uid` (billing user)
  - `companyId` ← NEW: for company attribution
  - `type` (pack|subscription)
  - `planId` (which product)
  - `status` ('pending')
  - `createdAt`

### Key: Company Context Captured
The `companyId` from `req.user.companyId` is stored at checkout time, ensuring reconciliation can properly attribute credits later.

---

## Stage 2: User Completes Payment on Paddle
**Outside our system** — Paddle collects payment and issues webhooks.

---

## Stage 3: Webhook - Payment Completed
**Endpoint:** `POST /api/credits/paddle/webhook` (for `transaction.completed` events)

### Flow:
```
Webhook received from Paddle
  ↓
Verify HMAC signature (Paddle-Signature header)
  ↓
Extract uid from transaction.custom_data
  ↓
  ├─ If subscription renewal: lookup uid via subscription ID ← FALLBACK
  │
  ├─ Fetch companyId from Firestore user doc ← NEW: if not in Paddle data
  │
  └─ Pass companyId to credit grant
     ↓
Credit transaction items (idempotent)
  ├─ One-time pack purchase
  │  └─ addCreditsIdempotent(credits, {companyId, ...})
  │
  └─ Subscription cycle
     └─ addCreditsIdempotent(credits, {companyId, paddleSubscriptionId, ...})
     ↓
Mark pending purchase as 'completed'
```

### Credit Grant (Idempotent):
- **Idempotency key:** `{transactionId}:{priceId}`
- **Stored in `credit_transactions`:**
  - `uid` (billing user)
  - `companyId` ← NEW: for team billing attribution
  - `type` (purchase|subscription|subscription_status_change)
  - `amount` (credits added)
  - `balanceAfter`
  - `paddleTransactionId`
  - `paddleSubscriptionId` (if subscription)
  - `source` ('webhook'|'sync')

### Guarantee:
- Webhook can fire multiple times → idempotent key prevents double-credit
- Each (transaction, price) pair credited at most once

---

## Stage 4: Webhook - Subscription Activated
**Event:** `subscription.activated` or `subscription.updated`

### Flow:
```
Webhook received from Paddle
  ↓
Resolve uid & companyId from subscription
  ├─ Try custom_data.uid
  └─ Fallback: lookup originating transaction
     ↓
For each subscription item (price):
  ├─ Lookup plan by price ID
  └─ upsertSubscription(uid, {
       paddleSubscriptionId,
       planId,
       status,
       creditsPerCycle,
       nextBillDate,
       companyId ← NEW: stored with subscription
     })
```

### Data Stored (`credit_subscriptions` collection):
```javascript
{
  uid: "firebase-uid",
  companyId: "team-id", ← NEW
  paddleSubscriptionId: "ctxn_xxxx",
  planId: "plan_pro",
  status: "active",
  creditsPerCycle: 700,
  nextBillDate: "2026-07-24T00:00:00Z",
  updatedAt: now
}
```

---

## Stage 5: Webhook - Subscription Status Changes
**Events:** `subscription.paused`, `subscription.canceled`, `subscription.past_due`

### Flow:
```
Webhook received
  ↓
Resolve uid & companyId
  ↓
Update subscription status
  ├─ paused → creditsPerCycle: 0, nextBillDate: null
  ├─ canceled → status: 'cancelled', creditsPerCycle: 0
  └─ past_due → status: 'past_due', keep creditsPerCycle
  ↓
Record status change in transaction history ← NEW: audit trail
  └─ credit_transactions entry with type: 'subscription_status_change'
     (visible in user's transaction history)
```

### Audit Trail:
- **When:** subscription paused/canceled
- **What:** New entry in `credit_transactions`:
  - `type: 'subscription_status_change'`
  - `description: 'Subscription {id} status changed to {status}'`
  - `amount: 0` (informational only)
  - `companyId` (for team visibility)

---

## Stage 6: Reconciliation (Safety Net)
**Endpoint:** `POST /api/credits/sync` (user calls when returning from checkout)

### Flow:
```
Client returns from Paddle checkout
  ↓
POST /api/credits/sync
  ↓
List pending purchases for this user
  ↓
For each pending purchase:
  ├─ Fetch actual transaction from Paddle API
  ├─ Check status (completed|pending|canceled)
  │
  └─ If completed:
     ├─ Pass companyId from pending purchase record ← NEW: company context
     ├─ Credit transaction items (same idempotency logic)
     └─ Mark as 'completed'
  
  └─ If still pending/past_due:
     └─ Leave for later check (will reconcile on next sync)
  
  └─ If canceled:
     └─ Mark as 'canceled'
     ↓
Return current balance & subscription status
```

### Why This Matters:
- Webhook might be delayed or dropped
- If client never got the webhook, sync catches it
- Idempotency key prevents double-crediting even if both paths run
- **companyId from pending purchase** ensures credits attributed to correct company

---

## Stage 7: Subscription Renewal (Recurring)
**Event:** `transaction.completed` with `subscription_id` set

### Flow:
```
Monthly billing date arrives
  ↓
Paddle charges subscription & creates transaction
  ↓
Send transaction.completed webhook (may NOT include custom_data)
  ↓
Our webhook handler:
  ├─ Try to extract uid from transaction.custom_data
  │
  └─ If missing: lookup uid via paddleSubscriptionId
     └─ Find subscription in credit_subscriptions collection
     ↓
Fetch companyId from user Firestore doc ← NEW: ensures company context
  ↓
Credit the user (same idempotent logic)
  ├─ amount = subscription.creditsPerCycle
  ├─ idempotencyKey = {transactionId}:{priceId}
  └─ companyId from user doc
```

### Key Points:
- Renewal transactions often lack `custom_data` → we use subscription ID as fallback
- **companyId lookup** ensures team subscriptions credit the company owner
- Credits applied are exactly what was promised (creditsPerCycle from subscription doc)

---

## Stage 8: Status Checks
**Endpoints:** 
- `GET /api/credits/balance` → user's current balance
- `GET /api/credits/subscription` → active subscription details
- `GET /api/credits/transactions` → full history with company attribution

### Query Example:
```javascript
// Fetch subscription (includes companyId)
GET /api/credits/subscription
Response: {
  paddleSubscriptionId: "ctxn_xxxx",
  planId: "plan_pro",
  status: "active",
  creditsPerCycle: 700,
  nextBillDate: "2026-07-24T00:00:00Z",
  companyId: "company-123"
}
```

---

## Data Integrity Guarantees

### 1. **Idempotency**: Exactly-Once Credit Grants
- **Key:** `{paddleTransactionId}:{priceId}`
- **Implementation:** Firestore transaction with guard document
- **Result:** Webhook retry + sync both safe; user never double-credited

### 2. **Company Context**: Preserved Through All Paths
```
Checkout
  └─ companyId captured
     ↓
  ├─ Webhook path
  │  └─ companyId from user lookup (if webhook missing it)
  │
  └─ Sync/reconciliation path
     └─ companyId from pending_purchase record
```

### 3. **Audit Trail**: Full Transaction History
- Every credit grant recorded (purchase|subscription|status_change)
- `source` field shows where it came from (webhook|sync)
- `companyId` enables team-level billing reports
- Status changes visible in transaction history

### 4. **Subscription Metadata**: Consistent
- Stored at activation/update time
- Updated on every status change
- Includes `companyId` for team billing
- `nextBillDate` used for renewal scheduling

---

## Error Scenarios & Recovery

| Scenario | What Happens | Recovery |
|----------|--------------|----------|
| Webhook never arrives | Credits pending | User calls `/sync` → reconciliation fetches from Paddle |
| Webhook arrives late | User sees pending, then credits granted | Idempotency key prevents double-credit |
| User cancels mid-checkout | Transaction marked 'canceled' | `/sync` marks pending purchase 'canceled'; no credits |
| Subscription renewal fails | Paddle sets status to 'past_due' | Webhook updates status; next payment retried by Paddle |
| Custom_data missing on renewal | Falls back to subscription ID lookup | `findUidByPaddleSubscriptionId` finds the owner |
| User lookup fails mid-webhook | Warning logged; no credits granted | Webhook will be retried by Paddle |

---

## Environment Configuration

```bash
# Paddle API
PADDLE_API_KEY=xxx
PADDLE_WEBHOOK_SECRET=xxx
PADDLE_ENVIRONMENT=sandbox|production

# Product Prices (from Paddle Dashboard)
PADDLE_PRICE_50_CREDITS=pri_xxxxx
PADDLE_PRICE_150_CREDITS=pri_xxxxx
PADDLE_PRICE_300_CREDITS=pri_xxxxx
PADDLE_PRICE_STARTER_MONTHLY=pri_xxxxx
PADDLE_PRICE_PRO_MONTHLY=pri_xxxxx

# App
FRONTEND_URL=https://your-domain.com
```

---

## Summary: All Stages Connected ✓

```
Stage 1: Checkout          → companyId recorded
         ↓
Stage 2: User pays         (Paddle handles)
         ↓
Stage 3: Webhook fired     → companyId fetched/passed to credit grant
         ↓
Stage 4: Subscription saved → companyId stored with subscription
         ↓
Stage 5: Status updates    → audit trail with companyId
         ↓
Stage 6: Reconciliation    → companyId from pending purchase
         ↓
Stage 7: Renewal           → companyId from user lookup
         ↓
Stage 8: Status checks     → companyId visible in responses
```

Every stage has company context. Every credit grant is idempotent. Every status change is audited.
