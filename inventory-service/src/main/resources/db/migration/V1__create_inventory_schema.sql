CREATE TABLE stock_items (
    product_id VARCHAR(100) PRIMARY KEY,
    available_quantity INTEGER NOT NULL CHECK (available_quantity >= 0)
);

CREATE TABLE inventory_streams (
    aggregate_id UUID PRIMARY KEY,
    aggregate_type VARCHAR(100) NOT NULL,
    current_version BIGINT NOT NULL CHECK (current_version >= 0)
);

CREATE TABLE inventory_events (
    event_id UUID PRIMARY KEY,
    aggregate_type VARCHAR(100) NOT NULL,
    aggregate_id UUID NOT NULL REFERENCES inventory_streams(aggregate_id),
    aggregate_version BIGINT NOT NULL CHECK (aggregate_version > 0),
    event_type VARCHAR(100) NOT NULL,
    payload JSONB NOT NULL,
    occurred_at TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT uq_inventory_events_stream_version UNIQUE (aggregate_id, aggregate_version)
);

CREATE TABLE processed_events (
    event_id UUID PRIMARY KEY,
    processed_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE INDEX idx_inventory_events_stream ON inventory_events(aggregate_id, aggregate_version);

INSERT INTO stock_items (product_id, available_quantity) VALUES
    ('mechanical-keyboard', 100),
    ('wireless-mouse', 200),
    ('monitor', 50),
    ('out-of-stock-item', 0);

CREATE PUBLICATION inventory_events_publication FOR TABLE inventory_events;

CREATE FUNCTION reject_inventory_event_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'inventory_events is append-only';
END;
$$;

CREATE TRIGGER inventory_events_are_append_only
BEFORE UPDATE OR DELETE ON inventory_events
FOR EACH ROW EXECUTE FUNCTION reject_inventory_event_mutation();

DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'debezium') THEN
        EXECUTE 'GRANT USAGE ON SCHEMA public TO debezium';
        EXECUTE 'GRANT SELECT ON TABLE inventory_events TO debezium';
    END IF;
END;
$$;
