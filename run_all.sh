#!/bin/bash
# ============================================================
# Final Project: Olist Database - One-Click Setup Script
# ============================================================

set -e  # Exit on error

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SQL_DIR="$PROJECT_DIR/sql"
DB_NAME="olist_db"
DB_USER="root"
DB_PASS="789456123"

echo "========================================"
echo "  Olist Database Setup Script"
echo "========================================"

# Check if MySQL is available
if ! command -v mysql > /dev/null 2>&1; then
    echo "Error: mysql command not found. Please install MySQL."
    exit 1
fi

echo ""
echo "Step 1/5: Creating database..."
mysql -u "$DB_USER" -p"$DB_PASS" < "$SQL_DIR/01_create_database.sql"

echo "Step 2/5: Creating tables with constraints..."
mysql -u "$DB_USER" -p"$DB_PASS" < "$SQL_DIR/02_create_tables.sql"

echo "Step 3/5: Loading data (this may take 1-2 minutes)..."
mysql --local-infile=1 -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$SQL_DIR/03_load_data.sql"

echo "Step 4/5: Loading advanced features..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$SQL_DIR/04_advanced_features.sql"

echo "Step 4b/5: Loading triggers and procedures..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$SQL_DIR/04b_triggers_procedures.sql"

echo "Step 5/5: Running analysis queries..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$SQL_DIR/05_analysis_queries.sql"

echo ""
echo "========================================"
echo "  Setup completed successfully!"
echo "========================================"
echo ""
echo "Database: $DB_NAME"
echo "Tables:"
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SHOW TABLES;"
echo ""
echo "Row counts:"
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "
SELECT 'customers' AS table_name, COUNT(*) AS `rows` FROM customers
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'order_payments', COUNT(*) FROM order_payments
UNION ALL SELECT 'order_reviews', COUNT(*) FROM order_reviews
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'sellers', COUNT(*) FROM sellers
UNION ALL SELECT 'geolocation', COUNT(*) FROM geolocation
UNION ALL SELECT 'inventory', COUNT(*) FROM inventory
UNION ALL SELECT 'inventory_alert', COUNT(*) FROM inventory_alert
UNION ALL SELECT 'inventory_log', COUNT(*) FROM inventory_log;
"

echo ""
echo "Next steps:"
echo "  1. Open MySQL Workbench to export ER diagram"
echo "  2. Take screenshots of query results for report"
echo "  3. Run EXPLAIN to show index optimization"
