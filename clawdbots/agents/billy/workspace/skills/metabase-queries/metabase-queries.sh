#!/bin/bash
# metabase-queries.sh — Instant answers to common Metabase questions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORMAT="${FORMAT:-text}"
QUERY_TYPE=""

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Run pre-built queries replacing common Metabase dashboards.

OPTIONS:
  --query <type>      Run specific query type:
                        campaigns    - Campaign counts by status
                        gmv          - Total GMV/revenue
                        creators     - Creator signup counts
                        moderation   - Moderation queue stats
                        top          - Top campaigns by engagement
  --quick             Quick overview (all queries, summarized)
  --all               Run all queries (detailed)
  --format <fmt>      Output format: text (default) or json
  -h, --help          Show this help

EXAMPLES:
  $0 --query gmv
  $0 --query campaigns
  $0 --quick
  $0 --all --format json
EOF
  exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --query)
      QUERY_TYPE="$2"
      shift 2
      ;;
    --quick)
      QUERY_TYPE="quick"
      shift
      ;;
    --all)
      QUERY_TYPE="all"
      shift
      ;;
    --format)
      FORMAT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

if [[ -z "$QUERY_TYPE" ]]; then
  usage
fi

# MySQL command wrapper
run_mysql() {
  local query="$1"
  mysql -N -e "$query" 2>/dev/null || echo "Error running query"
}

# JSON output helper
json_field() {
  local key="$1"
  local value="$2"
  echo "  \"$key\": \"$value\""
}

# Query 1: Campaign Counts by Status
query_campaigns() {
  if [[ "$FORMAT" == "json" ]]; then
    echo "{"
    echo "  \"query\": \"campaigns\","
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"results\": ["
  else
    echo -e "${BOLD}${BLUE}📊 Campanhas por Status${NC}\n"
  fi

  local result=$(run_mysql "
    SELECT 
      campaign_state_id,
      COUNT(*) AS total,
      COUNT(CASE WHEN created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY) THEN 1 END) AS ultimos_7d,
      COUNT(CASE WHEN created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY) THEN 1 END) AS ultimos_30d
    FROM campaigns
    WHERE deleted_at IS NULL
    GROUP BY campaign_state_id
    ORDER BY total DESC;
  ")

  if [[ "$FORMAT" == "json" ]]; then
    local first=true
    while IFS=$'\t' read -r status total last7d last30d; do
      [[ "$first" == true ]] && first=false || echo ","
      echo "    {\"status\": \"$status\", \"total\": $total, \"last_7d\": $last7d, \"last_30d\": $last30d}"
    done <<< "$result"
    echo "  ]"
    echo "}"
  else
    local total_all=0
    while IFS=$'\t' read -r status total last7d last30d; do
      echo -e "  ${GREEN}${status}:${NC} $total campanhas (${last7d} nos últimos 7d, ${last30d} nos últimos 30d)"
      total_all=$((total_all + total))
    done <<< "$result"
    echo -e "\n  ${BOLD}Total: $total_all campanhas${NC}\n"
  fi
}

# Query 2: Total GMV / Revenue
query_gmv() {
  if [[ "$FORMAT" == "json" ]]; then
    echo "{"
    echo "  \"query\": \"gmv\","
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  else
    echo -e "${BOLD}${BLUE}💰 GMV / Revenue${NC}\n"
  fi

  # Total GMV (all time)
  local total=$(run_mysql "
    SELECT 
      value_currency,
      COUNT(DISTINCT creator_id) AS criadores_pagos,
      COUNT(*) AS total_pagamentos,
      ROUND(SUM(value), 2) AS gmv_net,
      ROUND(SUM(gross_value), 2) AS gmv_gross,
      ROUND(AVG(value), 2) AS pagamento_medio
    FROM creator_payment_history
    WHERE payment_status IN ('complete', 'partial');
  ")

  # GMV by period
  local period=$(run_mysql "
    SELECT 
      CASE 
        WHEN date_of_transaction >= DATE_SUB(NOW(), INTERVAL 7 DAY) THEN 'ultimos_7d'
        WHEN date_of_transaction >= DATE_SUB(NOW(), INTERVAL 30 DAY) THEN 'ultimos_30d'
        WHEN date_of_transaction >= DATE_SUB(NOW(), INTERVAL 90 DAY) THEN 'ultimos_90d'
      END AS periodo,
      COUNT(DISTINCT creator_id) AS criadores,
      ROUND(SUM(value), 2) AS gmv_net
    FROM creator_payment_history
    WHERE payment_status IN ('complete', 'partial')
      AND date_of_transaction >= DATE_SUB(NOW(), INTERVAL 90 DAY)
    GROUP BY periodo
    ORDER BY 
      CASE periodo
        WHEN 'ultimos_7d' THEN 1
        WHEN 'ultimos_30d' THEN 2
        WHEN 'ultimos_90d' THEN 3
      END;
  ")

  if [[ "$FORMAT" == "json" ]]; then
    echo "  \"total\": {"
    while IFS=$'\t' read -r currency creators payments net gross avg; do
      echo "    \"currency\": \"$currency\","
      echo "    \"creators_paid\": $creators,"
      echo "    \"total_payments\": $payments,"
      echo "    \"gmv_net\": $net,"
      echo "    \"gmv_gross\": $gross,"
      echo "    \"avg_payment\": $avg"
    done <<< "$total"
    echo "  },"
    echo "  \"by_period\": ["
    local first=true
    while IFS=$'\t' read -r periodo creators gmv; do
      [[ "$first" == true ]] && first=false || echo ","
      echo "    {\"period\": \"$periodo\", \"creators\": $creators, \"gmv_net\": $gmv}"
    done <<< "$period"
    echo "  ]"
    echo "}"
  else
    echo -e "${BOLD}Total (all time):${NC}"
    while IFS=$'\t' read -r currency creators payments net gross avg; do
      echo -e "  GMV Net: ${GREEN}$currency $net${NC} | GMV Gross: $currency $gross"
      echo -e "  Criadores pagos: $creators | Pagamentos: $payments"
      echo -e "  Pagamento médio: $currency $avg"
    done <<< "$total"
    
    echo -e "\n${BOLD}Por período:${NC}"
    while IFS=$'\t' read -r periodo creators gmv; do
      echo -e "  ${YELLOW}$periodo:${NC} R$ $gmv ($creators criadores)"
    done <<< "$period"
    echo ""
  fi
}

# Query 3: Creator Signup Counts
query_creators() {
  if [[ "$FORMAT" == "json" ]]; then
    echo "{"
    echo "  \"query\": \"creators\","
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"results\": ["
  else
    echo -e "${BOLD}${BLUE}👥 Cadastros de Criadores${NC}\n"
  fi

  local weekly=$(run_mysql "
    SELECT 
      CASE 
        WHEN a.created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY) THEN 'esta_semana'
        WHEN a.created_at >= DATE_SUB(NOW(), INTERVAL 14 DAY) THEN 'semana_passada'
      END AS periodo,
      COUNT(DISTINCT a.creator_id) AS novos_criadores
    FROM actions a
    WHERE a.created_at >= DATE_SUB(NOW(), INTERVAL 14 DAY)
    GROUP BY periodo
    ORDER BY 
      CASE periodo
        WHEN 'esta_semana' THEN 1
        WHEN 'semana_passada' THEN 2
      END;
  ")

  if [[ "$FORMAT" == "json" ]]; then
    local first=true
    while IFS=$'\t' read -r periodo total completo taxa; do
      [[ "$first" == true ]] && first=false || echo ","
      echo "    {\"period\": \"$periodo\", \"signups\": $total, \"onboarding_complete\": $completo, \"completion_rate\": $taxa}"
    done <<< "$weekly"
    echo "  ]"
    echo "}"
  else
    local this_week=0
    local last_week=0
    while IFS=$'\t' read -r periodo total completo taxa; do
      if [[ "$periodo" == "esta_semana" ]]; then
        echo -e "  ${GREEN}Esta semana:${NC} $total novos criadores ($completo completaram onboarding — $taxa%)"
        this_week=$total
      else
        echo -e "  Semana passada: $total novos criadores ($completo completaram — $taxa%)"
        last_week=$total
      fi
    done <<< "$weekly"
    
    if [[ $last_week -gt 0 ]]; then
      local change=$(( (this_week - last_week) * 100 / last_week ))
      if [[ $change -gt 0 ]]; then
        echo -e "\n  Variação: ${GREEN}+$change%${NC} 📈"
      else
        echo -e "\n  Variação: ${RED}$change%${NC} 📉"
      fi
    fi
    echo ""
  fi
}

# Query 4: Moderation Queue Stats
query_moderation() {
  if [[ "$FORMAT" == "json" ]]; then
    echo "{"
    echo "  \"query\": \"moderation\","
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"results\": ["
  else
    echo -e "${BOLD}${BLUE}📋 Fila de Moderação${NC}\n"
  fi

  local queue=$(run_mysql "
    SELECT 
      CASE 
        WHEN pm.is_approved IS NULL THEN 'pendente'
        WHEN pm.is_approved = 1 THEN 'aprovado'
        WHEN pm.is_approved = 0 AND pmc.id IS NOT NULL THEN 'recusado_contestado'
        WHEN pm.is_approved = 0 THEN 'recusado'
      END AS status,
      COUNT(*) AS total,
      COUNT(CASE WHEN pm.created_at >= DATE_SUB(NOW(), INTERVAL 24 HOUR) THEN 1 END) AS ultimas_24h
    FROM proofread_medias pm
    LEFT JOIN proofread_media_contest pmc ON pmc.proofread_media_id = pm.id
    WHERE pm.deleted_at IS NULL
      AND pm.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
    GROUP BY status
    ORDER BY 
      CASE status
        WHEN 'pendente' THEN 1
        WHEN 'recusado_contestado' THEN 2
        WHEN 'aprovado' THEN 3
        WHEN 'recusado' THEN 4
      END;
  ")

  if [[ "$FORMAT" == "json" ]]; then
    local first=true
    while IFS=$'\t' read -r status total last24h; do
      [[ "$first" == true ]] && first=false || echo ","
      echo "    {\"status\": \"$status\", \"total\": $total, \"last_24h\": $last24h}"
    done <<< "$queue"
    echo "  ]"
    echo "}"
  else
    while IFS=$'\t' read -r status total last24h; do
      case "$status" in
        pendente)
          echo -e "  ${YELLOW}Pendentes:${NC} $total conteúdos ($last24h nas últimas 24h)"
          ;;
        aprovado)
          echo -e "  ${GREEN}Aprovados:${NC} $total"
          ;;
        recusado)
          echo -e "  ${RED}Recusados:${NC} $total"
          ;;
        recusado_contestado)
          echo -e "  ${RED}Recusados (contestados):${NC} $total"
          ;;
      esac
    done <<< "$queue"
    echo ""
  fi
}

# Query 5: Top Campaigns by Engagement
query_top_campaigns() {
  if [[ "$FORMAT" == "json" ]]; then
    echo "{"
    echo "  \"query\": \"top_campaigns\","
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"results\": ["
  else
    echo -e "${BOLD}${BLUE}🔥 Top Campanhas (últimos 30 dias)${NC}\n"
  fi

  local top=$(run_mysql "
    SELECT 
      c.title AS campanha,
      c.campaign_state_id AS status,
      b.name AS marca,
      COUNT(DISTINCT pm.creator_id) AS criadores_ativos,
      COUNT(pm.id) AS conteudos_submetidos,
      ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100, 1) AS taxa_aprovacao
    FROM campaigns c
    JOIN brands b ON c.brand_id = b.id
    LEFT JOIN proofread_medias pm ON pm.campaign_id = c.id 
      AND pm.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
      AND pm.deleted_at IS NULL
    WHERE c.campaign_state_id = 'active'
    GROUP BY c.id, c.title, c.campaign_state_id, b.name
    HAVING conteudos_submetidos > 0
    ORDER BY conteudos_submetidos DESC
    LIMIT 10;
  ")

  if [[ "$FORMAT" == "json" ]]; then
    local first=true
    while IFS=$'\t' read -r campanha status marca criadores conteudos taxa; do
      [[ "$first" == true ]] && first=false || echo ","
      echo "    {\"campaign\": \"$campanha\", \"brand\": \"$marca\", \"creators\": $criadores, \"content\": $conteudos, \"approval_rate\": $taxa}"
    done <<< "$top"
    echo "  ]"
    echo "}"
  else
    local rank=1
    while IFS=$'\t' read -r campanha status marca criadores conteudos taxa; do
      echo -e "${BOLD}$rank. $campanha${NC} ($marca)"
      echo -e "   $conteudos conteúdos | $criadores criadores | taxa aprovação: $taxa%"
      echo ""
      rank=$((rank + 1))
    done <<< "$top"
  fi
}

# Quick overview (all queries, summarized)
query_quick() {
  echo -e "${BOLD}${BLUE}⚡ Quick Overview${NC}\n"
  
  # Campaigns
  local campaigns=$(run_mysql "SELECT campaign_state_id, COUNT(*) FROM campaigns WHERE deleted_at IS NULL GROUP BY campaign_state_id ORDER BY COUNT(*) DESC;")
  echo -e "${BOLD}Campanhas:${NC}"
  while IFS=$'\t' read -r status count; do
    echo "  $status: $count"
  done <<< "$campaigns"
  
  # GMV last 30d
  local gmv=$(run_mysql "SELECT ROUND(SUM(value), 2) FROM creator_payment_history WHERE payment_status IN ('complete', 'partial') AND created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY);")
  echo -e "\n${BOLD}GMV (últimos 30d):${NC} R$ $gmv"
  
  # Creators this week
  local creators=$(run_mysql "SELECT COUNT(*) FROM creators WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY);")
  echo -e "${BOLD}Novos criadores (esta semana):${NC} $creators"
  
  # Pending moderation
  local pending=$(run_mysql "SELECT COUNT(*) FROM proofread_medias WHERE is_approved IS NULL AND deleted_at IS NULL AND created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY);")
  echo -e "${BOLD}Moderação pendente:${NC} $pending conteúdos"
  
  echo ""
}

# Run all queries
query_all() {
  query_campaigns
  echo ""
  query_gmv
  echo ""
  query_creators
  echo ""
  query_moderation
  echo ""
  query_top_campaigns
}

# Main execution
case "$QUERY_TYPE" in
  campaigns)
    query_campaigns
    ;;
  gmv)
    query_gmv
    ;;
  creators)
    query_creators
    ;;
  moderation)
    query_moderation
    ;;
  top)
    query_top_campaigns
    ;;
  quick)
    query_quick
    ;;
  all)
    query_all
    ;;
  *)
    echo "Unknown query type: $QUERY_TYPE"
    usage
    ;;
esac
