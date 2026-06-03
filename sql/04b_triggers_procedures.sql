-- ============================================================
-- Fix: Triggers and Procedures (run after 04_advanced_features.sql)
-- ============================================================

USE olist_db;

-- Drop existing triggers and procedures for clean re-run
DROP TRIGGER IF EXISTS trg_order_item_deduct_stock;
DROP TRIGGER IF EXISTS trg_inventory_low_stock_alert;
DROP TRIGGER IF EXISTS trg_review_negative_alert;

DROP PROCEDURE IF EXISTS sp_place_order;
DROP PROCEDURE IF EXISTS sp_state_monthly_revenue;
DROP PROCEDURE IF EXISTS sp_low_stock_report;
DROP PROCEDURE IF EXISTS sp_restock_product;

DELIMITER //

-- ------------------------------------------------------------
-- Trigger 1: trg_order_item_deduct_stock
-- ------------------------------------------------------------
CREATE TRIGGER trg_order_item_deduct_stock
BEFORE INSERT ON order_items
FOR EACH ROW
BEGIN
    DECLARE v_current_stock INT;

    SELECT stock_qty
    INTO v_current_stock
    FROM inventory
    WHERE product_id = NEW.product_id
    FOR UPDATE;

    IF v_current_stock IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: Product not found in inventory';
    END IF;

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
-- ------------------------------------------------------------
CREATE TRIGGER trg_inventory_low_stock_alert
AFTER UPDATE ON inventory
FOR EACH ROW
BEGIN
    IF NEW.stock_qty <= NEW.safety_stock AND OLD.stock_qty > NEW.safety_stock THEN
        INSERT INTO inventory_alert (product_id, alert_type, alert_msg)
        VALUES (
            NEW.product_id,
            'LOW_STOCK',
            CONCAT('Stock dropped to ', NEW.stock_qty,
                   ' (safety: ', NEW.safety_stock, ')')
        );
    END IF;
END //

-- ------------------------------------------------------------
-- Trigger 3: trg_review_negative_alert
-- ------------------------------------------------------------
CREATE TRIGGER trg_review_negative_alert
AFTER INSERT ON order_reviews
FOR EACH ROW
BEGIN
    IF NEW.review_score <= 2 THEN
        INSERT INTO inventory_alert (product_id, alert_type, alert_msg)
        SELECT
            oi.product_id,
            'NEGATIVE_REVIEW',
            CONCAT('Order ', NEW.order_id, ' received score ', NEW.review_score)
        FROM order_items oi
        WHERE oi.order_id = NEW.order_id
        LIMIT 1;
    END IF;
END //

-- ------------------------------------------------------------
-- Procedure 1: sp_place_order
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
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SET p_new_order_id = MD5(UUID());

    INSERT INTO orders (
        order_id, customer_id, order_status,
        order_purchase_timestamp, order_estimated_delivery_date
    ) VALUES (
        p_new_order_id, p_customer_id, 'created',
        NOW(), DATE_ADD(NOW(), INTERVAL 14 DAY)
    );

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
-- Procedure 4: sp_restock_product
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

-- ------------------------------------------------------------
-- Trigger 4: trg_inventory_log_insert
-- 记录初始库存入库
-- ------------------------------------------------------------
CREATE TRIGGER trg_inventory_log_insert
AFTER INSERT ON inventory
FOR EACH ROW
BEGIN
    INSERT INTO inventory_log (product_id, change_qty, old_stock, new_stock, change_type, reference_id)
    VALUES (NEW.product_id, NEW.stock_qty, 0, NEW.stock_qty, 'INIT', NULL);
END //

-- ------------------------------------------------------------
-- Trigger 5: trg_inventory_log_update
-- 记录每一次库存变更（下单扣减、补货、调整）
-- ------------------------------------------------------------
CREATE TRIGGER trg_inventory_log_update
AFTER UPDATE ON inventory
FOR EACH ROW
BEGIN
    DECLARE v_change_type ENUM('ORDER','RESTOCK','ADJUST','RETURN','INIT');
    DECLARE v_ref_id VARCHAR(32) DEFAULT NULL;

    -- 根据库存变化方向推断变更类型
    SET v_change_type = CASE
        WHEN NEW.stock_qty < OLD.stock_qty THEN 'ORDER'
        WHEN NEW.stock_qty > OLD.stock_qty THEN 'RESTOCK'
        ELSE 'ADJUST'
    END;

    INSERT INTO inventory_log (product_id, change_qty, old_stock, new_stock, change_type, reference_id)
    VALUES (
        NEW.product_id,
        NEW.stock_qty - OLD.stock_qty,
        OLD.stock_qty,
        NEW.stock_qty,
        v_change_type,
        v_ref_id
    );
END //

-- ------------------------------------------------------------
-- Procedure 5: sp_bulk_restock
-- 批量补货：传入逗号分隔的商品ID列表，统一补货
-- ------------------------------------------------------------
CREATE PROCEDURE sp_bulk_restock(
    IN p_product_id_list TEXT,
    IN p_qty_per_product INT
)
BEGIN
    DECLARE v_product_id VARCHAR(32);
    DECLARE v_done INT DEFAULT FALSE;
    DECLARE v_cursor CURSOR FOR
        SELECT TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(p_product_id_list, ',', n.n), ',', -1)) AS pid
        FROM (SELECT 1 AS n UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5
              UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9 UNION SELECT 10) n
        WHERE n.n <= 1 + LENGTH(p_product_id_list) - LENGTH(REPLACE(p_product_id_list, ',', ''));
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;

    IF p_qty_per_product <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: Restock quantity must be positive';
    END IF;

    OPEN v_cursor;
    read_loop: LOOP
        FETCH v_cursor INTO v_product_id;
        IF v_done THEN
            LEAVE read_loop;
        END IF;
        IF v_product_id IS NOT NULL AND LENGTH(v_product_id) > 0 THEN
            UPDATE inventory
            SET stock_qty = stock_qty + p_qty_per_product
            WHERE product_id = v_product_id;

            -- 自动解决预警
            UPDATE inventory_alert
            SET is_resolved = 1, resolved_at = NOW()
            WHERE product_id = v_product_id
              AND alert_type = 'LOW_STOCK'
              AND is_resolved = 0;
        END IF;
    END LOOP;
    CLOSE v_cursor;

    SELECT CONCAT('Bulk restock completed for up to 10 products, qty=', p_qty_per_product) AS result;
END //

-- ------------------------------------------------------------
-- Procedure 6: sp_adjust_inventory
-- 库存调整：处理盘点差异、损耗、退货入库等
-- ------------------------------------------------------------
CREATE PROCEDURE sp_adjust_inventory(
    IN p_product_id VARCHAR(32),
    IN p_adjust_qty INT,
    IN p_reason VARCHAR(100)
)
BEGIN
    DECLARE v_old_stock INT;
    DECLARE v_new_stock INT;

    SELECT stock_qty INTO v_old_stock FROM inventory WHERE product_id = p_product_id;

    IF v_old_stock IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: Product not found in inventory';
    END IF;

    SET v_new_stock = v_old_stock + p_adjust_qty;

    IF v_new_stock < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: Adjustment would result in negative stock';
    END IF;

    UPDATE inventory
    SET stock_qty = v_new_stock
    WHERE product_id = p_product_id;

    -- 手动记录调整日志（触发器也会记录，但这里记录更详细的 reason 信息）
    INSERT INTO inventory_log (product_id, change_qty, old_stock, new_stock, change_type, reference_id)
    VALUES (p_product_id, p_adjust_qty, v_old_stock, v_new_stock, 'ADJUST', LEFT(p_reason, 32));

    SELECT product_id, v_old_stock AS old_stock, v_new_stock AS new_stock, p_reason AS adjustment_reason;
END //

-- ------------------------------------------------------------
-- Procedure 7: sp_get_product_recommendations
-- 为指定商品返回 TOP N 关联推荐（基于 lift 排序）
-- ------------------------------------------------------------
CREATE PROCEDURE sp_get_product_recommendations(
    IN p_product_id VARCHAR(32),
    IN p_limit INT
)
BEGIN
    SELECT
        v.product_b AS recommended_product_id,
        pcat.product_category_name_english AS category,
        v.co_purchase_count,
        v.confidence_pct,
        v.support_pct,
        v.lift
    FROM v_product_recommendation v
    JOIN products pb ON v.product_b = pb.product_id
    LEFT JOIN product_category_translation pcat
        ON pb.product_category_name = pcat.product_category_name
    WHERE v.product_a = p_product_id
       OR (v.product_a > p_product_id AND v.product_b = p_product_id)
    ORDER BY v.lift DESC, v.co_purchase_count DESC
    LIMIT p_limit;
END //

-- ------------------------------------------------------------
-- Procedure 8: sp_get_customer_recommendations
-- 基于用户历史购买的个性化推荐（用户共现协同过滤）
-- ------------------------------------------------------------
CREATE PROCEDURE sp_get_customer_recommendations(
    IN p_customer_unique_id VARCHAR(32),
    IN p_limit INT
)
BEGIN
    -- 找到与该用户购买过相同商品的其他用户
    -- 然后推荐那些用户买过但该用户没买过的商品
    SELECT
        rec.product_id,
        pcat.product_category_name_english AS category,
        COUNT(*) AS co_customer_count,
        ROUND(AVG(rec.total_bought), 2) AS avg_peer_purchase
    FROM (
        SELECT DISTINCT oi2.product_id, oi2.order_id
        FROM customers c
        JOIN orders o ON c.customer_id = o.customer_id
        JOIN order_items oi ON o.order_id = oi.order_id
        JOIN order_items oi2 ON oi.product_id = oi2.product_id
        JOIN orders o2 ON oi2.order_id = o2.order_id
        JOIN customers c2 ON o2.customer_id = c2.customer_id
        WHERE c.customer_unique_id = p_customer_unique_id
          AND c2.customer_unique_id != p_customer_unique_id
    ) rec
    JOIN products p ON rec.product_id = p.product_id
    LEFT JOIN product_category_translation pcat
        ON p.product_category_name = pcat.product_category_name
    WHERE rec.product_id NOT IN (
        SELECT oi3.product_id
        FROM customers c3
        JOIN orders o3 ON c3.customer_id = o3.customer_id
        JOIN order_items oi3 ON o3.order_id = oi3.order_id
        WHERE c3.customer_unique_id = p_customer_unique_id
    )
    GROUP BY rec.product_id, pcat.product_category_name_english
    ORDER BY co_customer_count DESC
    LIMIT p_limit;
END //

DELIMITER ;

-- Verify
SELECT 'Triggers and procedures created successfully' AS status;
SHOW TRIGGERS;
SHOW PROCEDURE STATUS WHERE Db = 'olist_db';
