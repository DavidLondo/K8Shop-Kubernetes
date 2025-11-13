import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { CatalogItems, CartSnapshot, OrderResponse, RecommendationResponse } from "./types";
import {
  fetchCatalog,
  fetchCart,
  addCartItem,
  checkoutCart,
  createOrder,
  fetchRecommendations,
  fetchServiceHealth,
} from "./services/api";

const DEFAULT_USER = "demo-user";

type Toast = {
  type: "success" | "error" | "info";
  message: string;
};

export default function App() {
  const config = useMemo(() => {
    const fallback = import.meta.env;
    const normalizeBase = (value: string | undefined, segment: string) => {
      const base = (value || "").trim();
      if (!base) return "";
      const cleaned = base.replace(/\/+$/, "");
      const suffix = `/${segment}`;
      return cleaned.endsWith(suffix) ? cleaned.slice(0, -suffix.length) : cleaned;
    };

    const defaultBase = "/api";
    const catalogApi = normalizeBase(__APP_CONFIG__.catalogApi || fallback.VITE_CATALOG_API || defaultBase, "catalog");
    const cartApi = normalizeBase(__APP_CONFIG__.cartApi || fallback.VITE_CART_API || defaultBase, "cart");
    const orderApi = normalizeBase(__APP_CONFIG__.orderApi || fallback.VITE_ORDER_API || defaultBase, "orders");
    const recommendationApi = normalizeBase(
      __APP_CONFIG__.recommendationApi || fallback.VITE_RECOMMENDATION_API || defaultBase,
      "recommendations"
    );
    const inventoryApi = normalizeBase(
      __APP_CONFIG__.inventoryApi || fallback.VITE_INVENTORY_API || defaultBase,
      "inventory"
    );
    const paymentApi = normalizeBase(__APP_CONFIG__.paymentApi || fallback.VITE_PAYMENT_API || defaultBase, "payment");
    const notificationApi = normalizeBase(
      __APP_CONFIG__.notificationApi || fallback.VITE_NOTIFICATION_API || defaultBase,
      "notification"
    );

    const buildPath = (base: string, path: string) => {
      if (!base) return "";
      return `${base.replace(/\/+$/, "")}${path}`;
    };

    return {
      catalogApi,
      cartApi,
      orderApi,
      recommendationApi,
      inventoryApi,
      paymentApi,
      notificationApi,
      services: [
        {
          key: "catalog",
          name: "Catálogo",
          endpoint: buildPath(catalogApi, "/catalog"),
          healthUrl: buildPath(catalogApi, "/catalog/healthz"),
          description: "Node.js + PostgreSQL (catalog-service)",
        },
        {
          key: "cart",
          name: "Carrito",
          endpoint: buildPath(cartApi, "/cart"),
          healthUrl: buildPath(cartApi, "/cart/healthz"),
          description: "FastAPI + Redis StatefulSet (cart-service)",
        },
        {
          key: "orders",
          name: "Órdenes",
          endpoint: buildPath(orderApi, "/orders"),
          healthUrl: buildPath(orderApi, "/orders/healthz"),
          description: "FastAPI + RabbitMQ (order-service)",
        },
        {
          key: "inventory",
          name: "Inventario",
          endpoint: buildPath(inventoryApi, "/inventory/apply"),
          healthUrl: buildPath(inventoryApi, "/inventory/healthz"),
          description: "FastAPI + DynamoDB (inventory-service)",
        },
        {
          key: "payment",
          name: "Pagos",
          endpoint: buildPath(paymentApi, "/payments"),
          healthUrl: buildPath(paymentApi, "/payment/healthz"),
          description: "Go + RabbitMQ (payment-service)",
        },
        {
          key: "notification",
          name: "Notificaciones",
          endpoint: buildPath(notificationApi, "/notification/notify"),
          healthUrl: buildPath(notificationApi, "/notification/healthz"),
          description: "Node.js + RabbitMQ (notification-service)",
        },
        {
          key: "recommendation",
          name: "Recomendaciones",
          endpoint: buildPath(recommendationApi, "/recommendations"),
          healthUrl: buildPath(recommendationApi, "/recommendations/healthz"),
          description: "Go + gRPC Catalog (recommendation-service)",
        },
      ],
    };
  }, []);

  const [catalog, setCatalog] = useState<CatalogItems | null>(null);
  const [cart, setCart] = useState<CartSnapshot | null>(null);
  const [orderResult, setOrderResult] = useState<OrderResponse | null>(null);
  const [recommendations, setRecommendations] = useState<RecommendationResponse | null>(null);
  const [isLoadingCatalog, setIsLoadingCatalog] = useState(false);
  const [isLoadingCart, setIsLoadingCart] = useState(false);
  const [isLoadingRecommendations, setIsLoadingRecommendations] = useState(false);
  const [isOrdering, setIsOrdering] = useState(false);
  const [isCheckingServices, setIsCheckingServices] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [toast, setToast] = useState<Toast | null>(null);
  const [serviceStatus, setServiceStatus] = useState<Record<string, { ok: boolean; message?: string }>>({});

  const showToast = useCallback((type: Toast["type"], message: string) => {
    setToast({ type, message });
  }, []);

  const catalogRequestSeq = useRef(0);
  const cartRequestSeq = useRef(0);
  const serviceStatusRequestSeq = useRef(0);

  const catalogLookup = useMemo(() => {
    const map = new Map<string, CatalogItems["items"][number]>();
    if (catalog?.items?.length) {
      for (const item of catalog.items) {
        map.set(item.sku, item);
      }
    }
    return map;
  }, [catalog]);

  const highlightedProduct = useMemo(() => {
    if (!catalog?.items?.length) return null;
    return catalog.items[0];
  }, [catalog]);

  const cartLines = useMemo(() => {
    if (!cart) return [];
    return cart.items.map((item) => {
      const meta = catalogLookup.get(item.productId);
      return {
        ...item,
        title: meta?.title ?? item.productId,
        unitPrice: meta?.price ?? item.price,
      };
    });
  }, [cart, catalogLookup]);

  const orderLines = useMemo(() => {
    if (!orderResult?.items || orderResult.items.length === 0) return [];
    return orderResult.items.map((line) => {
      const legacy = line as unknown as { quantity?: number; qty?: number };
      const quantity = legacy.quantity ?? legacy.qty ?? 0;
      const meta = catalogLookup.get(line.sku);
      return {
        ...line,
        quantity,
        title: meta?.title ?? line.sku,
      };
    });
  }, [orderResult, catalogLookup]);

  const orderItemCount = useMemo(() => {
    if (orderResult?.itemCount !== undefined) {
      return orderResult.itemCount;
    }
    return orderLines.reduce((acc, line) => acc + line.quantity, 0);
  }, [orderResult, orderLines]);

  const orderCreatedAt = useMemo(() => {
    if (!orderResult?.createdAt) return null;
    const date = new Date(orderResult.createdAt);
    if (Number.isNaN(date.getTime())) return null;
    return date.toLocaleString();
  }, [orderResult]);

  const paymentStatus = useMemo(() => {
    if (!orderResult) return null;
    return orderResult.paymentStatus || orderResult.payment?.status || null;
  }, [orderResult]);

  const paymentStatusLabel = useMemo(() => {
    if (!paymentStatus) return null;
    if (paymentStatus.endsWith("succeeded")) return "Pago aprobado";
    if (paymentStatus.endsWith("failed")) return "Pago rechazado";
    if (paymentStatus.endsWith("error")) return "Error al procesar";
    if (paymentStatus.endsWith("disabled") || paymentStatus.endsWith("skipped")) return "Pago omitido";
    return paymentStatus;
  }, [paymentStatus]);

  const paymentChipClass = useMemo(() => {
    if (!paymentStatus) return "chip--neutral";
    if (paymentStatus.endsWith("succeeded")) return "chip--ok";
    if (paymentStatus.endsWith("failed") || paymentStatus.endsWith("error")) return "chip--warn";
    return "chip--neutral";
  }, [paymentStatus]);

  const paymentError = orderResult?.payment?.error ?? null;

  const recommendationList = useMemo(() => {
    if (!recommendations?.recommendations?.length) return [];
    return recommendations.recommendations;
  }, [recommendations]);

  useEffect(() => {
    if (!toast) return;
    const timer = setTimeout(() => setToast(null), 4000);
    return () => clearTimeout(timer);
  }, [toast]);

  useEffect(() => {
    if (!config.catalogApi) {
      setError("Falta configurar VITE_CATALOG_API");
    }
  }, [config.catalogApi]);

  const refreshCatalog = useCallback(
    async (silent = false) => {
      if (!config.catalogApi) return;
      setError(null);
      const requestId = ++catalogRequestSeq.current;
      setIsLoadingCatalog(true);
      try {
        const data = await fetchCatalog(config.catalogApi);
        if (requestId !== catalogRequestSeq.current) return;
        setCatalog(data);
        if (!silent) {
          showToast("success", "Catálogo actualizado");
        }
      } catch (err) {
        const message = (err as Error).message;
        if (requestId !== catalogRequestSeq.current) return;
        setError(message);
        showToast("error", message);
      } finally {
        if (requestId === catalogRequestSeq.current) {
          setIsLoadingCatalog(false);
        }
      }
    },
    [config.catalogApi, showToast]
  );

  const refreshCart = useCallback(
    async (silent = false) => {
      if (!config.cartApi) return;
      setError(null);
      const requestId = ++cartRequestSeq.current;
      setIsLoadingCart(true);
      try {
        const data = await fetchCart(config.cartApi, DEFAULT_USER);
        if (requestId !== cartRequestSeq.current) return;
        setCart(data);
        if (!silent) {
          showToast("success", "Carrito sincronizado");
        }
      } catch (err) {
        const message = (err as Error).message;
        if (requestId !== cartRequestSeq.current) return;
        setError(message);
        showToast("error", message);
      } finally {
        if (requestId === cartRequestSeq.current) {
          setIsLoadingCart(false);
        }
      }
    },
    [config.cartApi, showToast]
  );

  const refreshRecommendations = useCallback(
    async (
      options: { productId?: string; userId?: string; limit?: number; strategy?: string } = {},
      silent = false
    ) => {
      if (!config.recommendationApi) return;
      const { productId, userId, limit = 6, strategy } = options;
      const effectiveProduct = productId || catalog?.items?.[0]?.sku;
      if (!effectiveProduct) return;
      setIsLoadingRecommendations(true);
      try {
        const data = await fetchRecommendations(config.recommendationApi, {
          productId: effectiveProduct,
          userId,
          limit,
          strategy: strategy || (userId ? "personalized" : "related"),
        });
        setRecommendations(data);
        if (!silent) {
          showToast("success", "Recomendaciones actualizadas");
        }
      } catch (err) {
        const message = (err as Error).message;
        setRecommendations(null);
        setError(message);
        showToast("error", message);
      } finally {
        setIsLoadingRecommendations(false);
      }
    },
    [catalog?.items, config.recommendationApi, showToast]
  );

  const refreshServiceStatus = useCallback(
    async (silent = false) => {
      if (!config.services.length) return;
      setIsCheckingServices(true);
      const requestId = ++serviceStatusRequestSeq.current;
      const nextStatus: Array<[string, { ok: boolean; message?: string }]> = [];
      try {
        await Promise.all(
          config.services.map(async (svc) => {
            if (!svc.endpoint) {
              nextStatus.push([svc.key, { ok: false, message: "Sin endpoint" }]);
              return;
            }
            if (!svc.healthUrl) {
              nextStatus.push([svc.key, { ok: true }]);
              return;
            }
            try {
              const health = await fetchServiceHealth(svc.healthUrl);
              const ok = typeof health.ok === "boolean" ? health.ok : true;
              const details = typeof health.backend === "string" ? `Backend: ${health.backend}` : undefined;
              nextStatus.push([svc.key, { ok, message: details }]);
            } catch (err) {
              const message = (err as Error).message || "Error consultando healthz";
              nextStatus.push([svc.key, { ok: false, message }]);
            }
          })
        );
        if (requestId !== serviceStatusRequestSeq.current) return;
        setServiceStatus(Object.fromEntries(nextStatus));
        if (!silent) {
          showToast("info", "Estado de servicios actualizado");
        }
      } finally {
        if (requestId === serviceStatusRequestSeq.current) {
          setIsCheckingServices(false);
        }
      }
    },
    [config.services, showToast]
  );

  useEffect(() => {
    if (config.catalogApi) {
      refreshCatalog(true).catch(() => undefined);
    }
    if (config.cartApi) {
      refreshCart(true).catch(() => undefined);
    }
    refreshServiceStatus(true).catch(() => undefined);
  }, [config.catalogApi, config.cartApi, refreshCatalog, refreshCart, refreshServiceStatus]);

  useEffect(() => {
    if (!config.recommendationApi) return;
    if (!catalog?.items?.length) return;
    refreshRecommendations({ productId: catalog.items[0].sku, userId: DEFAULT_USER }, true).catch(() => undefined);
  }, [catalog, config.recommendationApi, refreshRecommendations]);

  useEffect(() => {
    const timer = window.setInterval(() => {
      refreshServiceStatus(true).catch(() => undefined);
    }, 30_000);
    return () => window.clearInterval(timer);
  }, [refreshServiceStatus]);

  const handleAddItem = async (sku: string, price: number, title: string) => {
    if (!config.cartApi) return;
    setError(null);
    const requestId = ++cartRequestSeq.current;
    setIsLoadingCart(true);
    try {
      const updated = await addCartItem(config.cartApi, DEFAULT_USER, sku, price);
      if (requestId !== cartRequestSeq.current) return;
      setCart(updated);
      showToast("success", `Añadido "${title}" al carrito`);
    } catch (err) {
      const message = (err as Error).message;
      if (requestId !== cartRequestSeq.current) return;
      setError(message);
      showToast("error", message);
    }
    finally {
      if (requestId === cartRequestSeq.current) {
        setIsLoadingCart(false);
      }
    }
  };

  const handleCheckout = async () => {
    if (!config.cartApi) return;
    setError(null);
    const requestId = ++cartRequestSeq.current;
    setIsLoadingCart(true);
    try {
      const updated = await checkoutCart(config.cartApi, DEFAULT_USER);
      if (requestId !== cartRequestSeq.current) return;
      setCart(updated);
      showToast("info", "Checkout ejecutado: carrito limpio");
      refreshCart(true).catch(() => undefined);
    } catch (err) {
      const message = (err as Error).message;
      if (requestId !== cartRequestSeq.current) return;
      setError(message);
      showToast("error", message);
    }
    finally {
      if (requestId === cartRequestSeq.current) {
        setIsLoadingCart(false);
      }
    }
  };

  const handleCreateOrder = async () => {
    if (!config.orderApi || !cart || cart.items.length === 0) return;
    setIsOrdering(true);
    setError(null);
    try {
      const order = await createOrder(config.orderApi, DEFAULT_USER, cart);
      setOrderResult(order);
      const shortId = order.orderId.slice(0, 8);
      const status = order.paymentStatus || order.payment?.status;
      let toastType: Toast["type"] = "success";
      let toastMessage = `Orden ${shortId} creada`;
      if (status) {
        if (status.endsWith("succeeded")) {
          toastMessage = `Orden ${shortId} cobrada`;
        } else if (status.endsWith("failed")) {
          toastType = "error";
          toastMessage = `Pago rechazado para orden ${shortId}`;
        } else if (status.endsWith("error")) {
          toastType = "error";
          toastMessage = `Pago con errores para orden ${shortId}`;
        } else if (status.endsWith("disabled") || status.endsWith("skipped")) {
          toastType = "info";
          toastMessage = `Orden ${shortId} creada (pago omitido)`;
        }
      }
      if (order.payment?.error) {
        toastMessage = `${toastMessage}. ${order.payment.error}`;
      }
      showToast(toastType, toastMessage);
    } catch (err) {
      const message = (err as Error).message;
      setError(message);
      showToast("error", message);
    } finally {
      setIsOrdering(false);
    }
  };

  return (
    <div className="page">
      {toast && <div className={`toast toast--${toast.type}`}>{toast.message}</div>}
      <div className="page__inner">
        <header className="hero">
          <div className="hero__content">
            <span className="badge">K8Shop demo</span>
            <h1>Bookstore Dashboard</h1>
            <p>
              Panel ligero para demostrar los microservicios desplegados en el clúster de Kubernetes.
              Usa el usuario demo para validar flujo completo: catálogo → carrito → orden.
            </p>
            <div className="hero__actions">
              <button
                type="button"
                className="btn btn--contrast"
                onClick={() => refreshCatalog()}
                disabled={isLoadingCatalog || !config.catalogApi}
              >
                {isLoadingCatalog ? "Cargando catálogo" : "Actualizar catálogo"}
              </button>
              <button
                type="button"
                className="btn btn--ghost"
                onClick={() => refreshCart()}
                disabled={isLoadingCart || !config.cartApi}
              >
                {isLoadingCart ? "Sincronizando carrito" : "Sincronizar carrito"}
              </button>
              <button
                type="button"
                className="btn btn--ghost"
                onClick={() => refreshServiceStatus()}
                disabled={isCheckingServices}
              >
                {isCheckingServices ? "Verificando servicios" : "Verificar servicios"}
              </button>
            </div>
            <dl className="hero__meta">
              <div>
                <dt>Usuario demo</dt>
                <dd>{DEFAULT_USER}</dd>
              </div>
              <div>
                <dt>Productos</dt>
                <dd>{catalog?.count ?? "--"}</dd>
              </div>
              <div>
                <dt>Items en carrito</dt>
                <dd>{cart?.itemCount ?? 0}</dd>
              </div>
            </dl>
          </div>
          <div className="hero__panel">
            <h3>Estado rápido</h3>
            <ul className="hero__status">
              {config.services.map((svc) => (
                <li key={svc.key}>
                  <span className={`dot ${serviceStatus[svc.key]?.ok ? "dot--ok" : "dot--warn"}`} />
                  <div>
                    <strong>{svc.name}</strong>
                    <small>{svc.endpoint || "Endpoint no configurado"}</small>
                    <small className="hero__status-note">
                      {svc.endpoint
                        ? serviceStatus[svc.key]
                          ? serviceStatus[svc.key]?.ok
                            ? serviceStatus[svc.key]?.message || "Operativo"
                            : serviceStatus[svc.key]?.message || "Error"
                          : "Sin verificación"
                        : "Sin endpoint"}
                    </small>
                  </div>
                </li>
              ))}
            </ul>
            <p className="hero__hint">Los endpoints se inyectan vía ConfigMap y secrets del clúster.</p>
          </div>
        </header>

        {error && <div className="callout callout--error">{error}</div>}

        <section className="section">
          <div className="section__head">
            <div>
              <h2>Catálogo de libros</h2>
              <p>Productos publicados por el microservicio catalog-service respaldado por PostgreSQL.</p>
            </div>
            <button
              type="button"
              className="btn btn--primary"
              onClick={() => refreshCatalog()}
              disabled={isLoadingCatalog || !config.catalogApi}
            >
              {isLoadingCatalog ? "Actualizando..." : "Refrescar catálogo"}
            </button>
          </div>

          {isLoadingCatalog && !catalog ? (
            <div className="skeleton">Cargando catálogo...</div>
          ) : (
            <div className="product-grid">
              {catalog && catalog.items.length ? (
                catalog.items.map((item) => (
                  <article key={item.sku} className="product-card">
                    <div className="product-card__tags">
                      {(item.tags || []).slice(0, 3).map((tag) => (
                        <span key={tag} className="chip">
                          {tag}
                        </span>
                      ))}
                    </div>
                    <h3>{item.title}</h3>
                    <p className="product-card__meta">SKU {item.sku}</p>
                    <p className="product-card__price">${item.price.toFixed(2)}</p>
                    <p className="product-card__stock">
                      {typeof item.stock === "number" ? `${item.stock} en stock` : "Inventario sin sincronizar"}
                    </p>
                    <button
                      type="button"
                      className="btn btn--primary"
                      onClick={() => handleAddItem(item.sku, item.price, item.title)}
                      disabled={!config.cartApi}
                    >
                      Añadir al carrito
                    </button>
                  </article>
                ))
              ) : (
                <div className="empty">No hay productos todavía. Corre el script de seed si es necesario.</div>
              )}
            </div>
          )}
        </section>

        <section className="section">
          <div className="section__head">
            <div>
              <h2>Operaciones rápidas</h2>
              <p>Comprueba que Redis y order-service respondan al flujo completo.</p>
            </div>
          </div>

          <div className="columns">
            <article className="panel">
              <div className="panel__head">
                <div>
                  <h3>Carrito de {DEFAULT_USER}</h3>
                  <p>Datos almacenados en Redis desplegado dentro del clúster.</p>
                </div>
                <button
                  type="button"
                  className="btn btn--ghost"
                  onClick={() => refreshCart()}
                  disabled={isLoadingCart || !config.cartApi}
                >
                  {isLoadingCart ? "Actualizando..." : "Actualizar"}
                </button>
              </div>

              {isLoadingCart && !cart ? (
                <div className="skeleton">Cargando carrito...</div>
              ) : cartLines.length ? (
                <div className="cart">
                  <ul className="cart__list">
                    {cartLines.map((item) => (
                      <li key={item.productId}>
                        <div>
                          <strong>{item.title}</strong>
                          <small>
                            SKU {item.productId} · {item.quantity} uds × ${item.unitPrice.toFixed(2)}
                          </small>
                        </div>
                        <span>${item.total.toFixed(2)}</span>
                      </li>
                    ))}
                  </ul>
                  <div className="cart__totals">
                    <span>{cart?.itemCount ?? 0} artículos</span>
                    <strong>${(cart?.subtotal ?? 0).toFixed(2)}</strong>
                  </div>
                  <div className="cart__actions">
                    <button type="button" className="btn btn--ghost" onClick={handleCheckout}>
                      Checkout
                    </button>
                    <button
                      type="button"
                      className="btn btn--primary"
                      onClick={handleCreateOrder}
                      disabled={!cartLines.length || isOrdering || !config.orderApi}
                    >
                      {isOrdering ? "Creando orden..." : "Crear orden"}
                    </button>
                  </div>
                </div>
              ) : (
                <div className="empty">Sin items todavía. Agrega uno desde el catálogo.</div>
              )}
            </article>

            <article className="panel">
              <div className="panel__head">
                <div>
                  <h3>Orden más reciente</h3>
                  <p>Respuesta de order-service (y notificaciones a RabbitMQ).</p>
                </div>
              </div>

              {orderResult ? (
                <div className="order">
                  <div className="order__cover">
                    <span>#{orderResult.orderId.slice(0, 8)}</span>
                  </div>
                  {orderLines.length > 0 && (
                    <ul className="order__items">
                      {orderLines.map((line) => (
                        <li key={line.sku}>
                          <div>
                            <strong>{line.title}</strong>
                            <small>
                              SKU {line.sku} · {line.quantity} uds × ${line.price.toFixed(2)}
                            </small>
                          </div>
                          <span>${line.total.toFixed(2)}</span>
                        </li>
                      ))}
                    </ul>
                  )}
                  <dl>
                    <div>
                      <dt>Estado</dt>
                      <dd>{orderResult.status}</dd>
                    </div>
                    <div>
                      <dt>Items</dt>
                      <dd>{orderItemCount}</dd>
                    </div>
                    <div>
                      <dt>Total</dt>
                      <dd>${orderResult.total.toFixed(2)}</dd>
                    </div>
                    {orderCreatedAt && (
                      <div>
                        <dt>Creada</dt>
                        <dd>{orderCreatedAt}</dd>
                      </div>
                    )}
                    <div>
                      <dt>Referencia</dt>
                      <dd>{orderResult.orderId}</dd>
                    </div>
                    {paymentStatus && (
                      <div>
                        <dt>Pago</dt>
                        <dd>
                          <span className={`chip ${paymentChipClass}`}>
                            {paymentStatusLabel ?? paymentStatus}
                          </span>
                          {paymentError && <small className="order__payment-note">{paymentError}</small>}
                        </dd>
                      </div>
                    )}
                  </dl>
                </div>
              ) : (
                <div className="empty">Genera una orden desde el carrito para ver el resultado.</div>
              )}
            </article>
          </div>
        </section>

        <section className="section">
          <div className="section__head">
            <div>
              <h2>Motor de recomendaciones</h2>
              <p>Resultados en vivo del microservicio recommendation-service.</p>
            </div>
            <button
              type="button"
              className="btn btn--primary"
              onClick={() =>
                refreshRecommendations(
                  { productId: highlightedProduct?.sku, userId: DEFAULT_USER, strategy: "related" },
                  false
                )
              }
              disabled={
                isLoadingRecommendations || !config.recommendationApi || (!highlightedProduct && !catalog?.items?.length)
              }
            >
              {isLoadingRecommendations ? "Cargando recomendaciones" : "Actualizar recomendaciones"}
            </button>
          </div>

          {!config.recommendationApi ? (
            <div className="empty">Configura VITE_RECOMMENDATION_API para habilitar este panel.</div>
          ) : isLoadingRecommendations && !recommendationList.length ? (
            <div className="skeleton">Consultando motor de recomendaciones...</div>
          ) : recommendationList.length ? (
            <>
              <div className="recommendation-meta">
                {highlightedProduct && (
                  <span>
                    Basado en <strong>{highlightedProduct.title}</strong> (SKU {highlightedProduct.sku})
                  </span>
                )}
                {recommendations?.strategy && <span>Estrategia: {recommendations.strategy}</span>}
              </div>
              <div className="recommendation-grid">
                {recommendationList.map((item) => {
                  const match = catalogLookup.get(item.id);
                  const displayTitle = match?.title ?? item.id;
                  const canAddToCart = Boolean(match);
                  const productTags = match?.tags?.slice(0, 3) ?? [];
                  const placeholder = displayTitle.trim().charAt(0).toUpperCase() || "☆";
                  const priceLabel = match ? `$${match.price.toFixed(2)}` : null;
                  const handleAdd = () => {
                    if (!match) return;
                    handleAddItem(match.sku, match.price, match.title);
                  };
                  return (
                    <article key={item.id} className="recommendation-card">
                      <div className="recommendation-card__media">
                        <span className="recommendation-card__placeholder">{placeholder}</span>
                      </div>
                      <div className="recommendation-card__body">
                        <div className="recommendation-card__header">
                          <h3>{displayTitle}</h3>
                          <span>{match ? `SKU ${match.sku}` : `ID ${item.id}`}</span>
                        </div>
                        {productTags.length > 0 && (
                          <div className="recommendation-card__tags">
                            {productTags.map((tag) => (
                              <span key={tag} className="chip">
                                {tag}
                              </span>
                            ))}
                          </div>
                        )}
                        <div className="recommendation-card__footer">
                          <div className="recommendation-card__badges">
                            <span className="chip chip--neutral">Score {item.score.toFixed(2)}</span>
                            {match && <span className="chip chip--ok">En catálogo</span>}
                          </div>
                          {priceLabel && <span className="recommendation-card__price">{priceLabel}</span>}
                        </div>
                        <div className="recommendation-card__actions">
                          {canAddToCart ? (
                            <button
                              type="button"
                              className="btn btn--primary btn--sm"
                              onClick={handleAdd}
                              disabled={isLoadingCart || !config.cartApi}
                            >
                              Añadir al carrito
                            </button>
                          ) : (
                            <span className="recommendation-card__hint">Sugerencia basada en afinidad.</span>
                          )}
                        </div>
                      </div>
                    </article>
                  );
                })}
              </div>
            </>
          ) : (
            <div className="empty">Sin recomendaciones disponibles todavía.</div>
          )}
        </section>

        <section className="section">
          <div className="section__head">
            <div>
              <h2>Servicios desplegados</h2>
              <p>Endpoints expuestos por el clúster de Kubernetes.</p>
            </div>
          </div>

          <div className="service-grid">
            {config.services.map((svc) => (
              <article key={svc.key} className="service-card">
                <h3>{svc.name}</h3>
                <p>{svc.description}</p>
                <span className={`chip ${svc.endpoint ? "chip--ok" : "chip--warn"}`}>
                  {svc.endpoint || "Sin configurar"}
                </span>
              </article>
            ))}
          </div>
        </section>
      </div>
    </div>
  );
}
