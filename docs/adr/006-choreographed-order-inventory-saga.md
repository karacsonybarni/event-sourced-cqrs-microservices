# ADR-006: Choreograph order confirmation with event-sourced inventory reservations

- Status: Accepted
- Date: 2026-08-28

## Context

An accepted order is not complete until inventory can reserve every requested item. Order and Inventory own separate databases, so one ACID transaction cannot cover both decisions. The system must either confirm the order after reservation, reject it without reducing stock, or release an existing reservation when a confirmed order is cancelled.

The workflow has two participants and each transition naturally follows a domain event. That is small enough for choreography; adding an orchestrator would introduce another state owner without resolving a coordination problem that the event streams do not already make visible.

## Decision

Use a choreographed saga keyed by `orderId`:

1. Order appends `OrderCreated.v1` in status `CREATED`.
2. Inventory consumes it, locks the requested stock rows, and atomically either adjusts stock and appends `InventoryReserved.v1`, or appends `InventoryRejected.v1` without changing stock.
3. Order consumes that result and appends `OrderConfirmed.v1` or `OrderRejected.v1`.
4. Cancelling a created or confirmed order appends `OrderCancelled.v1`. Inventory consumes it and, when a reservation is active, restores stock and appends the compensating `InventoryReleased.v1`.

Event-source the `InventoryReservation` lifecycle. Its stream is authoritative for reservation status, reserved items, rejection reason, and compensation eligibility. Keep `stock_items.available_quantity` as locked transactional current state: this service does not own a complete event history for catalog replenishment and stock corrections, so presenting that balance as replayable would be false event sourcing.

Publish both order and inventory event-store inserts through Debezium change data capture. Do not add a separate outbox row for a fact already represented by an authoritative domain event. Each consumer records the incoming `eventId` in the same local transaction as its state change, making at-least-once delivery idempotent. Failures retry twice and then move to a consumer-specific dead-letter topic.

Treat the first deployment as an explicit cutover. The deploy script completes fallible build preparation, stops command ingress, and only then persists `SAGA_ACTIVATION_AT`. Inventory records but does not act on order events whose business timestamp predates it. The command-store migration appends a deterministic `OrderConfirmed.v1` to every pre-saga order whose stream contains only `OrderCreated.v1`. Those already accepted orders are therefore grandfathered without consuming newly seeded stock, including orders older than Kafka retention. The saga-aware query projector advances to a new consumer-group generation, preventing an old projector from claiming and dead-lettering the new terminal events during a rolling replacement. Local startup persists the same cutoff outside Git for existing-volume upgrades and removes it when the volumes are explicitly destroyed.

## Consequences

Positive:

- no distributed transaction or synchronous service dependency;
- order and reservation state are reconstructable from immutable history;
- stock adjustment and reservation-event append share one local transaction;
- compensation is an explicit business event rather than a hidden cleanup;
- CDC publishes the authoritative event once, without a duplicate outbox representation;
- success, rejection, duplicate delivery, and late-result behavior are independently testable.
- the first deployment has deterministic semantics for all historical orders, independent of Kafka retention.

Negative:

- `CREATED` is now a real intermediate state and clients must tolerate eventual confirmation or rejection;
- another service, PostgreSQL database, Debezium connector, Kafka topic, inbox tables, and dead-letter topics increase operational cost;
- the stock balance cannot be rebuilt from reservation events alone and still needs conventional backup and recovery;
- cancellation completion is eventually consistent across Order and Inventory;
- grandfathered orders retain their historical acceptance but do not claim stock from the new Inventory service;
- choreography becomes difficult to reason about as participants, deadlines, or branching rules grow.

## Boundary for reconsideration

Replace choreography with an orchestrated saga when the workflow gains another consequential participant such as Payment or Shipping, when a central deadline or manual intervention state must be queryable, or when operators need one persisted workflow view spanning several branches. Do not add a participant merely to demonstrate the pattern.

## Alternatives considered

- **Transactional outbox with mutable reservation rows:** conventional and appropriate when mutable rows own the business state, but here it would store reservation lifecycle truth twice. It remains the right choice for a future participant whose aggregate is not event-sourced.
- **Event-source stock balances as well:** creates a misleading model because replenishment, adjustment, and catalog ownership are not implemented as events. Row locks on current balances express the actual consistency boundary.
- **Central saga orchestrator:** gives one workflow state and clearer timeout handling, but is unnecessary ownership for this two-participant linear flow.
- **Synchronous Order-to-Inventory call:** makes order availability depend on inventory availability and still needs durable recovery after partial failure.
- **Add Payment now:** invents a bounded context and compensation contract without a real payment provider or authorization requirement.
