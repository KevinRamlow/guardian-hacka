#!/bin/bash
# Revenue Forecasting & GMV Tracking
# Usage: ./revenue-forecasting.sh [--trend|--forecast|--full-report] [--months N] [--periods N] [--brand "Name"] [--format slack|json]

set -euo pipefail

# Default values
MODE="trend"
MONTHS=6
FORECAST_PERIODS=3
BRAND_FILTER=""
CAMPAIGN_FILTER=""
FORMAT="slack"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --trend)
      MODE="trend"
      shift
      ;;
    --forecast)
      MODE="forecast"
      shift
      ;;
    --full-report)
      MODE="full"
      shift
      ;;
    --months)
      MONTHS="$2"
      shift 2
      ;;
    --periods)
      FORECAST_PERIODS="$2"
      shift 2
      ;;
    --brand)
      BRAND_FILTER="$2"
      shift 2
      ;;
    --campaign)
      CAMPAIGN_FILTER="$2"
      shift 2
      ;;
    --format)
      FORMAT="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Helper: Format currency
format_currency() {
  local amount=$1
  # BRL format: R$ 1.403.500,00
  printf "%.2f" "$amount" | awk '{
    split($0, parts, ".");
    integer = parts[1];
    decimal = parts[2];
    
    len = length(integer);
    result = "";
    for (i = len; i > 0; i--) {
      result = substr(integer, i, 1) result;
      if ((len - i + 1) % 3 == 0 && i > 1) result = "." result;
    }
    
    print "R$ " result "," decimal;
  }'
}

# Helper: Calculate growth rate
calc_growth() {
  local current=$1
  local previous=$2
  if (( $(echo "$previous > 0" | bc -l) )); then
    echo "scale=1; (($current - $previous) / $previous) * 100" | bc -l
  else
    echo "0"
  fi
}

# Query: Monthly revenue trend
get_monthly_revenue() {
  local months=$1
  local brand_clause=""
  local campaign_clause=""
  
  if [[ -n "$BRAND_FILTER" ]]; then
    brand_clause="AND b.name LIKE '%$BRAND_FILTER%'"
  fi
  
  if [[ -n "$CAMPAIGN_FILTER" ]]; then
    campaign_clause="AND c.id = $CAMPAIGN_FILTER"
  fi
  
  mysql -N <<EOF
SELECT 
  DATE_FORMAT(cph.date_of_transaction, '%Y-%m') AS month,
  COUNT(DISTINCT cph.campaign_id) AS campaigns,
  COUNT(DISTINCT cph.creator_id) AS creators,
  ROUND(SUM(cph.value), 2) AS revenue_net,
  ROUND(SUM(cph.gross_value), 2) AS revenue_gross
FROM creator_payment_history cph
JOIN campaigns c ON cph.campaign_id = c.id
JOIN brands b ON c.brand_id = b.id
WHERE cph.date_of_transaction >= DATE_SUB(NOW(), INTERVAL $months MONTH)
  AND cph.payment_status IN ('complete', 'partial')
  $brand_clause
  $campaign_clause
GROUP BY month
ORDER BY month ASC;
EOF
}

# Query: Revenue by brand
get_revenue_by_brand() {
  local months=$1
  
  mysql -N <<EOF
SELECT 
  b.name AS brand,
  ROUND(SUM(cph.value), 2) AS revenue_net,
  COUNT(DISTINCT cph.campaign_id) AS campaigns,
  COUNT(DISTINCT cph.creator_id) AS creators,
  ROUND(SUM(cph.value) / $months, 2) AS avg_monthly
FROM creator_payment_history cph
JOIN campaigns c ON cph.campaign_id = c.id
JOIN brands b ON c.brand_id = b.id
WHERE cph.date_of_transaction >= DATE_SUB(NOW(), INTERVAL $months MONTH)
  AND cph.payment_status IN ('complete', 'partial')
GROUP BY b.id, b.name
ORDER BY revenue_net DESC
LIMIT 10;
EOF
}

# Trend analysis
if [[ "$MODE" == "trend" || "$MODE" == "full" ]]; then
  # Get monthly data
  MONTHLY_DATA=$(get_monthly_revenue "$MONTHS")
  
  if [[ -z "$MONTHLY_DATA" ]]; then
    echo "Error: No revenue data found for the specified period"
    exit 1
  fi
  
  # Parse data into arrays
  declare -a MONTHS_LIST
  declare -a REVENUE_LIST
  declare -a CAMPAIGNS_LIST
  declare -a CREATORS_LIST
  
  TOTAL_REVENUE=0
  MONTH_COUNT=0
  
  while IFS=$'\t' read -r month campaigns creators revenue_net revenue_gross; do
    MONTHS_LIST+=("$month")
    REVENUE_LIST+=("$revenue_net")
    CAMPAIGNS_LIST+=("$campaigns")
    CREATORS_LIST+=("$creators")
    TOTAL_REVENUE=$(echo "$TOTAL_REVENUE + $revenue_net" | bc -l)
    MONTH_COUNT=$((MONTH_COUNT + 1))
  done <<< "$MONTHLY_DATA"
  
  # Calculate average and growth rates
  AVG_REVENUE=$(echo "scale=2; $TOTAL_REVENUE / $MONTH_COUNT" | bc -l)
  
  # Calculate month-over-month growth rates
  declare -a GROWTH_RATES
  TOTAL_GROWTH=0
  GROWTH_COUNT=0
  
  for ((i=1; i<${#REVENUE_LIST[@]}; i++)); do
    current=${REVENUE_LIST[$i]}
    previous=${REVENUE_LIST[$((i-1))]}
    growth=$(calc_growth "$current" "$previous")
    GROWTH_RATES+=("$growth")
    TOTAL_GROWTH=$(echo "$TOTAL_GROWTH + $growth" | bc -l)
    GROWTH_COUNT=$((GROWTH_COUNT + 1))
  done
  
  if [[ $GROWTH_COUNT -gt 0 ]]; then
    AVG_GROWTH=$(echo "scale=1; $TOTAL_GROWTH / $GROWTH_COUNT" | bc -l)
  else
    AVG_GROWTH="0"
  fi
  
  # Get brand breakdown (if not filtering by brand)
  if [[ -z "$BRAND_FILTER" ]]; then
    BRAND_DATA=$(get_revenue_by_brand "$MONTHS")
  fi
  
  # Output: Trend report
  if [[ "$FORMAT" == "json" ]]; then
    # JSON format
    echo "{"
    echo "  \"period\": \"$MONTHS months\","
    echo "  \"total_revenue\": $TOTAL_REVENUE,"
    echo "  \"avg_monthly_revenue\": $AVG_REVENUE,"
    echo "  \"avg_growth_rate\": $AVG_GROWTH,"
    echo "  \"monthly_data\": ["
    
    for ((i=0; i<${#MONTHS_LIST[@]}; i++)); do
      growth_str="null"
      if [[ $i -gt 0 ]]; then
        growth_str="${GROWTH_RATES[$((i-1))]}"
      fi
      
      echo "    {"
      echo "      \"month\": \"${MONTHS_LIST[$i]}\","
      echo "      \"revenue\": ${REVENUE_LIST[$i]},"
      echo "      \"campaigns\": ${CAMPAIGNS_LIST[$i]},"
      echo "      \"creators\": ${CREATORS_LIST[$i]},"
      echo "      \"growth_rate\": $growth_str"
      echo -n "    }"
      if [[ $i -lt $((${#MONTHS_LIST[@]} - 1)) ]]; then
        echo ","
      else
        echo ""
      fi
    done
    
    echo "  ]"
    echo "}"
  else
    # Slack format
    TOTAL_REVENUE_FMT=$(format_currency "$TOTAL_REVENUE")
    AVG_REVENUE_FMT=$(format_currency "$AVG_REVENUE")
    
    if [[ -n "$BRAND_FILTER" ]]; then
      echo "📈 *Tendência de Revenue - $BRAND_FILTER*"
    elif [[ -n "$CAMPAIGN_FILTER" ]]; then
      echo "📈 *Tendência de Revenue - Campanha #$CAMPAIGN_FILTER*"
    else
      echo "📈 *Tendência de Revenue - Últimos $MONTHS Meses*"
    fi
    echo ""
    echo "💰 *RESUMO*"
    echo "• Total Período: $TOTAL_REVENUE_FMT"
    echo "• Média Mensal: $AVG_REVENUE_FMT"
    
    if (( $(echo "$AVG_GROWTH > 0" | bc -l) )); then
      echo "• Crescimento Médio: +${AVG_GROWTH}% m/m 📈"
    elif (( $(echo "$AVG_GROWTH < 0" | bc -l) )); then
      echo "• Crescimento Médio: ${AVG_GROWTH}% m/m 📉"
    else
      echo "• Crescimento Médio: ${AVG_GROWTH}% m/m ➖"
    fi
    
    # Last month stats
    last_idx=$((${#MONTHS_LIST[@]} - 1))
    echo "• Campanhas Ativas (último mês): ${CAMPAIGNS_LIST[$last_idx]}"
    echo "• Creators Pagos (último mês): ${CREATORS_LIST[$last_idx]}"
    echo ""
    
    echo "📊 *MÊS A MÊS*"
    for ((i=${#MONTHS_LIST[@]}-1; i>=0; i--)); do
      month=${MONTHS_LIST[$i]}
      revenue=${REVENUE_LIST[$i]}
      revenue_fmt=$(format_currency "$revenue")
      
      if [[ $i -gt 0 ]]; then
        growth=${GROWTH_RATES[$((i-1))]}
        if (( $(echo "$growth > 0" | bc -l) )); then
          echo "• $month: $revenue_fmt (+${growth}%)"
        elif (( $(echo "$growth < 0" | bc -l) )); then
          echo "• $month: $revenue_fmt (${growth}%)"
        else
          echo "• $month: $revenue_fmt (0%)"
        fi
      else
        echo "• $month: $revenue_fmt (baseline)"
      fi
    done
    
    # Brand breakdown
    if [[ -z "$BRAND_FILTER" && -n "$BRAND_DATA" ]]; then
      echo ""
      echo "🏆 *TOP BRANDS*"
      
      brand_idx=1
      while IFS=$'\t' read -r brand revenue campaigns creators avg_monthly; do
        revenue_fmt=$(format_currency "$revenue")
        pct=$(echo "scale=1; ($revenue / $TOTAL_REVENUE) * 100" | bc -l)
        echo "${brand_idx}. $brand: $revenue_fmt (${pct}%)"
        brand_idx=$((brand_idx + 1))
        if [[ $brand_idx -gt 3 ]]; then
          break
        fi
      done <<< "$BRAND_DATA"
    fi
  fi
fi

# Forecast
if [[ "$MODE" == "forecast" || "$MODE" == "full" ]]; then
  # Get historical data for forecasting
  MONTHLY_DATA=$(get_monthly_revenue "$MONTHS")
  
  if [[ -z "$MONTHLY_DATA" ]]; then
    echo "Error: No revenue data found for forecasting"
    exit 1
  fi
  
  # Parse data
  declare -a REVENUE_LIST
  while IFS=$'\t' read -r month campaigns creators revenue_net revenue_gross; do
    REVENUE_LIST+=("$revenue_net")
  done <<< "$MONTHLY_DATA"
  
  # Calculate average growth rate
  TOTAL_GROWTH=0
  GROWTH_COUNT=0
  declare -a GROWTH_RATES
  
  for ((i=1; i<${#REVENUE_LIST[@]}; i++)); do
    current=${REVENUE_LIST[$i]}
    previous=${REVENUE_LIST[$((i-1))]}
    growth=$(calc_growth "$current" "$previous")
    GROWTH_RATES+=("$growth")
    TOTAL_GROWTH=$(echo "$TOTAL_GROWTH + $growth" | bc -l)
    GROWTH_COUNT=$((GROWTH_COUNT + 1))
  done
  
  if [[ $GROWTH_COUNT -gt 0 ]]; then
    AVG_GROWTH_PCT=$(echo "scale=1; $TOTAL_GROWTH / $GROWTH_COUNT" | bc -l)
    AVG_GROWTH_DECIMAL=$(echo "scale=4; $AVG_GROWTH_PCT / 100" | bc -l)
  else
    AVG_GROWTH_PCT="0"
    AVG_GROWTH_DECIMAL="0"
  fi
  
  # Calculate volatility (standard deviation of growth rates)
  if [[ ${#GROWTH_RATES[@]} -gt 1 ]]; then
    SUM_SQ_DIFF=0
    for growth in "${GROWTH_RATES[@]}"; do
      diff=$(echo "$growth - $AVG_GROWTH_PCT" | bc -l)
      sq_diff=$(echo "$diff * $diff" | bc -l)
      SUM_SQ_DIFF=$(echo "$SUM_SQ_DIFF + $sq_diff" | bc -l)
    done
    VARIANCE=$(echo "scale=4; $SUM_SQ_DIFF / ${#GROWTH_RATES[@]}" | bc -l)
    VOLATILITY=$(echo "scale=4; sqrt($VARIANCE) / 100" | bc -l)
  else
    VOLATILITY="0.12"  # Default 12% volatility
  fi
  
  # Cap volatility at reasonable bounds
  if (( $(echo "$VOLATILITY > 0.25" | bc -l) )); then
    VOLATILITY="0.25"  # Max 25%
  elif (( $(echo "$VOLATILITY < 0.05" | bc -l) )); then
    VOLATILITY="0.05"  # Min 5%
  fi
  
  # Last month revenue (base for projection)
  LAST_REVENUE=${REVENUE_LIST[-1]}
  
  # Generate forecasts
  if [[ "$FORMAT" == "json" ]]; then
    echo "{"
    echo "  \"forecast_periods\": $FORECAST_PERIODS,"
    echo "  \"base_revenue\": $LAST_REVENUE,"
    echo "  \"avg_growth_rate\": $AVG_GROWTH_PCT,"
    echo "  \"volatility\": $VOLATILITY,"
    echo "  \"projections\": ["
    
    CURRENT_FORECAST=$LAST_REVENUE
    TOTAL_FORECAST=0
    
    for ((p=1; p<=$FORECAST_PERIODS; p++)); do
      # Apply growth rate
      CURRENT_FORECAST=$(echo "scale=2; $CURRENT_FORECAST * (1 + $AVG_GROWTH_DECIMAL)" | bc -l)
      
      # Calculate confidence range
      MIN_FORECAST=$(echo "scale=2; $CURRENT_FORECAST * (1 - $VOLATILITY)" | bc -l)
      MAX_FORECAST=$(echo "scale=2; $CURRENT_FORECAST * (1 + $VOLATILITY)" | bc -l)
      
      TOTAL_FORECAST=$(echo "$TOTAL_FORECAST + $CURRENT_FORECAST" | bc -l)
      
      # Future month (simplified: just increment)
      echo "    {"
      echo "      \"period\": $p,"
      echo "      \"forecast\": $CURRENT_FORECAST,"
      echo "      \"min\": $MIN_FORECAST,"
      echo "      \"max\": $MAX_FORECAST"
      echo -n "    }"
      if [[ $p -lt $FORECAST_PERIODS ]]; then
        echo ","
      else
        echo ""
      fi
    done
    
    echo "  ],"
    echo "  \"total_forecast\": $TOTAL_FORECAST"
    echo "}"
  else
    # Slack format
    if [[ "$MODE" == "full" ]]; then
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
    fi
    
    echo "🔮 *Projeção de Revenue - Próximos $FORECAST_PERIODS Meses*"
    echo ""
    echo "💡 *MÉTODO*"
    echo "• Base: Últimos $MONTHS meses"
    
    if (( $(echo "$AVG_GROWTH_PCT > 0" | bc -l) )); then
      echo "• Crescimento Médio: +${AVG_GROWTH_PCT}% m/m"
    elif (( $(echo "$AVG_GROWTH_PCT < 0" | bc -l) )); then
      echo "• Crescimento Médio: ${AVG_GROWTH_PCT}% m/m"
    else
      echo "• Crescimento Médio: ${AVG_GROWTH_PCT}% m/m"
    fi
    
    VOLATILITY_PCT=$(echo "scale=0; $VOLATILITY * 100" | bc -l)
    echo "• Volatilidade: ±${VOLATILITY_PCT}%"
    echo ""
    
    echo "📊 *PROJEÇÃO*"
    
    CURRENT_FORECAST=$LAST_REVENUE
    TOTAL_FORECAST=0
    
    # Get current month/year for future projections
    CURRENT_MONTH=$(date +%m)
    CURRENT_YEAR=$(date +%Y)
    
    for ((p=1; p<=$FORECAST_PERIODS; p++)); do
      # Apply growth rate
      CURRENT_FORECAST=$(echo "scale=2; $CURRENT_FORECAST * (1 + $AVG_GROWTH_DECIMAL)" | bc -l)
      
      # Calculate confidence range
      MIN_FORECAST=$(echo "scale=2; $CURRENT_FORECAST * (1 - $VOLATILITY)" | bc -l)
      MAX_FORECAST=$(echo "scale=2; $CURRENT_FORECAST * (1 + $VOLATILITY)" | bc -l)
      
      TOTAL_FORECAST=$(echo "$TOTAL_FORECAST + $CURRENT_FORECAST" | bc -l)
      
      # Format values
      forecast_fmt=$(format_currency "$CURRENT_FORECAST")
      min_fmt=$(format_currency "$MIN_FORECAST")
      max_fmt=$(format_currency "$MAX_FORECAST")
      
      # Calculate future month
      future_month=$(( (CURRENT_MONTH + p - 1) % 12 + 1 ))
      future_year=$(( CURRENT_YEAR + (CURRENT_MONTH + p - 1) / 12 ))
      month_label=$(printf "%04d-%02d" "$future_year" "$future_month")
      
      echo "• $month_label: $forecast_fmt (min: $min_fmt | max: $max_fmt)"
    done
    
    echo ""
    total_fmt=$(format_currency "$TOTAL_FORECAST")
    echo "💰 *TOTAL PROJETADO (próximos $FORECAST_PERIODS meses): $total_fmt*"
    
    echo ""
    echo "⚠️ *PREMISSAS*"
    if (( $(echo "$AVG_GROWTH_PCT > 0" | bc -l) )); then
      echo "• Mantém crescimento atual de +${AVG_GROWTH_PCT}% m/m"
    elif (( $(echo "$AVG_GROWTH_PCT < 0" | bc -l) )); then
      echo "• Considera queda atual de ${AVG_GROWTH_PCT}% m/m"
    else
      echo "• Mantém receita estável (sem crescimento)"
    fi
    echo "• Não considera sazonalidade ou eventos externos"
    echo "• Baseado em tendência linear dos últimos $MONTHS meses"
    echo "• Range de confiança baseado em volatilidade histórica"
  fi
fi
