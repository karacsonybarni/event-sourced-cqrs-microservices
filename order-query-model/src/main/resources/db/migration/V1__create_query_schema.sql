CREATE TABLE order_views (
    id UUID PRIMARY KEY,
    customer_id VARCHAR(100) NOT NULL,
    status VARCHAR(30) NOT NULL,
    total_amount NUMERIC(19, 2) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL,
    aggregate_version BIGINT NOT NULL
);

CREATE INDEX idx_order_views_customer_id ON order_views(customer_id);
CREATE INDEX idx_order_views_status ON order_views(status);

CREATE TABLE order_item_views (
    order_id UUID NOT NULL REFERENCES order_views(id) ON DELETE CASCADE,
    product_id VARCHAR(100) NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price NUMERIC(19, 2) NOT NULL
);

CREATE INDEX idx_order_item_views_order_id ON order_item_views(order_id);

CREATE TABLE processed_events (
    event_id UUID PRIMARY KEY,
    processed_at TIMESTAMP WITH TIME ZONE NOT NULL
);
