import type {
  CommandResponse,
  CreateOrderRequest,
  OrderDetails,
  OrderActivityEvent,
  OrderStatus,
  OrderSummary,
  Page,
} from './types';

export class ApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

async function readJson<T>(response: Response): Promise<T> {
  const body = await response.json();
  if (!response.ok) {
    const problem = body as { detail?: string; title?: string };
    throw new ApiError(response.status, problem.detail ?? problem.title ?? 'Request failed');
  }
  return body as T;
}

export async function createOrder(
  request: CreateOrderRequest,
  idempotencyKey: string,
): Promise<{ command: CommandResponse; replayed: boolean }> {
  const response = await fetch('/api/orders', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Idempotency-Key': idempotencyKey,
    },
    body: JSON.stringify(request),
  });
  const command = await readJson<CommandResponse>(response);
  return {
    command,
    replayed: response.headers.get('Idempotent-Replay') === 'true',
  };
}

export async function cancelOrder(orderId: string): Promise<CommandResponse> {
  const response = await fetch(`/api/orders/${orderId}/cancellation`, { method: 'PUT' });
  return readJson<CommandResponse>(response);
}

export async function getOrder(orderId: string): Promise<OrderDetails> {
  const response = await fetch(`/api/orders/${orderId}`);
  return readJson<OrderDetails>(response);
}

export async function findOrders(
  customerId: string,
  status?: OrderStatus,
): Promise<Page<OrderSummary>> {
  const parameters = new URLSearchParams({ customerId, size: '20', sort: 'updatedAt,desc' });
  if (status) {
    parameters.set('status', status);
  }
  const response = await fetch(`/api/orders?${parameters.toString()}`);
  return readJson<Page<OrderSummary>>(response);
}

export async function waitForOrder(
  orderId: string,
  expectedStatus: OrderStatus | readonly OrderStatus[],
  timeoutMs = 20_000,
): Promise<OrderDetails> {
  const expectedStatuses = Array.isArray(expectedStatus) ? expectedStatus : [expectedStatus];
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const order = await getOrder(orderId);
      if (expectedStatuses.includes(order.status)) {
        return order;
      }
    } catch (error) {
      if (!(error instanceof ApiError) || error.status !== 404) {
        throw error;
      }
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(
    `Read model did not reach ${expectedStatuses.join(' or ')} within ${timeoutMs / 1000} seconds`,
  );
}

export async function waitForOrderActivity(
  orderId: string,
  expectedEventCount: number,
  timeoutMs = 60_000,
): Promise<OrderActivityEvent[]> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const response = await fetch(`/serverless/api/activity/${orderId}`);
    const activity = await readJson<OrderActivityEvent[]>(response);
    if (activity.length >= expectedEventCount) {
      return activity;
    }
    await new Promise((resolve) => setTimeout(resolve, 1_000));
  }
  throw new Error(
    `Serverless activity projection did not reach ${expectedEventCount} events within ${timeoutMs / 1000} seconds`,
  );
}
