-- ============================================================
-- E-COMMERCE ANALYTICS — SCHEMA (PostgreSQL 16)
-- Star schema — migrated from SQLite
-- Key changes from SQLite version:
--   INTEGER PRIMARY KEY → SERIAL PRIMARY KEY (auto-increment)
--   TEXT → VARCHAR / TEXT (PostgreSQL uses both)
--   REAL → NUMERIC(10,2) (exact decimal for financials)
--   No INTEGER for booleans — use BOOLEAN with TRUE/FALSE
-- ============================================================

-- Drop tables if re-running (order matters — FK deps)
DROP TABLE IF EXISTS fact_events      CASCADE;
DROP TABLE IF EXISTS fact_order_items CASCADE;
DROP TABLE IF EXISTS fact_orders      CASCADE;
DROP TABLE IF EXISTS dim_channel      CASCADE;
DROP TABLE IF EXISTS dim_product      CASCADE;
DROP TABLE IF EXISTS dim_customer     CASCADE;
DROP TABLE IF EXISTS dim_date         CASCADE;

-- ── DIMENSION TABLES ────────────────────────────────────────

CREATE TABLE dim_date (
    date_key        INTEGER PRIMARY KEY,
    full_date       DATE NOT NULL,
    year            SMALLINT NOT NULL,
    quarter         SMALLINT NOT NULL,
    month           SMALLINT NOT NULL,
    month_name      VARCHAR(20) NOT NULL,
    week_of_year    SMALLINT NOT NULL,
    day_of_week     SMALLINT NOT NULL,
    day_name        VARCHAR(10) NOT NULL,
    is_weekend      BOOLEAN NOT NULL DEFAULT FALSE,
    is_holiday      BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE dim_customer (
    customer_key        SERIAL PRIMARY KEY,
    customer_id         VARCHAR(20) NOT NULL,
    first_name          VARCHAR(100) NOT NULL,
    last_name           VARCHAR(100) NOT NULL,
    email               VARCHAR(255) NOT NULL,
    country             VARCHAR(100) NOT NULL,
    city                VARCHAR(100) NOT NULL,
    age_band            VARCHAR(20) NOT NULL,
    acquisition_channel VARCHAR(50) NOT NULL,
    effective_date      DATE NOT NULL,
    expiry_date         DATE,
    is_current          BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE dim_product (
    product_key     SERIAL PRIMARY KEY,
    product_id      VARCHAR(20) NOT NULL,
    product_name    VARCHAR(200) NOT NULL,
    category        VARCHAR(100) NOT NULL,
    subcategory     VARCHAR(100) NOT NULL,
    brand           VARCHAR(100) NOT NULL,
    cost_price      NUMERIC(10,2) NOT NULL,
    list_price      NUMERIC(10,2) NOT NULL,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE dim_channel (
    channel_key     SERIAL PRIMARY KEY,
    channel_name    VARCHAR(100) NOT NULL,
    channel_type    VARCHAR(50) NOT NULL
);

-- ── FACT TABLES ─────────────────────────────────────────────

CREATE TABLE fact_orders (
    order_key       SERIAL PRIMARY KEY,
    order_id        VARCHAR(20) NOT NULL,
    date_key        INTEGER REFERENCES dim_date(date_key),
    customer_key    INTEGER REFERENCES dim_customer(customer_key),
    channel_key     INTEGER REFERENCES dim_channel(channel_key),
    order_status    VARCHAR(20) NOT NULL,
    item_count      SMALLINT NOT NULL,
    gross_revenue   NUMERIC(10,2) NOT NULL,
    discount_amount NUMERIC(10,2) DEFAULT 0,
    net_revenue     NUMERIC(10,2) NOT NULL,
    shipping_cost   NUMERIC(10,2) DEFAULT 0,
    is_first_order  BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE fact_order_items (
    item_key        SERIAL PRIMARY KEY,
    order_id        VARCHAR(20) NOT NULL,
    date_key        INTEGER REFERENCES dim_date(date_key),
    customer_key    INTEGER REFERENCES dim_customer(customer_key),
    product_key     INTEGER REFERENCES dim_product(product_key),
    quantity        SMALLINT NOT NULL,
    unit_price      NUMERIC(10,2) NOT NULL,
    discount_pct    NUMERIC(5,2) DEFAULT 0,
    line_revenue    NUMERIC(10,2) NOT NULL,
    line_cost       NUMERIC(10,2) NOT NULL,
    line_margin     NUMERIC(10,2) NOT NULL
);

CREATE TABLE fact_events (
    event_key       SERIAL PRIMARY KEY,
    date_key        INTEGER REFERENCES dim_date(date_key),
    customer_key    INTEGER REFERENCES dim_customer(customer_key),
    session_id      VARCHAR(50) NOT NULL,
    event_type      VARCHAR(50) NOT NULL,
    event_date      DATE NOT NULL,
    channel_key     INTEGER REFERENCES dim_channel(channel_key)
);

-- ── INDEXES for common query patterns ───────────────────────
CREATE INDEX idx_fact_orders_date     ON fact_orders(date_key);
CREATE INDEX idx_fact_orders_customer ON fact_orders(customer_key);
CREATE INDEX idx_fact_orders_status   ON fact_orders(order_status);
CREATE INDEX idx_fact_orders_first    ON fact_orders(is_first_order);
CREATE INDEX idx_fact_items_order     ON fact_order_items(order_id);
CREATE INDEX idx_fact_items_product   ON fact_order_items(product_key);
CREATE INDEX idx_dim_cust_current     ON dim_customer(is_current);
CREATE INDEX idx_dim_cust_id          ON dim_customer(customer_id);
CREATE INDEX idx_fact_events_type     ON fact_events(event_type);
