# Task 2 — Map.co / Food.co Reverse API Design

## The assignment

20-minute screen-share presentation for a Stripe Solutions Architect interview. Design a "reverse API" that food delivery partners (Food.co) must implement so that Map.co (Google Maps equivalent) can let users order food directly inside the Maps app.

## The prompt (verbatim objectives)

1. High-level design between Map.co and Food.co partners
2. List the necessary API endpoints that each Food.co partner will need to implement, including the key fields in each API request/response
3. Any additional functionality that your team might need to expose to each Food.co partner

## The user flow

1. Select a restaurant
2. View the menu and select/customize items
3. Make the order
4. Track the order

## Why this matters for a Stripe SA role

This is not a payments question. It tests whether you can:
- Design a clean multi-party API contract (Map.co = platform, Food.co = partner -- same dynamic as Stripe Connect platforms and connected accounts)
- Think about the patterns Stripe itself uses: idempotency, webhooks with signatures, versioning, error codes, pagination
- Communicate a technical design clearly to a non-technical stakeholder (the PM framing is deliberate)
- Handle follow-up questions about edge cases, scale, and failure modes

## Deliverable structure

Build one markdown document (`deliverable.md`) optimized for screen-share:

1. **Architecture overview** -- three systems (Map.co App, Map.co Backend, Food.co Partner API), who calls whom, sync vs async
2. **API endpoints** -- one section per endpoint, showing method + path, key request params, key response fields. Keep it tight: only fields that matter for the flow, not exhaustive schemas
3. **Webhooks** -- Food.co pushes status updates to Map.co. Signature verification, retry policy
4. **Cross-cutting concerns** -- auth, idempotency, pagination, versioning, error format, rate limiting
5. **Design decisions** -- short section explaining trade-offs (why reverse API, why webhooks over polling, who handles payment, how to onboard new partners)

## Design principles

- **Brevity over completeness.** 20 minutes. The interviewer wants to see you think, not read a spec. Each endpoint: 5-8 key fields max.
- **Stripe parallels are your advantage.** When you explain webhook signatures, mention it's the same pattern as Stripe's `Stripe-Signature` header. When you explain idempotency keys, reference Stripe's 24-hour window. This shows domain knowledge without being asked.
- **Edge cases as talking points, not spec.** Don't design for every failure in the doc. Have 3-4 ready to discuss verbally: restaurant closes mid-order, item goes unavailable after menu fetch, courier no-show, partner API is down.
- **Payment is Map.co's problem.** The reverse API is about food ordering and delivery. Map.co collects payment from the user (possibly via Stripe). Food.co gets a `payment_reference` on the order -- they don't process payment. This is a clean separation. Mention it explicitly.

## What NOT to do

- Don't build code or scripts. This is pure design.
- Don't create 20 endpoints. 5-6 is the right number.
- Don't write exhaustive JSON schemas with every optional field. Show the shape, not the full contract.
- Don't spend time on the draw.io diagram in this session. A clean markdown doc with a text-based architecture diagram is enough for screen-share. If you want a visual diagram, do it separately.

## Presentation flow (20 min)

- **0-2 min**: Architecture overview. Three boxes, two communication patterns (sync API calls, async webhooks).
- **2-12 min**: Walk through the 4 user steps, showing the endpoint for each. Pause on POST /orders -- it's the most interesting (idempotency, validation, payment reference).
- **12-16 min**: Webhooks and additional functionality (partner registration, signature verification).
- **16-20 min**: Cross-cutting concerns + design decisions. This is where you show depth.

## File layout

```
task-2-reverse-api/
  .kiro/steering.md        -- this file
  deliverable.md           -- the presentation document
```
