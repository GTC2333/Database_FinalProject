-- ============================================================
-- Final Project: Olist Brazilian E-Commerce Database
-- Table Creation with Constraints
--
-- 设计说明：
--   • 所有 32 位哈希 ID 使用 VARCHAR(32)，匹配源数据格式
--   • DECIMAL(10,2) 存储金额，避免 FLOAT 精度损失
--   • ENUM 约束订单状态，防止非法状态值进入系统
--   • TIMESTAMP 时间戳统一使用 ISO 格式（YYYY-MM-DD HH:MM:SS）
--   • InnoDB 引擎支持外键级联删除 & 行级锁，保证事务一致性
-- ============================================================

USE olist_db;

-- ============================================================
-- 【表 1】customers — 客户信息表
--
-- 设计意图：
--   • customer_id 为订单级标识（同一自然人每次下单生成新 ID）
--   • customer_unique_id 为真实客户标识，用于跨订单追踪同一客户
--   • zip_code_prefix 取邮编前 5 位，可 JOIN 到 geolocation 获取经纬度
--   • state 使用 CHAR(2) 固定长度，巴西全部 27 个州缩写均为 2 字符
-- ============================================================
CREATE TABLE customers (
    customer_id             VARCHAR(32) PRIMARY KEY COMMENT '订单级客户ID',
    customer_unique_id      VARCHAR(32) NOT NULL COMMENT '真实客户唯一ID（跨订单追踪）',
    customer_zip_code_prefix VARCHAR(10) NOT NULL COMMENT '邮编前缀（前5位）',
    customer_city           VARCHAR(50) NOT NULL COMMENT '城市名',
    customer_state          CHAR(2) NOT NULL COMMENT '州缩写（如SP=圣保罗,RJ=里约）',

    CONSTRAINT uq_customer_unique UNIQUE (customer_unique_id),
    INDEX idx_customer_state (customer_state) COMMENT '州级分组查询加速',
    INDEX idx_customer_zip (customer_zip_code_prefix) COMMENT '邮编地理查询加速'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='客户信息表（96,096条）';

-- ============================================================
-- 【表 2】sellers — 卖家信息表
--
-- 设计意图：
--   • 每个卖家有唯一 seller_id，与 customers 表对称设计
--   • 同样使用 zip/state 字段方便地理维度分析
--   • 数据量较小（3,095 家），索引压力低
-- ============================================================
CREATE TABLE sellers (
    seller_id               VARCHAR(32) PRIMARY KEY COMMENT '卖家ID',
    seller_zip_code_prefix  VARCHAR(10) NOT NULL COMMENT '邮编前缀',
    seller_city             VARCHAR(50) NOT NULL COMMENT '城市',
    seller_state            CHAR(2) NOT NULL COMMENT '州缩写',

    INDEX idx_seller_state (seller_state) COMMENT '卖家地理分布分析'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='卖家信息表（3,095家）';

-- ============================================================
-- 【表 3】product_category_translation — 品类翻译表
--
-- 设计意图：
--   • Olist 原始品类名为葡萄牙语，保留的同时提供英文翻译
--   • 使用 product_category_name 为主键（葡萄牙语名唯一）
--   • 可选外键关联：产品表中品类可为 NULL，避免因翻译缺失导致插入失败
-- ============================================================
CREATE TABLE product_category_translation (
    product_category_name           VARCHAR(50) PRIMARY KEY COMMENT '葡萄牙语品类名（如beleza_saude）',
    product_category_name_english   VARCHAR(50) NOT NULL COMMENT '英语品类名（如health_beauty）'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='产品品类名称翻译表（71个品类）';

-- ============================================================
-- 【表 4】products — 商品信息表
--
-- 设计意图：
--   • product_category_name 为可空外键关联（约 2% 商品品类缺失）
--   • 物理尺寸字段（weight/length/height/width）用于运费计算，可研究运费与尺寸关系
--   • name_lenght / description_lenght 为葡萄牙语原文拼写，保留不做纠正
-- ============================================================
CREATE TABLE products (
    product_id                  VARCHAR(32) PRIMARY KEY COMMENT '商品ID',
    product_category_name       VARCHAR(50) COMMENT '品类名（葡萄牙语，可空）',
    product_name_lenght         INT COMMENT '商品名字符长度',
    product_description_lenght  INT COMMENT '商品描述字符长度',
    product_photos_qty          INT COMMENT '商品展示照片数量',
    product_weight_g            INT COMMENT '商品重量（克）',
    product_length_cm           INT COMMENT '商品长度（厘米）',
    product_height_cm           INT COMMENT '商品高度（厘米）',
    product_width_cm            INT COMMENT '商品宽度（厘米）',

    CONSTRAINT fk_product_category
        FOREIGN KEY (product_category_name)
        REFERENCES product_category_translation(product_category_name)
        ON DELETE SET NULL,
    INDEX idx_product_category (product_category_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='商品信息表（32,951种）';

-- ============================================================
-- 【表 5】orders — 订单主表
--
-- 设计意图：
--   • order_status 使用 ENUM 而非 VARCHAR，节省空间并防止非法值
--   • 5 个时间戳完整记录订单生命周期：下单→审核→交运→送达→预计
--   • 审核/交运/送达三字段可为 NULL，因为非所有订单走完全流程
--   • 主键在创建表时就分配，storeid 到写入时才生成
-- ============================================================
CREATE TABLE orders (
    order_id                    VARCHAR(32) PRIMARY KEY COMMENT '订单ID',
    customer_id                 VARCHAR(32) NOT NULL COMMENT '下单客户ID',
    order_status                ENUM('delivered', 'shipped', 'canceled', 'unavailable', 'invoiced', 'processing', 'created', 'approved')
                                NOT NULL DEFAULT 'created' COMMENT '订单当前状态',
    order_purchase_timestamp        DATETIME NOT NULL COMMENT '客户下单时间',
    order_approved_at               DATETIME COMMENT '平台审核通过时间（可空）',
    order_delivered_carrier_date    DATETIME COMMENT '交给承运商时间（可空）',
    order_delivered_customer_date   DATETIME COMMENT '客户签收时间（可空）',
    order_estimated_delivery_date   DATETIME NOT NULL COMMENT '预计送达日期',

    CONSTRAINT fk_order_customer
        FOREIGN KEY (customer_id)
        REFERENCES customers(customer_id)
        ON DELETE RESTRICT,
    INDEX idx_order_status (order_status),
    INDEX idx_order_purchase_ts (order_purchase_timestamp) COMMENT '时间范围查询加速',
    INDEX idx_order_customer (customer_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='订单主表（96,096条）';

-- ============================================================
-- 【表 6】order_items — 订单明细表
--
-- 设计意图：
--   • 复合主键 (order_id, order_item_id)，一个订单可包含多个商品项
--   • 外键同时关联 orders / products / sellers，形成核心业务三角
--   • price 和 freight_value 分开存储，方便分析运费对总价影响
--   • CHECK 约束保证价格和运费非负
-- ============================================================
CREATE TABLE order_items (
    order_id            VARCHAR(32) NOT NULL COMMENT '所属订单ID',
    order_item_id       INT NOT NULL COMMENT '订单内项次（从1开始）',
    product_id          VARCHAR(32) NOT NULL COMMENT '购买商品ID',
    seller_id           VARCHAR(32) NOT NULL COMMENT '销售卖家ID',
    shipping_limit_date DATETIME NOT NULL COMMENT '卖家发货截止时间',
    price               DECIMAL(10,2) NOT NULL COMMENT '商品单价（BRL）',
    freight_value       DECIMAL(10,2) NOT NULL COMMENT '运费（BRL）',

    PRIMARY KEY (order_id, order_item_id),
    CONSTRAINT fk_oi_order
        FOREIGN KEY (order_id)
        REFERENCES orders(order_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_oi_product
        FOREIGN KEY (product_id)
        REFERENCES products(product_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_oi_seller
        FOREIGN KEY (seller_id)
        REFERENCES sellers(seller_id)
        ON DELETE RESTRICT,
    CONSTRAINT chk_price_non_negative CHECK (price >= 0),
    CONSTRAINT chk_freight_non_negative CHECK (freight_value >= 0),
    INDEX idx_oi_product (product_id) COMMENT '商品销售数据分析',
    INDEX idx_oi_seller (seller_id) COMMENT '卖家销售数据分析'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='订单明细表（108,578条）';

-- ============================================================
-- 【表 7】order_payments — 支付信息表
--
-- 设计意图：
--   • 复合主键 (order_id, payment_sequential)，支持一单多笔支付
--   • payment_installments 字段体现巴西特色——分期付款极为普遍
--   • payment_type 不设 ENUM 限制，保留对未知支付方式的兼容性
-- ============================================================
CREATE TABLE order_payments (
    order_id                VARCHAR(32) NOT NULL COMMENT '所属订单ID',
    payment_sequential      INT NOT NULL COMMENT '支付顺序号（一单可分多次收款）',
    payment_type            VARCHAR(20) NOT NULL COMMENT '支付方式（credit_card/boleto/voucher/debit_card）',
    payment_installments    INT NOT NULL DEFAULT 1 COMMENT '分期数（信用卡常见3-12期）',
    payment_value           DECIMAL(10,2) NOT NULL COMMENT '该笔支付金额（BRL）',

    PRIMARY KEY (order_id, payment_sequential),
    CONSTRAINT chk_payment_value CHECK (payment_value >= 0),
    CONSTRAINT chk_installments CHECK (payment_installments >= 1),
    INDEX idx_payment_type (payment_type) COMMENT '支付偏好分析'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='订单支付信息表（103,884条支付记录）';

-- ============================================================
-- 【表 8】order_reviews — 评价信息表
--
-- 设计意图：
--   • review_score 使用 CHECK(1-5) + TINYINT，1byte 存储，查询效率最高
--   • 标题/内容字段允许为空（很多用户只打分不写文字）
--   • review_answer_timestamp 记录商家回复时间，可分析响应速度
--   • 与 orders 一对多：一个订单可包含多个评价（但通常只有一个）
-- ============================================================
CREATE TABLE order_reviews (
    review_id               VARCHAR(32) PRIMARY KEY COMMENT '评价唯一ID',
    order_id                VARCHAR(32) NOT NULL COMMENT '被评价订单ID',
    review_score            TINYINT NOT NULL COMMENT '用户评分（1=最差, 5=最好）',
    review_comment_title    VARCHAR(255) COMMENT '评价标题（可空）',
    review_comment_message  TEXT COMMENT '评价详细内容（可空）',
    review_creation_date    DATETIME NOT NULL COMMENT '评价创建时间',
    review_answer_timestamp DATETIME COMMENT '商家回复时间（可空）',

    CONSTRAINT fk_review_order
        FOREIGN KEY (order_id)
        REFERENCES orders(order_id)
        ON DELETE CASCADE,
    CONSTRAINT chk_review_score CHECK (review_score BETWEEN 1 AND 5),
    INDEX idx_review_order (order_id),
    INDEX idx_review_score (review_score) COMMENT '评价分数分布分析'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='订单评价表（95,668条）';

-- ============================================================
-- 【表 9】geolocation — 巴西地理坐标表
--
-- 设计意图：
--   • 反规范化设计：每个地理坐标点同时冗余 city + state 字段，避免 JOIN
--   • 一个 zip 前缀可有多个坐标点（城市不同区域），因此无单列主键
--   • lat/lng 使用 DECIMAL(12,8) 精度约 1cm，满足物流和可视化需求
--   • 100 万行数据量较大，索引设计仅覆盖常见查询场景
-- ============================================================
CREATE TABLE geolocation (
    geolocation_zip_code_prefix VARCHAR(10) NOT NULL COMMENT '邮编前缀（前5位）',
    geolocation_lat             DECIMAL(12,8) NOT NULL COMMENT '纬度（-34 到 +5）',
    geolocation_lng             DECIMAL(12,8) NOT NULL COMMENT '经度（-74 到 -35）',
    geolocation_city            VARCHAR(50) NOT NULL COMMENT '城市名',
    geolocation_state           CHAR(2) NOT NULL COMMENT '州缩写',

    INDEX idx_geo_zip (geolocation_zip_code_prefix) COMMENT '邮编→坐标查询',
    INDEX idx_geo_lat_lng (geolocation_lat, geolocation_lng) COMMENT '范围查询（如地图可视化）'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='巴西邮编地理坐标表（1,000,163条）';

-- ============================================================
-- 【表 10】inventory — 商品库存表（自建）
--
-- 设计意图：
--   • 与 products 一对一，通过外键严格关联
--   • stock_qty 存当前库存，safety_stock 存安全水位线阈值
--   • last_updated 自动维护（ON UPDATE CURRENT_TIMESTAMP），无需应用层显式管理
--   • 设计为独立表而非 products 中的字段：库存是运营数据，商品是主数据，职责分离
-- ============================================================
CREATE TABLE inventory (
    product_id      VARCHAR(32) PRIMARY KEY COMMENT '商品ID（与products一对一）',
    stock_qty       INT NOT NULL DEFAULT 100 COMMENT '当前库存数量（随机5%设为≤8用于触发器演示）',
    safety_stock    INT NOT NULL DEFAULT 20 COMMENT '安全库存阈值（低于此值触发预警）',
    last_updated    TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '库存最后更新时间',

    CONSTRAINT fk_inv_product
        FOREIGN KEY (product_id)
        REFERENCES products(product_id)
        ON DELETE CASCADE,
    CONSTRAINT chk_stock_non_negative CHECK (stock_qty >= 0),
    CONSTRAINT chk_safety_positive CHECK (safety_stock >= 0),
    INDEX idx_inv_stock (stock_qty) COMMENT '低库存商品快速定位'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='商品库存表（32,938条，自建数据）';

-- ============================================================
-- 【表 11】inventory_alert — 库存预警日志表（自建）
--
-- 设计意图：
--   • 不入为手动插入，由两个触发器自动生成：
--       ① trg_inventory_low_stock_alert（库存低于安全线）
--       ② trg_review_negative_alert（差评关联商品标记预警）
--   • alert_type 区分预警来源，方便后期按类型统计
--   • product_id 外键关联 products（CASCADE删除：商品下架后预警记录自动清除）
-- ============================================================
CREATE TABLE inventory_alert (
    alert_id        INT AUTO_INCREMENT PRIMARY KEY COMMENT '预警自增ID',
    product_id      VARCHAR(32) NOT NULL COMMENT '触发预警的商品ID',
    alert_type      VARCHAR(50) NOT NULL COMMENT '预警类型（LOW_STOCK / NEGATIVE_REVIEW）',
    alert_msg       VARCHAR(255) NOT NULL COMMENT '预警详细描述',
    is_resolved     TINYINT NOT NULL DEFAULT 0 COMMENT '是否已解决（0=未解决, 1=已解决）',
    resolved_at     TIMESTAMP NULL DEFAULT NULL COMMENT '预警解决时间',
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '预警生成时间',

    CONSTRAINT fk_alert_product
        FOREIGN KEY (product_id)
        REFERENCES products(product_id)
        ON DELETE CASCADE,
    INDEX idx_alert_created (created_at) COMMENT '按时间回溯预警历史',
    INDEX idx_alert_resolved (is_resolved) COMMENT '快速筛选未解决预警'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='库存预警日志表（触发器自动填充）';

-- ============================================================
-- 【表 12】inventory_log — 库存变更审计日志表（自建）
--
-- 设计意图：
--   • 记录每一次库存数量变更的完整上下文（旧值→新值、变更原因、关联单据）
--   • 支持库存追溯审计、运营对账、异常排查
--   • change_type 区分变更来源：ORDER(下单扣减)、RESTOCK(补货)、
--     ADJUST(盘点调整)、RETURN(退货入库)、INIT(初始入库)
--   • reference_id 关联订单ID或操作批次号，实现端到端追踪
-- ============================================================
CREATE TABLE inventory_log (
    log_id          INT AUTO_INCREMENT PRIMARY KEY COMMENT '日志自增ID',
    product_id      VARCHAR(32) NOT NULL COMMENT '变更库存的商品ID',
    change_qty      INT NOT NULL COMMENT '变更数量（正数=入库/补货，负数=出库/扣减）',
    old_stock       INT NOT NULL COMMENT '变更前库存',
    new_stock       INT NOT NULL COMMENT '变更后库存',
    change_type     ENUM('ORDER','RESTOCK','ADJUST','RETURN','INIT') NOT NULL COMMENT '变更类型',
    reference_id    VARCHAR(32) COMMENT '关联订单ID或操作批次号',
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT '变更时间',

    CONSTRAINT fk_log_product
        FOREIGN KEY (product_id)
        REFERENCES products(product_id)
        ON DELETE CASCADE,
    INDEX idx_log_product (product_id) COMMENT '按商品追溯库存历史',
    INDEX idx_log_created (created_at) COMMENT '按时间范围查询',
    INDEX idx_log_type (change_type) COMMENT '按变更类型统计'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='库存变更审计日志表（触发器自动记录）';

-- ============================================================
-- 建表完成：12 张表，23 个约束，20 个索引
-- 下一脚本：sql/03_load_data.sql（数据导入 + 库存生成）
-- ============================================================