#!/bin/bash
# Creator Churn Prediction & Alerts
# Identifies creators at risk: declining activity, long gaps, previously active now silent

set -euo pipefail

# Configurable thresholds
CHURN_DECLINE_PCT="${CHURN_DECLINE_PCT:-50}"
CHURN_MIN_ACTIVE="${CHURN_MIN_ACTIVE:-5}"
CHURN_MIN_PRIOR="${CHURN_MIN_PRIOR:-3}"
CHURN_GAP_WARN="${CHURN_GAP_WARN:-14}"
CHURN_GAP_ALERT="${CHURN_GAP_ALERT:-30}"
CHURN_GAP_CRITICAL="${CHURN_GAP_CRITICAL:-60}"

# CLI options
FORMAT="${FORMAT:-text}"
CREATOR_ID=""
CRITICAL_ONLY=0

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --format)
      FORMAT="$2"
      shift 2
      ;;
    --creator)
      CREATOR_ID="$2"
      shift 2
      ;;
    --critical-only)
      CRITICAL_ONLY=1
      shift
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --format text|json    Output format (default: text)"
      echo "  --creator ID          Analyze specific creator"
      echo "  --critical-only       Only show critical risk creators"
      echo ""
      echo "Environment variables:"
      echo "  CHURN_DECLINE_PCT     Decline % threshold (default: 50)"
      echo "  CHURN_MIN_ACTIVE      Min submissions to be 'active' (default: 5)"
      echo "  CHURN_MIN_PRIOR       Min submissions in prior period (default: 3)"
      echo "  CHURN_GAP_WARN        Warning gap in days (default: 14)"
      echo "  CHURN_GAP_ALERT       Alert gap in days (default: 30)"
      echo "  CHURN_GAP_CRITICAL    Critical gap in days (default: 60)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# If specific creator requested, show detailed analysis
if [[ -n "$CREATOR_ID" ]]; then
  QUERY="
    SELECT 
      a.creator_id,
      COUNT(DISTINCT CASE WHEN a.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY) THEN a.id END) AS last_30d,
      COUNT(DISTINCT CASE WHEN a.created_at >= DATE_SUB(NOW(), INTERVAL 60 DAY) AND a.created_at < DATE_SUB(NOW(), INTERVAL 30 DAY) THEN a.id END) AS prior_30d,
      COUNT(DISTINCT CASE WHEN a.created_at >= DATE_SUB(NOW(), INTERVAL 90 DAY) AND a.created_at < DATE_SUB(NOW(), INTERVAL 60 DAY) THEN a.id END) AS prior_60d,
      COUNT(DISTINCT a.id) AS total_all_time,
      MAX(a.created_at) AS last_submission,
      DATEDIFF(NOW(), MAX(a.created_at)) AS days_since_last,
      COUNT(DISTINCT pm.campaign_id) AS campaigns_participated,
      ROUND(SUM(pm.is_approved = 1) / NULLIF(COUNT(pm.id), 0) * 100, 1) AS approval_rate
    FROM actions a
    LEFT JOIN proofread_medias pm ON pm.action_id = a.id AND pm.deleted_at IS NULL
    WHERE a.deleted_at IS NULL
      AND a.creator_id = ${CREATOR_ID}
    GROUP BY a.creator_id;
  "
  
  if [[ "$FORMAT" == "json" ]]; then
    mysql -s -N -e "$QUERY" | awk -F'\t' '{
      print "{"
      print "  \"creator_id\": " $1 ","
      print "  \"last_30d\": " $2 ","
      print "  \"prior_30d\": " $3 ","
      print "  \"prior_60d\": " $4 ","
      print "  \"total_all_time\": " $5 ","
      print "  \"last_submission\": \"" $6 "\","
      print "  \"days_since_last\": " $7 ","
      print "  \"campaigns_participated\": " $8 ","
      print "  \"approval_rate\": " ($9 == "NULL" ? "null" : $9)
      print "}"
    }'
  else
    RESULT=$(mysql -s -N -e "$QUERY")
    
    if [[ -z "$RESULT" ]]; then
      echo "❌ Creator #${CREATOR_ID} não encontrado"
      exit 1
    fi
    
    # Parse tab-separated output properly (timestamp contains space)
    IFS=$'\t' read -r creator last_30d prior_30d prior_60d total last_sub days_since campaigns approval <<< "$RESULT"
    
    # Format last_sub to show only date (strip time)
    last_sub_date=$(echo "$last_sub" | cut -d' ' -f1)
    
    echo "📊 Análise de Risco — Creator #${creator}"
    echo ""
    echo "**Tendência de Submissões:**"
    echo "• Últimos 30d: ${last_30d} submissões"
    echo "• 30-60d atrás: ${prior_30d} submissões"
    echo "• 60-90d atrás: ${prior_60d} submissões"
    echo "• Total histórico: ${total} submissões"
    echo ""
    echo "**Status:**"
    echo "• Última submissão: ${last_sub_date} (${days_since} dias atrás)"
    echo "• Campanhas participadas: ${campaigns}"
    [[ "$approval" != "NULL" ]] && echo "• Taxa de aprovação: ${approval}%"
    echo ""
    
    # Determine risk level
    if [[ $last_30d -eq 0 && $total -ge $CHURN_MIN_ACTIVE ]]; then
      echo "🔴 **RISCO: CRÍTICO** — Anteriormente ativo, agora silencioso"
      echo ""
      echo "💡 Recomendação: Contato urgente para reengajamento"
    elif [[ $days_since -ge $CHURN_GAP_CRITICAL ]]; then
      echo "🔴 **RISCO: CRÍTICO** — Gap de ${days_since} dias (>60d)"
      echo ""
      echo "💡 Recomendação: Verificar se creator ainda está ativo na plataforma"
    elif [[ $days_since -ge $CHURN_GAP_ALERT ]]; then
      echo "🟠 **RISCO: ALTO** — Gap de ${days_since} dias (>30d)"
      echo ""
      echo "💡 Recomendação: Entrar em contato para reativar"
    elif [[ $prior_30d -ge $CHURN_MIN_PRIOR && $last_30d -lt $(( prior_30d * (100 - CHURN_DECLINE_PCT) / 100 )) ]]; then
      decline_pct=$(( (prior_30d - last_30d) * 100 / prior_30d ))
      echo "🟡 **RISCO: MÉDIO** — Queda de ${decline_pct}% na atividade recente"
      echo ""
      echo "💡 Recomendação: Entender causa da redução"
    elif [[ $days_since -ge $CHURN_GAP_WARN ]]; then
      echo "🟢 **RISCO: BAIXO** — Gap de ${days_since} dias (>14d)"
      echo ""
      echo "💡 Recomendação: Monitorar nas próximas semanas"
    else
      echo "✅ **RISCO: MÍNIMO** — Creator ativo e engajado"
    fi
  fi
  
  exit 0
fi

# At-Risk Summary (all creators)
QUERY="
  WITH creator_activity AS (
    SELECT 
      a.creator_id,
      COUNT(DISTINCT a.id) AS total_submissions,
      COUNT(DISTINCT CASE WHEN a.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY) THEN a.id END) AS last_30d,
      COUNT(DISTINCT CASE WHEN a.created_at >= DATE_SUB(NOW(), INTERVAL 60 DAY) AND a.created_at < DATE_SUB(NOW(), INTERVAL 30 DAY) THEN a.id END) AS prior_30d,
      MAX(a.created_at) AS last_submission,
      DATEDIFF(NOW(), MAX(a.created_at)) AS days_since_last
    FROM actions a
    WHERE a.deleted_at IS NULL
    GROUP BY a.creator_id
  )
  SELECT 
    creator_id,
    total_submissions,
    last_30d,
    prior_30d,
    last_submission,
    days_since_last,
    CASE 
      WHEN last_30d = 0 AND total_submissions >= ${CHURN_MIN_ACTIVE} THEN 'CRITICAL_SILENT'
      WHEN days_since_last >= ${CHURN_GAP_CRITICAL} THEN 'CRITICAL_GAP'
      WHEN days_since_last >= ${CHURN_GAP_ALERT} THEN 'HIGH'
      WHEN prior_30d >= ${CHURN_MIN_PRIOR} AND last_30d < prior_30d * (1 - ${CHURN_DECLINE_PCT} / 100.0) THEN 'MEDIUM'
      WHEN days_since_last >= ${CHURN_GAP_WARN} THEN 'LOW'
      ELSE 'WATCH'
    END AS risk_level
  FROM creator_activity
  WHERE (last_30d = 0 AND total_submissions >= ${CHURN_MIN_ACTIVE})
     OR (days_since_last >= ${CHURN_GAP_WARN})
     OR (prior_30d >= ${CHURN_MIN_PRIOR} AND last_30d < prior_30d * (1 - ${CHURN_DECLINE_PCT} / 100.0))
  ORDER BY 
    CASE risk_level
      WHEN 'CRITICAL_SILENT' THEN 1
      WHEN 'CRITICAL_GAP' THEN 2
      WHEN 'HIGH' THEN 3
      WHEN 'MEDIUM' THEN 4
      WHEN 'LOW' THEN 5
      ELSE 6
    END,
    days_since_last DESC
  LIMIT 100;
"

RESULTS=$(mysql -s -N -e "$QUERY")

if [[ -z "$RESULTS" ]]; then
  if [[ "$FORMAT" == "json" ]]; then
    echo '{"status": "ok", "at_risk_count": 0, "message": "No creators at risk"}'
  else
    echo "✅ Nenhum creator em risco detectado — todos creators ativos estão engajados!"
  fi
  exit 0
fi

# Count by risk level
critical_silent=$(echo "$RESULTS" | grep -c "CRITICAL_SILENT" || true)
critical_gap=$(echo "$RESULTS" | grep -c "CRITICAL_GAP" || true)
high=$(echo "$RESULTS" | grep -c "HIGH" || true)
medium=$(echo "$RESULTS" | grep -c "MEDIUM" || true)
low=$(echo "$RESULTS" | grep -c "LOW" || true)
total=$((critical_silent + critical_gap + high + medium + low))

if [[ "$FORMAT" == "json" ]]; then
  echo "{"
  echo "  \"status\": \"at_risk\","
  echo "  \"at_risk_count\": $total,"
  echo "  \"breakdown\": {"
  echo "    \"critical_silent\": $critical_silent,"
  echo "    \"critical_gap\": $critical_gap,"
  echo "    \"high\": $high,"
  echo "    \"medium\": $medium,"
  echo "    \"low\": $low"
  echo "  },"
  echo "  \"creators\": ["
  
  first=1
  while IFS=$'\t' read -r creator_id total_subs last_30d prior_30d last_sub days_since risk; do
    [[ $first -eq 0 ]] && echo ","
    first=0
    echo "    {"
    echo "      \"creator_id\": $creator_id,"
    echo "      \"total_submissions\": $total_subs,"
    echo "      \"last_30d\": $last_30d,"
    echo "      \"prior_30d\": $prior_30d,"
    echo "      \"last_submission\": \"$last_sub\","
    echo "      \"days_since_last\": $days_since,"
    echo "      \"risk_level\": \"$risk\""
    echo -n "    }"
  done <<< "$RESULTS"
  
  echo ""
  echo "  ]"
  echo "}"
else
  # Text output
  echo "🔴 Creator Churn Alert — ${total} creators em risco"
  echo ""
  
  # Critical Silent
  if [[ $critical_silent -gt 0 ]]; then
    echo "🚨 CRÍTICO (anteriormente ativos, agora silenciosos)"
    echo "$RESULTS" | grep "CRITICAL_SILENT" | head -5 | while IFS=$'\t' read -r creator_id total_subs last_30d prior_30d last_sub days_since risk; do
      echo "• Creator #${creator_id} — 0 submissões nos últimos 30d (tinha ${total_subs} total | última: ${last_sub}, ${days_since} dias atrás)"
    done
    [[ $critical_silent -gt 5 ]] && echo "• [+$((critical_silent - 5)) mais]"
    echo ""
  fi
  
  # Critical Gap
  if [[ $critical_gap -gt 0 ]] && [[ $CRITICAL_ONLY -eq 0 || $critical_silent -eq 0 ]]; then
    echo "🔴 CRÍTICO (gap >60 dias)"
    echo "$RESULTS" | grep "CRITICAL_GAP" | head -5 | while IFS=$'\t' read -r creator_id total_subs last_30d prior_30d last_sub days_since risk; do
      echo "• Creator #${creator_id} — ${days_since} dias sem submissão (tinha ${total_subs} total | última: ${last_sub})"
    done
    [[ $critical_gap -gt 5 ]] && echo "• [+$((critical_gap - 5)) mais]"
    echo ""
  fi
  
  if [[ $CRITICAL_ONLY -eq 0 ]]; then
    # High
    if [[ $high -gt 0 ]]; then
      echo "🟠 ALTO (gap >30 dias)"
      echo "$RESULTS" | grep "HIGH" | head -5 | while IFS=$'\t' read -r creator_id total_subs last_30d prior_30d last_sub days_since risk; do
        echo "• Creator #${creator_id} — ${days_since} dias sem submissão (tinha ${total_subs} total)"
      done
      [[ $high -gt 5 ]] && echo "• [+$((high - 5)) mais]"
      echo ""
    fi
    
    # Medium
    if [[ $medium -gt 0 ]]; then
      echo "🟡 MÉDIO (queda >50% nas submissões)"
      echo "$RESULTS" | grep "MEDIUM" | head -5 | while IFS=$'\t' read -r creator_id total_subs last_30d prior_30d last_sub days_since risk; do
        decline_pct=$(( (prior_30d - last_30d) * 100 / prior_30d ))
        echo "• Creator #${creator_id} — ${prior_30d} → ${last_30d} submissões (queda de ${decline_pct}% nos últimos 30d)"
      done
      [[ $medium -gt 5 ]] && echo "• [+$((medium - 5)) mais]"
      echo ""
    fi
    
    # Low
    if [[ $low -gt 0 ]]; then
      echo "🟢 BAIXO (gap >14 dias)"
      echo "$RESULTS" | grep "LOW" | head -5 | while IFS=$'\t' read -r creator_id total_subs last_30d prior_30d last_sub days_since risk; do
        echo "• Creator #${creator_id} — ${days_since} dias sem submissão"
      done
      [[ $low -gt 5 ]] && echo "• [+$((low - 5)) mais]"
      echo ""
    fi
  fi
  
  # Recommendation
  if [[ $critical_silent -gt 0 ]]; then
    echo "💡 Recomendação: priorizar reengajamento dos ${critical_silent} críticos (anteriormente ativos, agora silenciosos)"
  elif [[ $critical_gap -gt 0 ]]; then
    echo "💡 Recomendação: verificar status dos ${critical_gap} creators com gap >60 dias"
  else
    echo "💡 Recomendação: monitorar tendências semanais para detectar novos riscos"
  fi
fi
