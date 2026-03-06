#!/bin/bash
# Sales Enablement — Campaign Success Stories for Pitches
# Usage: ./sales-enablement.sh [--top N] [--brand NAME] [--campaign-id ID] [--metric METRIC] [--export-sheets] [--year YYYY]

set -euo pipefail

# Default values
TOP_N=10
BRAND=""
CAMPAIGN_ID=""
METRIC="approval_rate"
EXPORT_SHEETS=false
YEAR=""
FORMAT="narrative"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --top)
      TOP_N="$2"
      shift 2
      ;;
    --brand)
      BRAND="$2"
      shift 2
      ;;
    --campaign-id)
      CAMPAIGN_ID="$2"
      shift 2
      ;;
    --metric)
      METRIC="$2"
      shift 2
      ;;
    --export-sheets)
      EXPORT_SHEETS=true
      shift
      ;;
    --year)
      YEAR="$2"
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

# Get platform average for last 6 months
get_platform_baseline() {
  mysql -N -e "
    SELECT 
      ROUND(AVG(approval_rate), 1),
      ROUND(AVG(total_creators), 0),
      ROUND(AVG(total_content), 0),
      ROUND(AVG(contest_rate), 1)
    FROM (
      SELECT 
        c.id,
        SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100 AS approval_rate,
        COUNT(DISTINCT pm.creator_id) AS total_creators,
        COUNT(DISTINCT pm.id) AS total_content,
        COUNT(DISTINCT pmc.id) / NULLIF(COUNT(DISTINCT pm.id), 0) * 100 AS contest_rate
      FROM \`db-maestro-prod\`.campaigns c
      LEFT JOIN \`db-maestro-prod\`.proofread_medias pm ON pm.campaign_id = c.id AND pm.deleted_at IS NULL
      LEFT JOIN \`db-maestro-prod\`.proofread_media_contest pmc ON pmc.proofread_media_id = pm.id
      WHERE c.published_at >= DATE_SUB(NOW(), INTERVAL 6 MONTH)
        AND c.deleted_at IS NULL
      GROUP BY c.id
      HAVING total_content >= 10
    ) AS campaign_stats;
  " | tr '\t' '|'
}

# Format currency
format_currency() {
  local value="$1"
  if [[ "$value" == "NULL" ]] || [[ -z "$value" ]]; then
    echo "R$ 0,00"
  else
    printf "R$ %'.2f\n" "$value" | sed 's/\./,/g; s/,\([0-9]\{2\}\)$/.\1/'
  fi
}

# Single campaign success story
campaign_story() {
  local campaign_id=$1
  
  # Query returns pipe-delimited fields
  local data=$(mysql -N -e "
    SELECT 
      c.title,
      b.name,
      c.budget,
      COALESCE(c.main_objective, 'N/A'),
      DATE_FORMAT(c.published_at, '%d/%m/%Y'),
      COUNT(DISTINCT pm.creator_id),
      COUNT(DISTINCT pm.id),
      SUM(pm.is_approved = 1),
      SUM(pm.is_approved = 0),
      ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100, 1),
      COUNT(DISTINCT pmc.id),
      ROUND(COUNT(DISTINCT pmc.id) / NULLIF(COUNT(DISTINCT pm.id), 0) * 100, 1),
      ROUND(COALESCE(SUM(cph.value), 0), 2),
      ROUND(COALESCE(SUM(cph.gross_value), 0), 2),
      ROUND(COALESCE(SUM(cph.value), 0) / NULLIF(c.budget, 0) * 100, 1),
      COUNT(DISTINCT cph.id),
      ROUND(COALESCE(AVG(cph.value), 0), 2),
      COALESCE(SUM(cph.payment_status = 'complete'), 0),
      COALESCE(SUM(cph.payment_status = 'partial'), 0),
      COALESCE(SUM(cph.payment_status = 'in_process'), 0),
      COALESCE(DATEDIFF(MAX(pm.created_at), c.published_at), 0),
      DATE_FORMAT(MAX(pm.created_at), '%d/%m/%Y')
    FROM \`db-maestro-prod\`.campaigns c
    JOIN \`db-maestro-prod\`.brands b ON c.brand_id = b.id
    LEFT JOIN \`db-maestro-prod\`.proofread_medias pm ON pm.campaign_id = c.id AND pm.deleted_at IS NULL
    LEFT JOIN \`db-maestro-prod\`.proofread_media_contest pmc ON pmc.proofread_media_id = pm.id
    LEFT JOIN \`db-maestro-prod\`.creator_payment_history cph ON cph.campaign_id = c.id
    WHERE c.id = $campaign_id
    GROUP BY c.id, c.title, b.name, c.budget, c.main_objective, c.published_at;
  " | tr '\t' '|')
  
  if [[ -z "$data" ]]; then
    echo "❌ Campanha não encontrada (ID: $campaign_id)"
    return 1
  fi
  
  IFS='|' read -r campaign_name brand budget main_objective published_at total_creators total_content approved_content refused_content approval_rate contests contest_rate total_paid_net total_paid_gross budget_utilization total_payments avg_creator_payment payments_complete payments_partial payments_in_process campaign_duration_days last_submission <<< "$data"
  
  # Get platform baseline
  local baseline=$(get_platform_baseline)
  IFS='|' read -r platform_avg _ _ platform_contest <<< "$baseline"
  
  # Handle NULL values
  approval_rate=${approval_rate:-0.0}
  contest_rate=${contest_rate:-0.0}
  total_creators=${total_creators:-0}
  campaign_duration_days=${campaign_duration_days:-0}
  
  # Calculate velocity
  local velocity="standard"
  if [[ $(echo "$campaign_duration_days < 21" | bc) -eq 1 ]]; then
    velocity="fast"
  elif [[ $(echo "$campaign_duration_days > 60" | bc) -eq 1 ]]; then
    velocity="extended"
  fi
  
  # Calculate approval delta
  local approval_delta=$(echo "$approval_rate - $platform_avg" | bc)
  local approval_indicator="="
  if [[ $(echo "$approval_delta > 0" | bc) -eq 1 ]]; then
    approval_indicator="acima"
  elif [[ $(echo "$approval_delta < 0" | bc) -eq 1 ]]; then
    approval_indicator="abaixo"
    approval_delta=$(echo "$approval_delta * -1" | bc)
  fi
  
  # Format output
  cat <<EOF
📊 Case de Sucesso: $campaign_name
Marca: $brand | Objetivo: $main_objective

✨ DESTAQUES
• $total_creators creators engajados gerando $total_content conteúdos de alta qualidade
• Taxa de aprovação de ${approval_rate}% — ${approval_delta}pp $approval_indicator da média da plataforma
• ${budget_utilization}% do budget utilizado de forma eficiente
• Campanha concluída em $campaign_duration_days dias — $velocity velocity
• Apenas ${contest_rate}% de contestações — conteúdo de excelente qualidade

💰 INVESTIMENTO & ROI
• Budget: $(format_currency $budget)
• Investido: $(format_currency $total_paid_net) (${budget_utilization}%)
• Pagamento médio por creator: $(format_currency $avg_creator_payment)
• $payments_complete pagamentos completos de $total_payments totais

📈 PERFORMANCE
• $approved_content conteúdos aprovados de $total_content submetidos
• $total_creators creators ativos
• Taxa de aprovação: ${approval_rate}% (média da plataforma: ${platform_avg}%)
• $contests contestações (${contest_rate}%) — quality indicator

🎯 CONTEXTO
Publicada em $published_at, essa campanha demonstra $(get_success_insight "$approval_rate" "$contest_rate" "$total_creators" "$campaign_duration_days").

EOF
}

# Get success insight based on metrics
get_success_insight() {
  local approval=$1
  local contest=$2
  local creators=$3
  local duration=$4
  
  local insights=()
  
  if [[ $(echo "$approval >= 85" | bc) -eq 1 ]]; then
    insights+=("excelente alinhamento de brief e guidelines")
  fi
  
  if [[ $(echo "$contest < 2" | bc) -eq 1 ]]; then
    insights+=("guidelines claras e conteúdo de alta qualidade")
  fi
  
  if [[ $(echo "$duration < 30" | bc) -eq 1 ]]; then
    insights+=("alto engajamento e execução rápida")
  fi
  
  if [[ $creators -gt 50 ]]; then
    insights+=("campanha de grande escala com forte participação")
  fi
  
  # Join insights
  local result=""
  if [[ ${#insights[@]} -eq 0 ]]; then
    result="performance consistente"
  else
    for i in "${!insights[@]}"; do
      if [[ $i -eq 0 ]]; then
        result="${insights[$i]}"
      else
        result="$result, ${insights[$i]}"
      fi
    done
  fi
  
  echo "$result"
}

# Top campaigns list
top_campaigns() {
  local limit=$1
  local order_by="approval_rate DESC, total_creators DESC"
  
  # Simple version - get campaign IDs first, then format output
  echo "🏆 TOP $limit CAMPANHAS — Últimos 6 Meses"
  echo ""
  
  # Get campaign data with proper GROUP BY
  mysql -N -e "
    SELECT 
      c.id,
      c.title,
      b.name,
      COUNT(DISTINCT pm.creator_id) AS total_creators,
      COUNT(DISTINCT pm.id) AS total_content,
      ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100, 1) AS approval_rate,
      ROUND(COALESCE(SUM(cph.value), 0), 2) AS total_paid,
      COALESCE(DATEDIFF(MAX(pm.created_at), c.published_at), 0) AS campaign_duration_days,
      ROUND(COALESCE(SUM(cph.value), 0) / NULLIF(c.budget, 0) * 100, 1) AS budget_utilization
    FROM \`db-maestro-prod\`.campaigns c
    JOIN \`db-maestro-prod\`.brands b ON c.brand_id = b.id
    LEFT JOIN \`db-maestro-prod\`.proofread_medias pm ON pm.campaign_id = c.id AND pm.deleted_at IS NULL
    LEFT JOIN \`db-maestro-prod\`.creator_payment_history cph ON cph.campaign_id = c.id
    WHERE c.published_at >= DATE_SUB(NOW(), INTERVAL 6 MONTH)
      AND c.deleted_at IS NULL
    GROUP BY c.id, c.title, b.name, c.budget, c.published_at
    HAVING total_creators >= 10 AND total_content >= 30
    ORDER BY approval_rate DESC, total_creators DESC
    LIMIT $limit;
  " | while IFS=$'\t' read -r campaign_id campaign_name brand total_creators total_content approval_rate total_paid campaign_duration_days budget_utilization; do
    local rank=$((rank + 1))
    local emoji=""
    case $rank in
      1) emoji="1️⃣" ;;
      2) emoji="2️⃣" ;;
      3) emoji="3️⃣" ;;
      4) emoji="4️⃣" ;;
      5) emoji="5️⃣" ;;
      6) emoji="6️⃣" ;;
      7) emoji="7️⃣" ;;
      8) emoji="8️⃣" ;;
      9) emoji="9️⃣" ;;
      10) emoji="🔟" ;;
      *) emoji="  " ;;
    esac
    
    # Determine highlight
    local highlight=""
    approval_rate=${approval_rate:-0}
    if [[ $(echo "$approval_rate >= 90" | bc) -eq 1 ]]; then
      highlight="Taxa de aprovação excepcional"
    elif [[ $total_creators -gt 100 ]]; then
      highlight="Grande escala de participação"
    elif [[ $campaign_duration_days -lt 21 ]]; then
      highlight="Execução rápida"
    else
      highlight="Performance consistente"
    fi
    
    echo "$emoji $campaign_name — $brand"
    echo "   • $total_creators creators | $total_content conteúdos | ${approval_rate}% aprovação"
    echo "   • $(format_currency $total_paid) investido | $campaign_duration_days dias de duração"
    echo "   • Destaque: $highlight"
    echo ""
  done
  
  # Add platform baseline
  local baseline=$(get_platform_baseline)
  IFS='|' read -r platform_avg avg_creators avg_content platform_contest <<< "$baseline"
  
  cat <<EOF
📊 Média da Plataforma (6 meses)
• Aprovação: ${platform_avg}% | Creators/campanha: ${avg_creators} | Conteúdo/campanha: ${avg_content}
• Taxa de contestação: ${platform_contest}%

💡 Insight: As campanhas de maior sucesso apresentam briefs claros, guidelines bem definidas, e ofertas atrativas para creators.
EOF
}

# Brand performance summary
brand_performance() {
  local brand_name=$1
  local year_filter=""
  
  if [[ -n $YEAR ]]; then
    year_filter="AND YEAR(c.published_at) = $YEAR"
  else
    year_filter="AND c.published_at >= DATE_SUB(NOW(), INTERVAL 12 MONTH)"
  fi
  
  # Get campaign count
  local campaign_count=$(mysql -N -e "
    SELECT COUNT(DISTINCT c.id)
    FROM \`db-maestro-prod\`.campaigns c
    JOIN \`db-maestro-prod\`.brands b ON c.brand_id = b.id
    WHERE b.name LIKE '%$brand_name%'
      $year_filter
      AND c.deleted_at IS NULL;
  ")
  
  echo "📈 PERFORMANCE DA MARCA: $brand_name"
  echo ""
  
  if [[ -n $YEAR ]]; then
    echo "🎯 Ano $YEAR — $campaign_count campanhas realizadas"
  else
    echo "🎯 Últimos 12 Meses — $campaign_count campanhas realizadas"
  fi
  
  echo ""
  echo "🏆 MELHORES CAMPANHAS"
  
  local rank=1
  mysql -N -e "
    SELECT 
      c.title,
      ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100, 1) AS approval_rate,
      COUNT(DISTINCT pm.creator_id) AS total_creators
    FROM \`db-maestro-prod\`.campaigns c
    JOIN \`db-maestro-prod\`.brands b ON c.brand_id = b.id
    LEFT JOIN \`db-maestro-prod\`.proofread_medias pm ON pm.campaign_id = c.id AND pm.deleted_at IS NULL
    WHERE b.name LIKE '%$brand_name%'
      $year_filter
      AND c.deleted_at IS NULL
    GROUP BY c.id, c.title
    HAVING total_creators >= 5
    ORDER BY approval_rate DESC, total_creators DESC
    LIMIT 3;
  " | while IFS=$'\t' read -r campaign_name approval_rate total_creators; do
    echo "$rank. $campaign_name — ${approval_rate}% aprovação, $total_creators creators"
    ((rank++))
  done
  
  echo ""
  echo "📊 ESTATÍSTICAS GERAIS"
  
  local stats=$(mysql -N -e "
    SELECT 
      COUNT(DISTINCT pm.creator_id),
      COUNT(DISTINCT pm.id),
      ROUND(AVG(campaign_approval), 1),
      ROUND(SUM(campaign_paid), 2)
    FROM (
      SELECT 
        c.id,
        SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100 AS campaign_approval,
        SUM(cph.value) AS campaign_paid
      FROM \`db-maestro-prod\`.campaigns c
      JOIN \`db-maestro-prod\`.brands b ON c.brand_id = b.id
      LEFT JOIN \`db-maestro-prod\`.proofread_medias pm ON pm.campaign_id = c.id AND pm.deleted_at IS NULL
      LEFT JOIN \`db-maestro-prod\`.creator_payment_history cph ON cph.campaign_id = c.id
      WHERE b.name LIKE '%$brand_name%'
        $year_filter
        AND c.deleted_at IS NULL
      GROUP BY c.id
    ) AS brand_stats;
  " | tr '\t' '|')
  
  IFS='|' read -r sum_creators sum_content avg_approval sum_paid <<< "$stats"
  
  cat <<EOF
• Total de creators engajados: $sum_creators
• Total de conteúdos criados: $sum_content
• Taxa média de aprovação: ${avg_approval}%
• Investimento total: $(format_currency $sum_paid)

✨ DESTAQUES
• Aprovação consistentemente $(if [[ $(echo "$avg_approval > 80" | bc) -eq 1 ]]; then echo "alta"; else echo "dentro da média"; fi) ao longo do período
• $(if [[ $sum_creators -gt 100 ]]; then echo "Forte engajamento de creators na plataforma"; else echo "Base sólida de creators participantes"; fi)
• Investimento eficiente com foco em qualidade de conteúdo

🎤 NARRATIVA PARA PITCH
$brand_name é um case $(if [[ $(echo "$avg_approval > 85" | bc) -eq 1 ]]; then echo "de excelência"; else echo "consistente de sucesso"; fi) na plataforma, 
com $campaign_count campanhas $(if [[ -n $YEAR ]]; then echo "em $YEAR"; else echo "nos últimos 12 meses"; fi) mantendo taxa de 
aprovação média de ${avg_approval}%, $(if [[ $(echo "$avg_approval > 80" | bc) -eq 1 ]]; then echo "acima"; else echo "alinhada com"; fi) a média do mercado.
EOF
}

# Main execution
main() {
  if [[ -n $CAMPAIGN_ID ]]; then
    campaign_story "$CAMPAIGN_ID"
  elif [[ -n $BRAND ]]; then
    brand_performance "$BRAND"
  else
    top_campaigns "$TOP_N"
  fi
  
  # TODO: Google Sheets export (requires nano-banana integration)
  if $EXPORT_SHEETS; then
    echo ""
    echo "📊 Google Sheets export: [Feature coming soon]"
  fi
}

main
