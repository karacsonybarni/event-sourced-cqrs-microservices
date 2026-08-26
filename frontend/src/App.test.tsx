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
const cancelledOrder = { ...createdOrder, status: 'CANCELLED', version: 2 };

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
    expect(screen.getByText('Read model projected')).toBeVisible();
  });

  it('executes the complete event-sourced CQRS proof through the public API contract', async () => {
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(jsonResponse(command, 202, { 'Idempotent-Replay': 'false' }))
      .mockResolvedValueOnce(jsonResponse(command, 202, { 'Idempotent-Replay': 'true' }))
      .mockResolvedValueOnce(
        jsonResponse({ status: 409, detail: 'Idempotency key belongs to a different create command' }, 409),
      )
      .mockResolvedValueOnce(jsonResponse(createdOrder))
      .mockResolvedValueOnce(jsonResponse({ orderId, status: 'CANCELLED' }, 202))
      .mockResolvedValueOnce(jsonResponse(cancelledOrder))
      .mockResolvedValueOnce(
        jsonResponse({
          content: [cancelledOrder],
          totalElements: 1,
        }),
      );
    vi.stubGlobal('fetch', fetchMock);

    render(<App />);
    fireEvent.click(screen.getByRole('button', { name: 'Run complete architecture proof' }));

    expect(
      await screen.findByText('All CQRS and event-sourcing guarantees completed successfully.'),
    ).toBeVisible();
    await waitFor(() => expect(screen.getAllByText('Passed')).toHaveLength(6));
    expect(screen.getByText('v2')).toBeVisible();
    expect(screen.getAllByText('CANCELLED').length).toBeGreaterThan(0);

    expect(fetchMock).toHaveBeenCalledTimes(7);
    expect(fetchMock.mock.calls[0]?.[0]).toBe('/api/orders');
    expect(fetchMock.mock.calls[3]?.[0]).toBe(`/api/orders/${orderId}`);
    expect(fetchMock.mock.calls[4]?.[0]).toBe(`/api/orders/${orderId}/cancellation`);
    expect(String(fetchMock.mock.calls[6]?.[0])).toContain('status=CANCELLED');
  });
});
