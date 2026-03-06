#!/usr/bin/env python3
"""
Billy Daily Digest Generator — Runs daily queries and formats a Slack-ready summary.

Usage:
    python generate.py [--format slack|json] [--date YYYY-MM-DD]

Environment:
    MySQL credentials expected in ~/.my.cnf or via environment variables:
    MYSQL_HOST, MYSQL_PORT, MYSQL_USER, MYSQL_PASSWORD, MYSQL_DATABASE
"""

import argparse
import json
import os
import sys
import subprocess
from datetime import datetime, timedelta


def run_query(sql: str) -> list[dict]:
    """Execute a MySQL query and return results as list of dicts."""
    cmd = ["mysql", "--batch", "--raw", "-e", sql]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode != 0:
            print(f"⚠️  Query error: {result.stderr.strip()}", file=sys.stderr)
            return []
        
        lines = result.stdout.strip().split("\n")
        if len(lines) < 2:
            return []
        
        headers = lines[0].split("\t")
        rows = []
        for line in lines[1:]:
            values = line.split("\t")
            row = {}
            for i, h in enumerate(headers):
                val = values[i] if i < len(values) else None
                # Try numeric conversion
                if val and val != "NULL":
                    try:
                        if "." in val:
                            row[h] = float(val)
                        else:
                            row[h] = int(val)
                    except ValueError:
                        row[h] = val
                else:
                    row[h] = None
            rows.append(row)
        return rows
    except subprocess.TimeoutExpired:
        print("⚠️  Query timed out", file=sys.stderr)
        return []


def format_number(n, prefix="", suffix=""):
    """Format number with thousands separator (pt-BR style)."""
    if n is None:
        return "—"
    if isinstance(n, float):
        formatted = f"{n:,.1f}".replace(",", "X").replace(".", ",").replace("X", ".")
    else:
        formatted = f"{n:,}".replace(",", ".")
    return f"{prefix}{formatted}{suffix}"


def delta_indicator(current, previous, unit="", is_rate=False):
    """Generate ↑/↓ indicator for comparison."""
    if current is None or previous is None or previous == 0:
        return ""
    
    if is_rate:
        diff = current - previous
        if abs(diff) < 0.1:
            return " (estável)"
        arrow = "↑" if diff > 0 else "↓"
        return f" ({arrow} {abs(diff):.1f}pp)"
    else:
        pct = ((current - previous) / previous) * 100
        if abs(pct) < 1:
            return " (estável)"
        arrow = "↑" if pct > 0 else "↓"
        return f" ({arrow} {abs(pct):.0f}%{unit})"


def generate_digest(target_date=None):
    """Generate the daily digest data."""
    if target_date is None:
        target_date = datetime.now() - timedelta(days=1)  # Yesterday by default
    
    date_str = target_date.strftime('%Y-%m-%d')
    data = {"date": date_str}
    
    # Q1: Yesterday's Volume Overview
    print("📊 Running volume overview...", file=sys.stderr)
    q1 = f"""
    SELECT
      COUNT(*) AS total_moderado,
      SUM(pm.is_approved = 1) AS aprovados,
      SUM(pm.is_approved = 0) AS recusados,
      ROUND(SUM(pm.is_approved = 1) / COUNT(*) * 100, 1) AS taxa_aprovacao,
      COUNT(DISTINCT pm.creator_id) AS creators_ativos,
      COUNT(DISTINCT pmc.id) AS contestados,
      ROUND(COUNT(DISTINCT pmc.id) / NULLIF(COUNT(DISTINCT pm.id), 0) * 100, 1) AS taxa_contestacao
    FROM `db-maestro-prod`.proofread_medias pm
    LEFT JOIN `db-maestro-prod`.proofread_media_contest pmc ON pmc.proofread_media_id = pm.id
    WHERE DATE(pm.created_at) = '{date_str}'
      AND pm.deleted_at IS NULL;
    """
    volume_result = run_query(q1)
    data["volume"] = volume_result[0] if volume_result else {}
    
    # Q2: Volume comparison (yesterday vs same day last week)
    print("📈 Running volume comparison...", file=sys.stderr)
    week_ago = (target_date - timedelta(days=7)).strftime('%Y-%m-%d')
    q2 = f"""
    SELECT
      DATE(pm.created_at) AS dia,
      COUNT(*) AS total,
      ROUND(SUM(pm.is_approved = 1) / COUNT(*) * 100, 1) AS taxa_aprovacao
    FROM `db-maestro-prod`.proofread_medias pm
    WHERE DATE(pm.created_at) IN ('{date_str}', '{week_ago}')
      AND pm.deleted_at IS NULL
    GROUP BY DATE(pm.created_at)
    ORDER BY dia DESC;
    """
    comparison = run_query(q2)
    data["comparison"] = {row["dia"]: row for row in comparison}
    
    # Q3: New Campaigns (last 24h)
    print("🆕 Running new campaigns...", file=sys.stderr)
    q3 = f"""
    SELECT
      c.id,
      c.title AS campanha,
      b.name AS marca,
      c.budget,
      c.main_objective AS objetivo,
      c.published_at
    FROM `db-maestro-prod`.campaigns c
    JOIN `db-maestro-prod`.brands b ON c.brand_id = b.id
    WHERE c.published_at >= '{date_str} 00:00:00'
      AND c.published_at < DATE_ADD('{date_str}', INTERVAL 1 DAY)
      AND c.deleted_at IS NULL
    ORDER BY c.published_at DESC;
    """
    data["new_campaigns"] = run_query(q3)
    
    # Q4: Completed Campaigns (yesterday - changed to canceled state)
    print("✅ Running completed campaigns...", file=sys.stderr)
    q4 = f"""
    SELECT
      c.id,
      c.title AS campanha,
      b.name AS marca,
      c.updated_at,
      (SELECT COUNT(*) FROM `db-maestro-prod`.proofread_medias pm
       WHERE pm.campaign_id = c.id AND pm.is_approved = 1 AND pm.deleted_at IS NULL) AS total_aprovados
    FROM `db-maestro-prod`.campaigns c
    JOIN `db-maestro-prod`.brands b ON c.brand_id = b.id
    WHERE c.campaign_state_id = 3
      AND DATE(c.updated_at) = '{date_str}'
      AND c.deleted_at IS NULL
    ORDER BY total_aprovados DESC;
    """
    data["completed_campaigns"] = run_query(q4)
    
    # Q5: Top 5 Active Campaigns by Volume (yesterday)
    print("🔥 Running top campaigns...", file=sys.stderr)
    q5 = f"""
    SELECT
      c.title AS campanha,
      b.name AS marca,
      COUNT(*) AS total,
      SUM(pm.is_approved = 1) AS aprovados,
      ROUND(SUM(pm.is_approved = 1) / COUNT(*) * 100, 1) AS taxa_aprovacao
    FROM `db-maestro-prod`.proofread_medias pm
    JOIN `db-maestro-prod`.campaigns c ON pm.campaign_id = c.id
    JOIN `db-maestro-prod`.brands b ON c.brand_id = b.id
    WHERE DATE(pm.created_at) = '{date_str}'
      AND pm.deleted_at IS NULL
    GROUP BY c.id, c.title, b.name
    ORDER BY total DESC
    LIMIT 5;
    """
    data["top_campaigns"] = run_query(q5)
    
    # Q6: High Rejection Rate Campaigns (last 7 days, >50%)
    print("⚠️ Running high rejection alerts...", file=sys.stderr)
    q6 = """
    SELECT
      c.title AS campanha,
      b.name AS marca,
      COUNT(*) AS total_moderado,
      SUM(pm.is_approved = 0) AS rejeitados,
      ROUND(SUM(pm.is_approved = 0) / COUNT(*) * 100, 1) AS taxa_rejeicao
    FROM `db-maestro-prod`.proofread_medias pm
    JOIN `db-maestro-prod`.campaigns c ON pm.campaign_id = c.id
    JOIN `db-maestro-prod`.brands b ON c.brand_id = b.id
    WHERE pm.created_at >= NOW() - INTERVAL 7 DAY
      AND pm.deleted_at IS NULL
      AND c.campaign_state_id = 2
    GROUP BY c.id, c.title, b.name
    HAVING total_moderado >= 10
      AND taxa_rejeicao >= 50
    ORDER BY taxa_rejeicao DESC;
    """
    data["high_rejection"] = run_query(q6)
    
    # Q7: Stalled Campaigns (no submissions in >7 days)
    print("⏸️ Running stalled campaigns...", file=sys.stderr)
    q7 = """
    SELECT
      c.id,
      c.title AS campanha,
      b.name AS marca,
      MAX(pm.created_at) AS ultima_submissao,
      DATEDIFF(NOW(), MAX(pm.created_at)) AS dias_sem_submissao
    FROM `db-maestro-prod`.campaigns c
    JOIN `db-maestro-prod`.brands b ON c.brand_id = b.id
    LEFT JOIN `db-maestro-prod`.proofread_medias pm ON pm.campaign_id = c.id AND pm.deleted_at IS NULL
    WHERE c.campaign_state_id = 2
      AND c.deleted_at IS NULL
    GROUP BY c.id, c.title, b.name
    HAVING ultima_submissao IS NOT NULL
      AND dias_sem_submissao >= 7
    ORDER BY dias_sem_submissao DESC
    LIMIT 5;
    """
    data["stalled_campaigns"] = run_query(q7)
    
    # Q8: Upcoming Deadlines (moments ending in 2-3 days)
    print("📅 Running upcoming deadlines...", file=sys.stderr)
    q8 = """
    SELECT DISTINCT
      c.id,
      c.title AS campanha,
      b.name AS marca,
      MIN(m.ends_at) AS prazo,
      DATEDIFF(MIN(m.ends_at), NOW()) AS dias_restantes,
      (SELECT COUNT(DISTINCT pm.creator_id)
       FROM `db-maestro-prod`.proofread_medias pm
       WHERE pm.campaign_id = c.id AND pm.deleted_at IS NULL) AS creators_ativos
    FROM `db-maestro-prod`.campaigns c
    JOIN `db-maestro-prod`.brands b ON c.brand_id = b.id
    JOIN `db-maestro-prod`.moments m ON m.campaign_id = c.id
    WHERE c.campaign_state_id = 2
      AND m.ends_at IS NOT NULL
      AND m.ends_at BETWEEN NOW() AND NOW() + INTERVAL 3 DAY
      AND c.deleted_at IS NULL
      AND m.deleted_at IS NULL
    GROUP BY c.id, c.title, b.name
    ORDER BY dias_restantes ASC;
    """
    data["deadlines"] = run_query(q8)
    
    return data


def format_slack(data: dict) -> str:
    """Format digest data as a Slack message."""
    date_obj = datetime.strptime(data["date"], '%Y-%m-%d')
    date_formatted = date_obj.strftime('%d/%m/%Y (%A)').replace('Monday', 'Segunda').replace('Tuesday', 'Terça').replace('Wednesday', 'Quarta').replace('Thursday', 'Quinta').replace('Friday', 'Sexta').replace('Saturday', 'Sábado').replace('Sunday', 'Domingo')
    
    lines = [f"🌅 *Resumo Diário — {date_formatted}*\n"]
    
    # Volume section
    volume = data.get("volume", {})
    comparison = data.get("comparison", {})
    
    if volume and volume.get("total_moderado"):
        total = volume.get("total_moderado", 0)
        aprovados = volume.get("aprovados", 0)
        recusados = volume.get("recusados", 0)
        taxa_aprov = volume.get("taxa_aprovacao", 0)
        creators = volume.get("creators_ativos", 0)
        contestados = volume.get("contestados", 0)
        taxa_contest = volume.get("taxa_contestacao", 0)
        
        # Get comparison data
        yesterday = comparison.get(data["date"], {})
        week_ago_date = (date_obj - timedelta(days=7)).strftime('%Y-%m-%d')
        week_ago = comparison.get(week_ago_date, {})
        
        week_ago_total = week_ago.get("total", 0) if week_ago else 0
        week_ago_rate = week_ago.get("taxa_aprovacao", 0) if week_ago else 0
        
        lines.append("*📊 Volume de Ontem*")
        lines.append(f"• Total moderado: {format_number(total)}{delta_indicator(total, week_ago_total)}")
        lines.append(f"• Aprovação: {format_number(taxa_aprov, suffix='%')}{delta_indicator(taxa_aprov, week_ago_rate, is_rate=True)}")
        lines.append(f"• Recusados: {format_number(recusados)}")
        lines.append(f"• Creators ativos: {format_number(creators)}")
        if contestados:
            lines.append(f"• Contestações: {format_number(contestados)} ({format_number(taxa_contest, suffix='%')})")
    else:
        lines.append("*📊 Volume de Ontem*")
        lines.append("• Sem dados de moderação para esta data")
    
    # New campaigns
    new_camps = data.get("new_campaigns", [])
    if new_camps:
        lines.append(f"\n*🆕 Novas Campanhas (últimas 24h)* — {len(new_camps)}")
        for c in new_camps[:5]:
            campanha = c.get("campanha", "?")
            marca = c.get("marca", "?")
            budget = c.get("budget", 0)
            if budget:
                lines.append(f"• *{campanha}* ({marca}) — Budget: R$ {format_number(budget)}")
            else:
                lines.append(f"• *{campanha}* ({marca})")
        if len(new_camps) > 5:
            lines.append(f"  _...e mais {len(new_camps) - 5} campanhas_")
    
    # Completed campaigns
    completed = data.get("completed_campaigns", [])
    if completed:
        lines.append(f"\n*✅ Campanhas Finalizadas Ontem* — {len(completed)}")
        for c in completed[:5]:
            campanha = c.get("campanha", "?")
            marca = c.get("marca", "?")
            total_aprov = c.get("total_aprovados", 0)
            lines.append(f"• *{campanha}* ({marca}) — {format_number(total_aprov)} conteúdos aprovados")
    
    # Top campaigns
    top = data.get("top_campaigns", [])
    if top:
        lines.append(f"\n*🔥 Top Campanhas Ontem (por volume)*")
        for i, c in enumerate(top, 1):
            campanha = c.get("campanha", "?")
            marca = c.get("marca", "?")
            total = format_number(c.get("total", 0))
            rate = c.get("taxa_aprovacao", 0)
            lines.append(f"{i}. *{campanha}* ({marca}) — {total} conteúdos, {rate}% aprovação")
    
    # Alerts section
    alerts = []
    
    # High rejection alerts
    high_rej = data.get("high_rejection", [])
    for c in high_rej[:3]:
        campanha = c.get("campanha", "?")
        marca = c.get("marca", "?")
        taxa = c.get("taxa_rejeicao", 0)
        alerts.append(f"• *{campanha}* ({marca}) com {taxa}% de rejeição (últimos 7d)")
    
    # Stalled campaigns
    stalled = data.get("stalled_campaigns", [])
    for c in stalled[:3]:
        campanha = c.get("campanha", "?")
        marca = c.get("marca", "?")
        dias = c.get("dias_sem_submissao", 0)
        alerts.append(f"• *{campanha}* ({marca}) sem submissões há {dias} dias")
    
    if alerts:
        lines.append(f"\n*⚠️ Alertas*")
        lines.extend(alerts)
    
    # Upcoming deadlines
    deadlines = data.get("deadlines", [])
    if deadlines:
        lines.append(f"\n*📅 Prazos Próximos (2-3 dias)*")
        for c in deadlines[:5]:
            campanha = c.get("campanha", "?")
            marca = c.get("marca", "?")
            dias = c.get("dias_restantes", 0)
            creators = c.get("creators_ativos", 0)
            if dias == 0:
                lines.append(f"• *{campanha}* ({marca}) — termina HOJE ({format_number(creators)} creators)")
            elif dias == 1:
                lines.append(f"• *{campanha}* ({marca}) — termina AMANHÃ ({format_number(creators)} creators)")
            else:
                lines.append(f"• *{campanha}* ({marca}) — termina em {dias} dias ({format_number(creators)} creators)")
    
    lines.append("\n_Dados: MySQL db-maestro-prod | Gerado automaticamente_")
    
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Generate daily platform digest")
    parser.add_argument("--format", choices=["slack", "json"], default="slack",
                       help="Output format (default: slack)")
    parser.add_argument("--date", type=str, default=None,
                       help="Target date (YYYY-MM-DD, default: yesterday)")
    
    args = parser.parse_args()
    
    # Parse target date
    target_date = None
    if args.date:
        try:
            target_date = datetime.strptime(args.date, '%Y-%m-%d')
        except ValueError:
            print(f"❌ Invalid date format: {args.date} (expected YYYY-MM-DD)", file=sys.stderr)
            sys.exit(1)
    
    # Generate digest
    print(f"🚀 Generating daily digest...", file=sys.stderr)
    data = generate_digest(target_date)
    
    # Output
    if args.format == "json":
        print(json.dumps(data, indent=2, ensure_ascii=False, default=str))
    else:
        output = format_slack(data)
        print(output)
    
    print(f"\n✅ Digest generated successfully!", file=sys.stderr)


if __name__ == "__main__":
    main()
