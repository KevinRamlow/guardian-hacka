#!/usr/bin/env python3
"""
Billy Weekly Digest Generator — Runs all digest queries and formats a Slack-ready summary.

Usage:
    python generate.py [--output slack|json|pptx] [--weeks-back N]

Environment:
    MYSQL_HOST (default: 127.0.0.1)
    MYSQL_PORT (default: 3306)
    MYSQL_USER (default: root)
    MYSQL_PASSWORD
    MYSQL_DATABASE (default: db-maestro-prod)
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
    """Generate ↑/↓ indicator for week-over-week change."""
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


def generate_digest(weeks_back=0):
    """Generate the weekly digest data."""
    data = {}
    
    # Q1: Weekly Volume Overview
    print("📊 Running volume overview...", file=sys.stderr)
    q1 = """
    SELECT
      CASE
        WHEN pm.created_at >= DATE_SUB(CURDATE(), INTERVAL WEEKDAY(CURDATE()) DAY)
        THEN 'esta_semana'
        ELSE 'semana_passada'
      END AS periodo,
      COUNT(*) AS total_moderado,
      SUM(pm.is_approved = 1) AS aprovados,
      SUM(pm.is_approved = 0) AS recusados,
      ROUND(SUM(pm.is_approved = 1) / COUNT(*) * 100, 1) AS taxa_aprovacao,
      COUNT(DISTINCT pm.creator_id) AS creators_ativos
    FROM `db-maestro-prod`.proofread_medias pm
    WHERE pm.created_at >= DATE_SUB(CURDATE(), INTERVAL (WEEKDAY(CURDATE()) + 7) DAY)
      AND pm.created_at < DATE_ADD(CURDATE(), INTERVAL 1 DAY)
      AND pm.deleted_at IS NULL
    GROUP BY periodo;
    """
    volume = run_query(q1)
    data["volume"] = {row["periodo"]: row for row in volume}
    
    # Q2: Top 10 Campaigns
    print("🏆 Running top campaigns...", file=sys.stderr)
    q2 = """
    SELECT
      c.title AS campanha,
      b.name AS marca,
      COUNT(*) AS total,
      SUM(pm.is_approved = 1) AS aprovados,
      ROUND(SUM(pm.is_approved = 1) / COUNT(*) * 100, 1) AS taxa_aprovacao,
      COUNT(DISTINCT pm.creator_id) AS creators
    FROM `db-maestro-prod`.proofread_medias pm
    JOIN `db-maestro-prod`.campaigns c ON pm.campaign_id = c.id
    JOIN `db-maestro-prod`.brands b ON c.brand_id = b.id
    WHERE pm.created_at >= DATE_SUB(CURDATE(), INTERVAL WEEKDAY(CURDATE()) DAY)
      AND pm.deleted_at IS NULL
    GROUP BY c.id, c.title, b.name
    ORDER BY total DESC
    LIMIT 10;
    """
    data["top_campaigns"] = run_query(q2)
    
    # Q3: New Campaigns Published
    print("🆕 Running new campaigns...", file=sys.stderr)
    q3 = """
    SELECT c.title, b.name AS marca, c.budget, c.main_objective, c.published_at
    FROM `db-maestro-prod`.campaigns c
    JOIN `db-maestro-prod`.brands b ON c.brand_id = b.id
    WHERE c.published_at >= DATE_SUB(CURDATE(), INTERVAL WEEKDAY(CURDATE()) DAY)
      AND c.deleted_at IS NULL
    ORDER BY c.published_at DESC;
    """
    data["new_campaigns"] = run_query(q3)
    
    # Q4: Contest Rate
    print("⚖️ Running contest analysis...", file=sys.stderr)
    q4 = """
    SELECT
      COUNT(DISTINCT pm.id) AS total_moderado,
      COUNT(DISTINCT pmc.id) AS contestados,
      ROUND(COUNT(DISTINCT pmc.id) / NULLIF(COUNT(DISTINCT pm.id), 0) * 100, 1) AS taxa_contestacao
    FROM `db-maestro-prod`.proofread_medias pm
    LEFT JOIN `db-maestro-prod`.proofread_media_contest pmc ON pmc.proofread_media_id = pm.id
    WHERE pm.created_at >= DATE_SUB(CURDATE(), INTERVAL WEEKDAY(CURDATE()) DAY);
    """
    contests = run_query(q4)
    data["contests"] = contests[0] if contests else {}
    
    # Q5: Most Contested Campaigns
    print("🔥 Running most contested...", file=sys.stderr)
    q5 = """
    SELECT
      c.title AS campanha,
      b.name AS marca,
      COUNT(DISTINCT pm.id) AS moderados,
      COUNT(DISTINCT pmc.id) AS contestados,
      ROUND(COUNT(DISTINCT pmc.id) / NULLIF(COUNT(DISTINCT pm.id), 0) * 100, 1) AS taxa_contestacao
    FROM `db-maestro-prod`.proofread_medias pm
    JOIN `db-maestro-prod`.campaigns c ON pm.campaign_id = c.id
    JOIN `db-maestro-prod`.brands b ON c.brand_id = b.id
    LEFT JOIN `db-maestro-prod`.proofread_media_contest pmc ON pmc.proofread_media_id = pm.id
    WHERE pm.created_at >= DATE_SUB(CURDATE(), INTERVAL WEEKDAY(CURDATE()) DAY)
      AND pm.deleted_at IS NULL
    GROUP BY c.id, c.title, b.name
    HAVING moderados >= 5
    ORDER BY taxa_contestacao DESC
    LIMIT 5;
    """
    data["most_contested"] = run_query(q5)
    
    # Q6: Payment Activity
    print("💰 Running payment activity...", file=sys.stderr)
    q6 = """
    SELECT
      COUNT(*) AS pagamentos,
      COUNT(DISTINCT cph.creator_id) AS creators_pagos,
      ROUND(SUM(cph.value), 2) AS total_pago,
      cph.value_currency
    FROM `db-maestro-prod`.creator_payment_history cph
    WHERE cph.date_of_transaction >= DATE_SUB(CURDATE(), INTERVAL WEEKDAY(CURDATE()) DAY)
    GROUP BY cph.value_currency;
    """
    data["payments"] = run_query(q6)
    
    # Q7: Daily Volume Trend (14 days)
    print("📈 Running daily trend...", file=sys.stderr)
    q7 = """
    SELECT
      DATE(pm.created_at) AS dia,
      COUNT(*) AS total,
      SUM(pm.is_approved = 1) AS aprovados,
      ROUND(SUM(pm.is_approved = 1) / COUNT(*) * 100, 1) AS taxa_aprovacao
    FROM `db-maestro-prod`.proofread_medias pm
    WHERE pm.created_at >= DATE_SUB(CURDATE(), INTERVAL 14 DAY)
      AND pm.deleted_at IS NULL
    GROUP BY DATE(pm.created_at)
    ORDER BY dia;
    """
    data["daily_trend"] = run_query(q7)
    
    return data


def format_slack(data: dict) -> str:
    """Format digest data as a Slack message."""
    today = datetime.now()
    week_start = today - timedelta(days=today.weekday())
    week_end = today
    date_range = f"{week_start.strftime('%d/%m')} — {week_end.strftime('%d/%m/%Y')}"
    
    lines = [f"📊 *Resumo Semanal — {date_range}*\n"]
    
    # Volume section
    this_week = data.get("volume", {}).get("esta_semana", {})
    last_week = data.get("volume", {}).get("semana_passada", {})
    
    if this_week:
        tw_total = this_week.get("total_moderado", 0)
        lw_total = last_week.get("total_moderado", 0) if last_week else 0
        tw_rate = this_week.get("taxa_aprovacao", 0)
        lw_rate = last_week.get("taxa_aprovacao", 0) if last_week else 0
        tw_creators = this_week.get("creators_ativos", 0)
        
        lines.append("*📋 Volume*")
        lines.append(f"• Total moderado: {format_number(tw_total)}{delta_indicator(tw_total, lw_total)}")
        lines.append(f"• Aprovação: {format_number(tw_rate, suffix='%')}{delta_indicator(tw_rate, lw_rate, is_rate=True)}")
        lines.append(f"• Recusados: {format_number(this_week.get('recusados', 0))}")
        lines.append(f"• Creators ativos: {format_number(tw_creators)}")
    else:
        lines.append("*📋 Volume*")
        lines.append("• Sem dados de moderação nesta semana")
    
    # Contest section
    contests = data.get("contests", {})
    if contests:
        lines.append(f"\n*⚖️ Contestações*")
        lines.append(f"• Total: {format_number(contests.get('contestados', 0))} ({format_number(contests.get('taxa_contestacao', 0), suffix='%')} dos moderados)")
    
    # Top campaigns
    top = data.get("top_campaigns", [])
    if top:
        lines.append(f"\n*🏆 Top Campanhas (por volume)*")
        for i, c in enumerate(top[:5], 1):
            name = c.get("campanha", "?")
            brand = c.get("marca", "?")
            total = format_number(c.get("total", 0))
            rate = c.get("taxa_aprovacao", 0)
            lines.append(f"{i}. *{name}* ({brand}) — {total} conteúdos, {rate}% aprovação")
    
    # New campaigns
    new_camps = data.get("new_campaigns", [])
    if new_camps:
        lines.append(f"\n*🆕 Novas Campanhas ({len(new_camps)})*")
        for c in new_camps[:5]:
            title = c.get("title", "?")
            brand = c.get("marca", "?")
            budget = c.get("budget", 0)
            lines.append(f"• *{title}* ({brand}) — Budget: R$ {format_number(budget)}")
        if len(new_camps) > 5:
            lines.append(f"  _...e mais {len(new_camps) - 5} campanhas_")
    
    # Most contested
    contested = data.get("most_contested", [])
    alerts = []
    if contested:
        for c in contested:
            rate = c.get("taxa_contestacao", 0)
            if rate and rate > 10:
                alerts.append(f"• *{c.get('campanha', '?')}* ({c.get('marca', '?')}) com {rate}% de contestação")
    
    # Anomaly detection
    if this_week and last_week:
        tw_rate = this_week.get("taxa_aprovacao", 0)
        lw_rate = last_week.get("taxa_aprovacao", 0) if last_week else 0
        if lw_rate and tw_rate and (lw_rate - tw_rate) > 5:
            alerts.append(f"• Taxa de aprovação caiu {lw_rate - tw_rate:.1f}pp vs semana passada")
        
        tw_total = this_week.get("total_moderado", 0)
        lw_total = last_week.get("total_moderado", 0) if last_week else 0
        if lw_total and tw_total and ((lw_total - tw_total) / lw_total * 100) > 30:
            pct = (lw_total - tw_total) / lw_total * 100
            alerts.append(f"• Volume caiu {pct:.0f}% vs semana passada")
    
    wins = []
    if this_week and last_week:
        tw_rate = this_week.get("taxa_aprovacao", 0)
        lw_rate = last_week.get("taxa_aprovacao", 0) if last_week else 0
        if tw_rate and lw_rate and (tw_rate - lw_rate) > 3:
            wins.append(f"• Taxa de aprovação subiu {tw_rate - lw_rate:.1f}pp! 🎉")
    
    for c in top[:3]:
        rate = c.get("taxa_aprovacao", 0)
        total = c.get("total", 0)
        if rate and rate > 95 and total and total > 100:
            wins.append(f"• *{c.get('campanha', '?')}* com {rate}% de aprovação em {format_number(total)} conteúdos 🌟")
    
    if wins:
        lines.append(f"\n*🎉 Destaques*")
        lines.extend(wins)
    
    if alerts:
        lines.append(f"\n*⚠️ Atenção*")
        lines.extend(alerts)
    
    # Payments
    payments = data.get("payments", [])
    if payments:
        lines.append(f"\n*💰 Pagamentos*")
        for p in payments:
            currency = p.get("value_currency", "BRL")
            symbol = "R$" if currency == "BRL" else "US$"
            lines.append(f"• {format_number(p.get('creators_pagos', 0))} creators pagos — Total: {symbol} {format_number(p.get('total_pago', 0))}")
    
    lines.append(f"\n_Dados: MySQL db-maestro-prod | Gerado em {datetime.now().strftime('%d/%m/%Y %H:%M')}_")
    
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Billy Weekly Digest Generator")
    parser.add_argument("--output", choices=["slack", "json"], default="slack",
                       help="Output format")
    parser.add_argument("--weeks-back", type=int, default=0,
                       help="Generate for N weeks ago (0=current)")
    args = parser.parse_args()
    
    data = generate_digest(args.weeks_back)
    
    if args.output == "json":
        print(json.dumps(data, ensure_ascii=False, indent=2, default=str))
    else:
        print(format_slack(data))


if __name__ == "__main__":
    main()
