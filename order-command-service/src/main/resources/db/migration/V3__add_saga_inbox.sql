CREATE TABLE processed_inventory_events (
    event_id UUID PRIMARY KEY,
    processed_at TIMESTAMP WITH TIME ZONE NOT NULL
);

-- Orders accepted before inventory choreography existed are grandfathered as
-- confirmed. The deterministic event id keeps this append-only migration
-- reproducible, while the runtime activation boundary prevents their original
-- OrderCreated events from reserving newly seeded stock.
WITH legacy_orders AS (
    SELECT
        streams.aggregate_id,
        events.occurred_at,
        md5(streams.aggregate_id::text || ':inventory-saga-grandfather:v1')::uuid AS event_id
    FROM aggregate_streams streams
    JOIN order_events events
      ON events.aggregate_id = streams.aggregate_id
     AND events.aggregate_version = 1
     AND events.event_type = 'OrderCreated.v1'
    WHERE streams.aggregate_type = 'orders'
      AND streams.current_version = 1
      AND events.occurred_at < '${sagaActivationAt}'::timestamptz
), grandfathered_events AS (
    INSERT INTO order_events (
        event_id,
        aggregate_type,
        aggregate_id,
        aggregate_version,
        event_type,
        payload,
        occurred_at
    )
    SELECT
        event_id,
        'orders',
        aggregate_id,
        2,
        'OrderConfirmed.v1',
        jsonb_build_object(
            'eventId', event_id::text,
            'eventType', 'OrderConfirmed.v1',
            'aggregateId', aggregate_id::text,
            'aggregateVersion', 2,
            'occurredAt', to_char(
                occurred_at AT TIME ZONE 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
            ),
            'payload', jsonb_build_object(
                'status', 'CONFIRMED',
                'confirmedAt', to_char(
                    occurred_at AT TIME ZONE 'UTC',
                    'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
                )
            )
        ),
        occurred_at
    FROM legacy_orders
    RETURNING aggregate_id
)
UPDATE aggregate_streams
SET current_version = 2
WHERE aggregate_id IN (SELECT aggregate_id FROM grandfathered_events);
