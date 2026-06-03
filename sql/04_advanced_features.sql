-- ============================================================
-- Final Project: Olist Brazilian E-Commerce Database
-- Advanced Features: Views, Stored Procedures, Triggers,
-- Functions, Transactions, Index Optimization
-- ============================================================

USE olist_db;

-- Clean up existing triggers for re-runs
DROP TRIGGER IF EXISTS trg_order_item_deduct_stock;
DROP TRIGGER IF EXISTS trg_inventory_low_stock_alert;
DROP TRIGGER IF EXISTS trg_review_negative_alert;

-- ============================================================
-- PART 1: VIEWS
-- ============================================================

-- ------------------------------------------------------------
-- View 1: v_order_full (订单宽表 - 订单+客户+支付+评价聚合)
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_order_full AS
SELECT
    o.order_id,
    o.customer_id,
    c.customer_unique_id,
    c.customer_city,
    c.customer_state,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    COUNT(DISTINCT oi.product_id) AS product_count,
    COUNT(DISTINCT oi.seller_id) AS seller_count,
    ROUND(SUM(oi.price), 2) AS total_price,
    ROUND(SUM(oi.freight_value), 2) AS total_freight,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_amount,
    AVG(r.review_score) AS avg_review_score
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
LEFT JOIN order_items oi ON o.order_id = oi.order_id
LEFT JOIN order_reviews r ON o.order_id = r.order_id
GROUP BY o.order_id, o.customer_id, c.customer_unique_id,
         c.customer_city, c.customer_state, o.order_status,
         o.order_purchase_timestamp, o.order_delivered_customer_date,
         o.order_estimated_delivery_date;

-- ------------------------------------------------------------
-- View 2: v_category_sales (品类销售统计)
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_category_sales AS
SELECT
    pcat.product_category_name_english AS category_en,
    COUNT(DISTINCT oi.order_id) AS order_count,
    COUNT(oi.order_item_id) AS item_count,
    ROUND(SUM(oi.price), 2) AS total_revenue,
    ROUND(AVG(oi.price), 2) AS avg_price,
    ROUND(AVG(oi.freight_value), 2) AS avg_freight
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
LEFT JOIN product_category_translation pcat
    ON p.product_category_name = pcat.product_category_name
GROUP BY pcat.product_category_name_english
ORDER BY total_revenue DESC;

-- ------------------------------------------------------------
-- View 3: v_customer_rfm (RFM客户价值分析)
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_customer_rfm AS
WITH customer_stats AS (
    SELECT
        c.customer_unique_id,
        DATEDIFF(
            (SELECT MAX(order_purchase_timestamp) FROM orders),
            MAX(o.order_purchase_timestamp)
        ) AS recency,
        COUNT(DISTINCT o.order_id) AS frequency,
        ROUND(SUM(oi.price), 2) AS monetary
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT
    customer_unique_id,
    recency,
    frequency,
    monetary,
    -- RFM scoring using NTILE quintiles
    NTILE(5) OVER (ORDER BY recency DESC) AS r_score,
    NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
    NTILE(5) OVER (ORDER BY monetary ASC) AS m_score,
    CONCAT(
        NTILE(5) OVER (ORDER BY recency DESC),
        NTILE(5) OVER (ORDER BY frequency ASC),
        NTILE(5) OVER (ORDER BY monetary ASC)
    ) AS rfm_segment
FROM customer_stats;

-- ------------------------------------------------------------
-- View 4: v_monthly_revenue (月度收入趋势)
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_monthly_revenue AS
SELECT
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS month,
    COUNT(DISTINCT o.order_id) AS order_count,
    COUNT(DISTINCT o.customer_id) AS unique_customers,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_revenue,
    ROUND(AVG(oi.price + oi.freight_value), 2) AS avg_order_value
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
ORDER BY month;

-- ------------------------------------------------------------
-- View 5: v_product_recommendation (买了A的人也买了B)
-- 增强版：添加 Support 和 Lift 完整关联规则指标
--   • confidence = P(B|A) = count(A,B) / count(A)
--   • support    = P(A,B) = count(A,B) / total_orders
--   • lift       = P(B|A) / P(B) = confidence / support(B)
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_product_recommendation AS
WITH total_orders AS (
    SELECT COUNT(DISTINCT order_id) AS total FROM order_items
),
product_orders AS (
    SELECT product_id, COUNT(DISTINCT order_id) AS order_count
    FROM order_items
    GROUP BY product_id
)
SELECT
    a.product_id AS product_a,
    b.product_id AS product_b,
    COUNT(DISTINCT a.order_id) AS co_purchase_count,
    ROUND(
        COUNT(DISTINCT a.order_id) * 100.0 / pa.order_count,
        2
    ) AS confidence_pct,
    ROUND(
        COUNT(DISTINCT a.order_id) * 100.0 / t.total,
        4
    ) AS support_pct,
    ROUND(
        (COUNT(DISTINCT a.order_id) * 1.0 / pa.order_count)
        / (pb.order_count * 1.0 / t.total),
        4
    ) AS lift
FROM order_items a
JOIN order_items b
    ON a.order_id = b.order_id AND a.product_id < b.product_id
JOIN product_orders pa ON a.product_id = pa.product_id
JOIN product_orders pb ON b.product_id = pb.product_id
CROSS JOIN total_orders t
GROUP BY a.product_id, b.product_id, pa.order_count, pb.order_count, t.total
HAVING co_purchase_count >= 5
ORDER BY lift DESC, co_purchase_count DESC;

-- ------------------------------------------------------------
-- View 6: v_category_cross_sell (品类交叉销售分析)
-- 回答：买A品类的人还常买什么品类
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_category_cross_sell AS
WITH category_orders AS (
    SELECT
        pcat.product_category_name_english AS category_a,
        pcat2.product_category_name_english AS category_b,
        COUNT(DISTINCT oi.order_id) AS co_purchase_count
    FROM order_items oi
    JOIN products p ON oi.product_id = p.product_id
    LEFT JOIN product_category_translation pcat ON p.product_category_name = pcat.product_category_name
    JOIN order_items oi2 ON oi.order_id = oi2.order_id AND oi.product_id != oi2.product_id
    JOIN products p2 ON oi2.product_id = p2.product_id
    LEFT JOIN product_category_translation pcat2 ON p2.product_category_name = pcat2.product_category_name
    WHERE pcat.product_category_name_english IS NOT NULL
      AND pcat2.product_category_name_english IS NOT NULL
    GROUP BY pcat.product_category_name_english, pcat2.product_category_name_english
)
SELECT
    category_a,
    category_b,
    co_purchase_count,
    ROUND(co_purchase_count * 100.0 / SUM(co_purchase_count) OVER (PARTITION BY category_a), 2) AS pct_of_category_a
FROM category_orders
WHERE category_a != category_b
ORDER BY category_a, co_purchase_count DESC;

-- ------------------------------------------------------------
-- View 7: v_review_weighted_recommendation (评分过滤推荐)
-- 过滤掉差评商品对（avg_review_score < 3）
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_review_weighted_recommendation AS
SELECT
    v.product_a,
    v.product_b,
    v.co_purchase_count,
    v.confidence_pct,
    v.support_pct,
    v.lift,
    ROUND(AVG(ra.review_score), 2) AS avg_score_a,
    ROUND(AVG(rb.review_score), 2) AS avg_score_b
FROM v_product_recommendation v
LEFT JOIN order_items oia ON v.product_a = oia.product_id
LEFT JOIN order_reviews ra ON oia.order_id = ra.order_id
LEFT JOIN order_items oib ON v.product_b = oib.product_id
LEFT JOIN order_reviews rb ON oib.order_id = rb.order_id
GROUP BY v.product_a, v.product_b, v.co_purchase_count, v.confidence_pct, v.support_pct, v.lift
HAVING avg_score_a >= 3 AND avg_score_b >= 3
ORDER BY v.lift DESC;

-- ------------------------------------------------------------
-- View 8: v_instock_recommendation (库存感知推荐)
-- 只推荐有充足库存的商品（stock_qty > safety_stock）
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_instock_recommendation AS
SELECT
    v.product_a,
    v.product_b,
    v.co_purchase_count,
    v.confidence_pct,
    v.support_pct,
    v.lift,
    ia.stock_qty AS stock_a,
    ia.safety_stock AS safety_a,
    ib.stock_qty AS stock_b,
    ib.safety_stock AS safety_b
FROM v_product_recommendation v
JOIN inventory ia ON v.product_a = ia.product_id
JOIN inventory ib ON v.product_b = ib.product_id
WHERE ia.stock_qty > ia.safety_stock
  AND ib.stock_qty > ib.safety_stock
ORDER BY v.lift DESC;

-- ------------------------------------------------------------
-- View 9: v_inventory_status (库存健康度总览)
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_inventory_status AS
SELECT
    i.product_id,
    pcat.product_category_name_english AS category,
    i.stock_qty,
    i.safety_stock,
    (i.stock_qty - i.safety_stock) AS surplus,
    CASE
        WHEN i.stock_qty = 0 THEN 'Out of Stock'
        WHEN i.stock_qty <= i.safety_stock THEN 'Low Stock'
        WHEN i.stock_qty <= i.safety_stock * 2 THEN 'Warning'
        ELSE 'Healthy'
    END AS stock_status,
    i.last_updated
FROM inventory i
LEFT JOIN products p ON i.product_id = p.product_id
LEFT JOIN product_category_translation pcat ON p.product_category_name = pcat.product_category_name;

-- ------------------------------------------------------------
-- View 10: v_inventory_turnover (库存周转分析)
-- 基于历史订单数据计算每个商品的"虚拟"周转率
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_inventory_turnover AS
SELECT
    p.product_id,
    pcat.product_category_name_english AS category,
    i.stock_qty AS current_stock,
    i.safety_stock,
    COUNT(DISTINCT oi.order_id) AS total_orders,
    COUNT(oi.order_item_id) AS total_units_sold,
    ROUND(AVG(oi.price), 2) AS avg_selling_price,
    ROUND(SUM(oi.price), 2) AS total_revenue,
    ROUND(COUNT(oi.order_item_id) * 1.0 / NULLIF(i.stock_qty, 0), 4) AS turnover_ratio,
    CASE
        WHEN COUNT(oi.order_item_id) = 0 THEN 'Dead Stock'
        WHEN COUNT(oi.order_item_id) * 1.0 / NULLIF(i.stock_qty, 0) < 0.1 THEN 'Slow Moving'
        WHEN COUNT(oi.order_item_id) * 1.0 / NULLIF(i.stock_qty, 0) < 0.5 THEN 'Normal'
        ELSE 'Fast Moving'
    END AS movement_class
FROM products p
LEFT JOIN inventory i ON p.product_id = i.product_id
LEFT JOIN order_items oi ON p.product_id = oi.product_id
LEFT JOIN orders o ON oi.order_id = o.order_id AND o.order_status = 'delivered'
LEFT JOIN product_category_translation pcat ON p.product_category_name = pcat.product_category_name
GROUP BY p.product_id, pcat.product_category_name_english, i.stock_qty, i.safety_stock
ORDER BY turnover_ratio DESC;

-- ============================================================
-- PART 2: FUNCTIONS
-- ============================================================

-- ------------------------------------------------------------
-- Function: fn_shipping_days (计算物流天数)
-- ------------------------------------------------------------
DELIMITER //

CREATE FUNCTION fn_shipping_days(
    p_order_id VARCHAR(32)
)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_purchase DATETIME;
    DECLARE v_delivered DATETIME;
    DECLARE v_days INT;

    SELECT order_purchase_timestamp, order_delivered_customer_date
    INTO v_purchase, v_delivered
    FROM orders WHERE order_id = p_order_id;

    IF v_delivered IS NULL THEN
        RETURN NULL;
    END IF;

    SET v_days = DATEDIFF(v_delivered, v_purchase);
    RETURN v_days;
END //

-- ------------------------------------------------------------
-- Function: fn_order_total (计算订单总价含运费)
-- ------------------------------------------------------------
CREATE FUNCTION fn_order_total(
    p_order_id VARCHAR(32)
)
RETURNS DECIMAL(12,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(12,2);

    SELECT ROUND(SUM(price + freight_value), 2)
    INTO v_total
    FROM order_items
    WHERE order_id = p_order_id;

    RETURN IFNULL(v_total, 0);
END //

DELIMITER ;

-- ============================================================
-- PART 3: INDEX OPTIMIZATION
-- ============================================================

-- Composite index for order status + time range queries
CREATE INDEX idx_order_status_time ON orders(order_status, order_purchase_timestamp);

-- Composite index for product-seller analysis
CREATE INDEX idx_oi_product_seller ON order_items(product_id, seller_id);

-- Index for review analysis by score
CREATE INDEX idx_review_score_date ON order_reviews(review_score, review_creation_date);

-- ============================================================
-- PART 4: TRIGGERS
-- ============================================================

DELIMITER //

-- ------------------------------------------------------------
-- Trigger 1: trg_order_item_deduct_stock
-- On inserting an order item, deduct inventory stock.
-- Raises error if stock insufficient (simulates real stock check).
-- ------------------------------------------------------------
CREATE TRIGGER trg_order_item_deduct_stock
BEFORE INSERT ON order_items
FOR EACH ROW
BEGIN
    DECLARE v_current_stock INT;
    DECLARE v_safety_stock INT;

    SELECT stock_qty, safety_stock
    INTO v_current_stock, v_safety_stock
    FROM inventory
    WHERE product_id = NEW.product_id
    FOR UPDATE;

    IF v_current_stock IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: Product not found in inventory';
    END IF;

    -- Simulate deduction: in reality this would be 1 per item,
    -- but for demo we deduct a random qty between 1-3
    IF v_current_stock < 1 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: Insufficient stock for product';
    END IF;

    UPDATE inventory
    SET stock_qty = stock_qty - 1
    WHERE product_id = NEW.product_id;
END //

-- ------------------------------------------------------------
-- Trigger 2: trg_inventory_low_stock_alert
-- After inventory update, if stock drops below safety level,
-- insert an alert record (avoids duplicate alerts for same product).
-- ------------------------------------------------------------
CREATE TRIGGER trg_inventory_low_stock_alert
AFTER UPDATE ON inventory
FOR EACH ROW
BEGIN
    IF NEW.stock_qty <= NEW.safety_stock AND OLD.stock_qty > NEW.safety_stock THEN
        INSERT INTO inventory_alert (product_id, alert_type, alert_msg, is_resolved)
        VALUES (
            NEW.product_id,
            'LOW_STOCK',
            CONCAT('Stock dropped to ', NEW.stock_qty,
                   ' (safety: ', NEW.safety_stock, ')'),
            0
        );
    END IF;
END //

-- ------------------------------------------------------------
-- Trigger 3: trg_review_negative_alert
-- When a review with score <= 2 is inserted, log an alert.
-- ------------------------------------------------------------
CREATE TRIGGER trg_review_negative_alert
AFTER INSERT ON order_reviews
FOR EACH ROW
BEGIN
    IF NEW.review_score <= 2 THEN
        INSERT INTO inventory_alert (product_id, alert_type, alert_msg, is_resolved)
        SELECT
            oi.product_id,
            'NEGATIVE_REVIEW',
            CONCAT('Order ', NEW.order_id, ' received score ', NEW.review_score),
            0
        FROM order_items oi
        WHERE oi.order_id = NEW.order_id
        LIMIT 1;
    END IF;
END //

DELIMITER ;

-- ============================================================
-- PART 5: STORED PROCEDURES
-- ============================================================

DELIMITER //

-- ------------------------------------------------------------
-- Procedure 1: sp_place_order (下单事务演示)
-- Simulates placing a new order with inventory check and deduction.
-- Uses explicit transaction with rollback on error.
-- ------------------------------------------------------------
CREATE PROCEDURE sp_place_order(
    IN p_customer_id VARCHAR(32),
    IN p_product_id VARCHAR(32),
    IN p_seller_id VARCHAR(32),
    IN p_price DECIMAL(10,2),
    IN p_freight DECIMAL(10,2),
    OUT p_new_order_id VARCHAR(32)
)
BEGIN
    DECLARE v_stock INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Generate new order ID (using MD5 of UUID)
    SET p_new_order_id = MD5(UUID());

    -- Insert order
    INSERT INTO orders (
        order_id, customer_id, order_status,
        order_purchase_timestamp, order_estimated_delivery_date
    ) VALUES (
        p_new_order_id, p_customer_id, 'created',
        NOW(), DATE_ADD(NOW(), INTERVAL 14 DAY)
    );

    -- Insert order item (trigger will check and deduct stock)
    INSERT INTO order_items (
        order_id, order_item_id, product_id, seller_id,
        shipping_limit_date, price, freight_value
    ) VALUES (
        p_new_order_id, 1, p_product_id, p_seller_id,
        DATE_ADD(NOW(), INTERVAL 3 DAY), p_price, p_freight
    );

    COMMIT;
END //

-- ------------------------------------------------------------
-- Procedure 2: sp_state_monthly_revenue
-- Returns monthly revenue for a specific state.
-- ------------------------------------------------------------
CREATE PROCEDURE sp_state_monthly_revenue(
    IN p_state CHAR(2),
    IN p_year INT
)
BEGIN
    SELECT
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS month,
        COUNT(DISTINCT o.order_id) AS order_count,
        ROUND(SUM(oi.price + oi.freight_value), 2) AS total_revenue
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE c.customer_state = p_state
      AND YEAR(o.order_purchase_timestamp) = p_year
      AND o.order_status = 'delivered'
    GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
    ORDER BY month;
END //

-- ------------------------------------------------------------
-- Procedure 3: sp_low_stock_report
-- Returns all products with stock at or below safety level.
-- ------------------------------------------------------------
CREATE PROCEDURE sp_low_stock_report()
BEGIN
    SELECT
        p.product_id,
        pcat.product_category_name_english AS category,
        i.stock_qty,
        i.safety_stock,
        (i.stock_qty - i.safety_stock) AS surplus,
        i.last_updated
    FROM inventory i
    JOIN products p ON i.product_id = p.product_id
    LEFT JOIN product_category_translation pcat
        ON p.product_category_name = pcat.product_category_name
    WHERE i.stock_qty <= i.safety_stock
    ORDER BY surplus ASC;
END //

-- ------------------------------------------------------------
-- Procedure 4: sp_restock_product (补货)
-- 增强：补货后自动将未解决的 LOW_STOCK 预警标记为已解决
-- ------------------------------------------------------------
CREATE PROCEDURE sp_restock_product(
    IN p_product_id VARCHAR(32),
    IN p_add_qty INT
)
BEGIN
    IF p_add_qty <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: Restock quantity must be positive';
    END IF;

    UPDATE inventory
    SET stock_qty = stock_qty + p_add_qty
    WHERE product_id = p_product_id;

    -- 自动解决该商品的未处理 LOW_STOCK 预警
    UPDATE inventory_alert
    SET is_resolved = 1, resolved_at = NOW()
    WHERE product_id = p_product_id
      AND alert_type = 'LOW_STOCK'
      AND is_resolved = 0;

    SELECT product_id, stock_qty, safety_stock
    FROM inventory
    WHERE product_id = p_product_id;
END //

DELIMITER ;

-- ============================================================
-- PART 6: VERIFY FEATURES
-- ============================================================

SELECT 'Advanced features loaded successfully' AS status;
SHOW TRIGGERS;
SHOW PROCEDURE STATUS WHERE Db = 'olist_db';
