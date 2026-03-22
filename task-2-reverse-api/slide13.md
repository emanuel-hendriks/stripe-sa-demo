Sync flow (edges 1-4) — user-triggered:

| Edge | Direction | What happens |
|------|-----------|-------------|
| 1 | App → Backend | User action (search, tap, order, track) |
| 2 | Backend → App | Rendered data (restaurants, menu, confirmation, status) |
| 3 | Backend → Partner | HTTP call to reverse API (the contract boundary) |
| 4 | Partner → Backend | JSON response (restaurant list, order confirmation) |

Async flow (edges 5, 7) — partner-triggered:

| Edge | Direction | What happens |
|------|-----------|-------------|
| 5 | Partner → Webhook Receiver | Status update push (preparing, picked up, delivered) |
| 6 | Backend → DB | Persist order state (source of truth) |
| 7 | Webhook Receiver → DB | Verify HMAC, write new status |

Key points per edge:

- **Edge 3** is the core of the design — everything interesting happens at this boundary. HTTP because it's the universal transport.
- **Edge 5** handles discrete state transitions only. Courier location streaming is a separate polling endpoint.
- **Edges 6-7** are the same database, written from two paths: sync (after order placement) and async (after webhook receipt). Both paths produce the same order record — the webhook path updates it.





| Node | Role | Owns |
|------|------|------|
| Map.co App | User interface | Renders restaurants, menus, order form, live tracking |
| Map.co Backend | Orchestrator | Calls partner APIs, stores order state, receives webhooks. Never exposes partners directly to the app |
| Food.co Partner API | Implementor | Each partner exposes identical endpoints per the reverse API contract |
| Order State DB | Source of truth | Order history, status, reconciliation. Written from two paths (sync + async) |
| Webhook Receiver | Async ingress | Verifies HMAC signature, writes status updates to DB |



Why the `map.co` backend does not passs from webhook receiver? dDifferent traffic patterns, different scaling profiles. 
The backend serves latency-sensitive user requests. The webhook receiver handles unpredictable partner event bursts. 

Separating them means a webhook spike during peak dinner hours doesn't degrade the user experience. Both write to the same DB, but they're independent services with independent failure domains.




Map.co sends `If-None-Match: "menu_v42"` on repeat requests. Unchanged menu returns `304 Not Modified (no body)`. Changed menu returns the full payload with a new `ETag`.

A briefly stale menu is safe — the order endpoint validates item availability at submission time and returns `422 item_unavailable` if something is out of stock.
