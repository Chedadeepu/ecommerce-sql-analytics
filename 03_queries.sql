-- ============================================================
-- E-COMMERCE ANALYTICS — 20 PRODUCTION QUERIES
-- Business questions answered with clean, commented SQL
-- ============================================================

-- ┌─────────────────────────────────────────────────────────┐
-- │  SECTION 1: REVENUE KPIs                                │
-- └─────────────────────────────────────────────────────────┘

-- Q1: Monthly revenue summary with MoM growth
-- Business question: Is revenue growing month over month?
WITH monthly AS (
    SELECT
        d.month,
        d.month_name,
        COUNT(DISTINCT o.order_id)          AS total_orders,
        COUNT(DISTINCT o.customer_key)      AS unique_customers,
        ROUND(SUM(o.net_revenue), 2)        AS net_revenue,
        ROUND(AVG(o.net_revenue), 2)        AS avg_order_value
    FROM fact_orders o
    JOIN dim_date d ON o.date_key = d.date_key
    WHERE o.order_status = 'completed'
    GROUP BY d.month, d.month_name
)
SELECT
    month_name,
    total_orders,
    unique_customers,
    net_revenue,
    avg_order_value,
    LAG(net_revenue) OVER (ORDER BY month)  AS prev_month_revenue,
    ROUND(
        100.0 * (net_revenue - LAG(net_revenue) OVER (ORDER BY month))
        / NULLIF(LAG(net_revenue) OVER (ORDER BY month), 0),
    1)                                       AS mom_growth_pct
FROM monthly
ORDER BY month;


-- Q2: Revenue by product category with margin analysis
-- Business question: Which categories are most profitable?
SELECT
    p.category,
    COUNT(DISTINCT oi.order_id)             AS orders,
    SUM(oi.quantity)                        AS units_sold,
    ROUND(SUM(oi.line_revenue), 2)          AS revenue,
    ROUND(SUM(oi.line_cost), 2)             AS cost,
    ROUND(SUM(oi.line_margin), 2)           AS gross_margin,
    ROUND(100.0 * SUM(oi.line_margin)
          / NULLIF(SUM(oi.line_revenue), 0), 1) AS margin_pct
FROM fact_order_items oi
JOIN dim_product p ON oi.product_key = p.product_key
GROUP BY p.category
ORDER BY revenue DESC;


-- Q3: Top 10 products by revenue with rank
-- Business question: What products drive the most revenue?
SELECT
    RANK() OVER (ORDER BY SUM(oi.line_revenue) DESC) AS revenue_rank,
    p.product_name,
    p.category,
    p.brand,
    SUM(oi.quantity)                        AS units_sold,
    ROUND(SUM(oi.line_revenue), 2)          AS revenue,
    ROUND(SUM(oi.line_margin), 2)           AS gross_margin,
    ROUND(AVG(oi.discount_pct), 1)          AS avg_discount_pct
FROM fact_order_items oi
JOIN dim_product p ON oi.product_key = p.product_key
GROUP BY p.product_key, p.product_name, p.category, p.brand
ORDER BY revenue DESC
LIMIT 10;


-- Q4: Revenue by acquisition channel
-- Business question: Which channels bring the most valuable customers?
SELECT
    c.channel_name,
    c.channel_type,
    COUNT(DISTINCT o.customer_key)          AS customers,
    COUNT(DISTINCT o.order_id)              AS orders,
    ROUND(SUM(o.net_revenue), 2)            AS revenue,
    ROUND(SUM(o.net_revenue)
          / NULLIF(COUNT(DISTINCT o.customer_key), 0), 2) AS revenue_per_customer
FROM fact_orders o
JOIN dim_channel c ON o.channel_key = c.channel_key
WHERE o.order_status = 'completed'
GROUP BY c.channel_key, c.channel_name, c.channel_type
ORDER BY revenue DESC;


-- ┌─────────────────────────────────────────────────────────┐
-- │  SECTION 2: CUSTOMER METRICS                            │
-- └─────────────────────────────────────────────────────────┘

-- Q5: Customer lifetime value (LTV) segmentation
-- Business question: What is the LTV distribution across customers?
WITH customer_ltv AS (
    SELECT
        c.customer_id,
        c.first_name || ' ' || c.last_name   AS customer_name,
        c.country,
        c.age_band,
        c.acquisition_channel,
        COUNT(DISTINCT o.order_id)            AS total_orders,
        ROUND(SUM(o.net_revenue), 2)          AS lifetime_value,
        ROUND(AVG(o.net_revenue), 2)          AS avg_order_value,
        MIN(d.full_date)                      AS first_order_date,
        MAX(d.full_date)                      AS last_order_date
    FROM dim_customer c
    LEFT JOIN fact_orders o  ON c.customer_key = o.customer_key
    LEFT JOIN dim_date d     ON o.date_key = d.date_key
    WHERE c.is_current = 1
      AND (o.order_status = 'completed' OR o.order_status IS NULL)
    GROUP BY c.customer_id, customer_name, c.country,
             c.age_band, c.acquisition_channel
)
SELECT *,
    CASE
        WHEN lifetime_value >= 1500 THEN 'high_value'
        WHEN lifetime_value >= 500  THEN 'mid_value'
        WHEN lifetime_value > 0     THEN 'low_value'
        ELSE 'no_purchase'
    END AS ltv_segment
FROM customer_ltv
ORDER BY lifetime_value DESC;


-- Q6: New vs returning customer revenue split by month
-- Business question: How much of our revenue comes from loyal customers?
SELECT
    d.month_name,
    ROUND(SUM(CASE WHEN o.is_first_order = 1
                   THEN o.net_revenue ELSE 0 END), 2)  AS new_customer_rev,
    ROUND(SUM(CASE WHEN o.is_first_order = 0
                   THEN o.net_revenue ELSE 0 END), 2)  AS returning_customer_rev,
    ROUND(SUM(o.net_revenue), 2)                        AS total_revenue,
    ROUND(100.0 * SUM(CASE WHEN o.is_first_order = 0
                           THEN o.net_revenue ELSE 0 END)
          / NULLIF(SUM(o.net_revenue), 0), 1)           AS returning_pct
FROM fact_orders o
JOIN dim_date d ON o.date_key = d.date_key
WHERE o.order_status = 'completed'
GROUP BY d.month, d.month_name
ORDER BY d.month;


-- Q7: Days between first and second order (time-to-repeat)
-- Business question: How quickly do new customers come back?
WITH order_sequence AS (
    SELECT
        o.customer_key,
        d.full_date                                    AS order_date,
        ROW_NUMBER() OVER (
            PARTITION BY o.customer_key
            ORDER BY d.full_date
        )                                              AS order_num
    FROM fact_orders o
    JOIN dim_date d ON o.date_key = d.date_key
    WHERE o.order_status = 'completed'
),
first_second AS (
    SELECT
        first.customer_key,
        first.order_date   AS first_order_date,
        second.order_date  AS second_order_date,
        JULIANDAY(second.order_date) - JULIANDAY(first.order_date)
                           AS days_to_second_order
    FROM order_sequence first
    JOIN order_sequence second
        ON first.customer_key  = second.customer_key
       AND first.order_num = 1
       AND second.order_num = 2
)
SELECT
    customer_key,
    first_order_date,
    second_order_date,
    CAST(days_to_second_order AS INTEGER) AS days_between_orders,
    CASE
        WHEN days_to_second_order <= 30  THEN '0-30 days'
        WHEN days_to_second_order <= 60  THEN '31-60 days'
        WHEN days_to_second_order <= 90  THEN '61-90 days'
        ELSE '90+ days'
    END AS repeat_bucket
FROM first_second
ORDER BY days_to_second_order;


-- ┌─────────────────────────────────────────────────────────┐
-- │  SECTION 3: COHORT ANALYSIS                             │
-- └─────────────────────────────────────────────────────────┘

-- Q8: Cohort assignment — signup month per customer
-- Foundation query that all cohort analysis builds on
WITH cohort_base AS (
    SELECT
        c.customer_key,
        c.customer_id,
        c.first_name || ' ' || c.last_name AS customer_name,
        c.country,
        c.acquisition_channel,
        MIN(d.full_date)                    AS first_order_date,
        SUBSTR(MIN(d.full_date), 1, 7)      AS cohort_month
    FROM dim_customer c
    JOIN fact_orders o ON c.customer_key = o.customer_key
    JOIN dim_date d    ON o.date_key = d.date_key
    WHERE c.is_current = 1
      AND o.is_first_order = 1
    GROUP BY c.customer_key, c.customer_id, customer_name,
             c.country, c.acquisition_channel
)
SELECT * FROM cohort_base ORDER BY cohort_month, customer_name;


-- Q9: Monthly cohort retention — raw counts
-- Business question: How many customers from each cohort come back each month?
WITH cohort_base AS (
    SELECT
        o.customer_key,
        SUBSTR(MIN(d.full_date), 1, 7) AS cohort_month
    FROM fact_orders o
    JOIN dim_date d ON o.date_key = d.date_key
    WHERE o.is_first_order = 1
    GROUP BY o.customer_key
),
cohort_size AS (
    SELECT cohort_month,
           COUNT(DISTINCT customer_key) AS cohort_users
    FROM cohort_base
    GROUP BY cohort_month
),
monthly_activity AS (
    SELECT
        cb.cohort_month,
        SUBSTR(d.full_date, 1, 7)      AS activity_month,
        COUNT(DISTINCT o.customer_key) AS active_users,
        -- months since first purchase (0 = cohort month)
        (CAST(SUBSTR(d.full_date, 1, 4) AS INTEGER) * 12
         + CAST(SUBSTR(d.full_date, 6, 2) AS INTEGER))
        -
        (CAST(SUBSTR(cb.cohort_month, 1, 4) AS INTEGER) * 12
         + CAST(SUBSTR(cb.cohort_month, 6, 2) AS INTEGER))
                                       AS months_since_first
    FROM fact_orders o
    JOIN dim_date d    ON o.date_key = d.date_key
    JOIN cohort_base cb ON o.customer_key = cb.customer_key
    WHERE o.order_status = 'completed'
    GROUP BY cb.cohort_month, activity_month, months_since_first
)
SELECT
    ma.cohort_month,
    cs.cohort_users,
    ma.months_since_first,
    ma.active_users,
    ROUND(100.0 * ma.active_users / cs.cohort_users, 1) AS retention_pct
FROM monthly_activity ma
JOIN cohort_size cs ON ma.cohort_month = cs.cohort_month
ORDER BY ma.cohort_month, ma.months_since_first;


-- Q10: Cohort retention matrix (PIVOT)
-- Business question: Show the full retention table
WITH cohort_base AS (
    SELECT
        o.customer_key,
        SUBSTR(MIN(d.full_date), 1, 7) AS cohort_month
    FROM fact_orders o
    JOIN dim_date d ON o.date_key = d.date_key
    WHERE o.is_first_order = 1
    GROUP BY o.customer_key
),
cohort_size AS (
    SELECT cohort_month,
           COUNT(DISTINCT customer_key) AS cohort_users
    FROM cohort_base GROUP BY cohort_month
),
activity AS (
    SELECT
        cb.cohort_month,
        o.customer_key,
        (CAST(SUBSTR(d.full_date, 1, 4) AS INTEGER) * 12
         + CAST(SUBSTR(d.full_date, 6, 2) AS INTEGER))
        -
        (CAST(SUBSTR(cb.cohort_month, 1, 4) AS INTEGER) * 12
         + CAST(SUBSTR(cb.cohort_month, 6, 2) AS INTEGER)) AS month_num
    FROM fact_orders o
    JOIN dim_date d ON o.date_key = d.date_key
    JOIN cohort_base cb ON o.customer_key = cb.customer_key
    WHERE o.order_status = 'completed'
)
SELECT
    a.cohort_month,
    cs.cohort_users,
    COUNT(DISTINCT CASE WHEN month_num = 0 THEN customer_key END)  AS m0,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN month_num = 1 THEN customer_key END)
          / cs.cohort_users, 0)  AS m1_pct,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN month_num = 2 THEN customer_key END)
          / cs.cohort_users, 0)  AS m2_pct,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN month_num = 3 THEN customer_key END)
          / cs.cohort_users, 0)  AS m3_pct,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN month_num = 4 THEN customer_key END)
          / cs.cohort_users, 0)  AS m4_pct
FROM activity a
JOIN cohort_size cs ON a.cohort_month = cs.cohort_month
GROUP BY a.cohort_month, cs.cohort_users
ORDER BY a.cohort_month;


-- ┌─────────────────────────────────────────────────────────┐
-- │  SECTION 4: FUNNEL ANALYSIS                             │
-- └─────────────────────────────────────────────────────────┘

-- Q11: Overall conversion funnel
-- Business question: Where are we losing customers in the purchase flow?
WITH funnel_steps AS (
    SELECT event_type,
           COUNT(DISTINCT session_id)  AS sessions,
           COUNT(DISTINCT customer_key) AS users
    FROM fact_events
    GROUP BY event_type
),
top AS (
    SELECT users AS top_users FROM funnel_steps WHERE event_type = 'pageview'
)
SELECT
    CASE event_type
        WHEN 'pageview'       THEN '1. Page view'
        WHEN 'add_to_cart'    THEN '2. Add to cart'
        WHEN 'checkout_start' THEN '3. Checkout start'
        WHEN 'purchase'       THEN '4. Purchase'
    END                                         AS funnel_step,
    users,
    ROUND(100.0 * users / top.top_users, 1)     AS pct_of_top,
    LAG(users) OVER (ORDER BY
        CASE event_type
            WHEN 'pageview'       THEN 1
            WHEN 'add_to_cart'    THEN 2
            WHEN 'checkout_start' THEN 3
            WHEN 'purchase'       THEN 4
        END)                                    AS prev_step_users,
    ROUND(100.0 * users / NULLIF(
        LAG(users) OVER (ORDER BY
            CASE event_type
                WHEN 'pageview'       THEN 1
                WHEN 'add_to_cart'    THEN 2
                WHEN 'checkout_start' THEN 3
                WHEN 'purchase'       THEN 4
            END), 0), 1)                        AS step_conversion_pct
FROM funnel_steps, top
ORDER BY
    CASE event_type
        WHEN 'pageview'       THEN 1
        WHEN 'add_to_cart'    THEN 2
        WHEN 'checkout_start' THEN 3
        WHEN 'purchase'       THEN 4
    END;


-- Q12: Funnel conversion by channel
-- Business question: Which channels convert best through the funnel?
SELECT
    c.channel_name,
    COUNT(DISTINCT CASE WHEN e.event_type = 'pageview'
                        THEN e.session_id END)       AS pageviews,
    COUNT(DISTINCT CASE WHEN e.event_type = 'add_to_cart'
                        THEN e.session_id END)        AS add_to_cart,
    COUNT(DISTINCT CASE WHEN e.event_type = 'purchase'
                        THEN e.session_id END)        AS purchases,
    ROUND(100.0 *
        COUNT(DISTINCT CASE WHEN e.event_type = 'purchase'
                            THEN e.session_id END)
        / NULLIF(COUNT(DISTINCT CASE WHEN e.event_type = 'pageview'
                                     THEN e.session_id END), 0), 1) AS overall_cvr
FROM fact_events e
JOIN dim_channel c ON e.channel_key = c.channel_key
GROUP BY c.channel_key, c.channel_name
ORDER BY overall_cvr DESC;


-- ┌─────────────────────────────────────────────────────────┐
-- │  SECTION 5: RETENTION                                   │
-- └─────────────────────────────────────────────────────────┘

-- Q13: 30/60/90 day retention rates
-- Business question: What % of customers come back within key windows?
WITH first_orders AS (
    SELECT
        o.customer_key,
        MIN(d.full_date) AS first_order_date
    FROM fact_orders o
    JOIN dim_date d ON o.date_key = d.date_key
    WHERE o.order_status = 'completed'
    GROUP BY o.customer_key
),
subsequent AS (
    SELECT
        fo.customer_key,
        fo.first_order_date,
        MIN(CASE WHEN d.full_date > fo.first_order_date
                  AND JULIANDAY(d.full_date) - JULIANDAY(fo.first_order_date) <= 30
                 THEN d.full_date END) AS retained_30d,
        MIN(CASE WHEN d.full_date > fo.first_order_date
                  AND JULIANDAY(d.full_date) - JULIANDAY(fo.first_order_date) <= 60
                 THEN d.full_date END) AS retained_60d,
        MIN(CASE WHEN d.full_date > fo.first_order_date
                  AND JULIANDAY(d.full_date) - JULIANDAY(fo.first_order_date) <= 90
                 THEN d.full_date END) AS retained_90d
    FROM first_orders fo
    LEFT JOIN fact_orders o2    ON fo.customer_key = o2.customer_key
                                AND o2.order_status = 'completed'
    LEFT JOIN dim_date d        ON o2.date_key = d.date_key
                                AND d.full_date > fo.first_order_date
    GROUP BY fo.customer_key, fo.first_order_date
)
SELECT
    COUNT(*)                                    AS total_customers,
    COUNT(retained_30d)                         AS retained_30d,
    COUNT(retained_60d)                         AS retained_60d,
    COUNT(retained_90d)                         AS retained_90d,
    ROUND(100.0 * COUNT(retained_30d) / COUNT(*), 1) AS d30_retention_pct,
    ROUND(100.0 * COUNT(retained_60d) / COUNT(*), 1) AS d60_retention_pct,
    ROUND(100.0 * COUNT(retained_90d) / COUNT(*), 1) AS d90_retention_pct
FROM subsequent;


-- Q14: Churn identification — customers who haven't ordered in 60+ days
-- Business question: Which customers are at risk of churning?
WITH last_order AS (
    SELECT
        c.customer_id,
        c.first_name || ' ' || c.last_name  AS customer_name,
        c.country,
        MAX(d.full_date)                     AS last_order_date,
        COUNT(DISTINCT o.order_id)           AS total_orders,
        ROUND(SUM(o.net_revenue), 2)         AS total_spent
    FROM dim_customer c
    JOIN fact_orders o  ON c.customer_key = o.customer_key
    JOIN dim_date d     ON o.date_key = d.date_key
    WHERE c.is_current = 1
      AND o.order_status = 'completed'
    GROUP BY c.customer_id, customer_name, c.country
)
SELECT *,
    CAST(JULIANDAY('2024-06-30') - JULIANDAY(last_order_date) AS INTEGER)
                                             AS days_since_last_order,
    CASE
        WHEN JULIANDAY('2024-06-30') - JULIANDAY(last_order_date) > 90
             THEN 'churned'
        WHEN JULIANDAY('2024-06-30') - JULIANDAY(last_order_date) > 60
             THEN 'at_risk'
        WHEN JULIANDAY('2024-06-30') - JULIANDAY(last_order_date) > 30
             THEN 'cooling'
        ELSE 'active'
    END AS churn_status
FROM last_order
ORDER BY days_since_last_order DESC;


-- ┌─────────────────────────────────────────────────────────┐
-- │  SECTION 6: ROLLING METRICS & TRENDS                    │
-- └─────────────────────────────────────────────────────────┘

-- Q15: Rolling 30-day revenue (moving window)
-- Business question: What is the revenue trend smoothed over 30 days?
WITH daily_rev AS (
    SELECT
        d.full_date,
        ROUND(SUM(o.net_revenue), 2) AS daily_revenue,
        COUNT(DISTINCT o.order_id)   AS daily_orders
    FROM fact_orders o
    JOIN dim_date d ON o.date_key = d.date_key
    WHERE o.order_status = 'completed'
    GROUP BY d.full_date
)
SELECT
    full_date,
    daily_revenue,
    daily_orders,
    ROUND(AVG(daily_revenue) OVER (
        ORDER BY full_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2)                            AS rolling_7d_avg_revenue,
    ROUND(SUM(daily_revenue) OVER (
        ORDER BY full_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ), 2)                            AS cumulative_revenue
FROM daily_rev
ORDER BY full_date;


-- Q16: Revenue concentration — top 20% of customers driving what % of revenue?
-- Business question: How concentrated is our revenue? (Pareto principle)
WITH customer_revenue AS (
    SELECT
        o.customer_key,
        ROUND(SUM(o.net_revenue), 2)  AS customer_ltv
    FROM fact_orders o
    WHERE o.order_status = 'completed'
    GROUP BY o.customer_key
),
ranked AS (
    SELECT *,
        NTILE(5) OVER (ORDER BY customer_ltv DESC) AS quintile,
        SUM(customer_ltv) OVER ()                   AS total_rev
    FROM customer_revenue
)
SELECT
    quintile,
    COUNT(*)                                         AS customers,
    ROUND(SUM(customer_ltv), 2)                      AS revenue,
    ROUND(100.0 * SUM(customer_ltv) / MAX(total_rev), 1) AS pct_of_revenue
FROM ranked
GROUP BY quintile
ORDER BY quintile;


-- ┌─────────────────────────────────────────────────────────┐
-- │  SECTION 7: ADVANCED ANALYTICS                          │
-- └─────────────────────────────────────────────────────────┘

-- Q17: Product affinity — what products are bought together most often?
-- Business question: What cross-sell opportunities exist?
SELECT
    p1.product_name  AS product_a,
    p2.product_name  AS product_b,
    COUNT(*)         AS times_bought_together
FROM fact_order_items oi1
JOIN fact_order_items oi2
    ON  oi1.order_id     = oi2.order_id
    AND oi1.product_key  < oi2.product_key   -- avoid duplicates
JOIN dim_product p1 ON oi1.product_key = p1.product_key
JOIN dim_product p2 ON oi2.product_key = p2.product_key
GROUP BY p1.product_name, p2.product_name
HAVING COUNT(*) >= 1
ORDER BY times_bought_together DESC
LIMIT 15;


-- Q18: Customer segmentation — RFM analysis
-- Recency, Frequency, Monetary — the gold standard segmentation
WITH rfm_raw AS (
    SELECT
        c.customer_id,
        c.first_name || ' ' || c.last_name        AS customer_name,
        MAX(d.full_date)                           AS last_order_date,
        CAST(JULIANDAY('2024-06-30')
             - JULIANDAY(MAX(d.full_date)) AS INTEGER) AS recency_days,
        COUNT(DISTINCT o.order_id)                 AS frequency,
        ROUND(SUM(o.net_revenue), 2)               AS monetary
    FROM dim_customer c
    JOIN fact_orders o  ON c.customer_key = o.customer_key
    JOIN dim_date d     ON o.date_key = d.date_key
    WHERE c.is_current = 1
      AND o.order_status = 'completed'
    GROUP BY c.customer_id, customer_name
),
rfm_scored AS (
    SELECT *,
        NTILE(5) OVER (ORDER BY recency_days ASC)  AS r_score,  -- lower days = higher score
        NTILE(5) OVER (ORDER BY frequency DESC)    AS f_score,
        NTILE(5) OVER (ORDER BY monetary DESC)     AS m_score
    FROM rfm_raw
)
SELECT *,
    ROUND((r_score + f_score + m_score) / 3.0, 1) AS rfm_score,
    CASE
        WHEN r_score >= 4 AND f_score >= 4 THEN 'Champions'
        WHEN r_score >= 3 AND f_score >= 3 THEN 'Loyal'
        WHEN r_score >= 4 AND f_score <= 2 THEN 'Recent'
        WHEN r_score <= 2 AND f_score >= 3 THEN 'At Risk'
        WHEN r_score <= 2 AND f_score <= 2 THEN 'Lost'
        ELSE 'Potential'
    END AS rfm_segment
FROM rfm_scored
ORDER BY rfm_score DESC;


-- Q19: Weekly revenue heatmap (day of week x week)
-- Business question: What days/weeks have highest revenue? Any patterns?
SELECT
    d.week_of_year,
    ROUND(SUM(CASE WHEN d.day_name = 'Monday'    THEN o.net_revenue ELSE 0 END), 0) AS Mon,
    ROUND(SUM(CASE WHEN d.day_name = 'Tuesday'   THEN o.net_revenue ELSE 0 END), 0) AS Tue,
    ROUND(SUM(CASE WHEN d.day_name = 'Wednesday' THEN o.net_revenue ELSE 0 END), 0) AS Wed,
    ROUND(SUM(CASE WHEN d.day_name = 'Thursday'  THEN o.net_revenue ELSE 0 END), 0) AS Thu,
    ROUND(SUM(CASE WHEN d.day_name = 'Friday'    THEN o.net_revenue ELSE 0 END), 0) AS Fri,
    ROUND(SUM(CASE WHEN d.day_name = 'Saturday'  THEN o.net_revenue ELSE 0 END), 0) AS Sat,
    ROUND(SUM(CASE WHEN d.day_name = 'Sunday'    THEN o.net_revenue ELSE 0 END), 0) AS Sun,
    ROUND(SUM(o.net_revenue), 0)                                                     AS week_total
FROM fact_orders o
JOIN dim_date d ON o.date_key = d.date_key
WHERE o.order_status = 'completed'
GROUP BY d.week_of_year
ORDER BY d.week_of_year;


-- Q20: Executive dashboard summary — single query, all KPIs
-- Business question: Give me the one-screen health check of the business
WITH
total_rev    AS (SELECT ROUND(SUM(net_revenue),2) v FROM fact_orders WHERE order_status='completed'),
total_orders AS (SELECT COUNT(DISTINCT order_id) v FROM fact_orders WHERE order_status='completed'),
total_cust   AS (SELECT COUNT(DISTINCT customer_key) v FROM fact_orders),
new_cust     AS (SELECT COUNT(DISTINCT customer_key) v FROM fact_orders WHERE is_first_order=1),
avg_ov       AS (SELECT ROUND(AVG(net_revenue),2) v FROM fact_orders WHERE order_status='completed'),
top_cat      AS (SELECT p.category FROM fact_order_items oi JOIN dim_product p ON oi.product_key=p.product_key GROUP BY p.category ORDER BY SUM(oi.line_revenue) DESC LIMIT 1),
refund_rate  AS (SELECT ROUND(100.0*SUM(CASE WHEN order_status='refunded' THEN 1 ELSE 0 END)/COUNT(*),1) v FROM fact_orders),
cancel_rate  AS (SELECT ROUND(100.0*SUM(CASE WHEN order_status='cancelled' THEN 1 ELSE 0 END)/COUNT(*),1) v FROM fact_orders)
SELECT
    total_rev.v    AS total_net_revenue,
    total_orders.v AS total_orders,
    total_cust.v   AS total_customers,
    new_cust.v     AS new_customers,
    total_cust.v - new_cust.v AS returning_customers,
    avg_ov.v       AS avg_order_value,
    top_cat.category AS top_category,
    refund_rate.v  AS refund_rate_pct,
    cancel_rate.v  AS cancel_rate_pct
FROM total_rev, total_orders, total_cust,
     new_cust, avg_ov, top_cat, refund_rate, cancel_rate;
