export type OrderStatus = 'CREATED' | 'CANCELLED';

export interface OrderItemInput {
  productId: string;
  quantity: number;
  unitPrice: number;
}

export interface CreateOrderRequest {
  customerId: string;
  items: OrderItemInput[];
}

export interface CommandResponse {
  orderId: string;
  status: OrderStatus;
}

export interface OrderSummary {
  orderId: string;
  customerId: string;
  status: OrderStatus;
  totalAmount: number;
  createdAt: string;
  updatedAt: string;
}

export interface OrderDetails extends OrderSummary {
  items: OrderItemInput[];
  version: number;
}

export interface Page<T> {
  content: T[];
  totalElements: number;
}

export type ProofStepState = 'idle' | 'running' | 'success' | 'error';

export interface ProofStep {
  id: string;
  label: string;
  detail: string;
  state: ProofStepState;
}
