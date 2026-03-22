# Prompt: Generate Presentation Slides for Task 2

## Source Document

Use the content of `deliverable--task-2-improved.md` (attached or pasted below) as the sole source of truth. Do not invent content beyond what is in that document.

## Audience

Stripe Solutions Architect interviewers. Technical, familiar with API design, webhooks, idempotency, Stripe products. Do not explain basics.

## Presentation Constraints

- 20 minutes total. Roughly 1 slide per minute. Target 18-20 slides.
- Screen-shared over video call. Text must be readable at screen-share resolution.

## Design Rules

- Minimalistic. White or very light background, dark text. No gradients, no shadows, no decorative elements.
- No emoticons, no icons, no clip art, no stock imagery.
- Colour is used ONLY to distinguish interacting parties in diagrams and sequence flows:
  - Map.co App / Backend: one colour (e.g. a muted blue)
  - Food.co Partner API: a second colour (e.g. a muted orange)
  - Webhook / async flow: a third colour (e.g. a muted green)
  - All other text remains black on white.
- Typography: one sans-serif font family throughout. Slide titles in bold, body in regular weight. No italics except for inline code emphasis if needed.
- Maximum 6 lines of text per slide (excluding code blocks). If a slide needs more, split it.

## Slide Structure

### Slide 1 — Title
"Map.co Food Ordering — Reverse API Design" and my name. Nothing else.

### Slide 2 — The Problem
- N partners, N custom integrations, doesn't scale.
- The reverse API inverts the relationship: one spec, many implementors.
- The USB analogy: one standard plug, every device conforms.
- Mention the Stripe parallel: one API, thousands of platforms.

### Slide 3 — Architecture Overview
Reproduce the system diagram from the document (Map.co App, Map.co Backend, Food.co Partners, Order State DB, Webhook Receiver). Use the party colours defined above. Label the 7 edges. Keep the mermaid structure but render it as a clean diagram on the slide.

### Slide 4 — Sync vs Async
- Edges 1-4: synchronous request-response (user-triggered).
- Edges 5, 7: asynchronous webhook push (partner-triggered).
- One sentence each. No code on this slide.

### Slide 5 — Payment Stays with Map.co
Reproduce the payment sequence diagram from the document. Key point: Food.co never sees card details, settles with Map.co separately via daily batch. Mention Stripe Connect parallel (platform = Map.co, connected accounts = partners, Separate Charges and Transfers).

### Slide 6 — Multiple Partners per Restaurant
Reproduce the fan-out dedup diagram. Key point: user sees one listing per restaurant, Map.co picks the best partner transparently. Failover is invisible to the user.

### Slide 7 — Full Order Lifecycle (reference diagram)
Reproduce the full sequence diagram. This is a reference slide — do not narrate every step. Label the four phases (Discovery, Menu, Order, Tracking) with visual separators.

### Slide 8 — Endpoints at a Glance
The 6-endpoint table from the document, plus the webhook. Clean table, no extra text.

### Slide 9 — Endpoint 1: GET /v1/restaurants
Show the query params table and the JSON response from the document as a code block. Highlight `is_open`, `estimated_delivery_min`, `min_order_amount` as the key fields. Mention pagination with limit/offset.

### Slide 10 — Endpoint 2: GET /v1/restaurants/{id}/menu
Show the JSON response as a code block. Call out: ETag caching (response headers table), `available` flag, `customizations` with `price_delta`. One line on the 304 Not Modified flow.

### Slide 11 — Endpoint 3: POST /v1/orders (request)
Show the request headers (Authorization, Idempotency-Key) and the full request body JSON as a code block. This is the most important slide.

### Slide 12 — Endpoint 3: POST /v1/orders (response + design decisions)
Show the 201 response JSON as a code block. Below it, three bullet points:
- Idempotency-Key prevents duplicate orders (same pattern as Stripe).
- payment_reference: Map.co's internal ID, Food.co never processes payment.
- Food.co validates and prices the order server-side; total_amount is authoritative.

### Slide 13 — Endpoint 3: POST /v1/orders (errors)
The error table from the document (400, 409, 422 x3). Clean table, no extra text.

### Slide 14 — Endpoint 4: GET /v1/orders/{id}
Show the JSON response with status_history as a code block. Show the state machine diagram (confirmed -> preparing -> ... -> delivered, with cancelled branch).

### Slide 15 — Endpoint 5: GET /v1/orders/{id}/courier-location
Show the JSON response as a code block. Key points: polled every 5s, 204 when courier not assigned, heading field for smooth map animation. One line on the scaling path (batch ingestion).

### Slide 16 — Endpoint 6: POST /v1/orders/{id}/cancel
Show request and response JSON as code blocks. Key point: cancellation_fee may be non-zero, 409 if order already picked up.

### Slide 17 — Webhooks
Show the webhook request (headers + body JSON) as a code block. Below: HMAC-SHA256 signature verification, 5-minute replay window, exponential backoff retry policy. Mention: same algorithm as Stripe's Stripe-Signature.

### Slide 18 — Partner Onboarding
Show the registration response JSON as a code block. Below: sandbox environment, reference implementation, contract test suite. One line: "Food.co is the design partner; additional partners onboard after v1.1 stabilizes."

### Slide 19 — Cross-Cutting Concerns
Bullet points only, one line each: Authentication (two-way), Error format (code + message), Rate limiting (429 + Retry-After), Versioning (URL path, 12-month support), Currencies (minor units, explicit currency field).

### Slide 20 — Edge Cases
List the seven edge cases from the document as short one-liners. Frame them as questions, not statements:
- "Restaurant closes mid-order — auto-cancel or let partner decide?"
- "Price mismatch — reject if delta > 5%, re-fetch menu"
- "Courier no-show — proactive cancel after SLA breach, re-route to another partner"
- "Partner API down — circuit breaker, graceful degradation"
- "Webhook failures — fall back to polling at increasing intervals"
- "Duplicate webhooks — dedup on order_id + status + timestamp"
- "Item unavailable — prompt user to modify, don't fail entire order"

## Code Block Formatting

- All JSON and HTTP examples must appear as syntax-highlighted code blocks on the slides.
- Use a monospace font for code. Font size large enough to read at screen-share resolution (minimum 14pt equivalent).
- Do not truncate or abbreviate the JSON from the source document. Show the full examples as they appear.
- If a code block is too tall for one slide, split across two slides with a "(continued)" label.

## What NOT to Include

- No "Thank you" or "Questions?" slide. The presentation ends on the edge cases slide and transitions into live discussion.
- No "About me" slide. The interviewer already has my CV.
- No agenda or table of contents slide. 20 minutes is too short for meta-navigation.
- No animations or transitions between slides.
- No speaker notes in the output (I will rehearse from the source document).
