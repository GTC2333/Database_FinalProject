# 数据库期末项目 —— CLAUDE.md

本项目说明文件，供 Claude Code 参考。

## 项目信息

- **课程**: 数据库系统（期末项目）
- **场景**: 巴西电商 Olist 运营管理系统
- **技术栈**: MySQL 8.0.35
- **数据规模**: ~10万订单，11张表

## 环境配置

### MySQL 路径
```
/usr/local/mysql-8.0.35-macos13-arm64/bin/mysql
```

### 数据库凭据
```
用户名: root
密码:   789456123
数据库: olist_db
```

### 快速运行
```bash
export PATH="/usr/local/mysql-8.0.35-macos13-arm64/bin:$PATH"
cd "/Users/gtc/Learning/数据库/finalproject"
./run_all.sh
```

### 手动逐行执行
```bash
mysql -u root -p789456123 < sql/01_create_database.sql
mysql -u root -p789456123 < sql/02_create_tables.sql
mysql --local-infile=1 -u root -p789456123 olist_db < sql/03_load_data.sql
mysql -u root -p789456123 olist_db < sql/04_advanced_features.sql
mysql -u root -p789456123 olist_db < sql/05_analysis_queries.sql
```

## 项目文件

- `sql/01_create_database.sql` — 创建数据库
- `sql/02_create_tables.sql` — 11张表 + 约束 + 索引
- `sql/03_load_data.sql` — 数据导入
- `sql/04_advanced_features.sql` — 视图/函数/触发器/存储过程/事务
- `sql/05_analysis_queries.sql` — 10个分析查询
- `report/initial_report.md` — 初步技术报告
- `run_all.sh` — 一键运行脚本
