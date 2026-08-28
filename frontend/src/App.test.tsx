import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import App from './App';

const orderId = '134fd971-7327-44c5-9afc-f2154eab8f64';
const createdAt = '2026-08-26T12:00:00Z';

function jsonResponse(body: unknown, status = 200, headers: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...headers },
  });
}

const command = { orderId, status: 'CREATED' };
const createdOrder = {
  orderId,
  customerId: 'customer-42',
  status: 'CREATED',
  totalAmount: 208.9,
  items: [
    { productId: 'mechanical-keyboard', quantity: 1, unitPrice: 129.9 },
    { productId: 'wireless-mouse', quantity: 2, unitPrice: 39.5 },
  ],
  createdAt,
  updatedAt: createdAt,
  version: 1,
};
const confirmedOrder = { ...createdOrder, status: 'CONFIRMED', version: 2 };
const cancelledOrder = { ...confirmedOrder, status: 'CANCELLED', version: 3 };

describe('App', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('presents a customer order portal and the architecture guarantees', () => {
    render(<App />);

    expect(
      screen.getByRole('heading', { name: /One simple portal.*Two purpose-built data paths/ }),
    ).toBeVisible();
    expect(screen.getByRole('button', { name: 'Run complete architecture proof' })).toBeEnabled();
    expect(screen.getByRole('heading', { name: 'Create order' })).toBeVisible();
    expect(screen.getByRole('heading', { name: 'Order history' })).toBeVisible();
    expect(screen.getByText('Idempotent replay')).toBeVisible();
    expect(screen.getByText('Inventory saga confirmed')).toBeVisible();
  });

  it('executes the complete event-sourced CQRS proof through the public API contract', async () => {
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(jsonResponse(command, 202, { 'Idempotent-Replay': 'false' }))
      .mockResolvedValueOnce(jsonResponse(command, 202, { 'Idempotent-Replay': 'true' }))
      .mockResolvedValueOnce(
        jsonResponse({ status: 409, detail: 'Idempotency key belongs to a different create command' }, 409),
      )
      .mockResolvedValueOnce(jsonResponse(confirmedOrder))
      .mockResolvedValueOnce(jsonResponse({ orderId, status: 'CANCELLED' }, 202))
      .mockResolvedValueOnce(jsonResponse(cancelledOrder))
      .mockResolvedValueOnce(
        jsonResponse({
          content: [cancelledOrder],
          totalElements: 1,
        }),
      )
      .mockResolvedValueOnce(
        jsonResponse([
          { id: 'event-1', orderId, eventType: 'OrderCreated.v1', aggregateVersion: 1 },
          { id: 'event-2', orderId, eventType: 'OrderConfirmed.v1', aggregateVersion: 2 },
          { id: 'event-3', orderId, eventType: 'OrderCancelled.v1', aggregateVersion: 3 },
        ]),
      );
    vi.stubGlobal('fetch', fetchMock);

    render(<App />);
    fireEvent.click(screen.getByRole('button', { name: 'Run complete architecture proof' }));

    expect(
      await screen.findByText(
        'All saga, CQRS, event-sourcing, and serverless projection guarantees completed successfully.',
      ),
    ).toBeVisible();
    await waitFor(() => expect(screen.getAllByText('Passed')).toHaveLength(7));
    expect(screen.getByText('v3')).toBeVisible();
    expect(screen.getAllByText('CANCELLED').length).toBeGreaterThan(0);

    expect(fetchMock).toHaveBeenCalledTimes(8);
    expect(fetchMock.mock.calls[0]?.[0]).toBe('/api/orders');
    expect(fetchMock.mock.calls[3]?.[0]).toBe(`/api/orders/${orderId}`);
    expect(fetchMock.mock.calls[4]?.[0]).toBe(`/api/orders/${orderId}/cancellation`);
    expect(String(fetchMock.mock.calls[6]?.[0])).toContain('status=CANCELLED');
    expect(fetchMock.mock.calls[7]?.[0]).toBe(`/serverless/api/activity/${orderId}`);
  });
});
