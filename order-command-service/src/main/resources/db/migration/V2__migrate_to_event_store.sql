CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE aggregate_streams (
    aggregate_id UUID PRIMARY KEY,
    aggregate_type VARCHAR(100) NOT NULL,
    current_version BIGINT NOT NULL CHECK (current_version >= 0)
);

CREATE TABLE order_events (
    event_id UUID PRIMARY KEY,
    aggregate_type VARCHAR(100) NOT NULL,
    aggregate_id UUID NOT NULL REFERENCES aggregate_streams(aggregate_id),
    aggregate_version BIGINT NOT NULL CHECK (aggregate_version > 0),
    event_type VARCHAR(100) NOT NULL,
    payload JSONB NOT NULL,
    occurred_at TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT uq_order_events_stream_version UNIQUE (aggregate_id, aggregate_version)
);

CREATE INDEX idx_order_events_stream
    ON order_events(aggregate_id, aggregate_version);

CREATE PUBLICATION orders_events_publication FOR TABLE order_events;

INSERT INTO aggregate_streams (aggregate_id, aggregate_type, current_version)
SELECT id,
       'orders',
       CASE WHEN status = 'CANCELLED' THEN 2 ELSE 1 END
FROM orders;

INSERT INTO order_events (
    event_id,
    aggregate_type,
    aggregate_id,
    aggregate_version,
    event_type,
    payload,
    occurred_at
)
SELECT generated.event_id,
       'orders',
       orders.id,
       1,
       'OrderCreated.v1',
       jsonb_build_object(
           'eventId', generated.event_id::text,
           'eventType', 'OrderCreated.v1',
           'aggregateId', orders.id::text,
           'aggregateVersion', 1,
           'occurredAt', to_char(orders.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
           'payload', jsonb_build_object(
               'customerId', orders.customer_id,
               'status', 'CREATED',
               'totalAmount', orders.total_amount,
               'items', COALESCE(items.value, '[]'::jsonb),
               'createdAt', to_char(orders.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
           )
       ),
       orders.created_at
FROM orders
CROSS JOIN LATERAL (SELECT gen_random_uuid() AS event_id) generated
LEFT JOIN LATERAL (
    SELECT jsonb_agg(
        jsonb_build_object(
            'productId', order_items.product_id,
            'quantity', order_items.quantity,
            'unitPrice', order_items.unit_price
        )
        ORDER BY order_items.product_id
    ) AS value
    FROM order_items
    WHERE order_items.order_id = orders.id
) items ON TRUE;

INSERT INTO order_events (
    event_id,
    aggregate_type,
    aggregate_id,
    aggregate_version,
    event_type,
    payload,
    occurred_at
)
SELECT generated.event_id,
       'orders',
       orders.id,
       2,
       'OrderCancelled.v1',
       jsonb_build_object(
           'eventId', generated.event_id::text,
           'eventType', 'OrderCancelled.v1',
           'aggregateId', orders.id::text,
           'aggregateVersion', 2,
           'occurredAt', to_char(orders.updated_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
           'payload', jsonb_build_object(
               'status', 'CANCELLED',
               'cancelledAt', to_char(orders.updated_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
           )
       ),
       orders.updated_at
FROM orders
CROSS JOIN LATERAL (SELECT gen_random_uuid() AS event_id) generated
WHERE orders.status = 'CANCELLED';

ALTER TABLE command_requests DROP CONSTRAINT fk_command_requests_order;
ALTER TABLE command_requests
    ADD CONSTRAINT fk_command_requests_stream
    FOREIGN KEY (order_id) REFERENCES aggregate_streams(aggregate_id)
    DEFERRABLE INITIALLY DEFERRED;

DROP TABLE outbox_events;
DROP TABLE order_items;
DROP TABLE orders;

CREATE FUNCTION reject_order_event_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'order_events is append-only';
END;
$$;

CREATE TRIGGER order_events_are_append_only
BEFORE UPDATE OR DELETE ON order_events
FOR EACH ROW EXECUTE FUNCTION reject_order_event_mutation();

DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'debezium') THEN
        EXECUTE 'GRANT USAGE ON SCHEMA public TO debezium';
        EXECUTE 'GRANT SELECT ON TABLE order_events TO debezium';
    END IF;
END;
$$;
