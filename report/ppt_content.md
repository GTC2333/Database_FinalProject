# 数据库期末项目 —— Olist 巴西电商运营管理系统

> **一条主线**：从原始 CSV 到完整的数据平台 —— 我们不只是把数据"放进去"，而是通过规范化的数据库设计、自动化的业务规则引擎、以及数据驱动的智能推荐，构建了一个真正"可用"的电商运营系统。

---

## 封面

**标题**：Olist 巴西电商运营管理系统 —— 从数据存储到智能推荐的完整数据库实践

**副标题**：基于 MySQL 8.0 的 12 张表、10 个视图、5 个触发器、8 个存储过程、16 个分析查询

**课程**：数据库系统期末项目

---

## 第一部分：项目概述（Why）

### 1.1 为什么选择 Olist 数据集

Olist 是巴西最大电商聚合平台之一，其数据集是**少有的原生多表关系型数据集**：

- **9 张业务表** + **3 张自建表** = 12 张表，覆盖用户→订单→商品→支付→评价→地理→库存的全链路
- **~10 万订单**，规模适中：足够展示性能优化，又不会过大导致导入耗时
- **真实商业数据**：保留脏数据、缺失值、异常值，贴近生产环境
- **丰富分析维度**：2 年时间跨度、巴西 27 个州、71 个品类、5 种支付方式

### 1.2 本项目的技术全景

| 层级 | 内容 | 对应评分项 |
|------|------|-----------|
| **基础层** | 建库建表、字段定义、数据类型选择 | 建库建表 |
| **约束层** | PK/FK/CHECK/ENUM/NOT NULL/UNIQUE/DEFAULT | 完整性约束 |
| **操作层** | LOAD DATA / INSERT / 子查询 / 多表 JOIN | 基础操作 |
| **进阶层** | 视图 / 存储过程 / 触发器 / 事务 / 函数 / 索引 | 进阶技术 |
| **分析层** | 16 个业务分析查询 + 11 张可视化图表 | 数据分析 |
| **应用层** | 基于数据库的关联推荐与库存预警系统 | 数据库驱动业务 |

> **核心亮点**：我们不只是"建了一个数据库"，而是构建了一个**完整的电商运营数据平台** —— 从数据导入、业务规则自动化，到数据驱动的智能推荐。

---

## 第二部分：数据库设计（How —— 基础层）

### 2.1 ER 图与实体关系

12 张表的核心关系：

```
customers ──1:N──→ orders ──1:N──→ order_items ──N:1──→ products ──N:1──→ category_translation
                    │            │                    │
                    │            └──1:N──→ order_payments    └──1:1──→ inventory
                    │            │
                    └──1:N──→ order_reviews

sellers ──1:N──→ order_items
geolocation（独立，通过 zip 关联）
inventory_alert / inventory_log（触发器自动生成）
```

### 2.2 关键设计决策

| 决策 | 说明 |
|------|------|
| **第三范式 + 适度反规范化** | geolocation 冗余 city/state，避免频繁 JOIN |
| **职责分离** | inventory 独立于 products，库存是运营数据，商品是主数据 |
| **ENUM 约束订单状态** | 8 种固定状态，节省空间并防止非法值 |
| **DECIMAL 存金额** | 禁止 FLOAT 浮点误差 |
| **InnoDB 统一引擎** | 支持事务、外键、行级锁、崩溃恢复 |

### 2.3 建表示例：订单主表

```sql
CREATE TABLE orders (
    order_id                    VARCHAR(32) PRIMARY KEY,
    customer_id                 VARCHAR(32) NOT NULL,
    order_status                ENUM('delivered', 'shipped', 'canceled',
                                     'unavailable', 'invoiced', 'processing',
                                     'created', 'approved')
                                NOT NULL DEFAULT 'created',
    order_purchase_timestamp        DATETIME NOT NULL,
    order_approved_at               DATETIME,
    order_delivered_carrier_date    DATETIME,
    order_delivered_customer_date   DATETIME,
    order_estimated_delivery_date   DATETIME NOT NULL,

    CONSTRAINT fk_order_customer
        FOREIGN KEY (customer_id)
        REFERENCES customers(customer_id)
        ON DELETE RESTRICT,
    INDEX idx_order_status (order_status),
    INDEX idx_order_purchase_ts (order_purchase_timestamp)
) ENGINE=InnoDB;
```

> **设计亮点**：5 个时间戳完整记录订单生命周期，可计算审核延迟、承运耗时、物流偏差。

---

## 第三部分：数据导入（How —— 操作层）

### 3.1 导入策略：按外键依赖拓扑排序

```
第 0 批（零依赖）:  category_translation, customers, sellers, geolocation
第 1 批（轻度依赖）: products
第 2 批（核心依赖）: orders
第 3 批（明细依赖）: order_items, order_payments, order_reviews
第 4 批（自建表）:   inventory（随机生成库存）
```

### 3.2 核心导入代码：LOAD DATA + 空值处理

```sql
-- 商品表导入：品类名为空字符串 → 映射为 NULL
LOAD DATA LOCAL INFILE '.../olist_products_dataset.csv'
INTO TABLE products
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
IGNORE 1 ROWS
(@pid, @cat, @name_len, @desc_len, @photos, @weight, @length, @height, @width)
SET
    product_id = @pid,
    product_category_name = NULLIF(TRIM(@cat), ''),  -- 空值处理
    product_name_lenght = NULLIF(@name_len, ''),
    ...;

-- 库存随机生成：5% 商品设为低库存（1-8件），触发器演示用
INSERT INTO inventory (product_id, stock_qty, safety_stock)
SELECT
    product_id,
    CASE WHEN RAND() < 0.05 THEN FLOOR(RAND() * 8 + 1)
         ELSE FLOOR(RAND() * 450 + 50) END,
    FLOOR(RAND() * 40 + 10)
FROM products;
```

### 3.3 导入结果

| 表名 | 行数 | 耗时 |
|------|------|------|
| geolocation | 1,000,163 | ~60s |
| customers | 99,441 | ~30s |
| orders | 99,441 | ~10s |
| order_items | 112,650 | ~15s |
| order_payments | 103,886 | ~10s |
| order_reviews | 104,720 | ~15s |
| **总计** | **~150 万** | **~2 分钟** |

---

## 第四部分：完整性约束体系（How —— 约束层）

### 4.1 三层完整性

| 类型 | 实现 | 数量 |
|------|------|------|
| **实体完整性** | PRIMARY KEY / UNIQUE / AUTO_INCREMENT | 12 张表 |
| **参照完整性** | FOREIGN KEY + 级联策略 | 9 条外键 |
| **用户定义完整性** | CHECK / ENUM / NOT NULL / DEFAULT | 7 CHECK + 1 ENUM + 40+ NOT NULL |

### 4.2 外键级联策略设计

| 父表 → 子表 | 删除策略 | 业务理由 |
|-------------|---------|---------|
| customers → orders | **RESTRICT** | 有历史订单的客户不可删（审计需求）|
| orders → order_items | **CASCADE** | 订单删除时明细无意义，自动清理 |
| products → order_items | **RESTRICT** | 有销售记录的商品不可删 |
| category_translation → products | **SET NULL** | 删除翻译时产品保持，品类置空 |

### 4.3 CHECK 约束示例

```sql
-- 评价评分只能 1-5 分
ALTER TABLE order_reviews
    ADD CONSTRAINT chk_review_score CHECK (review_score BETWEEN 1 AND 5);

-- 金额必须非负
ALTER TABLE order_items
    ADD CONSTRAINT chk_price_non_negative CHECK (price >= 0);
```

---

## 第五部分：进阶技术 —— 让数据库"活"起来（How —— 进阶层）

### 5.1 视图：10 个业务视角

| 视图 | 技术点 | 业务价值 |
|------|--------|---------|
| `v_order_full` | 4 表 JOIN + 聚合 | 订单全貌一键查询 |
| `v_customer_rfm` | **CTE + NTILE(5)** | 客户价值 125 分层 |
| `v_product_recommendation` | **自连接 + 关联规则** | 买了 A 的人也买了 B |
| `v_inventory_turnover` | JOIN + 比率计算 | 库存周转率分析 |

### 5.2 触发器：5 个自动化业务规则

**核心链路 —— 一次下单，三张表联动**：

```
用户下单 → INSERT order_items
  → 【触发器1】trg_order_item_deduct_stock（BEFORE INSERT）
    → 检查库存 → 扣减 1 件 → 不足则 SIGNAL 报错
      → 库存表 UPDATE
        → 【触发器2】trg_inventory_low_stock_alert（AFTER UPDATE）
          → stock ≤ safety → 自动写入 inventory_alert 预警表
```

```sql
-- 触发器1：下单时自动扣减库存
CREATE TRIGGER trg_order_item_deduct_stock
BEFORE INSERT ON order_items
FOR EACH ROW
BEGIN
    DECLARE v_current_stock INT;
    SELECT stock_qty INTO v_current_stock
    FROM inventory WHERE product_id = NEW.product_id FOR UPDATE;
    IF v_current_stock < 1 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: Insufficient stock';
    END IF;
    UPDATE inventory SET stock_qty = stock_qty - 1
    WHERE product_id = NEW.product_id;
END;

-- 触发器2：库存低于安全线时自动预警
CREATE TRIGGER trg_inventory_low_stock_alert
AFTER UPDATE ON inventory
FOR EACH ROW
BEGIN
    IF NEW.stock_qty <= NEW.safety_stock
       AND OLD.stock_qty > NEW.safety_stock THEN
        INSERT INTO inventory_alert (product_id, alert_type, alert_msg)
        VALUES (NEW.product_id, 'LOW_STOCK',
                CONCAT('Stock dropped to ', NEW.stock_qty));
    END IF;
END;
```

### 5.3 存储过程与事务：下单的原子性保证

```sql
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
        ROLLBACK;       -- 任一失败自动回滚
        RESIGNAL;
    END;

    START TRANSACTION;
    SET p_new_order_id = MD5(UUID());
    INSERT INTO orders (...) VALUES (...);
    INSERT INTO order_items (...) VALUES (...);  -- 触发器自动扣库存
    COMMIT;
END;
```

> **事务价值**：订单和明细要么同时成功，要么同时失败。库存不足时触发器抛错 → EXIT HANDLER 捕获 → 自动 ROLLBACK，保证数据一致性。

### 5.4 索引优化：从 11 个索引到查询加速

| 索引 | 场景 | 效果 |
|------|------|------|
| `idx_order_status_time` (复合) | `WHERE status='delivered' AND ts BETWEEN ...` | 避免回表 |
| `idx_oi_product_seller` (复合) | 商品-卖家交叉分析 | 覆盖索引查询 |
| `idx_inv_stock` | 低库存预警 | 快速定位 |

---

## 第六部分：数据分析 —— 数据告诉我们什么（What）

### 6.1 月度销售趋势：Black Friday 效应

```sql
SELECT DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS month,
       COUNT(DISTINCT order_id) AS total_orders,
       ROUND(SUM(total_amount), 2) AS total_revenue
FROM v_order_full
WHERE order_status = 'delivered'
GROUP BY month ORDER BY month;
```

| month | total_orders | total_revenue |
|-------|-------------|---------------|
| 2017-10 | 4,302 | 728,508.75 |
| **2017-11** | **7,060** | **1,121,888.39** ⬆️ |
| 2017-12 | 5,339 | 818,136.01 |
| 2018-01 | 6,834 | 1,043,798.22 |

> **发现**：2017-11 为峰值（7,060 单 / 112 万 BRL），与巴西黑色星期五促销高度吻合。

### 6.2 地理分布：高度集中的市场

| state | order_count | total_revenue | avg_order_value |
|-------|-------------|---------------|-----------------|
| SP | 39,103 | 5,589,933.71 | 142.99 |
| RJ | 11,900 | 1,988,478.39 | 167.13 |
| MG | 10,989 | 1,767,110.66 | 160.85 |

> **发现**：SP（圣保罗）州独占 35% 收入，前 3 州占总收入 60%。

### 6.3 支付方式：巴西信贷文化

| payment_type | order_count | total_payment | avg_installments |
|--------------|-------------|---------------|------------------|
| credit_card | 76,503 (74.6%) | 12,541,895.56 | **3.5** |
| boleto | 19,784 (19.3%) | 2,869,361.27 | 1.0 |
| voucher | 3,866 (3.8%) | 379,436.87 | 1.0 |

> **发现**：信用卡占绝对主导，平均分期 3.5 期，体现巴西信贷文化。

### 6.4 评价与物流：强负相关

| review_score | review_count | pct | avg_shipping_days |
|--------------|--------------|-----|-------------------|
| 5 ⭐ | 54,957 | 59.1% | 10.6 |
| 4 ⭐ | 18,379 | 19.8% | 12.3 |
| 3 ⭐ | 7,696 | 8.3% | 14.2 |
| 2 ⭐ | 2,832 | 3.0% | 16.6 |
| 1 ⭐ | 9,077 | 9.8% | **21.3** |

> **发现**：物流天数与评分呈强负相关。5 星订单平均 10.6 天，1 星订单平均 21.3 天（延迟 1 倍）。

---

## 第七部分：数据库驱动的推荐系统（Why 数据库完善性）

> **这一部分是整份报告的核心升华** —— 我们不只是在"分析历史数据"，而是在数据库内部构建了一个**实时可用的推荐引擎**，体现了数据库设计的完善性。

### 7.1 关联规则：买了 A 的人也买了 B

```sql
CREATE OR REPLACE VIEW v_product_recommendation AS
WITH total_orders AS (
    SELECT COUNT(DISTINCT order_id) AS total FROM order_items
),
product_orders AS (
    SELECT product_id, COUNT(DISTINCT order_id) AS order_count
    FROM order_items GROUP BY product_id
)
SELECT
    a.product_id AS product_a,
    b.product_id AS product_b,
    COUNT(DISTINCT a.order_id) AS co_purchase_count,
    ROUND(COUNT(DISTINCT a.order_id) * 100.0 / pa.order_count, 2) AS confidence_pct,
    ROUND(
        (COUNT(DISTINCT a.order_id) * 1.0 / pa.order_count)
        / (pb.order_count * 1.0 / t.total),
        4
    ) AS lift
FROM order_items a
JOIN order_items b ON a.order_id = b.order_id AND a.product_id < b.product_id
JOIN product_orders pa ON a.product_id = pa.product_id
JOIN product_orders pb ON b.product_id = pb.product_id
CROSS JOIN total_orders t
GROUP BY a.product_id, b.product_id, pa.order_count, pb.order_count, t.total
HAVING co_purchase_count >= 5
ORDER BY lift DESC;
```

**执行结果 TOP 5**：

| product_a | product_b | co_purchase_count | confidence_pct | lift |
|-----------|-----------|-------------------|----------------|------|
| ad4b5def... | e6b314a2... | 6 | 75.00% | **8,333.33** |
| 3ce94399... | b7d94dc0... | 5 | 71.43% | **7,936.51** |
| 94634469... | ad0a798e... | 6 | 40.00% | 3,333.33 |

> **业务含义**：Lift = 8,333 意味着"买了 A 的人买 B 的概率"是"随机买 B 的概率"的 **8,333 倍**，说明这是极强的搭配关系（computers_accessories 品类内配件搭配）。

### 7.2 为什么推荐系统体现数据库完善性？

| 数据库特性 | 对推荐系统的支撑 |
|-----------|-----------------|
| **视图 (v_product_recommendation)** | 将复杂关联规则封装为虚拟表，业务层直接 `SELECT * FROM v_product_recommendation` |
| **存储过程 (sp_get_product_recommendations)** | 输入商品 ID，返回 TOP N 推荐，参数化调用 |
| **库存感知推荐 (v_instock_recommendation)** | JOIN inventory 表，只推荐有库存的商品，避免推荐断货商品 |
| **评分过滤推荐 (v_review_weighted_recommendation)** | JOIN order_reviews，过滤掉差评商品（avg_score < 3），保证推荐质量 |
| **触发器自动化** | 库存变动自动预警、差评自动标记，保证推荐数据源的质量 |

> **核心观点**：如果没有触发器保证库存数据实时准确、没有视图封装复杂查询、没有存储过程提供标准接口，推荐系统就只是一堆离线脚本。正是**数据库的完善设计**，让推荐成为了一个**可实时查询、可参数化调用、与业务数据联动**的生产级功能。

### 7.3 品类交叉销售分析

```sql
SELECT category_a, category_b, co_purchase_count, pct_of_category_a
FROM v_category_cross_sell
ORDER BY co_purchase_count DESC LIMIT 5;
```

| category_a | category_b | co_purchase_count | pct_of_category_a |
|------------|------------|-------------------|-------------------|
| furniture_decor | bed_bath_table | 61 | 31.77% |
| bed_bath_table | furniture_decor | 61 | 32.97% |
| bed_bath_table | home_confort | 42 | 22.70% |

> **运营策略**：家具装饰与床上用品是最强交叉销售组合。可在商品详情页设置"搭配购买"模块。

---

## 第八部分：库存管理与预警系统（数据库自动化运维）

### 8.1 库存健康度总览

| stock_status | product_count | pct |
|--------------|---------------|-----|
| Healthy | 30,131 | 91.5% |
| Low Stock | 1,678 | 5.1% |
| Warning | 1,129 | 3.4% |

### 8.2 库存周转最快 TOP 5

| product_id | category | current_stock | total_units_sold | turnover_ratio |
|------------|----------|---------------|------------------|----------------|
| 11875b30... | sports_leisure | 1 | 63 | **63.0x** |
| e0cf7976... | health_beauty | 3 | 136 | **45.3x** |
| 5d6bea33... | furniture_decor | 1 | 44 | **44.0x** |

> **发现**：周转率 63x 意味着历史销量是当前库存的 63 倍，需高度关注补货。

### 8.3 自动化运维闭环

```
下单 → 触发器扣库存 → 库存低于安全线 → 自动预警
   ↓                                      ↓
补货 ← 存储过程 sp_restock_product ← 人工/系统响应
   ↓
触发器自动标记预警为"已解决"
```

> **价值**：无需人工巡检库存，数据库自动完成"扣减→预警→补货→解决"的全流程。

---

## 第九部分：总结与反思

### 9.1 项目成果

| 维度 | 成果 |
|------|------|
| **数据规模** | 12 张表，~150 万行数据，130MB |
| **约束体系** | 9 外键 + 7 CHECK + 1 ENUM + 40+ NOT NULL |
| **进阶技术** | 10 视图 + 2 函数 + 5 触发器 + 8 存储过程 + 11 索引 |
| **分析查询** | 16 个业务分析，覆盖销售/地理/品类/支付/物流/RFM/评价/推荐/库存 |
| **可复现性** | 5 个 SQL 脚本按顺序执行，2 分钟完成全量部署 |

### 9.2 核心收获

1. **数据库不只是"存数据"**：通过触发器和存储过程，数据库可以成为业务规则引擎
2. **索引是性能的灵魂**：复合索引让"状态+时间"查询从全表扫描变为索引覆盖
3. **数据质量决定分析上限**：空值处理、CHECK 约束、触发器预警，保证了分析结果的可靠性
4. **数据库设计支撑业务创新**：正是完善的表结构、视图和存储过程，让"关联推荐"从想法变成了可执行的 SQL

### 9.3 后续可扩展方向

| 方向 | 实现思路 |
|------|---------|
| **实时库存监控大屏** | 基于 v_inventory_status 的定时刷新仪表盘 |
| **个性化推荐 API** | 将 sp_get_customer_recommendations 封装为 REST API |
| **预测性补货** | 基于 v_inventory_turnover 的历史周转率，预测未来 7 天库存需求 |
| **物流时效优化** | 基于 fn_shipping_days 和各州平均时效，优化配送路线规划 |

---

## 附录：快速验证

```bash
# 一键部署（约 2 分钟）
cd "/Users/gtc/Learning/数据库/finalproject"
./run_all.sh

# 验证数据
mysql -u root -p olist_db -e "
SELECT 'customers' AS tbl, COUNT(*) AS cnt FROM customers
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'inventory', COUNT(*) FROM inventory;"

# 生成图表
python3 generate_charts.py
```

---

> **报告版本**: v3.0 — PPT 专用精简版  
> **生成日期**: 2026-06-04  
> **总页数建议**: 15-20 页 PPT
