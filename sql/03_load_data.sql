-- ============================================================
-- Final Project: Olist Brazilian E-Commerce Database
-- Data Import Script (LOAD DATA LOCAL INFILE)
--
-- 导入策略：
--   • 按外键依赖顺序导入：无依赖表先导，有外键的表递进导入
--   • 品类翻译表最先（products 的外键依赖它）
--   • 客户/卖家在 orders 之前（外键约束）
--   • 商品在 order_items 之前（外键约束）
--   • orders 在 payments/reviews 之前（外键 + CASCADE 语义）
--   • geolocation 无依赖，任意时机导入
--   • inventory 最后生成（依赖 products 表存在）
--
-- CSV 格式说明：
--   • 所有文件 UTF-8 编码，逗号分隔
--   • 部分字段含双引号包裹（城市名含空格/特殊字符）
--   • 巴西时间格式 YYYY-MM-DD HH:MM:SS（与 DATETIME 兼容）
--   • 空值处理：日期字段空值映射为 NULL（订单流程未走到的阶段）
--   • product_category_translation.csv 含 BOM 头（﻿），需 TRIM
-- ============================================================

USE olist_db;

-- ============================================================
-- 第 1 批：零依赖表（无外键，安全先行导入）
-- ============================================================

-- 1.1 品类翻译表（仅 71 行，秒级导入）
-- BOM 头处理：第一列 product_category_name 前有 ﻿，需 TRIM
LOAD DATA LOCAL INFILE '/Users/gtc/Learning/数据库/finalproject/data/raw/product_category_name_translation.csv'
INTO TABLE product_category_translation
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(@col1, @col2)
SET
    product_category_name = TRIM(BOTH '\r' FROM @col1),
    product_category_name_english = TRIM(BOTH '\r' FROM @col2);

-- 1.2 客户表（99,441 行，约 30 秒导入）
-- 字段映射：列名与表列名一致，直接加载
LOAD DATA LOCAL INFILE '/Users/gtc/Learning/数据库/finalproject/data/raw/olist_customers_dataset.csv'
INTO TABLE customers
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

-- 1.3 卖家表（3,096 行，秒级导入）
LOAD DATA LOCAL INFILE '/Users/gtc/Learning/数据库/finalproject/data/raw/olist_sellers_dataset.csv'
INTO TABLE sellers
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

-- 1.4 地理坐标表（1,000,163 行，约 60 秒导入——最耗时步骤）
-- 100 万行直接倒入，MySQL LOAD DATA 效率优于逐行 INSERT
LOAD DATA LOCAL INFILE '/Users/gtc/Learning/数据库/finalproject/data/raw/olist_geolocation_dataset.csv'
INTO TABLE geolocation
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

-- ============================================================
-- 第 2 批：轻度依赖表（仅依赖第 1 批表）
-- ============================================================

-- 2.1 商品表（32,951 行，依赖品类翻译表）
-- 空值处理：品类名、尺寸/重量字段可能为空，NULLIF 转换空串为 NULL
LOAD DATA LOCAL INFILE '/Users/gtc/Learning/数据库/finalproject/data/raw/olist_products_dataset.csv'
INTO TABLE products
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(@pid, @cat, @name_len, @desc_len, @photos, @weight, @length, @height, @width)
SET
    product_id = @pid,
    product_category_name = NULLIF(TRIM(@cat), ''),
    product_name_lenght = NULLIF(@name_len, ''),
    product_description_lenght = NULLIF(@desc_len, ''),
    product_photos_qty = NULLIF(@photos, ''),
    product_weight_g = NULLIF(@weight, ''),
    product_length_cm = NULLIF(@length, ''),
    product_height_cm = NULLIF(@height, ''),
    product_width_cm = NULLIF(@width, '');

-- ============================================================
-- 第 3 批：核心依赖表（依赖第 1-2 批表）
-- ============================================================

-- 3.1 订单主表（99,441 行，依赖客户表）
-- 三处日期字段可空：审核/承运/签收，未发生的阶段为空串
LOAD DATA LOCAL INFILE '/Users/gtc/Learning/数据库/finalproject/data/raw/olist_orders_dataset.csv'
INTO TABLE orders
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(@oid, @cid, @status, @purchase, @approved, @carrier, @delivered, @estimated)
SET
    order_id = @oid,
    customer_id = @cid,
    order_status = @status,
    order_purchase_timestamp = @purchase,
    order_approved_at = NULLIF(@approved, ''),
    order_delivered_carrier_date = NULLIF(@carrier, ''),
    order_delivered_customer_date = NULLIF(@delivered, ''),
    order_estimated_delivery_date = @estimated;

-- ============================================================
-- 第 4 批：明细依赖表（依赖 orders + products + sellers）
-- ============================================================

-- 4.1 订单明细表（112,650 行，三重外键约束）
LOAD DATA LOCAL INFILE '/Users/gtc/Learning/数据库/finalproject/data/raw/olist_order_items_dataset.csv'
INTO TABLE order_items
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

-- 4.2 支付记录表（103,886 行，依赖 orders）
-- payment_installments 空值：未使用分期的支付方式（boleto/voucher）分期数为 1
LOAD DATA LOCAL INFILE '/Users/gtc/Learning/数据库/finalproject/data/raw/olist_order_payments_dataset.csv'
INTO TABLE order_payments
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

-- 4.3 评价表（104,720 行，依赖 orders）
-- 标题/内容为空：许多用户只给分不写文字，空串→NULL
-- answer_timestamp 为空：商家尚未回复的评价，空串→NULL
LOAD DATA LOCAL INFILE '/Users/gtc/Learning/数据库/finalproject/data/raw/olist_order_reviews_dataset.csv'
INTO TABLE order_reviews
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(@rid, @oid, @score, @title, @msg, @create_dt, @answer_ts)
SET
    review_id = @rid,
    order_id = @oid,
    review_score = @score,
    review_comment_title = NULLIF(TRIM(@title), ''),
    review_comment_message = NULLIF(TRIM(@msg), ''),
    review_creation_date = @create_dt,
    review_answer_timestamp = NULLIF(@answer_ts, '');

-- ============================================================
-- 第 5 批：自建表（依赖 products 表）
-- ============================================================

-- 5.1 库存表生成
-- 基于 products 表为每个商品生成库存记录
-- 95% 商品分配充足库存（50-500），5% 刻意设为≤8件（触发库存预警演示）
-- safety_stock 为安全水位线（10-50），约 5% 商品当前库存≤安全线
INSERT INTO inventory (product_id, stock_qty, safety_stock)
SELECT
    product_id,
    CASE
        WHEN RAND() < 0.05 THEN FLOOR(RAND() * 8 + 1)     -- 5% 低库存（1-8件）
        ELSE FLOOR(RAND() * 450 + 50)                      -- 95% 正常库存（50-499件）
    END AS stock_qty,
    FLOOR(RAND() * 40 + 10) AS safety_stock                -- 安全线 10-50
FROM products;

-- 5.2 初始低库存预警生成
-- 库存初始化时 stock_qty <= safety_stock 的商品需生成预警记录
-- （触发器 trg_inventory_low_stock_alert 只在 UPDATE 时触发，INSERT 时不触发）
INSERT INTO inventory_alert (product_id, alert_type, alert_msg, is_resolved)
SELECT
    product_id,
    'LOW_STOCK',
    CONCAT('Initial stock ', stock_qty, ' is at or below safety level ', safety_stock),
    0
FROM inventory
WHERE stock_qty <= safety_stock;

-- ============================================================
-- 导入验证：各表行数确认
-- ============================================================
SELECT '数据导入完成' AS status;
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'sellers', COUNT(*) FROM sellers
UNION ALL SELECT 'product_category_translation', COUNT(*) FROM product_category_translation
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'order_payments', COUNT(*) FROM order_payments
UNION ALL SELECT 'order_reviews', COUNT(*) FROM order_reviews
UNION ALL SELECT 'geolocation', COUNT(*) FROM geolocation
UNION ALL SELECT 'inventory', COUNT(*) FROM inventory
UNION ALL SELECT 'inventory_alert', COUNT(*) FROM inventory_alert;