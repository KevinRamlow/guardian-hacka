#!/bin/bash
# Boost Configuration Management
set -euo pipefail

ACTION="${1:-}"
BRAND="${2:-}"
VALUE="${3:-}"

if [ -z "$ACTION" ]; then
  echo "Usage: $0 {show|update|enable|disable} <brand> [value]" >&2
  exit 1
fi

# MySQL connection (via Cloud SQL Proxy or direct)
MYSQL_CMD="mysql -h 127.0.0.1 -P 3306"

case "$ACTION" in
  show)
    if [ -z "$BRAND" ]; then
      # Show all
      $MYSQL_CMD -e "
        SELECT 
          b.name as Brand,
          c.name as Campaign,
          bc.enabled as Enabled,
          bc.monthly_limit as Monthly_Limit,
          bc.current_usage as Current_Usage,
          CONCAT(ROUND(bc.current_usage/bc.monthly_limit*100, 1), '%') as Usage_Pct
        FROM boost_configurations bc
        JOIN brands b ON bc.brand_id = b.id
        JOIN campaigns c ON bc.campaign_id = c.id
        ORDER BY b.name, c.name
      " 2>&1
    else
      # Show specific brand
      $MYSQL_CMD -e "
        SELECT 
          b.name as Brand,
          c.name as Campaign,
          bc.enabled as Enabled,
          bc.monthly_limit as Monthly_Limit,
          bc.current_usage as Current_Usage,
          CONCAT(ROUND(bc.current_usage/bc.monthly_limit*100, 1), '%') as Usage_Pct
        FROM boost_configurations bc
        JOIN brands b ON bc.brand_id = b.id
        JOIN campaigns c ON bc.campaign_id = c.id
        WHERE b.name LIKE '%${BRAND}%'
        ORDER BY c.name
      " 2>&1
    fi
    ;;
  
  update)
    if [ -z "$BRAND" ] || [ -z "$VALUE" ]; then
      echo "Usage: $0 update <brand> <new_limit>"
      exit 1
    fi
    
    # Get brand ID
    BRAND_ID=$($MYSQL_CMD -se "SELECT id FROM brands WHERE name LIKE '%${BRAND}%' LIMIT 1" 2>&1)
    
    if [ -z "$BRAND_ID" ]; then
      echo "❌ Brand not found: $BRAND"
      exit 1
    fi
    
    # Get old limit
    OLD_LIMIT=$($MYSQL_CMD -se "SELECT monthly_limit FROM boost_configurations WHERE brand_id = $BRAND_ID LIMIT 1" 2>&1)
    
    # Update
    $MYSQL_CMD -e "UPDATE boost_configurations SET monthly_limit = $VALUE WHERE brand_id = $BRAND_ID" 2>&1
    
    echo "✅ Updated $BRAND boost limit: $OLD_LIMIT → $VALUE"
    ;;
  
  enable)
    if [ -z "$BRAND" ]; then
      echo "Usage: $0 enable <brand> [campaign]"
      exit 1
    fi
    
    BRAND_ID=$($MYSQL_CMD -se "SELECT id FROM brands WHERE name LIKE '%${BRAND}%' LIMIT 1" 2>&1)
    
    if [ -z "$BRAND_ID" ]; then
      echo "❌ Brand not found: $BRAND"
      exit 1
    fi
    
    if [ -n "$VALUE" ]; then
      # Enable specific campaign
      CAMPAIGN_ID=$($MYSQL_CMD -se "SELECT id FROM campaigns WHERE name LIKE '%${VALUE}%' AND brand_id = $BRAND_ID LIMIT 1" 2>&1)
      $MYSQL_CMD -e "UPDATE boost_configurations SET enabled = 1 WHERE brand_id = $BRAND_ID AND campaign_id = $CAMPAIGN_ID" 2>&1
      echo "✅ Enabled boost for $BRAND - $VALUE"
    else
      # Enable all campaigns for brand
      $MYSQL_CMD -e "UPDATE boost_configurations SET enabled = 1 WHERE brand_id = $BRAND_ID" 2>&1
      echo "✅ Enabled boost for all $BRAND campaigns"
    fi
    ;;
  
  disable)
    if [ -z "$BRAND" ]; then
      echo "Usage: $0 disable <brand> [campaign]"
      exit 1
    fi
    
    BRAND_ID=$($MYSQL_CMD -se "SELECT id FROM brands WHERE name LIKE '%${BRAND}%' LIMIT 1" 2>&1)
    
    if [ -z "$BRAND_ID" ]; then
      echo "❌ Brand not found: $BRAND"
      exit 1
    fi
    
    if [ -n "$VALUE" ]; then
      # Disable specific campaign
      CAMPAIGN_ID=$($MYSQL_CMD -se "SELECT id FROM campaigns WHERE name LIKE '%${VALUE}%' AND brand_id = $BRAND_ID LIMIT 1" 2>&1)
      $MYSQL_CMD -e "UPDATE boost_configurations SET enabled = 0 WHERE brand_id = $BRAND_ID AND campaign_id = $CAMPAIGN_ID" 2>&1
      echo "✅ Disabled boost for $BRAND - $VALUE"
    else
      # Disable all campaigns for brand
      $MYSQL_CMD -e "UPDATE boost_configurations SET enabled = 0 WHERE brand_id = $BRAND_ID" 2>&1
      echo "✅ Disabled boost for all $BRAND campaigns"
    fi
    ;;
  
  *)
    echo "Unknown action: $ACTION"
    echo "Usage: $0 {show|update|enable|disable} <brand> [value]"
    exit 1
    ;;
esac
