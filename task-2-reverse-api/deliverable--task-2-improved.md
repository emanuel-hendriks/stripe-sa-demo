# Map.co Food Ordering — Reverse API Design

## Context

Map.co (think Google Maps) has signed partnerships with the largest on-demand food delivery companies worldwide — the most prominent being Food.co (think Uber Eats, DoorDash). The goal: let Map.co users order food from nearby restaurants directly inside the Maps app, without switching to another app.

The frontend team has built a working UX. The delivery partners have agreed to integrate against a "reverse API" — an interface of Map.co's design where Map.co makes the requests and partners handle them.

**User flow:**
1. Select a restaurant
2. View the menu and select/customize items
3. Make the order
4. Track the order

**Design objectives:**
1. High-level architecture between Map.co and Food.co partners
2. API endpoints each Food.co partner must implement, with key request/response fields
3. Additional functionality Map.co needs to expose to each partner 

1. Webhook receiver (POST /v1/webhooks/delivery-events) -- partners push order status updates here. 
Map.co has to expose this endpoint, document the expected payload format, provide the HMAC shared 
secret, and define the retry policy.

2. Partner registration/onboarding -- partners need to receive their API credentials (api_key for 
Map.co to authenticate against them) and webhook secret (for them to sign calls to Map.co). Map.co 
exposes this provisioning flow.


---

## The Problem

Map.co has hundreds of millions of users. Food.co has restaurants, couriers, and logistics. The opportunity: let users order food without leaving the map.

The naive approach -- build a custom integration per partner -- doesn't scale. N partners means N connectors with different endpoints, data formats, auth, and error codes, all maintained independently.

The reverse API inverts this. Map.co publishes one spec; all partners conform to it. Adding a partner means they implement the same contract -- Map.co's code doesn't change. Same principle as USB: one standard plug, every manufacturer adapts. Partners agree because Map.co's distribution is the leverage -- access to demand they can't generate alone.

The API covers four operations matching the user journey: find restaurants, browse a menu, place an order, track delivery. Everything else -- payment, user accounts, the map UI -- stays on Map.co's side.

---

## Architecture Overview

Two systems, two communication patterns. Map.co on one side, partners on the other. REST for the synchronous request-response flow, webhooks for the asynchronous event-driven flow.

### System Diagram

```mermaid
graph LR
    App["Map.co App<br/>(mobile + web)"]
    Backend["Map.co Backend<br/>(orchestrator)"]
    Partners["Food.co<br/>MealDash<br/>QuickBite<br/>... (N partners)"]
    DB["Order State<br/>(database)"]
    Webhook["Webhook Receiver<br/>(HMAC-verified)"]

    App -- "1" --> Backend
    Backend -- "2" --> App
    Backend -- "3" --> Partners
    Partners -- "4" --> Backend
    Partners -- "5" --> Webhook
    Backend -- "6" --> DB
    Webhook -- "7" --> DB
```

**Nodes**

- **Map.co App** -- User interface: restaurants, menus, order form, live tracking.
- **Map.co Backend** -- Orchestrator. Calls partner APIs, stores order state, receives webhooks. Never exposes partner APIs directly to the app (controls caching, error handling, failover).
- **Food.co Partner API** -- Every partner implements the same contract. Map.co talks to all of them identically.
- **Webhook Receiver** -- Listens at `POST /v1/webhooks/delivery-events`. Validates HMAC signature, deduplicates on `event_id`, writes status to the Order State DB. Ingestion point for all partner-pushed events.
- **Order State DB** -- Map.co's source of truth for order status. Every change (webhook or polling fallback) lands here. `status_history` timestamps power per-partner SLA enforcement (e.g., detecting courier no-shows).

**Edges**

Edges 1--4 are synchronous (user-initiated request-response). Edge 5 is asynchronous (partner-pushed).

1. **App -> Backend** -- User action (open map, tap restaurant, confirm order) sent to backend.
2. **Backend -> App** -- Response rendered in UI (restaurant list, menu, order confirmation, tracking status).
3. **Backend -> Partner API** -- The core boundary. Map.co calls the partner over HTTP using the reverse API contract. This is the design surface of the entire system.
4. **Partner API -> Backend** -- JSON response (restaurant data, order confirmation, status).
5. **Partner -> Webhook Receiver** -- Async push when state changes on the partner side (courier assigned, food ready, delivered).

## Sync path -- user-initiated, request-response.

Covers restaurant discovery, menu browsing, order placement, and cancellation. User does something 
in the app, Backend calls the partner, partner responds, Backend writes to DB and returns to the 
app. The user is waiting for the response.

Examples: user opens the map -> Backend calls GET `/v1/restaurants` -> partner returns nearby 
restaurants -> app renders them. User confirms order -> Backend calls `POST /v1/orders` -> partner 
returns `order_id` and confirmed status -> Backend persists the order record to DB -> app shows 
confirmation.

##  Async path -- partner-initiated, event-driven.

Covers order tracking. After the order is placed, the user isn't triggering anything -- state 
changes happen on the partner's side (kitchen starts cooking, courier picks up, courier delivers). 
The partner pushes these via webhook to Map.co's receiver, which validates the signature, 
deduplicates, writes to DB, and pushes to the user's app over WebSocket.

Examples: courier picks up the food -> partner POSTs order.picked_up webhook -> receiver writes to 
DB -> app updates the tracking screen in real time. Food is delivered -> partner POSTs 
order.delivered -> receiver writes to DB -> app shows "delivered."

The direction of communication flips: in the sync path, Map.co calls partners. In the async path, 
partners call Map.co.



## Endpoints at a Glance

The reverse API has five endpoints that Food.co partners must implement, plus a webhook that Map.co exposes.

| # | Method | Endpoint | Purpose |
|---|--------|----------|---------|
| 1 | `GET` | `/v1/restaurants` | List nearby open restaurants |
| 2 | `GET` | `/v1/restaurants/{id}/menu` | Get a restaurant's menu (supports ETag caching) |
| 3 | `POST` | `/v1/orders` | Place an order |
| 4 | `GET` | `/v1/orders/{id}` | Get order status (fallback for webhooks) |
| 5 | `POST` | `/v1/orders/{id}/cancel` | Cancel an order |

```
GET /v1/restaurants/rest_982/menu HTTP/1.1
Host: api.foodco.com
Authorization: Bearer maps_live_sk_abc123
X-Maps-Request-Id: req_a1b2c3
If-None-Match: "menu-rest_982-v7"
Accept-Language: de-DE
```
Map.co also exposes a **webhook endpoint** that partners call to push real-time order status updates (courier assigned, food ready, delivered).

### What Triggers Each API Call

Every synchronous API call is triggered by a user action in the Map.co app.

| User Action | Calls |
|-------------|-------|
| Opens the map, pans, or zooms | `GET /v1/restaurants` |
| Taps a restaurant | `GET /v1/restaurants/{id}/menu` |
| Confirms an order | `POST /v1/orders` |
| Opens the tracking screen | `GET /v1/orders/{id}` |
| Taps "Cancel order" | `POST /v1/orders/{id}/cancel` |

The exception is **webhooks**: they flow in the opposite direction — Food.co calls Map.co whenever something changes on their side.

---

## API Endpoints — Detail

All endpoints are implemented by Food.co partners. Map.co Backend is the caller.

Base URL per partner: `https://api.foodco.example/v1`

All monetary amounts are in **minor units** (cents). EUR 15.00 = `1500`.

---

### 1. Select a Restaurant

**`GET /v1/restaurants`**

Returns restaurants near the user that are currently accepting orders.

Request (query params):

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `lat` | float | yes | User latitude |
| `lng` | float | yes | User longitude |
| `radius_km` | float | no | Search radius. Default: 5 |
| `cuisine` | string | no | Filter: "italian", "sushi", etc. |
| `limit` | int | no | Page size. Default: 20 |
| `offset` | int | no | Pagination offset. Default: 0 |

Response `200`:

```json
{
  "restaurants": [
    {
      "id": "rest_abc123",
      "name": "Pizza Hut",
      "address": "Friedrichstr. 42, 10117 Berlin",
      "lat": 52.5200,
      "lng": 13.4050,
      "cuisine": "italian",
      "rating": 4.6,
      "estimated_delivery_min": 35,
      "is_open": true,
      "min_order_amount": 1500
    }
  ],
  "total": 87,
  "limit": 20,
  "offset": 0
}
```

```
curl -s "https://api.foodco.example/v1/restaurantslat=52.52&lng=13.40&radius_km=5&limit=20&offset=0" \
  -H "Authorization: Bearer mk_live_partner_abc123"
```


`is_open` reflects real-time operating hours. `estimated_delivery_min` is a live estimate based on current kitchen/courier load. Pagination follows the `limit`/`offset` pattern; `total` lets the client calculate page count.

---

### 2. View the Menu and Customize Items

**`GET /v1/restaurants/{restaurant_id}/menu`**

Returns the full menu for a restaurant, grouped by category. Each item includes available customizations so the user can modify their selection before ordering.

**Caching:** Menus change infrequently (a few times per day) but get fetched thousands of times per hour for popular restaurants. Partners return `ETag` and `Cache-Control` headers to enable conditional requests.

Response headers:

| Header | Example Value | Purpose |
|--------|---------------|---------|
| `ETag` | `"menu_v42"` | Version identifier for the current menu state |
| `Cache-Control` | `max-age=300` | Map.co can serve cached menu for 5 minutes without re-fetching |

On subsequent requests, Map.co sends `If-None-Match: "menu_v42"`. If the menu hasn't changed, the partner returns `304 Not Modified` with no body. If it has changed, the partner returns the full menu with a new ETag.

For real-time item availability (e.g. "Lobster tails is sold out"), a 5-minute cache staleness is acceptable because the order endpoint validates freshness at submission time and returns `422 item_unavailable` for out-of-stock items.

Response `200`:

```json
{
  "restaurant_id": "rest_abc123",
  "categories": [
    {
      "name": "Pizza",
      "items": [
        {
          "id": "item_001",
          "name": "Margherita",
          "description": "Tomato, mozzarella, basil",
          "price": 1200,
          "currency": "eur",
          "available": true,
          "customizations": [
            {
              "id": "cust_size",
              "name": "Size",
              "type": "single_select",
              "required": true,
              "options": [
                { "id": "opt_s", "name": "Small (26cm)", "price_delta": 0 },
                { "id": "opt_l", "name": "Large (32cm)", "price_delta": 400 }
              ]
            },
            {
              "id": "cust_toppings",
              "name": "Extra Toppings",
              "type": "multi_select",
              "required": false,
              "max_selections": 3,
              "options": [
                { "id": "opt_mush", "name": "Mushrooms", "price_delta": 150 },
                { "id": "opt_olives", "name": "Olives", "price_delta": 100 }
              ]
            }
          ]
        }
      ]
    }
  ]
}
```

```http
GET /v1/restaurants/rest_abc123/menu HTTP/1.1
Host: api.foodco.com
Authorization: Bearer maps_live_sk_abc123
X-Maps-Request-Id: req_a1b2c3
If-None-Match: "menu_v42"
Accept-Language: de-DE

HTTP/1.1 304 Not Modified
ETag: "menu_v42"
```

**Customization model:**

- `type: "single_select"` -- user picks exactly one (e.g. size). `required: true` means the order fails without it.
- `type: "multi_select"` -- user picks zero to `max_selections` (e.g. toppings). `required: false` means it's optional.
- `price_delta` is added to the base `price`. Large Margherita with mushrooms = 1200 + 400 + 150 = EUR 17.50.

The user's selections are submitted in the order request (see Objective 3).

---

### 3. Make the Order

**`POST /v1/orders`**

Map.co places an order on behalf of the user. This is the most important endpoint.

Request headers:

| Header | Value |
|--------|-------|
| `Authorization` | `Bearer {partner_api_key}` |
| `Idempotency-Key` | `mapco_order_{map_order_id}` |

**3. Make the Order** 

Request body:
```json
POST /v1/orders HTTP/1.1
Host: api.foodco.com
Authorization: Bearer maps_live_sk_abc123
Idempotency-Key: mapco_order_789
Content-Type: application/json
X-Maps-Request-Id: req_d4e5f6

{
  "restaurant_id": "rest_982",
  "maps_order_ref": "maps_ord_789",
  "items": [
    {
      "item_id": "item_42",
      "quantity": 2,
      "notes": "no onions",
      "customizations": [
        { "customization_id": "cust_size", "selected": ["opt_l"] },
        { "customization_id": "cust_toppings", "selected": ["opt_mush"] }
      ]
    },
    { "item_id": "item_17", "quantity": 1 }
  ],
  "delivery_address": {
    "street": "Maximilianstrasse 10",
    "city": "Munich",
    "postal_code": "80539",
    "country": "DE",
    "lat": 48.1391,
    "lng": 11.5802
  },
  "customer": {
    "name": "Max Mustermann",
    "phone": "+49 170 1234567"
  },
  "requested_delivery_at": "2026-03-23T13:00:00Z",
  "currency": "EUR"
}
```

Response `201`:

```json
{
  "order_id": "ord_food_456",
  "status": "confirmed",
  "estimated_delivery_min": 40,
  "total_amount": 3200,
  "currency": "eur",
  "created_at": "2026-03-23T12:30:00Z"
}
```

**Key design decisions:**

- **Idempotency-Key** prevents duplicate orders on network retries. Same key + same body = return original response. Same key + different body = `409 Conflict`. Same pattern as Stripe's `POST /v1/payment_intents`.
- **`payment_reference`** is Map.co's internal payment ID. Food.co does NOT process payment. Map.co collects from the user and settles with Food.co in a daily batch (see Payment and Settlement).
- **Food.co validates and prices the order.** The `total_amount` in the response is Food.co's calculated total, not what Map.co sent. Food.co checks item availability, applies customization pricing, and returns the authoritative total.

**Error responses:**

| Status | Code | When |
|--------|------|------|
| `400` | `invalid_request` | Missing required fields, malformed body |
| `409` | `idempotency_conflict` | Same key, different body |
| `422` | `restaurant_closed` | Restaurant not accepting orders |
| `422` | `item_unavailable` | One or more items out of stock |
| `422` | `below_minimum` | Order total below restaurant minimum |

---

### 4. Track the Order
```
POST /v1/webhooks/delivery-events HTTP/1.1
Host: api.maps.co
Authorization: Bearer foodco_wh_sk_xyz789
X-Webhook-Signature: sha256=a1b2c3d4e5...
X-Webhook-Timestamp: 1711191540
Content-Type: application/json
X-Maps-Request-Id: req_g7h8i9

{
  "event_id": "evt_abc123",
  "event_type": "order.status_updated",
  "partner_id": "food_co",
  "timestamp": "2026-03-23T12:55:00Z",
  "data": {
    "order_id": "ord_food_456",
    "maps_order_ref": "maps_ord_789",
    "status": "ready_for_pickup",
    "courier": {
      "name": "Lisa",
      "location": { "lat": 48.1351, "lng": 11.5820 }
    },
    "estimated_arrival_at": "2026-03-23T13:10:00Z"
  }
}
```
**`GET /v1/orders/{order_id}`**

```http
GET /v1/orders/ord_food_456 HTTP/1.1
Host: api.foodco.com
Authorization: Bearer maps_live_sk_abc123
X-Maps-Request-Id: req_m3n4o5

```

Returns current order status. This is a **fallback** — the primary mechanism is webhooks. Map.co uses this for initial page load or if webhooks are delayed.

Response `200`:

```json
{
  "order_id": "ord_food_456",
  "status": "en_route",
  "status_history": [
    { "status": "confirmed",        "at": "2026-03-23T12:30:00Z" },
    { "status": "preparing",        "at": "2026-03-23T12:32:00Z" },
    { "status": "ready_for_pickup", "at": "2026-03-23T12:55:00Z" },
    { "status": "picked_up",        "at": "2026-03-23T12:58:00Z" },
    { "status": "en_route",         "at": "2026-03-23T12:59:00Z" }
  ],
  "courier": {
    "name": "Lisa"
  },
  "estimated_arrival_at": "2026-03-23T13:10:00Z"
}
```

**Order status state machine:**

```
confirmed → preparing → ready_for_pickup → picked_up → en_route → delivered
     │           │                                          │
     └───────────┴──────────────────────────────────────────┴──→ cancelled
```

Transitions are one-way. `cancelled` can happen from most states, but not after `delivered`. The `courier` object appears once a courier is assigned (from `picked_up` onward).

Success:

```http
HTTP/1.1 202 Accepted

{
  "event_id": "evt_abc123",
  "status": "received"
}
```
Duplicate (already processed):

```http
HTTP/1.1 200 OK

{
  "event_id": "evt_abc123",
  "status": "already_processed"
}
```

Signature invalid:

```http
HTTP/1.1 401 Unauthorized

{
  "error": {
    "code": "invalid_signature",
    "message": "Webhook signature verification failed"
  }
}
```


---

### 5. Order Cancellation

**`POST /v1/orders/{order_id}/cancel`**

Maps.co calls this when the user requests cancellation. Cancellability depends on order status -- partners reject if the order is too far along.

Path params:

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `order_id` | string | yes | Partner's order identifier |

Request body:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `maps_order_ref` | string | yes | Maps.co's order reference |
| `reason` | string | yes | `customer_requested`, `payment_failed` |

Error codes:

| Status | Code | When |
|--------|------|------|
| 404 | `order_not_found` | Order does not exist |
| 409 | `cancellation_not_allowed` | Order is `picked_up`, `en_route`, or `delivered` |
| 429 | `rate_limited` | Too many requests |

Request:

```http
POST /v1/orders/ord_food_456/cancel HTTP/1.1
Host: api.foodco.com
Authorization: Bearer maps_live_sk_abc123
Content-Type: application/json
X-Maps-Request-Id: req_s9t0u1

{
  "maps_order_ref": "maps_ord_789",
  "reason": "customer_requested"
}
```

Response (200 OK -- cancelled, no fee):

```http
HTTP/1.1 200 OK

{
  "order_id": "ord_food_456",
  "maps_order_ref": "maps_ord_789",
  "status": "cancelled",
  "cancelled_at": "2026-03-23T12:34:00Z",
  "cancellation_fee": 0,
  "currency": "EUR"
}
```

Response (200 OK -- cancelled, with fee):

```http
HTTP/1.1 200 OK

{
  "order_id": "ord_food_456",
  "maps_order_ref": "maps_ord_789",
  "status": "cancelled",
  "cancelled_at": "2026-03-23T12:45:00Z",
  "cancellation_fee": 500,
  "currency": "EUR"
}
```

`cancellation_fee` may be non-zero if the restaurant already started preparing (e.g. 500 = EUR 5.00). Maps.co decides whether to absorb this or pass it to the user based on cancellation policy and timing.

Response (409 -- too late to cancel):

```http
HTTP/1.1 409 Conflict

{
  "error": {
    "code": "cancellation_not_allowed",
    "message": "Order is already in_transit and cannot be cancelled"
  }
}
```

Response (404 -- order not found):

```http
HTTP/1.1 404 Not Found

{
  "error": {
    "code": "order_not_found",
    "message": "Order ord_xyz999 not found"
  }
}
```

---
# Additional Features 

## Webhooks — Food.co Calls Map.co

Polling `GET /orders/{id}` every few seconds doesn't scale across millions of orders for state transitions. Instead, Food.co pushes status updates to Map.co.

**`POST https://api.mapco.com/webhooks/partner/order-status`**

Request headers:

| Header | Value |
|--------|-------|
| `X-Webhook-Signature` | HMAC-SHA256 of the raw body using a shared secret |
| `X-Webhook-Timestamp` | Unix timestamp when the event was created |

Request body:

```json
{
  "event_type": "order.status_updated",
  "order_id": "ord_food_456",
  "status": "picked_up",
  "timestamp": "2026-03-23T12:58:00Z",
  "courier": {
    "name": "Lisa"
  },
  "estimated_arrival_at": "2026-03-23T13:10:00Z"
}
```

**Signature verification:** Map.co computes `HMAC-SHA256(webhook_secret, timestamp + "." + raw_body)` and compares it to the header. Rejects if the timestamp is older than 5 minutes (replay protection). Same algorithm as Stripe's `Stripe-Signature` with `v1=` signatures.

**Retry policy:** If Map.co returns non-2xx, Food.co retries with exponential backoff: 1s, 5s, 30s, 5min, 1hr. After 24 hours of failures, the event is dropped and Map.co falls back to polling.

**Idempotency:** Map.co handles duplicate webhook deliveries using `order_id` + `status` + `timestamp` as a dedup key. Processing the same event twice is a no-op.

---

## Partner Onboarding and Developer Experience

### Credential Provisioning

**`POST https://api.mapco.com/partners/register`** (Map.co endpoint)

Response:

```json
{
  "partner_id": "partner_foodco",
  "api_key": "mk_live_...",
  "webhook_secret": "whsec_...",
  "webhook_url": "https://api.mapco.com/webhooks/partner/order-status",
  "sandbox_url": "https://sandbox.mapco.com"
}
```

- `api_key`: Map.co sends as `Authorization: Bearer` when calling Food.co's endpoints.
- `webhook_secret`: shared secret for HMAC signatures on webhooks.
- `webhook_url`: where Food.co sends status updates.
- `sandbox_url`: test environment for integration development.

The `api_key` / `webhook_secret` pair maps directly to Stripe's publishable key / webhook signing secret pair.

### Developer Experience

Map.co provides three things to reduce integration friction:

1. **Sandbox environment.** A test environment where partners develop against mock data without real orders, real users, or real money. The sandbox simulates the full order lifecycle: Map.co sends test requests, the partner returns responses, webhooks flow back, and both sides validate the integration end-to-end. Same model as Stripe's test mode.

2. **Reference implementation.** A sample server (Python and Node) that passes all contract tests. Partners use it as a starting point or as a reference to verify their own implementation.

3. **Contract test suite.** An automated test suite partners run against their own API before going live. It exercises every endpoint, validates response schemas, tests error cases, and verifies webhook delivery. Map.co gates production access on passing the test suite.

### Rollout Strategy

Food.co is the design partner — the largest partner, with the engineering capacity to implement quickly. Their feedback shapes the spec. Once the API is stable (v1.1 after ~3 months of production traffic), Map.co opens onboarding to additional partners.

---

## Cross-Cutting Concerns

**Authentication:** Every request from Map.co to Food.co carries `Authorization: Bearer {partner_api_key}`. Every webhook from Food.co to Map.co carries an HMAC signature. Two-way trust.

**Error format:** All errors return a consistent structure:
```json
{
  "error": {
    "code": "restaurant_closed",
    "message": "Pizza Hut is currently closed. Opens at 11:00."
  }
}
```
`code` is machine-readable (programmatic handling). `message` is human-readable (logging/debugging).

**Rate limiting:** Food.co returns `429 Too Many Requests` with a `Retry-After` header. Map.co respects it. This protects partners from traffic spikes during promotions or outages.

**Versioning:** API version in the URL path (`/v1/`, `/v2/`). Adding new fields to a response is backwards-compatible. Removing fields or changing types requires a new version. Map.co supports each major version for at least 12 months after the next version launches.

**Currencies:** All amounts in minor units. `currency` field on every response that includes an amount. No implicit currency assumptions.

---

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Reverse API (Map.co defines, Food.co implements)** | One spec, many partners. Scales to 50 delivery companies without 50 custom integrations. |
| **Map.co owns payment** | Partners never handle money. This keeps PCI scope and refund logic out of the partner contract, and gives Map.co control over holds, commission, and disputes. |
| **Webhooks for order tracking** | Webhooks give real-time state updates with retries. `GET /v1/orders/{id}` remains as a fallback. |
| **ETag caching on menus** | Menus change rarely but get fetched constantly. Conditional requests with ETags eliminate redundant data transfer. The order endpoint validates freshness at submission time, so a briefly stale menu is safe. |
| **Idempotency on order creation** | Network failures happen. Without `Idempotency-Key` header, a retry could create a duplicate order |
| **Status history on the order object** | Customer support and debugging need the full timeline, not just the current state. Also useful for SLA tracking and settlement reconciliation. |
| **Partner-specific base URLs** | Each partner hosts their own API. Map.co routes to the correct partner based on `partner_id`. Partners control their own infrastructure, scaling, and deployments. |
| **Food.co first as design partner, then scale** | One flagship partner stabilizes the spec under real traffic before opening to additional partners. |


### Payment and Settlement

Map.co handles payment collection separately. The partner receives a `payment_reference` on the order but never processes payment or sees card details.

```mermaid
sequenceDiagram
    participant User as User
    participant App as Map.co App
    participant Pay as Map.co Payment<br/>(Stripe, Apple Pay, etc.)
    participant Backend as Map.co Backend
    participant Partner as Food.co

    User->>App: Confirms order
    App->>Pay: Collect payment
    Pay-->>App: payment_reference=mapco_pay_xyz789
    App->>Backend: Place order (with payment_reference)
    Backend->>Partner: POST /v1/orders (payment_reference in body)
    Note over Partner: Food.co never sees card details.<br/>Settles with Map.co separately.
```

**Settlement:** Daily batch per partner — aggregate delivered orders, subtract Map.co's commission (15-20%), single transfer. Report includes order-level line items for reconciliation.

**Reconciliation:** Daily comparison of Map.co's order DB against the partner's records. Discrepancies (delivered vs cancelled mismatches) flagged for manual review.

**Stripe Connect parallel:** Map.co = platform, partners = connected accounts. Each order maps to Separate Charges and Transfers with `application_fee_amount` for commission. The `payment_reference` correlates deliveries with payments across both systems.

### Multiple Partners per Restaurant

The same restaurant (e.g. Pizza Hut) can be listed by more than one delivery partner. When the user searches, Map.co queries all partners in parallel, merges the results, and picks the best option per restaurant. The user sees one listing per restaurant, not one per partner.

```
GET /v1/restaurants?lat=48.1391&lng=11.5802&radius=3000
  -> api.foodco.com
  -> api.eatsde.com
  -> api.delivereu.com

  Maps.co Backend
  |
  |--- GET /v1/restaurants?lat=48.1391&lng=11.5802&radius=3000 ---> api.foodco.com
  |
  |--- GET /v1/restaurants?lat=48.1391&lng=11.5802&radius=3000 ---> api.eatsde.com
  |
  |--- GET /v1/restaurants?lat=48.1391&lng=11.5802&radius=3000 ---> api.delivereu.com
```

```mermaid
graph TD
    Search["User searches near Friedrichstr."]
    Backend["Map.co Backend<br/>queries all partners in parallel"]

    FC["Food.co<br/>Pizza Hut · 35 min · EUR 15 min"]
    MD["MealDash<br/>Pizza Hut · 28 min · EUR 12 min"]
    QB["QuickBite<br/>No results"]

    Dedup["Deduplicate by restaurant<br/>Pick fastest delivery per restaurant"]
    Result["Pizza Hut — 28 min delivery<br/>Routed via MealDash · user never sees this"]

    Search --> Backend
    Backend --> FC
    Backend --> MD
    Backend --> QB
    FC --> Dedup
    MD --> Dedup
    QB --> Dedup
    Dedup --> Result
```

The user never knows which partner is fulfilling the order. If the user orders from Pizza Hut, Map.co routes `POST /v1/orders` to MealDash. If MealDash goes down, Map.co can failover to Food.co transparently.



---

## Edge Cases

**Restaurant closes after menu fetch, before order placement.**
The partner returns `422 restaurant_closed`. Map.co shows the user an error and suggests nearby alternatives from the cached restaurant list. Open question: auto-suggest a similar restaurant from a different partner, or show the error and let the user decide.

**Item becomes unavailable between menu fetch and order.**
Food.co returns `422 item_unavailable` with the specific item IDs. Map.co prompts the user to modify their order rather than failing the entire order. The 5-minute ETag cache on menus means this is a known window of staleness — the order endpoint is the validation gate.

**Price mismatch between displayed total and partner-confirmed total.**
Food.co validates and prices the order server-side. If the returned `total_amount` differs from what Map.co showed the user (e.g. a menu item price changed between fetch and order), Map.co compares the two. If the delta exceeds a configurable threshold (starting point: 5%), Map.co rejects the order, re-fetches the menu, and shows the user updated pricing. The user is never charged more than what they saw. Mismatch frequency per partner should be tracked as a data quality signal.

**Courier no-show / excessive delay.**
Food.co sends a webhook with status `cancelled` and reason `courier_unavailable`. Map.co handles the refund (since Map.co owns payment). A per-partner SLA defines the maximum acceptable pickup time (e.g. 45 minutes); if exceeded, Map.co proactively cancels and re-routes to another partner. SLA compliance is monitored using `status_history` timestamps.

**Partner API is down.**
Map.co Backend runs a circuit breaker per partner. After N consecutive failures, it stops routing orders to that partner and shows the user "delivery unavailable" for restaurants served exclusively by that partner. For restaurant discovery, degradation is graceful: if one of three partners is down, the user still sees results from the other two. For in-flight orders, Map.co falls back to polling `GET /v1/orders/{id}`.

**Webhook delivery failures.**
If Food.co's webhook infrastructure is down, Map.co falls back to polling `GET /v1/orders/{id}` at increasing intervals (5s, 15s, 30s) when no webhook has arrived within the expected window.

**Duplicate webhook delivery.**
Map.co deduplicates using `order_id` + `status` + `timestamp`. Processing the same event twice is a no-op.

---

## Edge Cases

| Category | Scenario | Resolution |
|----------|----------|------------|
| Sync | Price drift between menu cache and order submit | Partner's `total_amount` in the order response is authoritative. Backend compares against displayed price; if delta exceeds threshold, reject, re-fetch menu, show user updated pricing. |
| Async | Out-of-order webhooks | Append-only event log; update current status only if incoming timestamp is newer. State never regresses. |
| Payment | Order cancelled after payment collected | Webhook triggers automatic refund. If settlement already ran, clawback in next cycle. Partner never touches payment. |
| Operational | Partner implements contract incorrectly | Conformance test suite run during onboarding: schema validation, pagination, idempotency, error codes, webhook signing. 100% pass required for production access. |



