# Reverse API Architecture — Edge Cases

## Sync Path (Obj 1–3)

### 1. Partner timeout during order placement

User has committed, Backend's circuit breaker trips mid-checkout. Fail the order or queue it? If queued, the partner's price/availability may have changed by the time the circuit closes.

**Answer:** Fail fast and tell the user. Don't queue. The order contract requires the partner to validate availability and pricing at submission time — a stale queued order would likely be rejected anyway. The Backend returns a retriable error to the app ("Partner temporarily unavailable, try again in a moment"). The `Idempotency-Key: mapco_order_{id}` header means the user can retry safely without risk of duplicate orders. If the circuit breaker is open, the app can show which restaurants are currently affected and suggest alternatives from other partners. The key principle: never silently accept an order you can't confirm with the partner in real time.

---

### 2. Price drift between cart build and order submit

User adds items (menu GET cached via ETag), but by the time `POST /v1/orders` fires, the partner's prices changed. Server-side price validation rejects the order. User sees a "price changed" error on a cart they spent minutes building.

**Answer:** This is handled by the architecture's price validation step. When the partner's `POST /v1/orders` response returns `total_amount`, the Backend compares it against what the user was shown. If the delta exceeds a threshold (e.g., 2%), the Backend rejects the order, re-fetches the menu (bypassing cache with `If-None-Match`), and returns the updated prices to the app. The app shows a diff: "Margherita is now €13.00 (was €12.00). Confirm?" rather than a generic error. To reduce frequency: keep `Cache-Control: max-age=300` short (5 min is already reasonable), and re-validate the cart total client-side against cached prices before submitting. This won't eliminate the race but narrows the window.

---

### 3. ETag staleness window

Partner updates menu but cache hasn't expired. User orders an item now unavailable. Partner rejects with 409/422. How granular is cache invalidation? Do partners have a way to bust the cache proactively?

**Answer:** The contract already handles this at the order layer — `POST /v1/orders` returns `422 item_unavailable` if something is out of stock. So the cache staleness doesn't cause silent failures, just a slightly worse UX (user sees an item, tries to order it, gets rejected). To improve: (1) partners can set shorter `max-age` for volatile menus (e.g., 60s for a restaurant that 86's items frequently), (2) add an optional `POST /v1/webhooks/menu-events` webhook where partners push `menu.item_unavailable` events to proactively invalidate specific cache entries, (3) on any `422 item_unavailable` response, the Backend immediately invalidates the cached menu for that restaurant and re-fetches. Option 3 is the minimum viable approach and requires no contract changes.

---

### 4. Parallel fan-out to N partners for restaurant dedup

One partner responds in 50ms, another in 4s. Wait for all? Return partial results after a deadline? Timing out a slow partner makes its restaurants disappear intermittently.

**Answer:** Use a deadline with progressive rendering. Set a hard deadline (e.g., 2s) for the fan-out. Return results from all partners that responded within the deadline. For partners that timed out, return the results anyway using the last cached response (even if the ETag is stale — stale listings are better than missing listings). Mark those results with a `freshness: "cached"` flag so the app can optionally show a subtle indicator. On the backend, continue waiting for the slow partner in the background and update the cache when it responds, so the next request is fresh. If a partner consistently exceeds the deadline, the circuit breaker opens and the Backend serves cached data for that partner until it recovers. The user never sees restaurants vanish — they see slightly stale data at worst.

---

## Async Path (Obj 4)

### 5. Webhook replay after recovery

Receiver was down 10 minutes. Partner retries queued events. `event_id` dedup works, but if the partner's retry window is shorter than the downtime, events are lost permanently and the fallback poll must cover the gap.

**Answer:** The retry contract specifies exponential backoff: 1s, 5s, 30s, 2min, 10min — total window ~15 minutes. A 10-minute outage is within that window, so most events will be retried and received. For outages exceeding 15 minutes, the fallback poll kicks in. The Backend should track "last webhook received" per order. If an order is in an active state (not `delivered` or `cancelled`) and no webhook has arrived within the expected window for the current status (e.g., 10 minutes past `confirmed` with no `preparing`), the Backend polls `GET /v1/orders/{id}` to catch up. The poll response includes `status_history`, so the Backend can reconstruct any missed transitions. To make this more robust: after any outage recovery, run a batch poll for all orders in active states to reconcile, rather than waiting for individual timeouts.

---

### 6. Out-of-order webhooks

Partner sends `order.accepted` then `order.picked_up`, but network delivers them reversed. DB state machine must handle or reject out-of-sequence transitions. Rejecting depends on the partner retrying the earlier event.

**Answer:** Accept both, use timestamps to resolve. Each webhook carries a `timestamp` field. The DB should store events in an append-only event log (not just current status). When processing a webhook: (1) always write to the event log regardless of order, (2) update the "current status" field only if the incoming event's timestamp is newer than the current status timestamp. This means `order.picked_up` (timestamp T2) arrives first and sets current status. When `order.accepted` (timestamp T1) arrives later, it's written to the log but doesn't regress the current status because T1 < T2. The state machine diagram in the architecture doc defines valid transitions — if an event arrives that's not a valid successor of the current state, log it but don't update current status. The app always shows the latest valid state.

---

### 7. HMAC key rotation

Partner rotates signing secret. During the rotation window, valid webhooks may be rejected if only the old key is checked. Need to verify against both old and new keys temporarily.

**Answer:** Support two active keys per partner. During onboarding, each partner gets a `primary_secret` and a `secondary_secret` slot. The webhook receiver tries to verify against the primary first; if that fails, it tries the secondary. Rotation process: (1) partner generates a new secret via an onboarding/admin API, (2) Map.co stores it in the secondary slot, (3) partner starts signing with the new secret, (4) after a grace period (e.g., 24 hours), Map.co promotes secondary to primary and clears the old one. This is the same pattern Stripe uses for webhook endpoint secrets. The grace period ensures in-flight webhooks signed with the old key are still accepted.

---

### 8. Duplicate event_id with different payloads

Malicious or buggy partner sends the same `event_id` with contradictory data. Dedup accepts the first, silently drops the second. If the first was corrupted, state is wrong.

**Answer:** First-write-wins is the correct default for idempotency. To mitigate corruption: (1) log the full payload of every received webhook (including duplicates that were dropped) for audit, (2) if a duplicate `event_id` arrives with a different payload hash, flag it as an anomaly and alert the ops team — this should never happen in normal operation, (3) for the malicious case, the HMAC signature verification already prevents external attackers from injecting events. A compromised partner key is a separate security incident. For the buggy case, the conformance test suite (edge case #14) should validate that partners generate unique `event_id` values and don't reuse them. In practice, if state is wrong due to a corrupted first event, the fallback poll will eventually correct it because `GET /v1/orders/{id}` returns the partner's current state, which overwrites the corrupted webhook data.

---

## Fallback Poll Path

### 9. Poll storm

Webhooks fail for multiple orders simultaneously. Backend polls `GET /v1/orders/{id}` for all of them. N orders × M partners = rate limit pressure. Need backoff and concurrency limits per partner.

**Answer:** Rate-limit polls per partner with a token bucket. Each partner gets a poll budget (e.g., 10 requests/second). When the budget is exhausted, additional polls are queued with exponential backoff. Prioritize polls by order age and user activity — an order where the user is actively watching the tracking screen gets priority over a background order. Batch where possible: if the partner supports it, add a `GET /v1/orders?ids=ord_1,ord_2,...` batch endpoint to the contract (this is a contract extension worth considering). During a webhook outage affecting one partner, the Backend should detect the pattern (multiple orders from the same partner all missing webhooks) and switch to a single periodic bulk poll rather than per-order polls. Alert the partner's ops team via the partner dashboard.

---

### 10. Poll returns stale data

Partner's read replica is behind the write path. Poll returns `order.accepted` while the missed webhook already sent `order.delivered`. State regresses.

**Answer:** Never regress state. The same rule from edge case #6 applies: the DB state machine only moves forward. If the current status is `delivered` (from a webhook) and a poll returns `accepted`, the poll result is logged but the current status is not updated. The `status_history` array in the poll response helps — if it contains `delivered` in the history, the Backend can reconcile even if the top-level `status` field is stale. Additionally, the Backend should compare the poll's `status_history` timestamps against its own event log and only apply transitions that are both (a) newer than the current state and (b) valid according to the state machine. If the poll consistently returns stale data, it's a signal that the partner's read path has replication lag — worth flagging in partner health monitoring.

---

## Payment / Settlement Boundary

### 11. Order cancelled after payment collected

Map.co collected from the user, partner cancels (kitchen closed, driver unavailable). Refund is entirely on Map.co's side. Partner has no visibility into refund success. If batch settlement already ran, clawback happens next cycle.

**Answer:** The `order.cancelled` webhook triggers an automatic refund flow on Map.co's side. The Backend receives the webhook, updates order status to `cancelled`, and initiates a refund to the user's original payment method. The refund is Map.co's responsibility — the partner doesn't need to know whether it succeeded because the partner never touched the payment. For settlement: the cancelled order is excluded from the next batch settlement. If settlement already ran (the order was settled before cancellation), Map.co deducts the amount from the partner's next settlement cycle as a "clawback" line item. The settlement ledger should track: `order_id`, `original_settlement_date`, `cancellation_date`, `clawback_settlement_date`, `amount`. The partner sees this in their settlement report. Edge case within the edge case: if the user's payment method can't be refunded (expired card, closed account), Map.co absorbs the loss and still claws back from the partner — the partner caused the cancellation.

---

### 12. Partner disputes settlement amount

Map.co's batch settlement says €X, partner's records say €Y. No shared ledger. Reconciliation depends on both sides logging the same order totals, which depends on price validation being airtight.

**Answer:** The `total_amount` in the `POST /v1/orders` response is the single source of truth for what the partner charged. Map.co stores this value at order creation time. The settlement is computed from Map.co's stored `total_amount` values, not from any subsequent recalculation. To make disputes resolvable: (1) every order record includes the partner's `total_amount` response, Map.co's displayed price, and the validation result (match/mismatch/threshold), (2) the settlement report sent to partners includes per-order line items with `order_id`, `total_amount`, `settlement_amount`, `commission_deducted`, (3) partners can query a `GET /v1/settlements/{period}/orders` endpoint to download the full order-level breakdown and compare against their own records. If there's a discrepancy, it traces back to a specific `order_id` where the two sides recorded different `total_amount` values — which means the price validation step failed or was bypassed. That's a bug, not a business dispute.

---

### 13. Partial fulfillment

Partner delivers 4 of 5 items. Who decides the adjusted total? If `order.completed` webhook includes a revised total, price validation logic must handle partial amounts, not just full-order validation.

**Answer:** The partner decides the adjusted total — they're the ones who know what was actually delivered. Add an optional `revised_total_amount` field to the `order.delivered` webhook payload, along with a `fulfilled_items` array listing what was actually delivered. Map.co's Backend compares `revised_total_amount` against the original `total_amount`. If lower, Map.co issues a partial refund to the user for the difference and adjusts the settlement amount for the partner. If the partner doesn't send `revised_total_amount` (field is optional), Map.co assumes full fulfillment and settles at the original amount — disputes go through the reconciliation process from #12. The contract should specify that `revised_total_amount` can only be less than or equal to `total_amount`, never higher. This is a contract extension worth adding to the webhook event types: `order.delivered` with optional partial fulfillment data.

---

## Operational

### 14. Partner onboarding — contract conformance

Partner N+1 implements `GET /v1/restaurants` with wrong pagination, or returns `total_price` as string instead of integer. Need a conformance test suite partners run before going live, or bugs surface in production.

**Answer:** Provide a conformance test suite as part of the onboarding SDK. The suite is a set of automated tests that partners run against their own API before requesting production access. It covers: (1) schema validation — every endpoint returns the correct JSON structure with correct types (integers for amounts, not strings), (2) pagination — `GET /v1/restaurants` with `limit=1&offset=0` returns exactly 1 result and correct `total`, (3) idempotency — `POST /v1/orders` with the same `Idempotency-Key` returns the same response, (4) error codes — sending an invalid request returns the correct 4xx status and error code, (5) webhook signing — the partner's webhook sender produces a valid HMAC-SHA256 signature that Map.co's verifier accepts. Map.co also runs a shadow traffic phase during onboarding: route a small percentage of real requests to the new partner alongside an existing partner and compare responses for consistency. The partner gets a "conformance score" dashboard showing pass/fail per test. Production access requires 100% pass rate.

---

### 15. Single partner outage cascades

Circuit breaker opens for Partner A. Restaurants served exclusively by Partner A vanish from the app. Users see restaurants disappear and reappear. Need "temporarily unavailable" state rather than hiding them.

**Answer:** When the circuit breaker opens for a partner, the Backend should not remove that partner's restaurants from listings. Instead: (1) serve the last cached restaurant list for that partner (from the most recent successful `GET /v1/restaurants` response), (2) mark those restaurants with `"availability": "limited"` or `"partner_status": "degraded"` in the response to the app, (3) the app shows these restaurants with a visual indicator ("Ordering may be delayed") rather than hiding them, (4) if the user tries to order from a degraded restaurant, the app shows "This restaurant's delivery partner is experiencing issues. Try again shortly or choose another restaurant." This way restaurants don't flicker in and out of the listing. The circuit breaker state is per-partner, so restaurants served by multiple partners can fall back to a healthy partner transparently. Track circuit breaker open/close events in a partner health dashboard and alert Map.co ops if a partner's circuit breaker has been open for more than 5 minutes.
