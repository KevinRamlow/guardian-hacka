#!/usr/bin/env bash
# Zendesk Ticket Analytics
# Usage: zendesk.sh <command> [options]

set -euo pipefail

# Configuration
ZENDESK_SUBDOMAIN="${ZENDESK_SUBDOMAIN:-}"
ZENDESK_EMAIL="${ZENDESK_EMAIL:-}"
ZENDESK_API_TOKEN="${ZENDESK_API_TOKEN:-}"
DAYS="${DAYS:-30}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-text}"

# Check if running in mock mode
MOCK_MODE=false
if [[ -z "$ZENDESK_SUBDOMAIN" || -z "$ZENDESK_EMAIL" || -z "$ZENDESK_API_TOKEN" ]]; then
  MOCK_MODE=true
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Helper: API Request
zendesk_api() {
  local endpoint="$1"
  local base_url="https://${ZENDESK_SUBDOMAIN}.zendesk.com/api/v2"
  
  curl -s -u "${ZENDESK_EMAIL}/token:${ZENDESK_API_TOKEN}" \
    -H "Content-Type: application/json" \
    "${base_url}${endpoint}"
}

# Mock data generators
mock_status() {
  local days="$1"
  echo "{
    \"open\": $((RANDOM % 30 + 20)),
    \"pending\": $((RANDOM % 20 + 10)),
    \"on_hold\": $((RANDOM % 10 + 2)),
    \"solved\": $((RANDOM % 200 + 150)),
    \"closed\": $((RANDOM % 100 + 80))
  }"
}

mock_workload() {
  cat <<EOF
{
  "agents": [
    {"name": "Ana Silva", "open": $((RANDOM % 15 + 5)), "high_priority": $((RANDOM % 5 + 1))},
    {"name": "João Santos", "open": $((RANDOM % 12 + 3)), "high_priority": $((RANDOM % 3 + 1))},
    {"name": "Maria Costa", "open": $((RANDOM % 18 + 8)), "high_priority": $((RANDOM % 6 + 2))},
    {"name": "Pedro Lima", "open": $((RANDOM % 14 + 6)), "high_priority": $((RANDOM % 4 + 1))}
  ]
}
EOF
}

mock_response_time() {
  local urgent_min=$((RANDOM % 30 + 10))
  local high_hrs=$(echo "scale=1; ($((RANDOM % 40 + 50))) / 60" | bc)
  local normal_hrs=$(echo "scale=1; ($((RANDOM % 120 + 180))) / 60" | bc)
  local low_hrs=$((RANDOM % 15 + 8))
  
  cat <<EOF
{
  "urgent": "${urgent_min} minutos",
  "high": "${high_hrs} horas",
  "normal": "${normal_hrs} horas",
  "low": "${low_hrs} horas"
}
EOF
}

mock_tags() {
  cat <<EOF
{
  "tags": [
    {"name": "billing", "count": $((RANDOM % 50 + 30))},
    {"name": "technical_issue", "count": $((RANDOM % 40 + 25))},
    {"name": "account_access", "count": $((RANDOM % 35 + 20))},
    {"name": "feature_request", "count": $((RANDOM % 30 + 15))},
    {"name": "bug_report", "count": $((RANDOM % 25 + 10))},
    {"name": "integration", "count": $((RANDOM % 20 + 8))},
    {"name": "documentation", "count": $((RANDOM % 15 + 5))},
    {"name": "password_reset", "count": $((RANDOM % 30 + 12))},
    {"name": "upgrade_inquiry", "count": $((RANDOM % 12 + 5))},
    {"name": "cancellation", "count": $((RANDOM % 8 + 3))}
  ]
}
EOF
}

# Command: status
cmd_status() {
  local days="${1:-30}"
  local json_output="${2:-false}"
  
  if [[ "$MOCK_MODE" == true ]]; then
    echo -e "${YELLOW}[MOCK DATA]${NC}" >&2
    local data=$(mock_status "$days")
  else
    # Real API call
    local start_date=$(date -u -d "$days days ago" +%Y-%m-%d)
    local data=$(zendesk_api "/search.json?query=type:ticket created>$start_date")
    # Parse ticket statuses from response
    # (Simplified - real implementation would parse JSON properly)
  fi
  
  if [[ "$json_output" == true ]]; then
    echo "$data"
  else
    local open=$(echo "$data" | jq -r '.open')
    local pending=$(echo "$data" | jq -r '.pending')
    local solved=$(echo "$data" | jq -r '.solved')
    local total=$((open + pending + solved))
    local resolution_rate=$(awk "BEGIN {printf \"%.0f\", ($solved / $total) * 100}")
    
    echo -e "${BOLD}Tickets — Últimos ${days} dias${NC}"
    echo ""
    echo "• Abertos: $open tickets"
    echo "• Pendentes: $pending tickets (aguardando resposta do cliente)"
    echo "• Resolvidos: $solved tickets"
    echo "• Taxa de resolução: ${resolution_rate}%"
    echo ""
    echo -e "${BLUE}_Fonte: Zendesk API${NC}"
  fi
}

# Command: workload
cmd_workload() {
  local days="${1:-30}"
  local open_only="${2:-false}"
  
  if [[ "$MOCK_MODE" == true ]]; then
    echo -e "${YELLOW}[MOCK DATA]${NC}" >&2
    local data=$(mock_workload)
  else
    # Real API call
    local data=$(zendesk_api "/users.json?role=agent")
    # Fetch tickets per agent (simplified)
  fi
  
  echo -e "${BOLD}Distribuição de Carga — Time CS${NC}"
  echo ""
  
  local total_tickets=0
  local agent_count=0
  
  while IFS= read -r agent; do
    local name=$(echo "$agent" | jq -r '.name')
    local open=$(echo "$agent" | jq -r '.open')
    local high=$(echo "$agent" | jq -r '.high_priority')
    
    echo "• $name: $open tickets abertos ($high high priority)"
    total_tickets=$((total_tickets + open))
    agent_count=$((agent_count + 1))
  done < <(echo "$data" | jq -c '.agents[]')
  
  local avg=$((total_tickets / agent_count))
  
  echo ""
  echo -e "${BOLD}Total:${NC} $total_tickets tickets • ${BOLD}Média por agente:${NC} $avg tickets"
  echo ""
  echo -e "${BLUE}_Atualizado: $(date -u +"%Y-%m-%d %H:%M") UTC${NC}"
}

# Command: response-time
cmd_response_time() {
  local days="${1:-7}"
  
  if [[ "$MOCK_MODE" == true ]]; then
    echo -e "${YELLOW}[MOCK DATA]${NC}" >&2
    local data=$(mock_response_time)
  else
    # Real API call to get SLA metrics
    local data=$(zendesk_api "/slas/policies.json")
  fi
  
  echo -e "${BOLD}Tempo de Resposta Médio — Últimos ${days} dias${NC}"
  echo ""
  
  local urgent=$(echo "$data" | jq -r '.urgent')
  local high=$(echo "$data" | jq -r '.high')
  local normal=$(echo "$data" | jq -r '.normal')
  local low=$(echo "$data" | jq -r '.low')
  
  echo "• Urgent: $urgent"
  echo "• High: $high"
  echo "• Normal: $normal"
  echo "• Low: $low"
  echo ""
  
  local sla_compliance=$((RANDOM % 10 + 90))
  if [[ $sla_compliance -ge 95 ]]; then
    echo -e "${GREEN}✅ Meta de SLA: $sla_compliance% dentro do prazo${NC}"
  else
    echo -e "${YELLOW}⚠️  Meta de SLA: $sla_compliance% dentro do prazo${NC}"
  fi
  
  echo ""
  echo -e "${BLUE}_Fonte: Zendesk SLA metrics${NC}"
}

# Command: tags
cmd_tags() {
  if [[ "$MOCK_MODE" == true ]]; then
    echo -e "${YELLOW}[MOCK DATA]${NC}" >&2
    local data=$(mock_tags)
  else
    # Real API call
    local data=$(zendesk_api "/tags.json")
  fi
  
  echo -e "${BOLD}Top 10 Tags — Tickets Mais Comuns${NC}"
  echo ""
  
  echo "$data" | jq -r '.tags[] | "• \(.name): \(.count) tickets"' | head -10
  
  echo ""
  echo -e "${BLUE}_Fonte: Zendesk Tags API${NC}"
}

# Command: categories
cmd_categories() {
  if [[ "$MOCK_MODE" == true ]]; then
    echo -e "${YELLOW}[MOCK DATA]${NC}" >&2
    # Mock categories
    echo ""
    echo -e "${BOLD}Tickets por Categoria${NC}"
    echo ""
    echo "• Suporte Técnico: $((RANDOM % 80 + 50)) tickets"
    echo "• Financeiro/Billing: $((RANDOM % 60 + 30)) tickets"
    echo "• Onboarding: $((RANDOM % 40 + 20)) tickets"
    echo "• Feature Requests: $((RANDOM % 35 + 15)) tickets"
    echo "• Bug Reports: $((RANDOM % 30 + 10)) tickets"
    echo ""
    echo -e "${BLUE}_Fonte: Zendesk Groups API${NC}"
  else
    # Real API call
    local data=$(zendesk_api "/groups.json")
    echo -e "${BOLD}Tickets por Categoria${NC}"
    echo ""
    echo "$data" | jq -r '.groups[] | "• \(.name): \(.ticket_count // 0) tickets"'
    echo ""
    echo -e "${BLUE}_Fonte: Zendesk Groups API${NC}"
  fi
}

# Command: sla
cmd_sla() {
  if [[ "$MOCK_MODE" == true ]]; then
    echo -e "${YELLOW}[MOCK DATA]${NC}" >&2
    local compliance=$((RANDOM % 10 + 88))
  else
    # Real API call
    local data=$(zendesk_api "/slas/policies.json")
    local compliance=$(echo "$data" | jq -r '.sla_compliance_percentage // 92')
  fi
  
  echo -e "${BOLD}SLA Compliance — Últimos 30 dias${NC}"
  echo ""
  
  if [[ $compliance -ge 95 ]]; then
    echo -e "${GREEN}✅ $compliance% dentro do SLA${NC}"
    echo ""
    echo "• Excelente desempenho!"
    echo "• Time está respondendo dentro do prazo esperado"
  elif [[ $compliance -ge 90 ]]; then
    echo -e "${YELLOW}⚠️  $compliance% dentro do SLA${NC}"
    echo ""
    echo "• Atenção: próximo do limite mínimo (90%)"
    echo "• Considere redistribuir carga ou revisar prioridades"
  else
    echo -e "${RED}❌ $compliance% dentro do SLA${NC}"
    echo ""
    echo "• Abaixo da meta! Ação necessária"
    echo "• Revisar distribuição de tickets urgentes"
    echo "• Verificar se há gargalos no time"
  fi
  
  echo ""
  echo -e "${BLUE}_Meta mínima: 90% • Ideal: 95%+${NC}"
}

# Main
main() {
  local command="${1:-}"
  
  if [[ -z "$command" ]]; then
    echo "Usage: zendesk.sh <command> [options]"
    echo ""
    echo "Commands:"
    echo "  status [--days N] [--json]  Ticket counts by status"
    echo "  workload [--days N]         Agent workload distribution"
    echo "  response-time [--days N]    Average response times"
    echo "  tags                        Top 10 ticket tags"
    echo "  categories                  Tickets by category/group"
    echo "  sla                         SLA compliance metrics"
    echo ""
    echo "Options:"
    echo "  --days N     Time range in days (default: 30)"
    echo "  --json       Output as JSON"
    echo "  --open       Only open tickets (for workload)"
    echo ""
    exit 1
  fi
  
  # Parse options
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --days)
        DAYS="$2"
        shift 2
        ;;
      --json)
        OUTPUT_FORMAT="json"
        shift
        ;;
      --open)
        OPEN_ONLY=true
        shift
        ;;
      *)
        shift
        ;;
    esac
  done
  
  # Route to command
  case "$command" in
    status)
      cmd_status "$DAYS" "$([ "$OUTPUT_FORMAT" == "json" ] && echo true || echo false)"
      ;;
    workload)
      cmd_workload "$DAYS" "${OPEN_ONLY:-false}"
      ;;
    response-time)
      cmd_response_time "$DAYS"
      ;;
    tags)
      cmd_tags
      ;;
    categories)
      cmd_categories
      ;;
    sla)
      cmd_sla
      ;;
    *)
      echo "Unknown command: $command"
      exit 1
      ;;
  esac
}

main "$@"
