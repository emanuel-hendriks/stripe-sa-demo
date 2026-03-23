# Requests & Responses

## Endpoints at a Glance

The reverse API has five endpoints that Food.co partners must implement:

| # | Method | Endpoint | Purpose | Auth |
|---|--------|----------|---------|------|
| 1 | `GET` | `/v1/restaurants` | List nearby open restaurants | API key |
| 2 | `GET` | `/v1/restaurants/{id}/menu` | Get a restaurant's menu (ETag caching) | API key |
| 3 | `POST` | `/v1/orders` | Place an order | API key + Idempotency-Key |
| 4 | `GET` | `/v1/orders/{id}` | Get order status (polling fallback) | API key |
| 5 | `POST` | `/v1/orders/{id}/cancel` | Cancel an order | API key |

Maps.co exposes one endpoint that partners call:

| # | Method | Endpoint | Purpose | Auth |
|---|--------|----------|---------|------|
| 6 | `POST` | `/v1/webhooks/delivery-events` | Receive order status updates from partners | Webhook signature |

All partner endpoints are hosted at `https://api.{partner}.com`. All amounts are in currency minor units (e.g. 1200 = EUR 12.00). All timestamps are ISO 8601 / UTC. Every request includes `X-Maps-Request-Id` for tracing. Partners must return errors in a consistent envelope:

```json
{
  "error": {
    "code": "error_code",
    "message": "Human-readable description"
  }
}
```

---

### 1. Select a Restaurant

**`GET /v1/restaurants`**

Returns restaurants near the user that are currently accepting orders.

Request (query params):

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `lat` | float | yes | User latitude |
| `lng` | float | yes | User longitude |
| `radius` | int | no | Search radius in meters. Default: 5000 |
| `cuisine` | string | no | Filter: "italian", "sushi", etc. |
| `limit` | int | no | Page size. Default: 20 |
| `offset` | int | no | Pagination offset. Default: 0 |

Error codes:

| Status | Code | When |
|--------|------|------|
| 400 | `invalid_request` | Missing/malformed required params (lat, lng) |
| 429 | `rate_limited` | Too many requests |
| 503 | `service_unavailable` | Partner temporarily down |

Request:

```http
GET /v1/restaurants?lat=52.5200&lng=13.4050&radius=5000&limit=20&offset=0 HTTP/1.1
Host: api.foodco.com
Authorization: Bearer maps_live_sk_abc123
X-Maps-Request-Id: req_p6q7r8
Accept-Language: de-DE
```

Response (200 OK):

```http
HTTP/1.1 200 OK
Content-Type: application/json

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

Response (no results):

```http
HTTP/1.1 200 OK

{
  "restaurants": [],
  "total": 0,
  "limit": 20,
  "offset": 0
}
```

Response (400 -- invalid request):

```http
HTTP/1.1 400 Bad Request

{
  "error": {
    "code": "invalid_request",
    "message": "Missing required parameter: lat"
  }
}
```

Response (429 -- rate limited):

```http
HTTP/1.1 429 Too Many Requests
Retry-After: 30

{
  "error": {
    "code": "rate_limited",
    "message": "Too many requests. Retry after 30 seconds"
  }
}
```

Response (503 -- partner down):

```http
HTTP/1.1 503 Service Unavailable

{
  "error": {
    "code": "service_unavailable",
    "message": "Service temporarily unavailable. Please retry"
  }
}
```

---

### 2. View the Menu

**`GET /v1/restaurants/{restaurant_id}/menu`**

Returns the full menu for a restaurant. Supports ETag caching -- on subsequent requests Maps.co sends `If-None-Match` and the partner returns `304 Not Modified` if unchanged.

Path params:

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `restaurant_id` | string | yes | Partner's restaurant identifier |

Request headers:

| Header | Purpose |
|--------|---------|
| `If-None-Match` | ETag from previous response. Partner returns `304` if unchanged |
| `Accept-Language` | Preferred language for menu content |

Error codes:

| Status | Code | When |
|--------|------|------|
| 400 | `invalid_request` | Missing/malformed restaurant ID |
| 404 | `restaurant_not_found` | Restaurant does not exist |
| 429 | `rate_limited` | Too many requests |
| 503 | `service_unavailable` | Partner temporarily down |

Request:

```http
GET /v1/restaurants/rest_abc123/menu HTTP/1.1
Host: api.foodco.com
Authorization: Bearer maps_live_sk_abc123
X-Maps-Request-Id: req_a1b2c3
If-None-Match: "menu-rest_abc123-v7"
Accept-Language: de-DE
```

Response (200 OK -- menu changed or first fetch):

```http
HTTP/1.1 200 OK
Content-Type: application/json
ETag: "menu-rest_abc123-v8"
Cache-Control: max-age=300

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
          "currency": "EUR",
          "available": true
        },
        {
          "id": "item_002",
          "name": "Diavola",
          "description": "Tomato, mozzarella, spicy salami",
          "price": 1400,
          "currency": "EUR",
          "available": true
        }
      ]
    },
    {
      "name": "Drinks",
      "items": [
        {
          "id": "item_010",
          "name": "Sparkling Water 0.5L",
          "description": "",
          "price": 300,
          "currency": "EUR",
          "available": true
        }
      ]
    }
  ]
}
```

Response (304 Not Modified -- menu unchanged):

```http
HTTP/1.1 304 Not Modified
ETag: "menu-rest_abc123-v7"
```

Response (400 -- invalid request):

```http
HTTP/1.1 400 Bad Request

{
  "error": {
    "code": "invalid_request",
    "message": "Missing required parameter: restaurant_id"
  }
}
```

Response (404 -- restaurant not found):

```http
HTTP/1.1 404 Not Found

{
  "error": {
    "code": "restaurant_not_found",
    "message": "Restaurant rest_xyz999 not found"
  }
}
```

Response (429 -- rate limited):

```http
HTTP/1.1 429 Too Many Requests
Retry-After: 30

{
  "error": {
    "code": "rate_limited",
    "message": "Too many requests. Retry after 30 seconds"
  }
}
```

Response (503 -- partner down):

```http
HTTP/1.1 503 Service Unavailable

{
  "error": {
    "code": "service_unavailable",
    "message": "Service temporarily unavailable. Please retry"
  }
}
```

---

### 3. Make the Order

**`POST /v1/orders`**

Partners implement this. Maps.co calls it when the user confirms an order.

Request headers:

| Header | Purpose |
|--------|---------|
| `Authorization: Bearer {api_key}` | Partner authentication |
| `Idempotency-Key: mapco_order_{id}` | Prevents duplicate orders on retry |

Error codes:

| Status | Code | When |
|--------|------|------|
| 400 | `invalid_request` | Missing/malformed fields |
| 409 | `idempotency_conflict` | Same key, different body |
| 422 | `restaurant_closed` | Not accepting orders |
| 422 | `item_unavailable` | Item out of stock |
| 422 | `below_minimum` | Below restaurant minimum |

Request:

```http
POST /v1/orders HTTP/1.1
Host: api.foodco.com
Authorization: Bearer maps_live_sk_abc123
Idempotency-Key: mapco_order_789
Content-Type: application/json
X-Maps-Request-Id: req_d4e5f6

{
  "restaurant_id": "rest_abc123",
  "maps_order_ref": "maps_ord_789",
  "items": [
    { "item_id": "item_001", "quantity": 2, "notes": "extra basil" },
    { "item_id": "item_010", "quantity": 1 }
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

Response (201 Created):

```http
HTTP/1.1 201 Created
Content-Type: application/json
Idempotency-Key: mapco_order_789

{
  "order_id": "ord_food_456",
  "maps_order_ref": "maps_ord_789",
  "status": "confirmed",
  "total_amount": 2700,
  "currency": "EUR",
  "estimated_delivery_at": "2026-03-23T13:05:00Z"
}
```

Response (200 OK -- idempotent replay, same body):

```http
HTTP/1.1 200 OK

{
  "order_id": "ord_food_456",
  "maps_order_ref": "maps_ord_789",
  "status": "confirmed",
  "total_amount": 2700,
  "currency": "EUR",
  "estimated_delivery_at": "2026-03-23T13:05:00Z"
}
```

Response (400 -- invalid request):

```http
HTTP/1.1 400 Bad Request

{
  "error": {
    "code": "invalid_request",
    "message": "Missing required field: delivery_address"
  }
}
```

Response (409 -- idempotency conflict):

```http
HTTP/1.1 409 Conflict

{
  "error": {
    "code": "idempotency_conflict",
    "message": "Idempotency-Key mapco_order_789 already used with a different request body"
  }
}
```

Response (422 -- restaurant closed):

```http
HTTP/1.1 422 Unprocessable Entity

{
  "error": {
    "code": "restaurant_closed",
    "message": "Restaurant rest_abc123 is currently closed"
  }
}
```

Response (422 -- item unavailable):

```http
HTTP/1.1 422 Unprocessable Entity

{
  "error": {
    "code": "item_unavailable",
    "message": "Some items are no longer available",
    "unavailable_items": ["item_001"]
  }
}
```

Response (422 -- below minimum):

```http
HTTP/1.1 422 Unprocessable Entity

{
  "error": {
    "code": "below_minimum",
    "message": "Order total 300 is below minimum 1500",
    "minimum_order_amount": 1500,
    "currency": "EUR"
  }
}
```

---

### 4. Track the Order

Two mechanisms: webhooks (primary) and polling (fallback).

#### 4a. Webhook -- Partner pushes to Maps.co

**`POST /v1/webhooks/delivery-events`** (Maps.co exposes this)

Partners push status changes. The communication direction inverts here -- throughout objectives 1-3, Maps.co calls partners. For tracking, partners call Maps.co.

Error codes (Maps.co returns to partner):

| Status | Code | When |
|--------|------|------|
| 401 | `invalid_signature` | Webhook signature verification failed |
| 400 | `invalid_request` | Missing/malformed fields |
| 429 | `rate_limited` | Too many requests |

Request (from partner):

```http
POST /v1/webhooks/delivery-events HTTP/1.1
Host: api.maps.co
Authorization: Bearer foodco_wh_sk_xyz789
X-Webhook-Signature: sha256=a1b2c3d4e5...
X-Webhook-Timestamp: 1711191540
Content-Type: application/json

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

Response (202 Accepted):

```http
HTTP/1.1 202 Accepted

{
  "event_id": "evt_abc123",
  "status": "received"
}
```

Response (200 OK -- duplicate, already processed):

```http
HTTP/1.1 200 OK

{
  "event_id": "evt_abc123",
  "status": "already_processed"
}
```

Response (401 -- invalid signature):

```http
HTTP/1.1 401 Unauthorized

{
  "error": {
    "code": "invalid_signature",
    "message": "Webhook signature verification failed"
  }
}
```

#### 4b. Polling -- Maps.co calls partner (fallback)

**`GET /v1/orders/{order_id}`**

Maps.co uses this for initial page load or when webhooks are delayed. Polling intervals increase: 5s, 15s, 30s.

Path params:

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `order_id` | string | yes | Partner's order identifier |

Request:

```http
GET /v1/orders/ord_food_456 HTTP/1.1
Host: api.foodco.com
Authorization: Bearer maps_live_sk_abc123
X-Maps-Request-Id: req_m3n4o5
```

Response (200 OK):

```http
HTTP/1.1 200 OK
Content-Type: application/json

{
  "order_id": "ord_food_456",
  "maps_order_ref": "maps_ord_789",
  "status": "in_transit",
  "status_history": [
    { "status": "confirmed",        "at": "2026-03-23T12:32:00Z" },
    { "status": "preparing",        "at": "2026-03-23T12:35:00Z" },
    { "status": "ready_for_pickup", "at": "2026-03-23T12:55:00Z" },
    { "status": "in_transit",       "at": "2026-03-23T13:02:00Z" }
  ],
  "courier": {
    "name": "Lisa",
    "location": { "lat": 48.1365, "lng": 11.5810 }
  },
  "estimated_arrival_at": "2026-03-23T13:10:00Z",
  "restaurant": {
    "id": "rest_abc123",
    "name": "Pizza Hut"
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

### 5. Cancel an Order

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
| `reason` | string | yes | Cancellation reason: `customer_requested`, `payment_failed` |

Error codes:

| Status | Code | When |
|--------|------|------|
| 404 | `order_not_found` | Order does not exist |
| 409 | `cancellation_not_allowed` | Order too far along to cancel |
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

Response (200 OK -- cancelled):

```http
HTTP/1.1 200 OK

{
  "order_id": "ord_food_456",
  "maps_order_ref": "maps_ord_789",
  "status": "cancelled",
  "cancelled_at": "2026-03-23T12:34:00Z"
}
```

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
