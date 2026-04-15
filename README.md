# E-Commerce Analytics — SQL Portfolio Project

Built using PostgreSQL (production-ready SQL). Covers schema design, KPI dashboards, cohort analysis, funnel analysis, retention, RFM segmentation, and rolling metrics — the core queries every data analyst and data engineer is expected to write.

---

## Key findings

- **Revenue grew 103.9% MoM in March** driven by new cohort acquisition — but May saw a -30.7% dip, suggesting a dependency on first-order revenue rather than loyal repeat buyers
- **Jan cohort showed the strongest retention** with 50% returning in months 1 and 2 — all other cohorts dropped off faster, pointing to an onboarding or product-fit issue for later cohorts
- **Electronics drives 58% of gross margin** despite representing only ~30% of orders — the highest margin-per-unit category by a significant margin
- **Checkout-to-purchase conversion is 90%** (10 checkout starts → 9 purchases) — the main leakage is pageview-to-add-to-cart at 75%
- **Top 20% of customers (quintile 1) generate 47% of revenue** — a moderate Pareto concentration that suggests room to grow the mid-tier

---

## Schema design

Star schema with 3 fact tables and 4 dimension tables. Designed for analytical workloads (OLAP).

```
dim_date ──────────┐
dim_customer ──────┼──── fact_orders
dim_channel ───────┘       fact_order_items
dim_product ────────────── fact_order_items
                           fact_events
```

**Grain definitions:**
- `fact_orders` — one row per order
- `fact_order_items` — one row per order line item
- `fact_events` — one row per user event (pageview / add-to-cart / checkout / purchase)

**Key design decisions:**
- `dim_customer` uses **SCD Type 2** — `effective_date`, `expiry_date`, `is_current` preserve customer tier history
- `dim_date` is pre-populated with calendar attributes (quarter, week, is_weekend) to avoid date functions in queries
- Surrogate keys (`customer_key`, `product_key`) are integers for fast joins — never the natural source IDs
- `fact_orders.is_first_order` flag pre-computed at load time to avoid expensive subqueries in analytics

---

## Dataset

| Table | Rows | Description |
|---|---|---|
| `dim_date` | 37 | Jan–Jun 2024 calendar |
| `dim_customer` | 37 | 36 customers + 1 SCD2 version |
| `dim_product` | 15 | Products across 5 categories |
| `dim_channel` | 6 | Acquisition / traffic channels |
| `fact_orders` | 73 | 6 months of orders |
| `fact_order_items` | 81 | Line items per order |
| `fact_events` | 53 | Funnel events |

**6 monthly cohorts** — Jan through Jun 2024, 6 customers each — designed to show realistic retention decay curves.

---

## Queries (20 total)

### Section 1 — Revenue KPIs
| # | Query | Technique |
|---|---|---|
| Q1 | Monthly revenue with MoM growth | CTE + LAG window function |
| Q2 | Revenue by category with margin % | JOIN + GROUP BY + calculated columns |
| Q3 | Top 10 products by revenue | RANK() window function |

### Section 2 — Customer metrics
| # | Query | Technique |
|---|---|---|
| Q4 | Customer LTV segmentation | LEFT JOIN + CASE WHEN bucketing |
| Q5 | New vs returning revenue split by month | CASE WHEN conditional aggregation |
| Q6 | Days between first and second order | ROW_NUMBER + self-join |

### Section 3 — Cohort analysis
| # | Query | Technique |
|---|---|---|
| Q7 | Monthly cohort retention raw counts | Multi-CTE + date arithmetic |
| Q8 | Cohort retention matrix (pivot) | CASE WHEN pivot + division by cohort size |

### Section 4 — Retention
| # | Query | Technique |
|---|---|---|
| Q9 | 30/60/90-day retention rates | LEFT JOIN with date window filter in ON |
| Q10 | Churn identification and scoring | Date arithmetic + CASE WHEN |

### Section 5 — Rolling metrics
| # | Query | Technique |
|---|---|---|
| Q11 | Rolling 7-day avg + cumulative revenue | ROWS BETWEEN window frame |
| Q12 | Revenue concentration (Pareto) | NTILE(5) quintile analysis |
| Q13 | Product affinity / cross-sell pairs | Self-join on fact_order_items |
| Q14 | RFM segmentation | NTILE scoring + CASE WHEN labeling |
| Q15 | Executive dashboard (single query) | Multiple CTEs merged in final SELECT |

---

## Tech Stack
- PostgreSQL
- SQL (CTEs, Window Functions, Cohort Analysis)
- DBeaver
---

## SQL techniques demonstrated

Window functions (`ROW_NUMBER`, `RANK`, `LAG`, `NTILE`, `SUM OVER`, `AVG OVER`), CTEs and chained CTEs, cohort analysis with date arithmetic, pivot using `CASE WHEN` aggregation, SCD Type 2 schema design, self-joins for affinity analysis, RFM scoring, rolling averages with `ROWS BETWEEN`, LEFT JOIN retention pattern (date filter in `ON` not `WHERE`).

---

## Files

```
01_schema.sql        Star schema DDL — all CREATE TABLE statements
02_sample_data.sql   Realistic sample data (INSERT statements)
03_queries.sql       15 analytical queries with business context
README.md            This file
```

## Key Takeaway
Designed and implemented a star schema data warehouse with advanced analytical queries for real-world business insights.
