export type Sku = string;

export interface StockItem {
  sku: Sku;
  quantity: number;
}

export interface ReserveRequest {
  sku: Sku;
  quantity: number;
  orderId: string;
}

export interface ReserveResponse {
  ok: boolean;
  sku: Sku;
  reserved: number;
  remaining: number;
}

export interface CreateOrderRequest {
  sku: Sku;
  quantity: number;
  customerEmail: string;
}

export interface Order {
  id: string;
  sku: Sku;
  quantity: number;
  customerEmail: string;
  status: "accepted" | "rejected";
}

export interface NotifyRequest {
  orderId: string;
  customerEmail: string;
  message: string;
}

export interface NotifyResponse {
  ok: boolean;
  notificationId: string;
}
