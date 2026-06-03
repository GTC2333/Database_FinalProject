-- ============================================================
-- Final Project: Olist Brazilian E-Commerce Database
-- Data Analysis Queries
-- Covers: sales trends, geography, categories, RFM, repurchase,
-- delivery time, payment preferences, recommendations
-- ============================================================

USE olist_db;

-- ============================================================
-- 1. 月度销售趋势分析
-- ============================================================
SELECT
    DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS month,
    COUNT(DISTINCT order_id) AS total_orders,
    COUNT(DISTINCT customer_id) AS unique_customers,
    ROUND(SUM(total_amount), 2) AS total_revenue
FROM v_order_full
WHERE order_status = 'delivered'
GROUP BY month
ORDER BY month;

-- ============================================================
-- 2. 各州销售额地理分布
-- ============================================================
SELECT
    customer_state AS state,
    COUNT(DISTINCT order_id) AS order_count,
    ROUND(SUM(total_amount), 2) AS total_revenue,
    ROUND(AVG(total_amount), 2) AS avg_order_value
FROM v_order_full
WHERE order_status = 'delivered'
GROUP BY customer_state
ORDER BY total_revenue DESC
LIMIT 10;

-- ============================================================
-- 3. TOP 10 品类销售额排名
-- ============================================================
SELECT
    category_en,
    order_count,
    item_count,
    total_revenue,
    avg_price
FROM v_category_sales
WHERE category_en IS NOT NULL
ORDER BY total_revenue DESC
LIMIT 10;

-- ============================================================
-- 4. 支付方式偏好分析
-- ============================================================
SELECT
    payment_type,
    COUNT(DISTINCT order_id) AS order_count,
    ROUND(SUM(payment_value), 2) AS total_payment,
    ROUND(AVG(payment_value), 2) AS avg_payment,
    ROUND(AVG(payment_installments), 1) AS avg_installments
FROM order_payments
GROUP BY payment_type
ORDER BY total_payment DESC;

-- ============================================================
-- 5. 配送时效分析 (使用自定义函数)
-- ============================================================
SELECT
    c.customer_state,
    COUNT(*) AS delivered_orders,
    ROUND(AVG(fn_shipping_days(o.order_id)), 1) AS avg_shipping_days,
    ROUND(MIN(fn_shipping_days(o.order_id)), 1) AS min_days,
    ROUND(MAX(fn_shipping_days(o.order_id)), 1) AS max_days,
    ROUND(
        SUM(CASE WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
        2
    ) AS on_time_rate_pct
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY customer_state
ORDER BY avg_shipping_days ASC;

-- ============================================================
-- 6. 客户复购率分析
-- ============================================================
WITH customer_orders AS (
    SELECT
        customer_unique_id,
        COUNT(DISTINCT o.order_id) AS order_count,
        MIN(o.order_purchase_timestamp) AS first_order,
        MAX(o.order_purchase_timestamp) AS last_order
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY customer_unique_id
)
SELECT
    CASE
        WHEN order_count = 1 THEN 'One-time'
        WHEN order_count BETWEEN 2 AND 3 THEN '2-3 times'
        WHEN order_count BETWEEN 4 AND 5 THEN '4-5 times'
        ELSE '6+ times'
    END AS purchase_frequency,
    COUNT(*) AS customer_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct
FROM customer_orders
GROUP BY purchase_frequency
ORDER BY customer_count DESC;

-- ============================================================
-- 7. RFM 客户价值分层
-- ============================================================
SELECT
    rfm_segment,
    COUNT(*) AS customer_count,
    ROUND(AVG(monetary), 2) AS avg_monetary,
    ROUND(AVG(frequency), 1) AS avg_frequency,
    ROUND(AVG(recency), 1) AS avg_recency,
    CASE
        WHEN rfm_segment LIKE '5%' THEN 'Champions'
        WHEN rfm_segment LIKE '4%' OR rfm_segment LIKE '45%' OR rfm_segment LIKE '54%' THEN 'Loyal Customers'
        WHEN rfm_segment LIKE '1%' THEN 'Lost Customers'
        WHEN rfm_segment LIKE '2%' THEN 'At Risk'
        ELSE 'Potential Loyalists'
    END AS segment_label
FROM v_customer_rfm
GROUP BY rfm_segment
ORDER BY customer_count DESC;

-- ============================================================
-- 8. 评价情感分布与物流延迟关系
-- ============================================================
SELECT
    review_score,
    COUNT(*) AS review_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct,
    ROUND(AVG(fn_shipping_days(r.order_id)), 1) AS avg_shipping_days
FROM order_reviews r
JOIN orders o ON r.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY review_score
ORDER BY review_score DESC;

-- ============================================================
-- 9. TOP 10 热销商品 (含品类)
-- ============================================================
SELECT
    p.product_id,
    pcat.product_category_name_english AS category,
    COUNT(DISTINCT oi.order_id) AS order_count,
    SUM(oi.price) AS total_revenue,
    ROUND(AVG(oi.price), 2) AS avg_price
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
LEFT JOIN product_category_translation pcat
    ON p.product_category_name = pcat.product_category_name
GROUP BY p.product_id, pcat.product_category_name_english
ORDER BY total_revenue DESC
LIMIT 10;

-- ============================================================
-- 10. 商品关联推荐 TOP 20 (买了A的人也买了B)
-- ============================================================
SELECT
    pa.product_id AS product_a,
    pcat_a.product_category_name_english AS cat_a,
    pb.product_id AS product_b,
    pcat_b.product_category_name_english AS cat_b,
    v.co_purchase_count,
    v.confidence_pct
FROM v_product_recommendation v
JOIN products pa ON v.product_a = pa.product_id
JOIN products pb ON v.product_b = pb.product_id
LEFT JOIN product_category_translation pcat_a
    ON pa.product_category_name = pcat_a.product_category_name
LEFT JOIN product_category_translation pcat_b
    ON pb.product_category_name = pcat_b.product_category_name
ORDER BY v.co_purchase_count DESC
LIMIT 20;

-- ============================================================
-- 11. 库存健康度分布
-- ============================================================
SELECT
    stock_status,
    COUNT(*) AS product_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct
FROM v_inventory_status
GROUP BY stock_status
ORDER BY product_count DESC;

-- ============================================================
-- 12. 库存周转最快 TOP 10 商品
-- ============================================================
SELECT
    product_id,
    category,
    current_stock,
    total_units_sold,
    turnover_ratio,
    movement_class
FROM v_inventory_turnover
WHERE turnover_ratio IS NOT NULL
ORDER BY turnover_ratio DESC
LIMIT 10;

-- ============================================================
-- 13. 库存周转最慢 TOP 10 商品（死库存/滞销）
-- ============================================================
SELECT
    product_id,
    category,
    current_stock,
    total_units_sold,
    turnover_ratio,
    movement_class
FROM v_inventory_turnover
ORDER BY turnover_ratio ASC
LIMIT 10;

-- ============================================================
-- 14. 最强关联规则 TOP 20（按 Lift 排序）
-- ============================================================
SELECT
    pa.product_id AS product_a,
    pcat_a.product_category_name_english AS cat_a,
    pb.product_id AS product_b,
    pcat_b.product_category_name_english AS cat_b,
    v.co_purchase_count,
    v.confidence_pct,
    v.support_pct,
    v.lift
FROM v_product_recommendation v
JOIN products pa ON v.product_a = pa.product_id
JOIN products pb ON v.product_b = pb.product_id
LEFT JOIN product_category_translation pcat_a
    ON pa.product_category_name = pcat_a.product_category_name
LEFT JOIN product_category_translation pcat_b
    ON pb.product_category_name = pcat_b.product_category_name
ORDER BY v.lift DESC
LIMIT 20;

-- ============================================================
-- 15. 品类交叉销售 TOP 20 组合
-- ============================================================
SELECT
    category_a,
    category_b,
    co_purchase_count,
    pct_of_category_a
FROM v_category_cross_sell
ORDER BY co_purchase_count DESC
LIMIT 20;

-- ============================================================
-- 16. 库存预警历史趋势（按月份）
-- ============================================================
SELECT
    DATE_FORMAT(created_at, '%Y-%m') AS month,
    alert_type,
    COUNT(*) AS alert_count,
    SUM(CASE WHEN is_resolved = 1 THEN 1 ELSE 0 END) AS resolved_count,
    ROUND(SUM(CASE WHEN is_resolved = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS resolution_rate_pct
FROM inventory_alert
GROUP BY DATE_FORMAT(created_at, '%Y-%m'), alert_type
ORDER BY month, alert_type;
