#!/usr/bin/env python3
"""
Final Project: Olist Brazilian E-Commerce Database
Data Visualization Script for PPT Presentation
Generates 10 professional charts as PNG files.
"""

import os
import pymysql
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from sqlalchemy import create_engine

# ============================================================
# Configuration
# ============================================================
DB_CONFIG = {
    'host': 'localhost',
    'user': 'root',
    'password': '789456123',
    'database': 'olist_db',
    'charset': 'utf8mb4'
}

OUTPUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'report', 'charts')
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Set style
sns.set_style("whitegrid")
plt.rcParams['figure.dpi'] = 150
plt.rcParams['savefig.dpi'] = 150
plt.rcParams['figure.figsize'] = (10, 6)
plt.rcParams['font.size'] = 10

# Color palette
COLORS = sns.color_palette("husl", 10)


def get_engine():
    """Create SQLAlchemy engine."""
    url = f"mysql+pymysql://{DB_CONFIG['user']}:{DB_CONFIG['password']}@{DB_CONFIG['host']}/{DB_CONFIG['database']}"
    return create_engine(url)


def save_chart(fig, filename):
    """Save chart to output directory."""
    path = os.path.join(OUTPUT_DIR, filename)
    fig.tight_layout()
    fig.savefig(path, bbox_inches='tight', facecolor='white')
    plt.close(fig)
    print(f"Saved: {path}")


# ============================================================
# Chart 1: Monthly Revenue Trend
# ============================================================
def chart_monthly_revenue_trend():
    query = """
    SELECT
        DATE_FORMAT(order_purchase_timestamp, '%%Y-%%m') AS month,
        COUNT(DISTINCT order_id) AS orders,
        ROUND(SUM(total_amount), 2) AS revenue
    FROM v_order_full
    WHERE order_status = 'delivered'
    GROUP BY month
    ORDER BY month;
    """
    df = pd.read_sql(query, get_engine())

    fig, ax1 = plt.subplots(figsize=(12, 6))

    color1 = COLORS[0]
    ax1.set_xlabel('Month')
    ax1.set_ylabel('Revenue (BRL)', color=color1)
    ax1.plot(df['month'], df['revenue'], color=color1, marker='o', linewidth=2, label='Revenue')
    ax1.tick_params(axis='y', labelcolor=color1)
    ax1.tick_params(axis='x', rotation=45)

    ax2 = ax1.twinx()
    color2 = COLORS[3]
    ax2.set_ylabel('Order Count', color=color2)
    ax2.bar(df['month'], df['orders'], alpha=0.3, color=color2, label='Orders')
    ax2.tick_params(axis='y', labelcolor=color2)

    plt.title('Monthly Revenue & Order Count Trend', fontsize=14, fontweight='bold')
    fig.tight_layout()
    save_chart(fig, '01_monthly_revenue_trend.png')


# ============================================================
# Chart 2: Top 10 States by Revenue
# ============================================================
def chart_top_states_revenue():
    query = """
    SELECT
        customer_state AS state,
        COUNT(DISTINCT order_id) AS orders,
        ROUND(SUM(total_amount), 2) AS revenue
    FROM v_order_full
    WHERE order_status = 'delivered'
    GROUP BY customer_state
    ORDER BY revenue DESC
    LIMIT 10;
    """
    df = pd.read_sql(query, get_engine())

    fig, ax = plt.subplots(figsize=(10, 6))
    bars = ax.barh(df['state'][::-1], df['revenue'][::-1], color=COLORS[:10][::-1])
    ax.set_xlabel('Revenue (BRL)')
    ax.set_ylabel('State')
    ax.set_title('Top 10 States by Revenue', fontsize=14, fontweight='bold')

    # Add value labels
    for bar in bars:
        width = bar.get_width()
        ax.text(width, bar.get_y() + bar.get_height()/2,
                f'R$ {width:,.0f}', ha='left', va='center', fontsize=9)

    save_chart(fig, '02_top_states_revenue.png')


# ============================================================
# Chart 3: Top 10 Categories by Revenue
# ============================================================
def chart_top_categories():
    query = """
    SELECT
        category_en,
        order_count,
        total_revenue,
        avg_price
    FROM v_category_sales
    WHERE category_en IS NOT NULL
    ORDER BY total_revenue DESC
    LIMIT 10;
    """
    df = pd.read_sql(query, get_engine())

    fig, ax = plt.subplots(figsize=(11, 6))
    bars = ax.bar(range(len(df)), df['total_revenue'], color=COLORS[:10])
    ax.set_xticks(range(len(df)))
    ax.set_xticklabels(df['category_en'], rotation=45, ha='right')
    ax.set_ylabel('Revenue (BRL)')
    ax.set_title('Top 10 Product Categories by Revenue', fontsize=14, fontweight='bold')

    for i, bar in enumerate(bars):
        height = bar.get_height()
        ax.text(bar.get_x() + bar.get_width()/2., height,
                f'R$ {height:,.0f}', ha='center', va='bottom', fontsize=8)

    save_chart(fig, '03_top_categories.png')


# ============================================================
# Chart 4: Payment Type Distribution
# ============================================================
def chart_payment_distribution():
    query = """
    SELECT
        payment_type,
        COUNT(DISTINCT order_id) AS order_count,
        ROUND(SUM(payment_value), 2) AS total_payment
    FROM order_payments
    GROUP BY payment_type
    ORDER BY total_payment DESC;
    """
    df = pd.read_sql(query, get_engine())

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 6))

    # Pie chart by order count
    ax1.pie(df['order_count'], labels=df['payment_type'], autopct='%1.1f%%',
            colors=COLORS[:len(df)], startangle=90)
    ax1.set_title('Payment Type by Order Count', fontsize=12, fontweight='bold')

    # Pie chart by value
    ax2.pie(df['total_payment'], labels=df['payment_type'], autopct='%1.1f%%',
            colors=COLORS[:len(df)], startangle=90)
    ax2.set_title('Payment Type by Value', fontsize=12, fontweight='bold')

    save_chart(fig, '04_payment_distribution.png')


# ============================================================
# Chart 5: Average Delivery Days by State
# ============================================================
def chart_delivery_days_by_state():
    query = """
    SELECT
        c.customer_state,
        ROUND(AVG(fn_shipping_days(o.order_id)), 1) AS avg_days,
        COUNT(*) AS delivered_orders
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
    GROUP BY c.customer_state
    ORDER BY avg_days DESC;
    """
    df = pd.read_sql(query, get_engine())

    fig, ax = plt.subplots(figsize=(10, 8))
    colors_map = [COLORS[2] if d < 15 else COLORS[7] if d < 25 else COLORS[0] for d in df['avg_days']]
    bars = ax.barh(df['customer_state'][::-1], df['avg_days'][::-1], color=colors_map[::-1])
    ax.set_xlabel('Average Delivery Days')
    ax.set_ylabel('State')
    ax.set_title('Average Delivery Days by State', fontsize=14, fontweight='bold')
    ax.axvline(x=15, color='red', linestyle='--', alpha=0.5, label='15-day threshold')

    for bar in bars:
        width = bar.get_width()
        ax.text(width, bar.get_y() + bar.get_height()/2,
                f'{width:.1f}d', ha='left', va='center', fontsize=9)

    ax.legend()
    save_chart(fig, '05_delivery_days_by_state.png')


# ============================================================
# Chart 6: Review Score Distribution
# ============================================================
def chart_review_distribution():
    query = """
    SELECT
        review_score,
        COUNT(*) AS review_count,
        ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct
    FROM order_reviews
    GROUP BY review_score
    ORDER BY review_score DESC;
    """
    df = pd.read_sql(query, get_engine())

    fig, ax = plt.subplots(figsize=(8, 6))
    colors = ['#2ecc71', '#27ae60', '#f1c40f', '#e67e22', '#e74c3c']
    bars = ax.bar(df['review_score'], df['review_count'], color=colors[::-1])
    ax.set_xlabel('Review Score (1-5 Stars)')
    ax.set_ylabel('Number of Reviews')
    ax.set_title('Review Score Distribution', fontsize=14, fontweight='bold')
    ax.set_xticks([1, 2, 3, 4, 5])

    for i, bar in enumerate(bars):
        height = bar.get_height()
        pct = df.iloc[i]['pct']
        ax.text(bar.get_x() + bar.get_width()/2., height,
                f'{int(height)}\n({pct}%)', ha='center', va='bottom', fontsize=10)

    save_chart(fig, '06_review_distribution.png')


# ============================================================
# Chart 7: RFM Segment Distribution
# ============================================================
def chart_rfm_segments():
    query = """
    SELECT
        CASE
            WHEN rfm_segment LIKE '5%%' THEN 'Champions'
            WHEN rfm_segment LIKE '4%%' OR rfm_segment LIKE '45%%' OR rfm_segment LIKE '54%%' THEN 'Loyal'
            WHEN rfm_segment LIKE '1%%' THEN 'Lost'
            WHEN rfm_segment LIKE '2%%' THEN 'At Risk'
            ELSE 'Potential'
        END AS segment_label,
        COUNT(*) AS customer_count,
        ROUND(AVG(monetary), 2) AS avg_monetary
    FROM v_customer_rfm
    GROUP BY segment_label
    ORDER BY customer_count DESC;
    """
    df = pd.read_sql(query, get_engine())

    fig, ax = plt.subplots(figsize=(9, 6))
    colors_seg = {'Champions': '#2ecc71', 'Loyal': '#3498db',
                  'Potential': '#f1c40f', 'At Risk': '#e67e22', 'Lost': '#e74c3c'}
    bar_colors = [colors_seg.get(s, '#95a5a6') for s in df['segment_label']]

    bars = ax.bar(df['segment_label'], df['customer_count'], color=bar_colors)
    ax.set_ylabel('Customer Count')
    ax.set_title('RFM Customer Segment Distribution', fontsize=14, fontweight='bold')

    for bar in bars:
        height = bar.get_height()
        ax.text(bar.get_x() + bar.get_width()/2., height,
                f'{int(height)}', ha='center', va='bottom', fontsize=11, fontweight='bold')

    save_chart(fig, '07_rfm_segments.png')


# ============================================================
# Chart 8: Hourly Purchase Pattern
# ============================================================
def chart_hourly_pattern():
    query = """
    SELECT
        HOUR(order_purchase_timestamp) AS hour_of_day,
        COUNT(*) AS order_count
    FROM orders
    GROUP BY HOUR(order_purchase_timestamp)
    ORDER BY hour_of_day;
    """
    df = pd.read_sql(query, get_engine())

    fig, ax = plt.subplots(figsize=(12, 5))
    ax.fill_between(df['hour_of_day'], df['order_count'], alpha=0.4, color=COLORS[0])
    ax.plot(df['hour_of_day'], df['order_count'], color=COLORS[0], marker='o', linewidth=2)
    ax.set_xlabel('Hour of Day')
    ax.set_ylabel('Order Count')
    ax.set_title('Purchase Pattern by Hour of Day', fontsize=14, fontweight='bold')
    ax.set_xticks(range(0, 24))
    ax.grid(True, alpha=0.3)

    # Highlight peak hours
    peak_hour = df.loc[df['order_count'].idxmax(), 'hour_of_day']
    peak_count = df['order_count'].max()
    ax.annotate(f'Peak: {int(peak_count)} orders at {int(peak_hour)}:00',
                xy=(peak_hour, peak_count),
                xytext=(peak_hour + 2, peak_count + 500),
                arrowprops=dict(arrowstyle='->', color='red'),
                fontsize=11, color='red', fontweight='bold')

    save_chart(fig, '08_hourly_pattern.png')


# ============================================================
# Chart 9: Order Status Distribution
# ============================================================
def chart_order_status():
    query = """
    SELECT
        order_status,
        COUNT(*) AS count,
        ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct
    FROM orders
    GROUP BY order_status
    ORDER BY count DESC;
    """
    df = pd.read_sql(query, get_engine())

    fig, ax = plt.subplots(figsize=(8, 8))
    wedges, texts, autotexts = ax.pie(
        df['count'], labels=df['order_status'], autopct='%1.1f%%',
        colors=COLORS[:len(df)], startangle=90, explode=[0.02]*len(df))
    ax.set_title('Order Status Distribution', fontsize=14, fontweight='bold')

    for text in texts:
        text.set_fontsize(11)
    for autotext in autotexts:
        autotext.set_fontsize(10)
        autotext.set_fontweight('bold')

    save_chart(fig, '09_order_status.png')


# ============================================================
# Chart 10: Price vs Freight Scatter (by Category Sample)
# ============================================================
def chart_price_freight_scatter():
    query = """
    SELECT
        oi.price,
        oi.freight_value,
        pcat.product_category_name_english AS category
    FROM order_items oi
    JOIN products p ON oi.product_id = p.product_id
    LEFT JOIN product_category_translation pcat
        ON p.product_category_name = pcat.product_category_name
    WHERE pcat.product_category_name_english IN (
        'health_beauty', 'watches_gifts', 'bed_bath_table',
        'sports_leisure', 'computers_accessories', 'furniture_decor'
    )
    AND oi.price < 2000 AND oi.freight_value < 200
    ORDER BY RAND()
    LIMIT 3000;
    """
    df = pd.read_sql(query, get_engine())

    fig, ax = plt.subplots(figsize=(10, 7))
    categories = df['category'].unique()
    for i, cat in enumerate(categories):
        cat_df = df[df['category'] == cat]
        ax.scatter(cat_df['price'], cat_df['freight_value'],
                   alpha=0.5, label=cat, s=20, color=COLORS[i])

    ax.set_xlabel('Product Price (BRL)')
    ax.set_ylabel('Freight Value (BRL)')
    ax.set_title('Price vs Freight by Category (Sample)', fontsize=14, fontweight='bold')
    ax.legend(title='Category', bbox_to_anchor=(1.05, 1), loc='upper left')

    save_chart(fig, '10_price_freight_scatter.png')


# ============================================================
# Chart 11: Revenue vs Avg Order Value by State (Bubble)
# ============================================================
def chart_state_bubble():
    query = """
    SELECT
        customer_state AS state,
        COUNT(DISTINCT order_id) AS orders,
        ROUND(SUM(total_amount), 2) AS revenue,
        ROUND(AVG(total_amount), 2) AS avg_order_value
    FROM v_order_full
    WHERE order_status = 'delivered'
    GROUP BY customer_state;
    """
    df = pd.read_sql(query, get_engine())

    fig, ax = plt.subplots(figsize=(10, 7))
    scatter = ax.scatter(df['orders'], df['avg_order_value'],
                         s=df['revenue']/5000, alpha=0.6, c=range(len(df)), cmap='viridis')

    for i, row in df.iterrows():
        ax.annotate(row['state'], (row['orders'], row['avg_order_value']),
                    fontsize=9, ha='center')

    ax.set_xlabel('Order Count')
    ax.set_ylabel('Average Order Value (BRL)')
    ax.set_title('State Profile: Orders vs AOV (bubble size = revenue)', fontsize=14, fontweight='bold')
    ax.grid(True, alpha=0.3)

    save_chart(fig, '11_state_bubble.png')


# ============================================================
# Chart 12: TOP 20 Recommendation Pairs by Lift
# ============================================================
def chart_recommendation_lift_top20():
    query = """
    SELECT
        CONCAT(SUBSTRING(v.product_a, 1, 8), '...') AS product_a,
        CONCAT(SUBSTRING(v.product_b, 1, 8), '...') AS product_b,
        v.co_purchase_count,
        v.lift
    FROM v_product_recommendation v
    ORDER BY v.lift DESC
    LIMIT 20;
    """
    df = pd.read_sql(query, get_engine())
    df['pair'] = df['product_a'] + ' + ' + df['product_b']

    fig, ax = plt.subplots(figsize=(10, 8))
    bars = ax.barh(df['pair'][::-1], df['lift'][::-1], color=COLORS[5])
    ax.set_xlabel('Lift (Association Strength)')
    ax.set_title('TOP 20 Product Recommendation Pairs by Lift', fontsize=14, fontweight='bold')

    for bar in bars:
        width = bar.get_width()
        ax.text(width, bar.get_y() + bar.get_height()/2,
                f'{width:.2f}', ha='left', va='center', fontsize=8)

    save_chart(fig, '12_recommendation_lift_top20.png')


# ============================================================
# Chart 13: Category Cross-Sell Heatmap (Top 15 categories)
# ============================================================
def chart_category_cross_sell_heatmap():
    query = """
    WITH top_cats AS (
        SELECT category_a AS cat
        FROM v_category_cross_sell
        GROUP BY category_a
        ORDER BY SUM(co_purchase_count) DESC
        LIMIT 15
    )
    SELECT
        v.category_a,
        v.category_b,
        v.co_purchase_count
    FROM v_category_cross_sell v
    JOIN top_cats t1 ON v.category_a = t1.cat
    JOIN top_cats t2 ON v.category_b = t2.cat
    ORDER BY v.category_a, v.category_b;
    """
    df = pd.read_sql(query, get_engine())

    if df.empty:
        print("  Skipping heatmap: no cross-sell data available")
        return

    pivot = df.pivot(index='category_a', columns='category_b', values='co_purchase_count').fillna(0)

    fig, ax = plt.subplots(figsize=(12, 10))
    sns.heatmap(pivot, annot=False, fmt='.0f', cmap='YlOrRd', linewidths=0.5, ax=ax)
    ax.set_title('Category Cross-Sell Heatmap (Top 15 Categories)', fontsize=14, fontweight='bold')
    ax.set_xlabel('Category B')
    ax.set_ylabel('Category A')
    plt.setp(ax.get_xticklabels(), rotation=45, ha='right')
    plt.setp(ax.get_yticklabels(), rotation=0)

    save_chart(fig, '13_category_cross_sell_heatmap.png')


# ============================================================
# Chart 14: Inventory Health Distribution
# ============================================================
def chart_inventory_health_pie():
    query = """
    SELECT
        stock_status,
        COUNT(*) AS product_count
    FROM v_inventory_status
    GROUP BY stock_status
    ORDER BY product_count DESC;
    """
    df = pd.read_sql(query, get_engine())

    fig, ax = plt.subplots(figsize=(8, 8))
    colors_health = {'Healthy': '#2ecc71', 'Warning': '#f1c40f',
                     'Low Stock': '#e67e22', 'Out of Stock': '#e74c3c'}
    pie_colors = [colors_health.get(s, '#95a5a6') for s in df['stock_status']]

    wedges, texts, autotexts = ax.pie(
        df['product_count'], labels=df['stock_status'], autopct='%1.1f%%',
        colors=pie_colors, startangle=90, explode=[0.02]*len(df))
    ax.set_title('Inventory Health Distribution', fontsize=14, fontweight='bold')

    for text in texts:
        text.set_fontsize(11)
    for autotext in autotexts:
        autotext.set_fontsize(10)
        autotext.set_fontweight('bold')

    save_chart(fig, '14_inventory_health_pie.png')


# ============================================================
# Chart 15: Inventory Turnover TOP 10 (Fastest + Slowest)
# ============================================================
def chart_inventory_turnover_top10():
    query_fast = """
    SELECT product_id, turnover_ratio, movement_class
    FROM v_inventory_turnover
    WHERE turnover_ratio IS NOT NULL
    ORDER BY turnover_ratio DESC LIMIT 10;
    """
    query_slow = """
    SELECT product_id, turnover_ratio, movement_class
    FROM v_inventory_turnover
    ORDER BY turnover_ratio ASC LIMIT 10;
    """
    df_fast = pd.read_sql(query_fast, get_engine())
    df_slow = pd.read_sql(query_slow, get_engine())

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 6))

    # Fastest
    df_fast['label'] = df_fast['product_id'].str[:8] + '...'
    bars1 = ax1.barh(df_fast['label'][::-1], df_fast['turnover_ratio'][::-1], color=COLORS[2])
    ax1.set_xlabel('Turnover Ratio')
    ax1.set_title('TOP 10 Fastest Turnover Products', fontsize=12, fontweight='bold')
    for bar in bars1:
        width = bar.get_width()
        ax1.text(width, bar.get_y() + bar.get_height()/2,
                 f'{width:.2f}', ha='left', va='center', fontsize=8)

    # Slowest
    df_slow['label'] = df_slow['product_id'].str[:8] + '...'
    bars2 = ax2.barh(df_slow['label'][::-1], df_slow['turnover_ratio'][::-1], color=COLORS[0])
    ax2.set_xlabel('Turnover Ratio')
    ax2.set_title('TOP 10 Slowest Turnover Products', fontsize=12, fontweight='bold')
    for bar in bars2:
        width = bar.get_width()
        ax2.text(width, bar.get_y() + bar.get_height()/2,
                 f'{width:.4f}', ha='left', va='center', fontsize=8)

    save_chart(fig, '15_inventory_turnover_top10.png')


# ============================================================
# Main
# ============================================================
def main():
    print("=" * 50)
    print("Olist Database Chart Generator")
    print("=" * 50)
    print(f"Output directory: {OUTPUT_DIR}")
    print()

    charts = [
        chart_monthly_revenue_trend,
        chart_top_states_revenue,
        chart_top_categories,
        chart_payment_distribution,
        chart_delivery_days_by_state,
        chart_review_distribution,
        chart_rfm_segments,
        chart_hourly_pattern,
        chart_order_status,
        chart_price_freight_scatter,
        chart_state_bubble,
        chart_recommendation_lift_top20,
        chart_category_cross_sell_heatmap,
        chart_inventory_health_pie,
        chart_inventory_turnover_top10,
    ]

    for i, chart_fn in enumerate(charts, 1):
        try:
            print(f"[{i}/{len(charts)}] Generating {chart_fn.__name__} ...")
            chart_fn()
        except Exception as e:
            print(f"  ERROR: {e}")

    print()
    print("=" * 50)
    print("Done! Generated charts:")
    for f in sorted(os.listdir(OUTPUT_DIR)):
        if f.endswith('.png'):
            print(f"  - {f}")
    print("=" * 50)


if __name__ == '__main__':
    main()
