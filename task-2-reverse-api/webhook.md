# Webhook Design — Maps.co Exposes, Partners Push

The reverse API means Maps.co is the client for on-demand calls. But for async order updates, the direction flips: **partners push events to Maps.co** via a webhook endpoint Maps.co exposes.

## Endpoint Maps.co Provides

```
POST https://api.maps.co/v1/webhooks/delivery-events
```

Partners call this whenever an order's state changes.

## Request Body (Partner -> Maps.co)

```json
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

## Event Types

| event_type | Trigger |
|---|---|
| `order.confirmed` | Partner accepted the order |
| `order.preparing` | Restaurant started preparing |
| `order.ready_for_pickup` | Food ready, awaiting courier |
| `order.picked_up` | Courier collected the order |
| `order.en_route` | Courier heading to customer |
| `order.delivered` | Order delivered |
| `order.cancelled` | Order cancelled by partner/restaurant |

## Response from Maps.co

**200 OK** — event received and processed:
```json
{ "received": true }
```

**4xx/5xx** — Maps.co failed to process. Partner must retry.

## Security

- Partners sign each request with an HMAC-SHA256 signature using a shared secret provisioned during onboarding.
- Signature sent in header: `X-Maps-Signature: sha256=<hex_digest>`
- Maps.co verifies before processing. Reject on mismatch.

## Retry Contract

- Partners retry on non-2xx responses using exponential backoff (1s, 5s, 30s, 2min, 10min).
- Max 5 retries over ~15 minutes.
- After exhaustion, partner logs failure. Maps.co falls back to polling `GET /v1/orders/{order_id}`.

## Idempotency

`event_id` is unique per event. Maps.co deduplicates — processing the same `event_id` twice is a no-op. This makes retries safe.
