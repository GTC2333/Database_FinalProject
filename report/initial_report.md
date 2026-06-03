# 数据库期末项目 —— 技术报告

> **项目**: 巴西电商 Olist 运营管理系统  
> **技术栈**: MySQL 8.0.35  
> **数据规模**: 约 10 万订单，12 张数据表，1,000,163 条地理坐标  
> **核心模块**: DDL/DML/约束/视图/存储过程/触发器/事务/索引/函数/数据分析/可视化
> **报告版本**: v2.0 — 含完整数据库设计说明

---

## 一、项目背景与实际意义

### 1.1 电商与数据库

电子商务是数据库技术最密集的应用场景之一。一个典型的电商平台需要同时管理：

- **用户体系**：注册、登录、地址、偏好
- **商品体系**：SKU、品类、库存、上下架
- **交易体系**：订单、支付、退款、分期
- **物流体系**：发货、追踪、签收、时效
- **评价体系**：评分、评论、商家回复
- **分析体系**：销售趋势、用户画像、推荐算法

这些子系统之间的数据流转形成了复杂的关系网络：一个用户下多个订单、一个订单包含多个商品、一个商品被多个卖家销售、一笔支付可能分期多次执行。这正是关系数据库的用武之地。

### 1.2 为什么选择 Olist 数据集

Olist 是巴西最大的电商聚合平台之一，其公开数据集是少有的**原生多表关系型**数据集：

- **9 张业务表**，完整覆盖用户→订单→商品→支付→评价→地理的全链路
- **~10 万订单**，规模适中：对教学足够大以展示性能优化，又不会过大导致导入耗时
- **真实商业数据**：保留脏数据、缺失值、异常值，贴近生产环境
- **丰富分析维度**：2 年时间跨度、巴西 27 个州、71 个品类、5 种支付方式
- **Kaggle 公开许可**：CC-BY-NC-SA-4.0，可用于教学

### 1.3 本项目实现的全链路

```
用户注册 → 浏览商品 → 加入购物车(模拟) → 下单 → 扣库存(模拟)
    → 支付(分期/单次) → 发货 → 物流追踪 → 签收 → 评价
    → 商家回复 → 数据分析 → 客户分群 → 商品推荐
```

### 1.4 本项目的技术目标

| 目标层级 | 具体内容 | 对应评分项 |
|---------|---------|-----------|
| **基础层** | 建库建表、字段定义、数据类型选择 | 建库建表 |
| **约束层** | PK/FK/CHECK/ENUM/NOT NULL/UNIQUE/DEFAULT | 完整性约束 |
| **操作层** | INSERT/UPDATE/DELETE/SELECT/子查询/多表JOIN | 基础操作 |
| **进阶层** | 视图/存储过程/触发器/事务/函数/索引 | 进阶技术 |
| **分析层** | 10 个业务分析查询 + 11 张可视化图表 | 数据分析 |
| **工程层** | 可复现的 SQL 脚本、一键部署、Python 图表生成 | 代码可复现 |

---

## 二、数据库设计方法论

### 2.1 设计原则

本项目遵循以下数据库设计原则：

#### 规范化设计
- **第三范式（3NF）**：消除传递依赖。例如 `order_items` 中只存 `product_id` 和 `seller_id`，不冗余商品名和卖家名
- **适度反规范化**：`geolocation` 表在存经纬度的同时冗余 city 和 state 字段，避免每次地理查询都要 JOIN 其它表
- **职责分离**：`inventory` 独立于 `products`，库存是运营数据，商品是主数据，不应混在同一张表

#### 参照完整性
- **级联删除（CASCADE）**：订单取消时自动清理明细和评价
- **限制删除（RESTRICT）**：有订单记录的客户不允许删除
- **置空删除（SET NULL）**：品类翻译删除后不影响已有的商品记录

#### 类型选择原则
| 场景 | 选型 | 理由 |
|------|------|------|
| 哈希 ID | VARCHAR(32) | 源数据为 32 位 hex 字符串 |
| 货币金额 | DECIMAL(10,2) | 精确小数，禁止 FLOAT 浮点误差 |
| 地理坐标 | DECIMAL(12,8) | 约 1cm 精度，支持空间计算 |
| 订单状态 | ENUM | 8 个固定状态，节省空间并防止非法值 |
| 评分 | TINYINT + CHECK | 1byte 存储，CHECK(1-5) 约束范围 |
| 长文本 | TEXT | 评论内容不定长，最大 64KB |
| 时间戳 | DATETIME | 不依赖时区，范围到 9999 年 |

### 2.2 字符集与排序规则

```
CHARACTER SET: utf8mb4 (MySQL 8 默认)
COLLATION:     utf8mb4_unicode_ci
```

**utf8mb4 而非 utf8**：MySQL 的 `utf8` 别名实际只支持 3 字节（无法存 emoji）。`utf8mb4` 是真正的 UTF-8 完整实现。虽然本项目主要为拉美数据（拉丁字符），但使用 utf8mb4 体现数据库基本功。

**utf8mb4_unicode_ci 而非 utf8mb4_general_ci**：`unicode_ci` 基于 Unicode 官方排序算法，处理多语言排序更准确。

### 2.3 存储引擎选择

所有 11 张表统一使用 **InnoDB**：

| 特性 | InnoDB | MyISAM |
|------|--------|--------|
| 事务支持 | ✅ ACID | ❌ |
| 外键约束 | ✅ | ❌ |
| 行级锁 | ✅ | ❌（表锁）|
| 崩溃恢复 | ✅ | ❌ |
| 全文索引 | ❌（MySQL 5.6+ 支持）| ✅ |

本项目需要事务（下单扣库存）、外键（11 张表的关联）、行级锁（触发器并发），InnoDB 是唯一选择。

---

## 三、ER 图与实体关系设计

### 3.1 ER 图（文字版）

```
                        ┌─────────────────────┐
                        │  customers          │  ← 客户实体
                        │  customer_id (PK)   │
                        │  customer_unique_id │
                        │  zip / city / state │
                        └──────────┬──────────┘
                                   │ 1
                                   │
                                   │ N
                        ┌──────────▼──────────┐
┌───────────────────┐  │  orders             │  ← 订单实体
│  sellers          │  │  order_id (PK)      │
│  seller_id (PK)   │  │  customer_id (FK)   │
│  zip / city/state │  │  order_status (ENUM)│
└─────────┬─────────┘  │  5× 时间戳字段       │
          │             └──┬───────┬───────┬──┘
          │                │ 1     │ 1     │ 1
          │                │       │       │
          │ N              │ N     │ N     │ N
┌─────────▼──────────┐    ┌▼───────▼┐ ┌───▼──────────────┐
│  order_items       │    │payments │ │ order_reviews    │  ← 关联实体
│  (order_id, item_id│    │(oid,seq)│ │ review_id (PK)   │
│   product_id (FK)  │    │type     │ │ order_id (FK)    │
│   seller_id (FK)   │    │install  │ │ score (1-5)      │
│   price / freight  │    │value    │ │ comment / answer  │
└─────────┬──────────┘    └─────────┘ └──────────────────┘
          │ N
          │
          │ 1
┌─────────▼──────────┐    ┌──────────────────────┐
│  products          │    │ product_category_    │
│  product_id (PK)   │◄───│ translation          │  ← 字典表
│  category_name(FK) │ N:1│ category_name (PK)   │
│  weight / dim      │    │ category_name_en     │
└─────────┬──────────┘    └──────────────────────┘
          │ 1
          │
          │ 1
┌─────────▼──────────┐
│  inventory (自建)   │  ← 运营数据
│  product_id (PK,FK)│
│  stock_qty         │
│  safety_stock      │
└────────────────────┘

┌──────────────────────┐
│  geolocation         │  ← 独立数据
│  zip_prefix / lat    │
│  lng / city / state  │
└──────────────────────┘

┌──────────────────────┐
│  inventory_alert(自建)│ ← 日志数据（触发器写入）
│  alert_id (PK)       │
│  product_id (FK)     │
│  type / msg / time   │
└──────────────────────┘
```

### 3.2 核心关系详解

| # | 关系 | 基数 | 实现方式 | 业务含义 |
|----|------|------|---------|---------|
| 1 | Customers → Orders | 1:N | `orders.customer_id` FK | 一个客户可多次下单，每次生成新 order_id |
| 2 | Orders → Order_Items | 1:N | `order_items.order_id` FK | 一笔订单可购买多件商品 |
| 3 | Products → Order_Items | 1:N | `order_items.product_id` FK | 同一商品可出现在多个订单中 |
| 4 | Sellers → Order_Items | 1:N | `order_items.seller_id` FK | 同一卖家可成交多个订单项 |
| 5 | Orders → Payments | 1:N | `payments.order_id` FK | 一单可分多笔支付（如分期）|
| 6 | Orders → Reviews | 1:N | `reviews.order_id` FK | 一单可有多条评价（通常一条）|
| 7 | Products → Category | N:1 | `products.category` FK | 多商品属同一品类 |
| 8 | Products → Inventory | 1:1 | `inventory.product_id` PK+FK | 每商品有且仅有一条库存记录 |

### 3.3 外键删除策略

| 父表 | 子表 | 策略 | 理由 |
|------|------|------|------|
| customers | orders | RESTRICT | 有历史订单的客户不能删（审计需求）|
| orders | order_items | CASCADE | 订单删除时明细无意义 |
| orders | order_payments | CASCADE | 同上 |
| orders | order_reviews | CASCADE | 同上 |
| products | order_items | RESTRICT | 有销售记录的商品不能删 |
| products | inventory | CASCADE | 商品下架后库存记录随之清除 |
| products | inventory_alert | CASCADE | 商品下架后预警记录随之清除 |
| category_translation | products | SET NULL | 删除品类翻译时产品保持，品类字段置 NULL |

---

## 四、数据表结构与字段设计

### 4.1 真实数据表（Olist 数据集，9 张）

以下展示每张表的字段设计、数据来源和处理逻辑。

#### 表 1：customers — 客户信息表

| 字段名 | 类型 | 约束 | 默认值 | 说明 |
|--------|------|------|--------|------|
| customer_id | VARCHAR(32) | **PRIMARY KEY** | — | 订单级客户标识（每次下单生成新 ID）|
| customer_unique_id | VARCHAR(32) | NOT NULL, **UNIQUE** | — | 真实自然人唯一标识（跨订单追踪）|
| customer_zip_code_prefix | VARCHAR(10) | NOT NULL | — | 邮编前 5 位，可 JOIN geolocation 获取坐标 |
| customer_city | VARCHAR(50) | NOT NULL | — | 城市名（含葡萄牙语特殊字符）|
| customer_state | CHAR(2) | NOT NULL | — | 州缩写，巴西全境统一 2 字符 |

**索引策略**：`customer_state` 索引支持按州分组查询；`customer_zip_code_prefix` 索引支持邮编地理关联。

**数据量**：96,096 条。源 CSV 99,441 行，导入后扣除外键不匹配的行。

#### 表 2：sellers — 卖家信息表

| 字段名 | 类型 | 约束 | 说明 |
|--------|------|------|------|
| seller_id | VARCHAR(32) | **PRIMARY KEY** | 卖家唯一标识 |
| seller_zip_code_prefix | VARCHAR(10) | NOT NULL | 邮编前缀 |
| seller_city | VARCHAR(50) | NOT NULL | 卖家所在城市 |
| seller_state | CHAR(2) | NOT NULL | 卖家所在州 |

**数据量**：3,095 家。卖家地域分布高度集中（SP 州占 60%+）。

#### 表 3：product_category_translation — 品类翻译表

| 字段名 | 类型 | 约束 | 说明 |
|--------|------|------|------|
| product_category_name | VARCHAR(50) | **PRIMARY KEY** | 葡萄牙语品类名（如 `beleza_saude`）|
| product_category_name_english | VARCHAR(50) | NOT NULL | 英语品类名（如 `health_beauty`）|

**设计意义**：Olist 是巴西公司，原始品类名均为葡萄牙语。此表使英文查询和分析成为可能，同时保留原文以兼容源数据。

**数据量**：71 个品类。

#### 表 4：products — 商品信息表

| 字段名 | 类型 | 约束 | 说明 |
|--------|------|------|------|
| product_id | VARCHAR(32) | **PRIMARY KEY** | 商品唯一 ID |
| product_category_name | VARCHAR(50) | FK → translation（可空）| 品类（约 2% 缺失）|
| product_name_lenght | INT | 可空 | 商品名长度（原数据拼写保留）|
| product_description_lenght | INT | 可空 | 描述长度 |
| product_photos_qty | INT | 可空 | 展示照片张数 |
| product_weight_g | INT | 可空 | 重量（克），用于运费估算 |
| product_length_cm | INT | 可空 | 长度（厘米）|
| product_height_cm | INT | 可空 | 高度（厘米）|
| product_width_cm | INT | 可空 | 宽度（厘米）|

**数据量**：32,951 种商品。约 2% 的商品品类名缺失（外键为 NULL）。

#### 表 5：orders — 订单主表

| 字段名 | 类型 | 约束 | 说明 |
|--------|------|------|------|
| order_id | VARCHAR(32) | **PRIMARY KEY** | 订单唯一 ID |
| customer_id | VARCHAR(32) | FK → customers, NOT NULL | 下单客户 |
| order_status | ENUM(8 种状态) | NOT NULL, DEFAULT 'created' | 订单生命周期状态 |
| order_purchase_timestamp | DATETIME | NOT NULL | 客户点击下单时间 |
| order_approved_at | DATETIME | 可空 | 平台审核通过时间 |
| order_delivered_carrier_date | DATETIME | 可空 | 交给物流承运商时间 |
| order_delivered_customer_date | DATETIME | 可空 | 客户实际签收时间 |
| order_estimated_delivery_date | DATETIME | NOT NULL | 系统预估送达日期 |

**设计亮点**：5 个时间戳完整记录订单生命周期，可计算审核延迟、承运耗时、物流偏差（实际 vs 预估）。

**ENUM 取值**：`delivered`, `shipped`, `canceled`, `unavailable`, `invoiced`, `processing`, `created`, `approved`

**复合索引**：`(order_status, order_purchase_timestamp)` 用于"已送达订单按时间筛选"这类高频查询。

**数据量**：96,096 条。

#### 表 6：order_items — 订单明细表

| 字段名 | 类型 | 约束 | 说明 |
|--------|------|------|------|
| order_id | VARCHAR(32) | **PK** 组成, FK → orders | 所属订单 |
| order_item_id | INT | **PK** 组成 | 订单内项次（从 1 计数）|
| product_id | VARCHAR(32) | FK → products | 购买商品 |
| seller_id | VARCHAR(32) | FK → sellers | 销售卖家 |
| shipping_limit_date | DATETIME | NOT NULL | 卖家发货截止 |
| price | DECIMAL(10,2) | NOT NULL, CHECK ≥0 | 商品单价 |
| freight_value | DECIMAL(10,2) | NOT NULL, CHECK ≥0 | 运费 |

**设计亮点**：price 和 freight_value 分开存储，可分析运费/货价比。

**复合索引**：`(product_id, seller_id)` 用于"某商品由哪些卖家销售"的复合查询。

**数据量**：108,578 条订单项。

#### 表 7：order_payments — 支付信息表

| 字段名 | 类型 | 约束 | 说明 |
|--------|------|------|------|
| order_id | VARCHAR(32) | **PK** 组成, FK → orders | 所属订单 |
| payment_sequential | INT | **PK** 组成 | 支付顺序号 |
| payment_type | VARCHAR(20) | NOT NULL | 支付方式 |
| payment_installments | INT | NOT NULL, CHECK ≥1 | 分期数 |
| payment_value | DECIMAL(10,2) | NOT NULL, CHECK ≥0 | 支付金额 |

**巴西特色**：信贷文化盛行，信用卡分 3-12 期极为普遍。payment_installments 字段即为此设计。

**数据量**：103,884 条支付记录。

#### 表 8：order_reviews — 评价信息表

| 字段名 | 类型 | 约束 | 说明 |
|--------|------|------|------|
| review_id | VARCHAR(32) | **PRIMARY KEY** | 评价唯一 ID |
| order_id | VARCHAR(32) | FK → orders, NOT NULL | 被评价订单 |
| review_score | TINYINT | NOT NULL, CHECK 1-5 | 评分（1=最差, 5=最好）|
| review_comment_title | VARCHAR(255) | 可空 | 评价标题 |
| review_comment_message | TEXT | 可空 | 评价详细内容 |
| review_creation_date | DATETIME | NOT NULL | 评价创建时间 |
| review_answer_timestamp | DATETIME | 可空 | 商家回复时间 |

**数据量**：95,668 条评价。

#### 表 9：geolocation — 地理坐标表

| 字段名 | 类型 | 约束 | 说明 |
|--------|------|------|------|
| geolocation_zip_code_prefix | VARCHAR(10) | INDEX | 邮编前缀（巴西格式 5 位）|
| geolocation_lat | DECIMAL(12,8) | NOT NULL | 纬度 |
| geolocation_lng | DECIMAL(12,8) | NOT NULL | 经度 |
| geolocation_city | VARCHAR(50) | NOT NULL | 城市名 |
| geolocation_state | CHAR(2) | NOT NULL | 州缩写 |

**设计说明**：反规范化存储——city 和 state 在每条里冗余，以避免与 customers 表的 JOIN。一个邮编前缀可能有多个坐标点（城市不同区域），因此无法以 zip 为主键。

**数据量**：1,000,163 条。

### 4.2 自建辅助表（2 张）

#### 表 10：inventory — 库存表

| 字段名 | 类型 | 约束 | 说明 |
|--------|------|------|------|
| product_id | VARCHAR(32) | **PK, FK** → products | 商品 ID（与 products 一对一）|
| stock_qty | INT | NOT NULL, CHECK ≥0, DEFAULT 100 | 当前库存量 |
| safety_stock | INT | NOT NULL, CHECK ≥0, DEFAULT 20 | 安全库存阈值 |
| last_updated | TIMESTAMP | DEFAULT/ON UPDATE CURRENT_TIMESTAMP | 最后更新时间 |

**生成方式**：基于 products 表，每个商品随机分配库存。95% 商品库存充足（50-500），5% 刻意设为 ≤8 件，以便演示触发器**库存扣减→低库存预警**的完整链路。

**索引**：`idx_inv_stock(stock_qty)` 支持低库存快速筛选。

**数据量**：32,938 条。

#### 表 11：inventory_alert — 库存预警日志表

| 字段名 | 类型 | 约束 | 说明 |
|--------|------|------|------|
| alert_id | INT | **PK, AUTO_INCREMENT** | 预警自增 ID |
| product_id | VARCHAR(32) | FK → products | 触发预警的商品 |
| alert_type | VARCHAR(50) | NOT NULL | 预警类型 |
| alert_msg | VARCHAR(255) | NOT NULL | 预警详细描述 |
| is_resolved | TINYINT | NOT NULL, DEFAULT 0 | 是否已解决 |
| resolved_at | TIMESTAMP | NULL | 解决时间 |
| created_at | TIMESTAMP | DEFAULT CURRENT_TIMESTAMP | 预警生成时间 |

**填充方式**：由触发器自动写入，无需手动 INSERT。支持两种类型：
- `LOW_STOCK`：库存更新后低于安全线
- `NEGATIVE_REVIEW`：评价分数 ≤2 时关联商品
- 补货后 `sp_restock_product` 自动将未解决预警标记为已解决

#### 表 12：inventory_log — 库存变更审计日志表

| 字段名 | 类型 | 约束 | 说明 |
|--------|------|------|------|
| log_id | INT | **PK, AUTO_INCREMENT** | 日志自增 ID |
| product_id | VARCHAR(32) | FK → products | 变更库存的商品 |
| change_qty | INT | NOT NULL | 变更数量（正=入库，负=出库） |
| old_stock | INT | NOT NULL | 变更前库存 |
| new_stock | INT | NOT NULL | 变更后库存 |
| change_type | ENUM | NOT NULL | 变更类型（ORDER/RESTOCK/ADJUST/RETURN/INIT） |
| reference_id | VARCHAR(32) | — | 关联订单ID或操作批次号 |
| created_at | TIMESTAMP | DEFAULT CURRENT_TIMESTAMP | 变更时间 |

**填充方式**：由触发器 `trg_inventory_log_insert` / `trg_inventory_log_update` 自动记录所有库存变更，实现完整审计追溯。

---

## 五、完整性约束体系

### 5.1 实体完整性（Entity Integrity）

| 约束类型 | 应用表 | 实现 |
|---------|--------|------|
| PRIMARY KEY | 所有 12 张表 | 单列或复合主键 |
| UNIQUE | customers | customer_unique_id 防止重复自然人 |
| AUTO_INCREMENT | inventory_alert | alert_id 自增，避免手动管理 |

### 5.2 参照完整性（Referential Integrity）

共 **9 条外键约束**，分布在 order_items（3 条）、orders（1 条）、order_reviews（1 条）、products（1 条）、inventory（1 条）、inventory_alert（1 条）、order_payments（1 条）。

| 子表 → 父表 | 删除策略 | 更新策略 | 说明 |
|-------------|---------|---------|------|
| orders → customers | RESTRICT | CASCADE | 有订单的客户不可删 |
| order_items → orders | CASCADE | CASCADE | 订单删除时明细随之删除 |
| order_items → products | RESTRICT | CASCADE | 有销售记录的商品不可删 |
| order_items → sellers | RESTRICT | CASCADE | 有销售记录的卖家不可删 |
| order_reviews → orders | CASCADE | CASCADE | 订单删除时评价随之删除 |
| order_payments → orders | CASCADE | CASCADE | 订单删除时支付记录随之删除 |
| products → category_translation | SET NULL | CASCADE | 翻译删除后品类字段置空 |
| inventory → products | CASCADE | CASCADE | 商品删除后库存记录随之删除 |
| inventory_alert → products | CASCADE | CASCADE | 商品删除后预警记录随之删除 |

### 5.3 用户定义完整性（User-Defined Integrity）

```
CHECK 约束：
  ├── review_score BETWEEN 1 AND 5     (order_reviews)
  ├── price >= 0                       (order_items)
  ├── freight_value >= 0               (order_items)
  ├── payment_value >= 0               (order_payments)
  ├── payment_installments >= 1        (order_payments)
  ├── stock_qty >= 0                   (inventory)
  └── safety_stock >= 0                (inventory)

ENUM 约束：
  └── order_status IN ('delivered','shipped','canceled','unavailable',
                       'invoiced','processing','created','approved')

NOT NULL 约束：
  └── 所有业务必填字段（共 40+ 个字段设置 NOT NULL）

DEFAULT 约束：
  ├── order_status DEFAULT 'created'
  ├── stock_qty DEFAULT 100
  ├── safety_stock DEFAULT 20
  ├── payment_installments DEFAULT 1
  └── last_updated DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
```

---

## 六、数据导入策略

### 6.1 导入方法选择

使用 `LOAD DATA LOCAL INFILE` 而非逐行 `INSERT`：

| 方法 | 100 万行耗时 | 优势 |
|------|------------|------|
| `LOAD DATA INFILE` | **~30 秒** | CSV 批量流式加载，跳过 SQL 解析 |
| `INSERT INTO ... VALUES ...` | ~30 分钟 | 兼容性好，但极慢 |
| `INSERT INTO ... SELECT ...` | ~3 分钟 | 适合表间拷贝 |

对于 geolocation 表 100 万行的场景，LOAD DATA 是唯一合理选择。

### 6.2 导入批次设计

```
第 0 批：零依赖表
  ├── product_category_translation  (71 行, <1s)
  ├── customers                     (99K 行, ~30s)
  ├── sellers                       (3K 行, <1s)
  └── geolocation                   (1,000K 行, ~60s)  ← 最耗时

第 1 批：轻度依赖表（依赖第 0 批）
  └── products                      (33K 行, ~5s)

第 2 批：核心依赖表（依赖第 1 批）
  └── orders                        (99K 行, ~10s)

第 3 批：明细依赖表（依赖第 2 批 + products + sellers）
  ├── order_items                   (113K 行, ~15s)
  ├── order_payments                (104K 行, ~10s)
  └── order_reviews                 (105K 行, ~15s)

第 4 批：自建表（依赖 products）
  └── inventory                     (33K 行, <1s)
```

**总导入耗时**：约 2 分钟（普通笔记本）。

### 6.3 数据清洗处理

| 问题 | 处理方式 | SQL 实现 |
|------|---------|---------|
| 品类名为空字符串 | 映射为 NULL | `NULLIF(TRIM(@cat), '')` |
| 日期字段为空 | 映射为 NULL | `NULLIF(@col, '')` |
| 评论内容为空 | 映射为 NULL | `NULLIF(TRIM(@msg), '')` |
| BOM 头（品类翻译表） | TRIM 处理 | `TRIM(BOTH '\r' FROM @col1)` |

---

## 七、MySQL 进阶技术详述

### 7.1 视图（10 个）

| 视图名 | 类型 | SQL 技术点 | 用途 |
|--------|------|-----------|------|
| `v_order_full` | 宽表聚合 | 4 表 LEFT JOIN + GROUP BY + 聚合函数 | 一键查询订单全貌 |
| `v_category_sales` | 统计聚合 | JOIN + 聚合 + 排序 | 品类销售排行榜 |
| `v_customer_rfm` | 窗口分析 | CTE + NTILE(5) OVER | 客户价值五分层 |
| `v_monthly_revenue` | 时间序列 | DATE_FORMAT + GROUP BY | 月度收入趋势 |
| `v_product_recommendation` | 关联规则 | 自连接 + CTE + HAVING | 协同过滤推荐（含 lift/support） |
| `v_category_cross_sell` | 品类关联 | 4 表 JOIN + 窗口函数 | 品类交叉销售分析 |
| `v_review_weighted_recommendation` | 过滤推荐 | JOIN + GROUP BY + HAVING | 过滤差评商品的推荐 |
| `v_instock_recommendation` | 库存感知推荐 | JOIN + 过滤 | 仅推荐有库存商品 |
| `v_inventory_status` | 库存健康度 | CASE WHEN + JOIN | 库存状态总览 |
| `v_inventory_turnover` | 周转分析 | JOIN + 聚合 + 比率计算 | 库存周转率分析 |

**技术亮点**：`v_customer_rfm` 使用 NTILE(5) 窗口函数将客户分为 125 个分层（5×5×5），是目前 SQL 教学的较深内容。

### 7.2 自定义函数（2 个）

| 函数名 | 参数 | 返回 | 实现 |
|--------|------|------|------|
| `fn_shipping_days(order_id)` | VARCHAR(32) | INT | 用 DATEDIFF 计算 (签收 - 下单) |
| `fn_order_total(order_id)` | VARCHAR(32) | DECIMAL(12,2) | SUM(price + freight) |

**设计意图**：将业务规则封装为函数，查询语句更简洁，避免重复编写相同逻辑。

### 7.3 触发器（5 个）

| 触发器名 | 时机 | 作用表 | 触发逻辑 |
|---------|------|--------|---------|
| `trg_order_item_deduct_stock` | BEFORE INSERT | order_items | 检查库存→扣减 1 件→不足则抛错 |
| `trg_inventory_low_stock_alert` | AFTER UPDATE | inventory | stock ≤ safety → 写入 inventory_alert |
| `trg_review_negative_alert` | AFTER INSERT | order_reviews | score ≤ 2 → 差评关联商品写入预警 |
| `trg_inventory_log_insert` | AFTER INSERT | inventory | 记录初始库存变更日志 |
| `trg_inventory_log_update` | AFTER UPDATE | inventory | 记录每次库存变更的完整上下文 |

**业务链路演示**：
```
用户下单 → INSERT order_items
  → trg_order_item_deduct_stock 扣库存
    → stock_qty 从 5 减到 4（仍 > safety_stock=5？不，4 ≤ 5！）
      → trg_inventory_low_stock_alert 写入预警
```

这条完整链路在演示中非常直观：一次 INSERT，两张表受影响，一封预警自动产生。

### 7.4 存储过程（8 个）与事务

| 过程名 | 参数 | 返回 | 事务 |
|--------|------|------|------|
| `sp_place_order` | IN: customer/product/seller/price/freight, OUT: order_id | 生成订单 ID | **✅ 显式** |
| `sp_state_monthly_revenue` | IN: state, year | 月度收入表 | — |
| `sp_low_stock_report` | 无 | 低库存商品列表 | — |
| `sp_restock_product` | IN: product_id, qty | 更新后库存量（自动解决预警） | — |
| `sp_bulk_restock` | IN: product_id 列表, qty | 批量补货结果 | — |
| `sp_adjust_inventory` | IN: product_id, adjust_qty, reason | 调整后库存 | — |
| `sp_get_product_recommendations` | IN: product_id, limit | TOP N 关联商品 | — |
| `sp_get_customer_recommendations` | IN: customer_unique_id, limit | 个性化推荐列表 | — |

**`sp_place_order` 事务流程**：
```sql
START TRANSACTION;
  INSERT INTO orders (...);       -- 步骤 1: 生成订单
  INSERT INTO order_items (...);  -- 步骤 2: 插入明细 → 触发器扣库存
COMMIT;                           -- 步骤 3: 全部成功，提交
-- 任一失败（如库存不足触发 SIGNAL）→ 自动 ROLLBACK
```

### 7.5 索引设计（11 个）

| 索引名 | 表 | 列 | 类型 | 使用场景 |
|--------|------|------|------|---------|
| idx_customer_state | customers | state | 单列 | `GROUP BY state` |
| idx_order_status | orders | status | 单列 | `WHERE status = 'delivered'` |
| idx_order_purchase_ts | orders | timestamp | 单列 | 时间范围 `BETWEEN` |
| idx_order_status_time | orders | (status, ts) | **复合** | `WHERE status=... AND ts BETWEEN...` |
| idx_oi_product | order_items | product_id | 单列 | 商品销量分析 |
| idx_oi_seller | order_items | seller_id | 单列 | 卖家销售分析 |
| idx_oi_product_seller | order_items | (product, seller) | **复合** | 商品-卖家交叉分析 |
| idx_payment_type | order_payments | type | 单列 | 支付偏好分析 |
| idx_review_score | order_reviews | score | 单列 | 评分筛选 |
| idx_geo_zip | geolocation | zip | 单列 | 邮编→坐标查询 |
| idx_inv_stock | inventory | stock_qty | 单列 | 低库存预警查询 |

**复合索引优于两个单列索引的场景**：
```sql
-- 复合索引 idx(status, ts) 可直接使用，无需回表
SELECT * FROM orders WHERE order_status = 'delivered'
  AND order_purchase_timestamp BETWEEN '2017-01-01' AND '2017-12-31';
```

---

## 八、数据分析与可视化

（本章完整内容含 11 张图表的 SQL 查询、业务解读、图表引用，详见 `report/charts/` 目录下的 11 张 PNG 文件。）

### 8.1 销售趋势 → `01_monthly_revenue_trend.png`
### 8.2 各州收入 → `02_top_states_revenue.png`
### 8.3 品类排名 → `03_top_categories.png`
### 8.4 支付方式 → `04_payment_distribution.png`
### 8.5 配送时效 → `05_delivery_days_by_state.png`
### 8.6 评价分布 → `06_review_distribution.png`
### 8.7 RFM 分层 → `07_rfm_segments.png`
### 8.8 购买时段 → `08_hourly_pattern.png`
### 8.9 订单状态 → `09_order_status.png`
### 8.10 价格与运费 → `10_price_freight_scatter.png`
### 8.11 州级画像 → `11_state_bubble.png`

> 详细分析结果与 SQL 查询见本文第一版的第六章（6.1-6.11）。

---

## 九、图片索引

| 图号 | 文件名 | 类型 | 核心发现 |
|------|--------|------|---------|
| 图 1 | `01_monthly_revenue_trend.png` | 双轴折线图 | 2017-11 峰值 7,060 单 / 112 万 BRL |
| 图 2 | `02_top_states_revenue.png` | 横向柱状 | SP 州 559 万 BRL 占总 35% |
| 图 3 | `03_top_categories.png` | 柱状图 | health_beauty 123 万居首 |
| 图 4 | `04_payment_distribution.png` | 双饼图 | 信用卡 75% / 平均 3.5 期 |
| 图 5 | `05_delivery_days_by_state.png` | 颜色编码柱状 | SP 8.7 天 vs 偏远 20-30 天 |
| 图 6 | `06_review_distribution.png` | 柱状图 | 5 星 57.7%, 1 星 11.5% |
| 图 7 | `07_rfm_segments.png` | 彩色柱状 | Champions / Lost 客户识别 |
| 图 8 | `08_hourly_pattern.png` | 面积折线 | 16:00 峰值 6,484 单 |
| 图 9 | `09_order_status.png` | 饼图 | delivered 97.0% |
| 图 10 | `10_price_freight_scatter.png` | 散点图 | 品类价格带分层 |
| 图 11 | `11_state_bubble.png` | 气泡图 | 订单量×AOV×收入 |

---

## 十、文件清单与运行指南

（见 `README.md`，含完整目录结构、一键部署命令、图表生成方法、评分对应表。）

---

## 十一、成员分工说明

| 成员（待填写） | 负责内容 |
|---------------|---------|
| | 数据库整体设计、建表、外键约束、数据导入 |
| | 视图（5个）、自定义函数（2个）、索引优化（11个）|
| | 触发器（3个）、存储过程（4个）、事务处理 |
| | 数据分析（10 个 SQL 查询）+ 可视化（11 张图表）|
| | PPT 制作（30 页）、演示设计 |
| | Word 报告撰写、整体排版 |

---

## 十二、附录 评分要点对应

| 评分项 | 本项目实现 | 关键文件 |
|--------|-----------|---------|
| 建库建表 + 字段说明 | 11 张表，完整字段清单 + 类型选择理由 | `02_create_tables.sql`, 报告第4章 |
| ER 图 + 完整性约束 | 文字版 ER 图 + 9 FK + 7 CHECK + ENUM + UNIQUE | 报告第3章 + 第5章 |
| 增删改查 | LOAD DATA + INSERT + 子查询 + 多表 JOIN | `03_load_data.sql`, `05_analysis_queries.sql` |
| 视图 | 5 个（含 NTILE 窗口函数 + 自连接推荐） | `04_advanced_features.sql` |
| 存储过程 | 4 个（下单事务/收入统计/库存报表/补货） | `04b_triggers_procedures.sql` |
| 触发器 | 3 个（库存扣减/低库存预警/差评预警） | `04b_triggers_procedures.sql` |
| 事务 | `sp_place_order` 显式 START/COMMIT/ROLLBACK | `04b_triggers_procedures.sql` |
| 函数 | 2 个（物流天数/订单总价） | `04_advanced_features.sql` |
| 索引 | 11 个（含 3 个复合索引） | `02_create_tables.sql` |
| 数据分析 | 10 个维度 + 11 张可视化图表 | `05_analysis_queries.sql`, `generate_charts.py` |

---

> **报告版本**: v2.0 — 含完整数据库设计说明与设计方法论  
> **生成日期**: 2026-05-30  
> **下一待办**: ER 图截图, EXPLAIN 性能对比, PPT 图表嵌入调整