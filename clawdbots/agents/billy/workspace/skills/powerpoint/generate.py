#!/usr/bin/env python3
"""
Billy Presentation Generator — Quick text + image output.

Usage:
    python generate.py --template campaign-report --data data.json --output report.md

Returns: Formatted markdown + nano-banana generated images
"""

import argparse
import json
import os
import sys
import subprocess
from pathlib import Path
from datetime import datetime

NANO_BANANA = "/root/.openclaw/workspace/skills/nano-banana/scripts/generate_image.py"

def generate_chart(prompt, output_path):
    """Generate a chart image using nano-banana."""
    try:
        result = subprocess.run(
            ["python3", NANO_BANANA, "--prompt", prompt, "--output", output_path],
            capture_output=True,
            text=True,
            timeout=30
        )
        if result.returncode == 0:
            return output_path
        else:
            print(f"⚠️  Chart generation failed: {result.stderr}")
            return None
    except Exception as e:
        print(f"⚠️  Chart generation error: {e}")
        return None


def build_campaign_report(data, output_dir):
    """Build a campaign report as markdown + images."""
    campaign = data.get("campaign_name", "Campanha")
    period = data.get("period", "Último mês")
    
    output = []
    output.append(f"# 📊 Relatório: {campaign}")
    output.append(f"**Período:** {period}")
    output.append(f"**Gerado em:** {datetime.now().strftime('%Y-%m-%d %H:%M UTC')}")
    output.append("")
    
    # Metrics
    output.append("## 📈 Métricas Principais")
    output.append("")
    metrics = data.get("metrics", [])
    for m in metrics:
        label = m.get("label", "")
        value = m.get("value", "—")
        delta = m.get("delta", "")
        output.append(f"- **{label}:** {value} {delta}")
    output.append("")
    
    # Generate metrics chart
    if metrics:
        chart_prompt = f"Create a modern bar chart showing these metrics: {', '.join([f'{m.get('label')}: {m.get('value')}' for m in metrics[:4]])}. Use purple (#6C2BD9) and orange (#FF6B35) colors. Clean, professional style."
        chart_path = output_dir / "metrics_chart.png"
        generated = generate_chart(chart_prompt, str(chart_path))
        if generated:
            output.append(f"![Métricas]({chart_path.name})")
            output.append("")
    
    # Daily highlights
    output.append("## 📅 Tendência Diária")
    output.append("")
    daily = data.get("daily_highlights", [])
    for item in daily:
        output.append(f"- {item}")
    output.append("")
    
    # Top refusals
    output.append("## ❌ Principais Motivos de Recusa")
    output.append("")
    refusals = data.get("top_refusals", [])
    for item in refusals:
        output.append(f"- {item}")
    output.append("")
    
    # Next steps
    output.append("## 🎯 Próximos Passos")
    output.append("")
    next_steps = data.get("next_steps", [])
    for item in next_steps:
        output.append(f"- {item}")
    output.append("")
    
    output.append("---")
    output.append("*Gerado por Billy • Brandlovrs Guardian*")
    
    return "\n".join(output)


def build_weekly_digest(data, output_dir):
    """Build a weekly digest as markdown + images."""
    week = data.get("week", "Semana atual")
    
    output = []
    output.append(f"# 📅 Resumo Semanal")
    output.append(f"**{week}**")
    output.append(f"**Gerado em:** {datetime.now().strftime('%Y-%m-%d %H:%M UTC')}")
    output.append("")
    
    # Metrics
    output.append("## 📊 KPIs da Semana")
    output.append("")
    metrics = data.get("metrics", [])
    for m in metrics:
        label = m.get("label", "")
        value = m.get("value", "—")
        delta = m.get("delta", "")
        output.append(f"- **{label}:** {value} {delta}")
    output.append("")
    
    # Top campaigns
    output.append("## 🏆 Top Campanhas por Volume")
    output.append("")
    campaigns = data.get("top_campaigns", [])
    for item in campaigns:
        output.append(f"- {item}")
    output.append("")
    
    # Generate campaigns chart
    if campaigns and isinstance(campaigns[0], dict):
        chart_prompt = f"Create a horizontal bar chart showing top 5 campaigns by volume. Modern, professional style with purple (#6C2BD9) bars."
        chart_path = output_dir / "campaigns_chart.png"
        generated = generate_chart(chart_prompt, str(chart_path))
        if generated:
            output.append(f"![Top Campanhas]({chart_path.name})")
            output.append("")
    
    # Highlights
    output.append("## ✨ Destaques & Ações")
    output.append("")
    highlights = data.get("highlights", [])
    for item in highlights:
        output.append(f"- {item}")
    output.append("")
    
    output.append("---")
    output.append("*Gerado por Billy • Brandlovrs Guardian*")
    
    return "\n".join(output)


def build_brand_review(data, output_dir):
    """Build a brand review as markdown + images."""
    brand = data.get("brand_name", "Marca")
    period = data.get("period", "")
    
    output = []
    output.append(f"# 🏢 Review: {brand}")
    if period:
        output.append(f"**Período:** {period}")
    output.append(f"**Gerado em:** {datetime.now().strftime('%Y-%m-%d %H:%M UTC')}")
    output.append("")
    
    # Campaigns
    output.append("## 📋 Campanhas Ativas")
    output.append("")
    campaigns = data.get("campaigns", [])
    for item in campaigns:
        output.append(f"- {item}")
    output.append("")
    
    # Performance
    output.append("## 📊 Performance por Campanha")
    output.append("")
    performance = data.get("performance", [])
    for item in performance:
        output.append(f"- {item}")
    output.append("")
    
    # Recommendations
    output.append("## 💡 Recomendações")
    output.append("")
    recommendations = data.get("recommendations", [])
    for item in recommendations:
        output.append(f"- {item}")
    output.append("")
    
    output.append("---")
    output.append("*Gerado por Billy • Brandlovrs Guardian*")
    
    return "\n".join(output)


def build_executive_summary(data, output_dir):
    """Build an executive summary as markdown + images."""
    period = data.get("period", "")
    
    output = []
    output.append("# 🎯 Executive Summary")
    if period:
        output.append(f"**Período:** {period}")
    output.append(f"**Gerado em:** {datetime.now().strftime('%Y-%m-%d %H:%M UTC')}")
    output.append("")
    
    # Platform KPIs
    output.append("## 📊 KPIs da Plataforma")
    output.append("")
    metrics = data.get("metrics", [])
    for m in metrics:
        label = m.get("label", "")
        value = m.get("value", "—")
        delta = m.get("delta", "")
        output.append(f"- **{label}:** {value} {delta}")
    output.append("")
    
    # Trends
    output.append("## 📈 Tendências")
    output.append("")
    trends = data.get("trends", [])
    for item in trends:
        output.append(f"- {item}")
    output.append("")
    
    # Risks
    output.append("## ⚠️ Riscos & Oportunidades")
    output.append("")
    risks = data.get("risks", [])
    for item in risks:
        output.append(f"- {item}")
    output.append("")
    
    output.append("---")
    output.append("*Gerado por Billy • Brandlovrs Guardian*")
    
    return "\n".join(output)


TEMPLATE_BUILDERS = {
    "campaign-report": build_campaign_report,
    "weekly-digest": build_weekly_digest,
    "brand-review": build_brand_review,
    "executive-summary": build_executive_summary,
}


def main():
    parser = argparse.ArgumentParser(description="Billy Presentation Generator")
    parser.add_argument("--template", required=True, choices=TEMPLATE_BUILDERS.keys())
    parser.add_argument("--data", required=True, help="JSON file with presentation data")
    parser.add_argument("--output", required=True, help="Output markdown file path")
    args = parser.parse_args()

    # Load data
    with open(args.data) as f:
        data = json.load(f)

    # Output directory for images
    output_path = Path(args.output)
    output_dir = output_path.parent
    output_dir.mkdir(parents=True, exist_ok=True)

    # Build presentation
    builder = TEMPLATE_BUILDERS[args.template]
    content = builder(data, output_dir)

    # Save markdown
    output_path.write_text(content, encoding="utf-8")
    
    print(f"✅ Apresentação gerada: {output_path}")
    print(f"📄 Formato: Markdown + imagens")
    print(f"📁 Diretório: {output_dir}")


if __name__ == "__main__":
    main()
