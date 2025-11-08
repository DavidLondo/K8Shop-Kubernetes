\set ON_ERROR_STOP on

-- Allow overriding credentials when invoking the script with `psql -v`
\if :{?catalog_password}
\else
\set catalog_password 'changeme_catalog'
\endif
\if :{?order_password}
\else
\set order_password 'changeme_order'
\endif
\if :{?payment_password}
\else
\set payment_password 'changeme_payment'
\endif
\if :{?recommendation_password}
\else
\set recommendation_password 'changeme_recommendation'
\endif

-- Create required extensions once
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Pass passwords into server-side context to avoid psql variable expansion inside DO $$ $$
SET app.catalog_password        TO :'catalog_password';
SET app.order_password          TO :'order_password';
SET app.payment_password        TO :'payment_password';
SET app.recommendation_password TO :'recommendation_password';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'svc_catalog') THEN
    EXECUTE format('CREATE ROLE %I WITH LOGIN PASSWORD %L', 'svc_catalog', current_setting('app.catalog_password'));
  ELSE
    EXECUTE format('ALTER ROLE %I WITH LOGIN PASSWORD %L', 'svc_catalog', current_setting('app.catalog_password'));
  END IF;
  EXECUTE 'ALTER ROLE svc_catalog SET search_path TO catalog, public';
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'svc_order') THEN
    EXECUTE format('CREATE ROLE %I WITH LOGIN PASSWORD %L', 'svc_order', current_setting('app.order_password'));
  ELSE
    EXECUTE format('ALTER ROLE %I WITH LOGIN PASSWORD %L', 'svc_order', current_setting('app.order_password'));
  END IF;
  EXECUTE 'ALTER ROLE svc_order SET search_path TO "order", public';
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'svc_payment') THEN
    EXECUTE format('CREATE ROLE %I WITH LOGIN PASSWORD %L', 'svc_payment', current_setting('app.payment_password'));
  ELSE
    EXECUTE format('ALTER ROLE %I WITH LOGIN PASSWORD %L', 'svc_payment', current_setting('app.payment_password'));
  END IF;
  EXECUTE 'ALTER ROLE svc_payment SET search_path TO payment, public';
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'svc_recommendation') THEN
    EXECUTE format('CREATE ROLE %I WITH LOGIN PASSWORD %L', 'svc_recommendation', current_setting('app.recommendation_password'));
  ELSE
    EXECUTE format('ALTER ROLE %I WITH LOGIN PASSWORD %L', 'svc_recommendation', current_setting('app.recommendation_password'));
  END IF;
  EXECUTE 'ALTER ROLE svc_recommendation SET search_path TO recommendation, public';
END
$$;

-- Schemas per service (cart and inventory use other backing stores but we keep the structure for reference)
CREATE SCHEMA IF NOT EXISTS catalog;
ALTER SCHEMA catalog OWNER TO svc_catalog;
GRANT USAGE ON SCHEMA catalog TO svc_catalog;

CREATE SCHEMA IF NOT EXISTS "order";
ALTER SCHEMA "order" OWNER TO svc_order;
GRANT USAGE ON SCHEMA "order" TO svc_order;

CREATE SCHEMA IF NOT EXISTS payment;
ALTER SCHEMA payment OWNER TO svc_payment;
GRANT USAGE ON SCHEMA payment TO svc_payment;

CREATE SCHEMA IF NOT EXISTS recommendation;
ALTER SCHEMA recommendation OWNER TO svc_recommendation;
GRANT USAGE ON SCHEMA recommendation TO svc_recommendation;

-- Core catalog tables
CREATE TABLE IF NOT EXISTS catalog.products (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sku         text NOT NULL UNIQUE,
  title       text NOT NULL,
  description text,
  price       numeric(10, 2) NOT NULL,
  image_url   text,
  tags        text[] NOT NULL DEFAULT ARRAY[]::text[],
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE catalog.products OWNER TO svc_catalog;

CREATE TABLE IF NOT EXISTS catalog.product_inventory (
  product_id uuid PRIMARY KEY REFERENCES catalog.products(id) ON DELETE CASCADE,
  available  integer NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE catalog.product_inventory OWNER TO svc_catalog;

-- Orders schema
CREATE TABLE IF NOT EXISTS "order".orders (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      text NOT NULL,
  status       text NOT NULL DEFAULT 'created',
  total_amount numeric(10, 2) NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE "order".orders OWNER TO svc_order;

CREATE TABLE IF NOT EXISTS "order".order_items (
  id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id  uuid NOT NULL REFERENCES "order".orders(id) ON DELETE CASCADE,
  sku       text NOT NULL,
  quantity  integer NOT NULL CHECK (quantity > 0),
  unit_price numeric(10, 2) NOT NULL
);
ALTER TABLE "order".order_items OWNER TO svc_order;
CREATE INDEX IF NOT EXISTS order_items_order_id_idx ON "order".order_items(order_id);

-- Payments schema
CREATE TABLE IF NOT EXISTS payment.payments (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id      uuid NOT NULL,
  status        text NOT NULL,
  amount        numeric(10, 2) NOT NULL,
  transaction_ref text,
  processed_at  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE payment.payments OWNER TO svc_payment;
CREATE UNIQUE INDEX IF NOT EXISTS payment_order_id_idx ON payment.payments(order_id);

-- Recommendation log schema (optional analytics)
CREATE TABLE IF NOT EXISTS recommendation.recommendation_logs (
  id          bigserial PRIMARY KEY,
  product_id  text,
  user_id     text,
  strategy    text NOT NULL,
  payload     jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE recommendation.recommendation_logs OWNER TO svc_recommendation;
