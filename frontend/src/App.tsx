import { type FormEvent, useCallback, useState } from 'react';
import {
  ApiError,
  cancelOrder,
  createOrder,
  findOrders,
  getOrder,
  waitForOrder,
  waitForOrderActivity,
} from './api';
import type {
  CreateOrderRequest,
  OrderDetails,
  OrderItemInput,
  OrderStatus,
  OrderSummary,
  ProofStep,
} from './types';

const defaultItems: OrderItemInput[] = [
  { productId: 'mechanical-keyboard', quantity: 1, unitPrice: 129.9 },
  { productId: 'wireless-mouse', quantity: 2, unitPrice: 39.5 },
];

const serverlessProjectionEnabled = import.meta.env.VITE_SERVERLESS_PROJECTION_ENABLED !== 'false';

const coreProofSteps: ProofStep[] = [
  {
    id: 'command',
    label: 'Command accepted',
    detail: 'The command service appends OrderCreated.v1 and returns 202.',
    state: 'idle',
  },
  {
    id: 'replay',
    label: 'Idempotent replay',
    detail: 'The same key and payload resolve to the original order.',
    state: 'idle',
  },
  {
    id: 'conflict',
    label: 'Conflict protected',
    detail: 'The same key with another payload is rejected with 409.',
    state: 'idle',
  },
  {
    id: 'projection',
    label: 'Inventory saga confirmed',
    detail: 'Inventory reserves the items and OrderConfirmed.v1 reaches the query side.',
    state: 'idle',
  },
  {
    id: 'cancellation',
    label: 'Compensation requested',
    detail: 'OrderCancelled.v1 advances the read model and tells inventory to release the reservation.',
    state: 'idle',
  },
  {
    id: 'query',
    label: 'Customer query verified',
    detail: 'The denormalized query model returns the customer order.',
    state: 'idle',
  },
];

const serverlessProofStep: ProofStep = {
  id: 'serverless',
  label: 'Serverless activity verified',
  detail: 'Azure Functions projects the same Kafka events into a Cosmos DB document view.',
  state: 'idle',
};

const proofTemplate = serverlessProjectionEnabled
  ? [...coreProofSteps, serverlessProofStep]
  : coreProofSteps;

function newIdempotencyKey(): string {
  const suffix = globalThis.crypto?.randomUUID?.() ?? `${Date.now()}-${Math.random()}`;
  return `portal-${suffix}`;
}

function currency(value: number): string {
  return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(value);
}

function shortId(value: string): string {
  return `${value.slice(0, 8)}…${value.slice(-4)}`;
}

function formatTime(value: string): string {
  return new Intl.DateTimeFormat('en', {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value));
}

function StatusBadge({ status }: { status: OrderStatus }) {
  return <span className={`status status--${status.toLowerCase()}`}>{status}</span>;
}

function ArchitectureArrow() {
  return (
    <svg aria-hidden="true" className="architecture-arrow" viewBox="0 0 48 16">
      <path d="M1 8h42M37 2l6 6-6 6" />
    </svg>
  );
}

export default function App() {
  const [customerId, setCustomerId] = useState('customer-42');
  const [items, setItems] = useState<OrderItemInput[]>(defaultItems);
  const [orders, setOrders] = useState<OrderSummary[]>([]);
  const [selectedOrder, setSelectedOrder] = useState<OrderDetails | null>(null);
  const [statusFilter, setStatusFilter] = useState<OrderStatus | ''>('');
  const [proofSteps, setProofSteps] = useState<ProofStep[]>(proofTemplate);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('Ready to send commands through the live architecture.');
  const [error, setError] = useState('');

  const total = items.reduce((sum, item) => sum + item.quantity * item.unitPrice, 0);

  const updateProof = useCallback((id: string, update: Partial<ProofStep>) => {
    setProofSteps((current) =>
      current.map((step) => (step.id === id ? { ...step, ...update } : step)),
    );
  }, []);

  const loadOrders = useCallback(
    async (filter = statusFilter) => {
      if (!customerId.trim()) {
        return;
      }
      const page = await findOrders(customerId.trim(), filter || undefined);
      setOrders(page.content);
    },
    [customerId, statusFilter],
  );

  const changeItem = (index: number, field: keyof OrderItemInput, value: string) => {
    setItems((current) =>
      current.map((item, itemIndex) => {
        if (itemIndex !== index) {
          return item;
        }
        return {
          ...item,
          [field]: field === 'productId' ? value : Number(value),
        };
      }),
    );
  };

  const addItem = () => {
    setItems((current) => [
      ...current,
      { productId: 'monitor', quantity: 1, unitPrice: 249.9 },
    ]);
  };

  const removeItem = (index: number) => {
    setItems((current) => current.filter((_, itemIndex) => itemIndex !== index));
  };

  const request: CreateOrderRequest = {
    customerId: customerId.trim(),
    items,
  };

  const submitOrder = async (event: FormEvent) => {
    event.preventDefault();
    setBusy(true);
    setError('');
    setMessage('Appending the command to the event store…');
    try {
      const result = await createOrder(request, newIdempotencyKey());
      setMessage(`Command accepted for order ${shortId(result.command.orderId)}. Waiting for inventory…`);
      const projected = await waitForOrder(result.command.orderId, 'CONFIRMED');
      setSelectedOrder(projected);
      await loadOrders();
      setMessage(`Order ${shortId(projected.orderId)} is visible at event version ${projected.version}.`);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'The order could not be created.');
    } finally {
      setBusy(false);
    }
  };

  const runArchitectureProof = async () => {
    setBusy(true);
    setError('');
    setProofSteps(proofTemplate);
    const idempotencyKey = newIdempotencyKey();
    try {
      updateProof('command', { state: 'running' });
      setMessage('Appending OrderCreated.v1 in the command transaction…');
      const first = await createOrder(request, idempotencyKey);
      updateProof('command', {
        state: 'success',
        detail: `202 Accepted · order ${shortId(first.command.orderId)}`,
      });

      updateProof('replay', { state: 'running' });
      const replay = await createOrder(request, idempotencyKey);
      if (!replay.replayed || replay.command.orderId !== first.command.orderId) {
        throw new Error('The command retry was not identified as an idempotent replay.');
      }
      updateProof('replay', {
        state: 'success',
        detail: `Same key · same order ${shortId(replay.command.orderId)}`,
      });

      updateProof('conflict', { state: 'running' });
      try {
        await createOrder(
          {
            ...request,
            items: [{ productId: 'conflicting-product', quantity: 1, unitPrice: 1 }],
          },
          idempotencyKey,
        );
        throw new Error('The conflicting command was unexpectedly accepted.');
      } catch (caught) {
        if (!(caught instanceof ApiError) || caught.status !== 409) {
          throw caught;
        }
      }
      updateProof('conflict', { state: 'success', detail: '409 Conflict · no duplicate event appended' });

      updateProof('projection', { state: 'running' });
      setMessage('Waiting for inventory reservation and order confirmation…');
      const confirmed = await waitForOrder(first.command.orderId, 'CONFIRMED');
      if (confirmed.version !== 2) {
        throw new Error(`Expected projection version 2, received ${confirmed.version}.`);
      }
      setSelectedOrder(confirmed);
      updateProof('projection', {
        state: 'success',
        detail: `CONFIRMED · event version ${confirmed.version} · ${currency(confirmed.totalAmount)}`,
      });

      updateProof('cancellation', { state: 'running' });
      await cancelOrder(first.command.orderId);
      const cancelled = await waitForOrder(first.command.orderId, 'CANCELLED');
      if (cancelled.version !== 3) {
        throw new Error(`Expected projection version 3, received ${cancelled.version}.`);
      }
      setSelectedOrder(cancelled);
      updateProof('cancellation', {
        state: 'success',
        detail: `CANCELLED · event version ${cancelled.version}`,
      });

      updateProof('query', { state: 'running' });
      const page = await findOrders(customerId.trim(), 'CANCELLED');
      if (!page.content.some((order) => order.orderId === cancelled.orderId)) {
        throw new Error('The customer query did not return the projected order.');
      }
      setStatusFilter('CANCELLED');
      setOrders(page.content);
      updateProof('query', {
        state: 'success',
        detail: `Query model returned ${page.totalElements} cancelled customer order${page.totalElements === 1 ? '' : 's'}`,
      });

      if (serverlessProjectionEnabled) {
        updateProof('serverless', { state: 'running' });
        setMessage('Waiting for the serverless Kafka-to-Cosmos projection…');
        const activity = await waitForOrderActivity(cancelled.orderId, 3);
        const eventTypes = activity.map((entry) => entry.eventType);
        if (
          !eventTypes.includes('OrderCreated.v1')
          || !eventTypes.includes('OrderConfirmed.v1')
          || !eventTypes.includes('OrderCancelled.v1')
        ) {
          throw new Error('The Cosmos activity view did not contain the complete order lifecycle.');
        }
        updateProof('serverless', {
          state: 'success',
          detail: `${activity.length} immutable documents · Azure Functions + Cosmos DB`,
        });
        setMessage('All saga, CQRS, event-sourcing, and serverless projection guarantees completed successfully.');
      } else {
        setMessage('All local saga, CQRS, and event-sourcing guarantees completed successfully.');
      }
    } catch (caught) {
      const detail = caught instanceof Error ? caught.message : 'Architecture proof failed.';
      setProofSteps((current) =>
        current.map((step) =>
          step.state === 'running' ? { ...step, state: 'error', detail } : step,
        ),
      );
      setError(detail);
      setMessage('The proof stopped at the failed guarantee.');
    } finally {
      setBusy(false);
    }
  };

  const inspectOrder = async (orderId: string) => {
    setBusy(true);
    setError('');
    try {
      setSelectedOrder(await getOrder(orderId));
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'The order could not be loaded.');
    } finally {
      setBusy(false);
    }
  };

  const cancelSelected = async (orderId: string) => {
    setBusy(true);
    setError('');
    try {
      await cancelOrder(orderId);
      const cancelled = await waitForOrder(orderId, 'CANCELLED');
      setSelectedOrder(cancelled);
      await loadOrders();
      setMessage(`Order ${shortId(orderId)} advanced to event version ${cancelled.version}.`);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'The order could not be cancelled.');
    } finally {
      setBusy(false);
    }
  };

  const refresh = async () => {
    setBusy(true);
    setError('');
    try {
      await loadOrders();
      setMessage(`Customer query refreshed for ${customerId.trim()}.`);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Orders could not be loaded.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="app-shell">
      <header className="topbar">
        <a className="brand" href="#top" aria-label="CQRS Order Portal home">
          <span className="brand-mark">CQ</span>
          <span>
            <strong>Order Portal</strong>
            <small>Event-sourced CQRS</small>
          </span>
        </a>
        <div className="environment">
          <span className="environment-dot" />
          Live architecture
        </div>
      </header>

      <main id="top">
        <section className="hero">
          <div className="hero-copy">
            <span className="eyebrow">Customer order experience</span>
            <h1>One simple portal.<br />Two purpose-built data paths.</h1>
            <p>
              Place an order through the command model, let inventory confirm it through events,
              then watch the immutable lifecycle reach a query-optimized customer view.
            </p>
            <div className="hero-actions">
              <button className="button button--primary" disabled={busy} onClick={runArchitectureProof}>
                {busy ? 'Architecture running…' : 'Run complete architecture proof'}
              </button>
              <a className="button button--ghost" href="#orders">Open order portal</a>
            </div>
          </div>
          <div className="hero-metric">
            <span>Current customer</span>
            <strong>{customerId || 'Not selected'}</strong>
            <p>Customer identity stays an input boundary until profile ownership becomes a separate domain.</p>
          </div>
        </section>

        <section className="architecture" aria-label="Request flow">
          <div className="architecture-node">
            <span>01</span><strong>Command</strong><small>Spring service</small>
          </div>
          <ArchitectureArrow />
          <div className="architecture-node">
            <span>02</span><strong>Event store</strong><small>PostgreSQL + CDC</small>
          </div>
          <ArchitectureArrow />
          <div className="architecture-node">
            <span>03</span><strong>Inventory saga</strong><small>Reserve or reject</small>
          </div>
          <ArchitectureArrow />
          <div className="architecture-node">
            <span>04</span><strong>Read models</strong><small>Kafka + projections</small>
          </div>
        </section>

        <div className={`system-message${error ? ' system-message--error' : ''}`} role="status">
          <span>{error ? '!' : 'i'}</span>
          <p>{error || message}</p>
        </div>

        <section className="proof-section" aria-labelledby="proof-heading">
          <div className="section-heading">
            <div>
              <span className="eyebrow">Live verification</span>
              <h2 id="proof-heading">Architecture proof</h2>
            </div>
            <p>Each step calls the public API and verifies its observable contract.</p>
          </div>
          <div className="proof-grid">
            {proofSteps.map((step, index) => (
              <article className={`proof-card proof-card--${step.state}`} key={step.id}>
                <div className="proof-index">{String(index + 1).padStart(2, '0')}</div>
                <div>
                  <h3>{step.label}</h3>
                  <p>{step.detail}</p>
                </div>
                <span className="proof-state">
                  {step.state === 'success' ? 'Passed' : step.state === 'running' ? 'Running' : step.state === 'error' ? 'Failed' : 'Ready'}
                </span>
              </article>
            ))}
          </div>
        </section>

        <section className="portal-section" id="orders" aria-labelledby="orders-heading">
          <div className="section-heading">
            <div>
              <span className="eyebrow">Customer workspace</span>
              <h2 id="orders-heading">Orders</h2>
            </div>
            <p>Create commands on the left. Read the eventual projection on the right.</p>
          </div>

          <div className="portal-grid">
            <form className="panel order-form" onSubmit={submitOrder}>
              <div className="panel-heading">
                <div><span>New command</span><h3>Create order</h3></div>
                <span className="method method--post">POST</span>
              </div>

              <label className="field">
                <span>Customer ID</span>
                <input
                  required
                  maxLength={100}
                  value={customerId}
                  onChange={(event) => setCustomerId(event.target.value)}
                />
              </label>

              <div className="items-heading">
                <span>Order items</span>
                <button className="text-button" type="button" onClick={addItem}>+ Add item</button>
              </div>
              <div className="items-list">
                {items.map((item, index) => (
                  <div className="item-row" key={`${index}-${item.productId}`}>
                    <label>
                      <span>Product</span>
                      <input
                        required
                        value={item.productId}
                        onChange={(event) => changeItem(index, 'productId', event.target.value)}
                      />
                    </label>
                    <label>
                      <span>Qty</span>
                      <input
                        required
                        min="1"
                        type="number"
                        value={item.quantity}
                        onChange={(event) => changeItem(index, 'quantity', event.target.value)}
                      />
                    </label>
                    <label>
                      <span>Unit price</span>
                      <input
                        required
                        min="0.01"
                        step="0.01"
                        type="number"
                        value={item.unitPrice}
                        onChange={(event) => changeItem(index, 'unitPrice', event.target.value)}
                      />
                    </label>
                    <button
                      aria-label={`Remove ${item.productId}`}
                      className="remove-button"
                      disabled={items.length === 1}
                      type="button"
                      onClick={() => removeItem(index)}
                    >×</button>
                  </div>
                ))}
              </div>

              <div className="order-total">
                <span>Command total</span><strong>{currency(total)}</strong>
              </div>
              <button className="button button--primary button--wide" disabled={busy} type="submit">
                Submit order command
              </button>
              <p className="form-note">A new idempotency key is generated for every manual submission.</p>
            </form>

            <div className="panel order-query">
              <div className="panel-heading">
                <div><span>Customer projection</span><h3>Order history</h3></div>
                <span className="method method--get">GET</span>
              </div>
              <div className="query-controls">
                <label>
                  <span>Status</span>
                  <select
                    value={statusFilter}
                    onChange={(event) => setStatusFilter(event.target.value as OrderStatus | '')}
                  >
                    <option value="">All statuses</option>
                    <option value="CREATED">Created</option>
                    <option value="CONFIRMED">Confirmed</option>
                    <option value="REJECTED">Rejected</option>
                    <option value="CANCELLED">Cancelled</option>
                  </select>
                </label>
                <button className="button button--secondary" disabled={busy} onClick={refresh} type="button">
                  Refresh query
                </button>
              </div>

              {orders.length === 0 ? (
                <div className="empty-state">
                  <div>∿</div>
                  <h4>No projected orders loaded</h4>
                  <p>Refresh the customer query or run the complete architecture proof.</p>
                </div>
              ) : (
                <div className="order-list">
                  {orders.map((order) => (
                    <button className="order-row" key={order.orderId} onClick={() => inspectOrder(order.orderId)}>
                      <span>
                        <strong>{shortId(order.orderId)}</strong>
                        <small>{formatTime(order.updatedAt)}</small>
                      </span>
                      <StatusBadge status={order.status} />
                      <strong>{currency(order.totalAmount)}</strong>
                    </button>
                  ))}
                </div>
              )}
            </div>
          </div>
        </section>

        {selectedOrder && (
          <section className="detail-panel" aria-labelledby="detail-heading">
            <div>
              <span className="eyebrow">Projected aggregate</span>
              <h2 id="detail-heading">Order {shortId(selectedOrder.orderId)}</h2>
            </div>
            <div className="detail-facts">
              <div><span>Status</span><StatusBadge status={selectedOrder.status} /></div>
              <div><span>Event version</span><strong>v{selectedOrder.version}</strong></div>
              <div><span>Customer</span><strong>{selectedOrder.customerId}</strong></div>
              <div><span>Total</span><strong>{currency(selectedOrder.totalAmount)}</strong></div>
            </div>
            <div className="detail-items">
              {selectedOrder.items.map((item) => (
                <div key={item.productId}>
                  <span>{item.quantity} × {item.productId}</span>
                  <strong>{currency(item.quantity * item.unitPrice)}</strong>
                </div>
              ))}
            </div>
            {selectedOrder.rejectionReason && (
              <p className="rejection-reason">Inventory rejected this order: {selectedOrder.rejectionReason}</p>
            )}
            {(selectedOrder.status === 'CREATED' || selectedOrder.status === 'CONFIRMED') && (
              <button
                className="button button--danger"
                disabled={busy}
                onClick={() => cancelSelected(selectedOrder.orderId)}
                type="button"
              >
                Cancel order
              </button>
            )}
          </section>
        )}
      </main>

      <footer>
        <p>React · Spring Cloud · PostgreSQL · Debezium · Kafka · Azure Functions · Cosmos DB</p>
        <span>Event-sourced CQRS reference architecture</span>
      </footer>
    </div>
  );
}
