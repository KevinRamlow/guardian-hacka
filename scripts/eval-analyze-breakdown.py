#!/usr/bin/env python3
"""
Analyze Guardian eval results and generate breakdown by guideline type.
Identifies regressions, improvements, and patterns for backlog generation.

Usage: python3 scripts/eval-analyze-breakdown.py <run_dir> [baseline_accuracy]
"""

import json
import sys
from pathlib import Path
from collections import defaultdict
from typing import Dict, List, Any

def load_results(run_dir: Path) -> List[Dict]:
    """Load progress.jsonl results."""
    progress_file = run_dir / "progress.jsonl"
    if not progress_file.exists():
        return []
    
    results = []
    with open(progress_file) as f:
        for line in f:
            if line.strip():
                results.append(json.loads(line))
    return results

def classify_guideline(guideline_text: str) -> str:
    """Classify guideline into high-level types."""
    text_lower = guideline_text.lower()
    
    # Time constraints
    if any(k in text_lower for k in ['segundos', 'minutos', 'duração', 'primeiros', 'últimos', 'iniciar', 'finalizar']):
        return 'time_constraints'
    
    # Captions
    if any(k in text_lower for k in ['legenda', 'caption', 'ocr', 'texto', 'escrito']):
        return 'captions'
    
    # Color/clothing
    if any(k in text_lower for k in ['cor', 'roupa', 'camisa', 'vestido', 'blusa', 'azul', 'vermelho', 'verde', 'branco']):
        return 'color_clothing'
    
    # Brand mentions
    if any(k in text_lower for k in ['mencionar', 'falar', 'citar', 'nome da marca', 'produto']):
        return 'brand_mention'
    
    # CTA
    if any(k in text_lower for k in ['call to action', 'cta', 'link', 'acesse', 'compre', 'baixe']):
        return 'cta'
    
    # Product display
    if any(k in text_lower for k in ['mostrar', 'exibir', 'logo', 'embalagem', 'rótulo']):
        return 'product_display'
    
    return 'general'

def analyze_breakdown(results: List[Dict], baseline: float) -> Dict[str, Any]:
    """Analyze results and generate breakdown by type."""
    
    # Group by guideline type
    by_type = defaultdict(lambda: {'correct': 0, 'total': 0, 'errors': []})
    
    for result in results:
        if result.get('error'):
            continue  # Skip failed cases
        
        # Get guideline info from test_case
        test_case = result.get('test_case', {})
        guidelines = test_case.get('inputs', {}).get('guidelines', [])
        
        if not guidelines:
            continue
        
        # Classify the guideline
        guideline_text = guidelines[0].get('guideline', '')
        guideline_type = classify_guideline(guideline_text)
        
        # Get correctness
        is_correct = result.get('aggregate_score', 0) == 1.0
        
        by_type[guideline_type]['total'] += 1
        if is_correct:
            by_type[guideline_type]['correct'] += 1
        else:
            by_type[guideline_type]['errors'].append({
                'test_idx': result.get('test_idx'),
                'guideline': guideline_text[:100],
            })
    
    # Calculate accuracies
    breakdown = {}
    for gtype, data in by_type.items():
        if data['total'] > 0:
            accuracy = data['correct'] / data['total']
            breakdown[gtype] = {
                'accuracy': accuracy,
                'correct': data['correct'],
                'total': data['total'],
                'delta_vs_baseline': accuracy - baseline,
                'errors': data['errors'][:5],  # Top 5 errors
            }
    
    # Overall stats
    total_correct = sum(d['correct'] for d in by_type.values())
    total_cases = sum(d['total'] for d in by_type.values())
    overall_accuracy = total_correct / total_cases if total_cases > 0 else 0
    
    return {
        'overall': {
            'accuracy': overall_accuracy,
            'correct': total_correct,
            'total': total_cases,
            'delta_vs_baseline': overall_accuracy - baseline,
        },
        'by_type': breakdown,
    }

def identify_priorities(analysis: Dict) -> List[Dict[str, Any]]:
    """Identify priority areas for improvement."""
    priorities = []
    
    by_type = analysis['by_type']
    
    # Priority 1: Regressions (delta < -0.05)
    for gtype, data in by_type.items():
        if data['delta_vs_baseline'] < -0.05:
            priorities.append({
                'priority': 'high',
                'type': 'regression',
                'guideline_type': gtype,
                'accuracy': data['accuracy'],
                'delta': data['delta_vs_baseline'],
                'task': f"Fix: {gtype.replace('_', ' ').title()} regrediu {abs(data['delta_vs_baseline'])*100:.1f}pp",
            })
    
    # Priority 2: Low accuracy (< 0.70)
    for gtype, data in by_type.items():
        if data['accuracy'] < 0.70 and data['delta_vs_baseline'] >= -0.05:
            priorities.append({
                'priority': 'medium',
                'type': 'low_accuracy',
                'guideline_type': gtype,
                'accuracy': data['accuracy'],
                'delta': data['delta_vs_baseline'],
                'task': f"Improve: {gtype.replace('_', ' ').title()} accuracy ({data['accuracy']*100:.1f}% → 80%)",
            })
    
    # Priority 3: Improvements to document (delta > +0.05)
    for gtype, data in by_type.items():
        if data['delta_vs_baseline'] > 0.05:
            priorities.append({
                'priority': 'low',
                'type': 'improvement',
                'guideline_type': gtype,
                'accuracy': data['accuracy'],
                'delta': data['delta_vs_baseline'],
                'task': f"Document: {gtype.replace('_', ' ').title()} improved +{data['delta_vs_baseline']*100:.1f}pp",
            })
    
    return sorted(priorities, key=lambda x: {'high': 0, 'medium': 1, 'low': 2}[x['priority']])

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 eval-analyze-breakdown.py <run_dir> [baseline_accuracy]", file=sys.stderr)
        sys.exit(1)
    
    run_dir = Path(sys.argv[1])
    baseline = float(sys.argv[2]) if len(sys.argv) > 2 else 0.79
    
    if not run_dir.exists():
        print(f"Error: Run directory not found: {run_dir}", file=sys.stderr)
        sys.exit(1)
    
    results = load_results(run_dir)
    if not results:
        print(f"Error: No results found in {run_dir}", file=sys.stderr)
        sys.exit(1)
    
    analysis = analyze_breakdown(results, baseline)
    priorities = identify_priorities(analysis)
    
    # Output JSON for downstream processing
    output = {
        'run_dir': str(run_dir),
        'baseline': baseline,
        'analysis': analysis,
        'priorities': priorities,
    }
    
    print(json.dumps(output, indent=2))

if __name__ == '__main__':
    main()
