# 数据文件夹说明

本目录存放 Olist 巴西电商数据集的原始 CSV 文件，用于数据库导入。

## 数据来源

- **Kaggle**: [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)
- **许可**: CC-BY-NC-SA-4.0
- **总大小**: 约 130MB（9 个 CSV 文件）

## 文件清单

| 文件名 | 行数 | 大小 | 说明 |
|--------|------|------|------|
| `olist_customers_dataset.csv` | 99,441 | ~9MB | 客户信息 |
| `olist_sellers_dataset.csv` | 3,096 | ~174KB | 卖家信息 |
| `olist_products_dataset.csv` | 32,951 | ~2.4MB | 商品信息 |
| `olist_orders_dataset.csv` | 99,441 | ~17MB | 订单主表 |
| `olist_order_items_dataset.csv` | 112,650 | ~15MB | 订单明细 |
| `olist_order_payments_dataset.csv` | 103,886 | ~5.8MB | 支付记录 |
| `olist_order_reviews_dataset.csv` | 104,720 | ~14MB | 评价信息 |
| `olist_geolocation_dataset.csv` | 1,000,163 | ~61MB | 地理坐标 |
| `product_category_name_translation.csv` | 72 | ~3KB | 品类翻译 |

## 获取方式

由于 Git 不适合存储大文件（`geolocation` 单文件 61MB 超出 GitHub 推荐限制），本目录中的 CSV 文件**未纳入 Git 版本控制**。

### 方式一：从 Kaggle 下载（推荐）

1. 访问 [Kaggle 数据集页面](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)
2. 下载 `brazilian-ecommerce.zip`
3. 解压后将 9 个 CSV 文件放入本目录

### 方式二：使用项目提供的压缩包

若已从其他渠道获得 `raw.zip`，解压到本目录即可：

```bash
cd data
unzip raw.zip
```

## 数据导入

CSV 文件到位后，执行项目根目录的 SQL 脚本完成导入：

```bash
cd /Users/gtc/Learning/数据库/finalproject
mysql --local-infile=1 -u root -p olist_db < sql/03_load_data.sql
```

或一键运行：

```bash
./run_all.sh
```

## 目录结构

```
data/
├── README.md                              # 本文件
├── raw/                                   # 原始 CSV 文件（.gitignore 排除）
│   ├── olist_customers_dataset.csv
│   ├── olist_sellers_dataset.csv
│   ├── olist_products_dataset.csv
│   ├── olist_orders_dataset.csv
│   ├── olist_order_items_dataset.csv
│   ├── olist_order_payments_dataset.csv
│   ├── olist_order_reviews_dataset.csv
│   ├── olist_geolocation_dataset.csv
│   └── product_category_name_translation.csv
└── raw.zip                                # 可选：原始压缩包（.gitignore 排除）
```
