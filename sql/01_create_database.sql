-- ============================================================
-- Final Project: Olist Brazilian E-Commerce Database
-- Database Creation Script
--
-- 为什么选择 MySQL 8.x：
--   • 支持窗口函数、CTE、JSON 类型，语法现代
--   • InnoDB 引擎原生支持事务、行级锁、外键
--   • utf8mb4 完整支持 emoji，无需字符集转换
--   • 教学环境友好，社区版免费
--
-- 数据库设计遵循原则：
--   • 第三范式（3NF）：消除传递依赖，字段只与主键相关
--   • 适度反规范化：geolocation 表冗余 city/state 以加速 JOIN
--   • 一对一库存表：inventory 与 products 分离，避免污染商品主数据
-- ============================================================

DROP DATABASE IF EXISTS olist_db;

CREATE DATABASE olist_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE olist_db;

-- 开启本地文件导入（LOAD DATA LOCAL INFILE 需要）
SET GLOBAL local_infile = 1;