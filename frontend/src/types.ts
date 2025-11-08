export type CatalogItem = {
  id: string;
  sku: string;
  title: string;
  price: number;
  stock?: number;
  tags?: string[];
};

export type CatalogItems = {
  items: CatalogItem[];
  count: number;
};

export type CartItem = {
  productId: string;
  quantity: number;
  price: number;
  total: number;
};

export type CartSnapshot = {
  userId: string;
  items: CartItem[];
  itemCount: number;
  subtotal: number;
};

export type OrderLine = {
  sku: string;
  quantity: number;
  price: number;
  total: number;
};

export type OrderResponse = {
  orderId: string;
  status: string;
  total: number;
  itemCount?: number;
  createdAt?: string;
  items?: OrderLine[];
  paymentStatus?: string;
  payment?: PaymentResponse;
};

export type PaymentResponse = {
  order_id: string;
  status: string;
  error?: string;
};

export type RecommendationItem = {
  id: string;
  score: number;
};

export type RecommendationResponse = {
  productId?: string;
  userId?: string;
  strategy: string;
  recommendations: RecommendationItem[];
};

export type ServiceHealth = {
  ok: boolean;
  [key: string]: unknown;
};
