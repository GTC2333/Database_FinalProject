# 数据库期末项目 —— Olist 巴西电商运营管理系统

## 项目概述

基于巴西电商平台 **Olist** 的真实公开数据集（~10万订单），构建完整的关系数据库系统，演示 MySQL 核心技术与电商业务分析。

## 技术栈

- **DBMS**: MySQL 8.x
- **数据规模**: 9 张真实数据表 + 3 张自造辅助表，约 130MB
- **核心功能**: DDL/DML/约束/视图/存储过程/触发器/事务/索引/函数

## 目录结构

```
finalproject/
├── CLAUDE.md                           # 项目级说明（含环境配置和密码）
├── README.md                           # 本文件
├── run_all.sh                          # 一键运行脚本
├── generate_charts.py                  # Python 可视化图表生成脚本
├── data/
│   └── raw/                            # 9 个 CSV 原始数据文件
├── sql/
│   ├── 01_create_database.sql          # 创建数据库
│   ├── 02_create_tables.sql            # 建表 + 约束 + 索引
│   ├── 03_load_data.sql                # 数据导入 + 库存生成
│   ├── 04_advanced_features.sql        # 视图 + 函数 + 索引
│   ├── 04b_triggers_procedures.sql     # 触发器 + 存储过程（增强版）
│   └── 05_analysis_queries.sql         # 16 个分析查询
├── report/
│   ├── initial_report.md               # 完整技术报告（含图片索引）
│   └── charts/                         # 15 张 PNG 可视化图表
│       ├── 01_monthly_revenue_trend.png
│       ├── 02_top_states_revenue.png
│       ├── 03_top_categories.png
│       ├── 04_payment_distribution.png
│       ├── 05_delivery_days_by_state.png
│       ├── 06_review_distribution.png
│       ├── 07_rfm_segments.png
│       ├── 08_hourly_pattern.png
│       ├── 09_order_status.png
│       ├── 10_price_freight_scatter.png
│       └── 11_state_bubble.png
└── er_diagram/                         # ER 图（后续从 MySQL Workbench 导出）
```

## 快速开始

### 1. 环境准备
确保已安装 MySQL 8.0+，并开启 local_infile：

```bash
mysql --version
```

### 2. 执行脚本（按顺序）

```bash
cd "/Users/gtc/Learning/数据库/finalproject"

# Step 1: 创建数据库
mysql -u root -p < sql/01_create_database.sql

# Step 2: 创建表结构
mysql -u root -p < sql/02_create_tables.sql

# Step 3: 导入数据（需要 local_infile 权限）
mysql --local-infile=1 -u root -p olist_db < sql/03_load_data.sql

# Step 4: 加载进阶功能
mysql -u root -p olist_db < sql/04_advanced_features.sql

# Step 5: 运行分析查询
mysql -u root -p olist_db < sql/05_analysis_queries.sql
```

### 3. 一键运行

也提供了 shell 脚本（需要添加执行权限）：

```bash
chmod +x run_all.sh
./run_all.sh
```

### 4. 验证数据

```sql
USE olist_db;
SHOW TABLES;
SELECT 'customers' AS tbl, COUNT(*) AS cnt FROM customers
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'inventory', COUNT(*) FROM inventory;
```

## 核心功能一览

| 技术点 | 文件 | 说明 |
|--------|------|------|
| **DDL/约束** | `02_create_tables.sql` | 11 张表，PK/FK/CHECK/ENUM/NOT NULL/UNIQUE |
| **数据导入** | `03_load_data.sql` | LOAD DATA INFILE + 库存数据生成 |
| **视图** | `04_advanced_features.sql` | 订单宽表/品类销售/RFM/月度收入/商品推荐 |
| **函数** | `04_advanced_features.sql` | 物流天数计算 / 订单总价计算 |
| **触发器** | `04b_triggers_procedures.sql` | 库存扣减/低库存预警/差评告警 |
| **存储过程** | `04b_triggers_procedures.sql` | 下单事务/州月度收入/低库存报表/补货 |
| **事务** | `04b_triggers_procedures.sql` | `sp_place_order` 中 START TRANSACTION / COMMIT / ROLLBACK |
| **索引** | `02_create_tables.sql` + `04_advanced_features.sql` | 11 个索引，含 3 个复合索引 |
| **分析查询** | `05_analysis_queries.sql` | 10 个业务分析 SQL |
| **数据可视化** | `generate_charts.py` | 15 张专业 PNG 图表（matplotlib + seaborn）|

## 数据来源

- **Kaggle**: [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)
- **规模**: 约 10 万订单，9 张 CSV，130MB
- **许可**: CC-BY-NC-SA-4.0

## 评分要点对应

| 评分项 | 本项目中对应内容 |
|--------|-----------------|
| 建库建表 + 字段说明 | `02_create_tables.sql` + 本报告第三章 |
| ER 图 + 完整性约束 | ER 图 + 第四章约束设计 |
| 增删改查 | `03_load_data.sql` (LOAD DATA / INSERT) + `05_analysis_queries.sql` |
| 子查询/多表查询 | 所有分析查询均涉及 JOIN / 子查询 |
| 视图 | `v_order_full`, `v_category_sales`, `v_customer_rfm`, `v_monthly_revenue`, `v_product_recommendation`, `v_inventory_status`, `v_inventory_turnover`, `v_category_cross_sell` |
| 存储过程 | `sp_place_order`, `sp_state_monthly_revenue`, `sp_low_stock_report`, `sp_restock_product`, `sp_bulk_restock`, `sp_adjust_inventory`, `sp_get_product_recommendations`, `sp_get_customer_recommendations` |
| 触发器 | `trg_order_item_deduct_stock`, `trg_inventory_low_stock_alert`, `trg_review_negative_alert`, `trg_inventory_log_insert`, `trg_inventory_log_update` |
| 事务 | `sp_place_order` 中的显式事务控制 |
| 函数 | `fn_shipping_days`, `fn_order_total` |
| 索引 | 20 个索引，含复合索引 |

## 图表生成

所有可视化图表由 Python 脚本自动生成：

```bash
cd "/Users/gtc/Learning/数据库/finalproject"
python3 generate_charts.py
```

生成的 11 张 PNG 图表存放于 `report/charts/`，可直接拖入 PPT 使用。

## 待补充

- [x] ~~数据集下载~~
- [x] ~~数据库建表与导入~~
- [x] ~~视图/函数/触发器/存储过程/事务~~
- [x] ~~分析查询与可视化图表~~
- [ ] ER 图截图（从 MySQL Workbench 导出）
- [ ] 查询执行结果截图（MySQL Workbench）
- [ ] 索引前后性能对比（EXPLAIN）
- [x] ~~PPT 制作（插入图表 + 技术演示页）~~
- [ ] Word 正式报告（Markdown 转 Word）
- [ ] 成员分工表填写
- [ ] 演示脚本和话术准备

---

> 作者: （待补充）  
> 课程: 数据库系统  
> 日期: 2026-05-29
