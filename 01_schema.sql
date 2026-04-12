-- ============================================================
-- E-COMMERCE ANALYTICS — SCHEMA
-- Star schema design for analytics warehouse
-- Compatible with: PostgreSQL, SQLite (portfolio/learning)
-- ============================================================

-- ── DIMENSION TABLES ────────────────────────────────────────

CREATE TABLE dim_date (
    date_key        INTEGER PRIMARY KEY,   -- YYYYMMDD integer
    full_date       TEXT NOT NULL,         -- 'YYYY-MM-DD'
    year            INTEGER NOT NULL,
    quarter         INTEGER NOT NULL,      -- 1-4
    month           INTEGER NOT NULL,      -- 1-12
    month_name      TEXT NOT NULL,         -- 'January' etc
    week_of_year    INTEGER NOT NULL,
    day_of_week     INTEGER NOT NULL,      -- 0=Sun, 6=Sat
    day_name        TEXT NOT NULL,
    is_weekend      INTEGER NOT NULL,      -- 0/1
    is_holiday      INTEGER DEFAULT 0
);

CREATE TABLE dim_customer (
    customer_key    INTEGER PRIMARY KEY,   -- surrogate key (SCD2)
    customer_id     TEXT NOT NULL,         -- natural key from source
    first_name      TEXT NOT NULL,
    last_name       TEXT NOT NULL,
    email           TEXT NOT NULL,
    country         TEXT NOT NULL,
    city            TEXT NOT NULL,
    age_band        TEXT NOT NULL,         -- '18-24','25-34','35-44','45-54','55+'
    acquisition_channel TEXT NOT NULL,     -- 'organic','paid_search','social','email','referral'
    effective_date  TEXT NOT NULL,
    expiry_date     TEXT,                  -- NULL = current row (SCD Type 2)
    is_current      INTEGER DEFAULT 1
);

CREATE TABLE dim_product (
    product_key     INTEGER PRIMARY KEY,
    product_id      TEXT NOT NULL,
    product_name    TEXT NOT NULL,
    category        TEXT NOT NULL,         -- 'Electronics','Clothing','Home','Books','Sports'
    subcategory     TEXT NOT NULL,
    brand           TEXT NOT NULL,
    cost_price      REAL NOT NULL,
    list_price      REAL NOT NULL,
    is_active       INTEGER DEFAULT 1
);

CREATE TABLE dim_channel (
    channel_key     INTEGER PRIMARY KEY,
    channel_name    TEXT NOT NULL,         -- 'web','mobile_app','email','organic_search'
    channel_type    TEXT NOT NULL          -- 'owned','paid','organic'
);

-- ── FACT TABLES ─────────────────────────────────────────────

CREATE TABLE fact_orders (
    order_key       INTEGER PRIMARY KEY,
    order_id        TEXT NOT NULL,
    date_key        INTEGER REFERENCES dim_date(date_key),
    customer_key    INTEGER REFERENCES dim_customer(customer_key),
    channel_key     INTEGER REFERENCES dim_channel(channel_key),
    order_status    TEXT NOT NULL,         -- 'completed','cancelled','refunded'
    item_count      INTEGER NOT NULL,
    gross_revenue   REAL NOT NULL,
    discount_amount REAL DEFAULT 0,
    net_revenue     REAL NOT NULL,         -- gross - discount
    shipping_cost   REAL DEFAULT 0,
    is_first_order  INTEGER DEFAULT 0      -- 1 if customer's first ever order
);

CREATE TABLE fact_order_items (
    item_key        INTEGER PRIMARY KEY,
    order_id        TEXT NOT NULL,
    date_key        INTEGER REFERENCES dim_date(date_key),
    customer_key    INTEGER REFERENCES dim_customer(customer_key),
    product_key     INTEGER REFERENCES dim_product(product_key),
    quantity        INTEGER NOT NULL,
    unit_price      REAL NOT NULL,
    discount_pct    REAL DEFAULT 0,
    line_revenue    REAL NOT NULL,
    line_cost       REAL NOT NULL,
    line_margin     REAL NOT NULL          -- line_revenue - line_cost
);

CREATE TABLE fact_events (
    event_key       INTEGER PRIMARY KEY,
    date_key        INTEGER REFERENCES dim_date(date_key),
    customer_key    INTEGER REFERENCES dim_customer(customer_key),
    session_id      TEXT NOT NULL,
    event_type      TEXT NOT NULL,         -- 'pageview','add_to_cart','checkout_start','purchase'
    event_date      TEXT NOT NULL,
    channel_key     INTEGER REFERENCES dim_channel(channel_key)
);
