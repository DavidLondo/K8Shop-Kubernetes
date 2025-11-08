import {
  CatalogItems,
  CartSnapshot,
  OrderResponse,
  RecommendationResponse,
  ServiceHealth,
} from "../types";

const JSON_HEADERS = { "Content-Type": "application/json" } as const;

function withBase(url: string, path: string) {
  return `${url.replace(/\/$/, "")}${path}`;
}

async function handleResponse<T>(res: Response): Promise<T> {
  if (!res.ok) {
    const message = await res.text();
    throw new Error(message || `Error HTTP ${res.status}`);
  }
  return (await res.json()) as T;
}

export async function fetchCatalog(baseUrl: string): Promise<CatalogItems> {
  const apiUrl = withBase(baseUrl, "/catalog");
  const res = await fetch(apiUrl);
  return handleResponse<CatalogItems>(res);
}

export async function fetchCart(baseUrl: string, userId: string): Promise<CartSnapshot> {
  const apiUrl = withBase(baseUrl, `/cart/${encodeURIComponent(userId)}`);
  const res = await fetch(apiUrl);
  return handleResponse<CartSnapshot>(res);
}

export async function addCartItem(baseUrl: string, userId: string, sku: string, price: number) {
  const apiUrl = withBase(baseUrl, `/cart/${encodeURIComponent(userId)}/items`);
  const res = await fetch(apiUrl, {
    method: "POST",
    headers: JSON_HEADERS,
    body: JSON.stringify({ productId: sku, quantity: 1, price }),
  });
  return handleResponse<CartSnapshot>(res);
}

export async function checkoutCart(baseUrl: string, userId: string) {
  const apiUrl = withBase(baseUrl, `/cart/${encodeURIComponent(userId)}/checkout`);
  const res = await fetch(apiUrl, { method: "POST", headers: JSON_HEADERS });
  return handleResponse<CartSnapshot>(res);
}

export async function createOrder(baseUrl: string, userId: string, cart: CartSnapshot) {
  const apiUrl = withBase(baseUrl, "/orders");
  const payload = {
    userId,
    items: cart.items.map((item) => ({ sku: item.productId, qty: item.quantity, price: item.price })),
  };
  const res = await fetch(apiUrl, {
    method: "POST",
    headers: JSON_HEADERS,
    body: JSON.stringify(payload),
  });
  return handleResponse<OrderResponse>(res);
}

export async function fetchRecommendations(
  baseUrl: string,
  params: { productId?: string; userId?: string; limit?: number; strategy?: string } = {}
) {
  const apiUrl = withBase(baseUrl, "/recommendations");
  const search = new URLSearchParams();
  if (params.productId) search.set("productId", params.productId);
  if (params.userId) search.set("userId", params.userId);
  if (typeof params.limit === "number") search.set("limit", String(params.limit));
  if (params.strategy) search.set("strategy", params.strategy);
  const url = search.toString() ? `${apiUrl}?${search.toString()}` : apiUrl;
  const res = await fetch(url, { cache: "no-store" });
  return handleResponse<RecommendationResponse>(res);
}

export async function fetchServiceHealth(url: string) {
  const res = await fetch(url, { cache: "no-store" });
  return handleResponse<ServiceHealth>(res);
}
