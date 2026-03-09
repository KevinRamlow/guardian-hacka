#!/usr/bin/env python3
"""
Extract test scenarios from completed agent output logs.

Parses agent-logs/*-output.log files and identifies:
- Successful workflows (agents that completed with useful output)
- Edge cases discovered (permission blocks, empty outputs, validation failures)
- Error conditions handled (crash loops, timeouts, duplicate tasks)

Usage:
    python scripts/extract-test-scenarios.py [--log-dir /path/to/logs] [--output json|text]
"""

import argparse
import json
import os
import re
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path


@dataclass
class TestScenario:
    """A test scenario extracted from agent logs."""

    agent_id: str
    category: str  # "success", "edge_case", "error_condition"
    scenario_name: str
    description: str
    test_type: str  # "unit", "integration"
    relevant_code: list[str] = field(default_factory=list)
    tags: list[str] = field(default_factory=list)


def parse_agent_log(log_path: Path) -> dict:
    """Parse a single agent log file and extract metadata."""
    content = log_path.read_text(encoding="utf-8", errors="replace").strip()
    agent_id = log_path.stem.replace("-output", "").replace(".log", "")

    return {
        "agent_id": agent_id,
        "content": content,
        "size_bytes": len(content.encode("utf-8")),
        "has_permission_block": "permission" in content.lower() or "denied" in content.lower(),
        "has_sql": "SELECT" in content or "FROM" in content,
        "has_code_blocks": "```" in content,
        "has_error": "error" in content.lower() or "failed" in content.lower(),
        "mentions_severity": "severity" in content.lower() or "sev" in content.lower(),
        "mentions_tolerance": "tolerance" in content.lower() or "pattern" in content.lower(),
        "mentions_guideline": "guideline" in content.lower() or "diretriz" in content.lower(),
        "mentions_phase1": "phase 1" in content.lower() or "visual" in content.lower(),
        "mentions_phase2": "phase 2" in content.lower() or "moderation" in content.lower(),
    }


def classify_log(log_meta: dict) -> str:
    """Classify a log into category based on content."""
    if log_meta["size_bytes"] <= 1:
        return "empty_output"
    if log_meta["has_permission_block"] and log_meta["size_bytes"] < 200:
        return "permission_blocked"
    if log_meta["has_permission_block"]:
        return "partial_output"
    if log_meta["size_bytes"] > 500 and not log_meta["has_error"]:
        return "success"
    return "error_condition"


def extract_scenarios(log_dir: Path) -> list[TestScenario]:
    """Extract test scenarios from all agent output logs."""
    scenarios: list[TestScenario] = []
    log_files = sorted(log_dir.glob("*-output.log"))

    stats = {"total": 0, "empty": 0, "permission_blocked": 0, "partial": 0, "success": 0}

    for log_file in log_files:
        meta = parse_agent_log(log_file)
        category = classify_log(meta)
        stats["total"] += 1

        if category == "empty_output":
            stats["empty"] += 1
        elif category == "permission_blocked":
            stats["permission_blocked"] += 1
        elif category == "partial_output":
            stats["partial"] += 1
        elif category == "success":
            stats["success"] += 1

        # Extract scenarios based on content patterns
        if meta["mentions_severity"] and meta["mentions_guideline"]:
            scenarios.append(
                TestScenario(
                    agent_id=meta["agent_id"],
                    category="edge_case",
                    scenario_name="severity_boundary_moderation",
                    description="Severity 3 boundary case: light violation approved vs rejected by brand",
                    test_type="unit",
                    relevant_code=["src/services/content_moderation_service.py"],
                    tags=["severity", "boundary", "sev3"],
                )
            )

        if meta["mentions_tolerance"] and meta["mentions_guideline"]:
            scenarios.append(
                TestScenario(
                    agent_id=meta["agent_id"],
                    category="edge_case",
                    scenario_name="tolerance_pattern_integration",
                    description="Memory context with tolerance patterns affects moderation output",
                    test_type="unit",
                    relevant_code=["src/data/memory.py", "src/services/content_moderation_service.py"],
                    tags=["tolerance", "memory", "patterns"],
                )
            )

        if meta["mentions_phase1"] and meta["has_error"]:
            scenarios.append(
                TestScenario(
                    agent_id=meta["agent_id"],
                    category="error_condition",
                    scenario_name="phase1_agent_failure",
                    description="Phase 1 visual/audio agent failure handling",
                    test_type="unit",
                    relevant_code=["src/services/content_moderation_service.py"],
                    tags=["phase1", "error_handling"],
                )
            )

        if category == "empty_output":
            scenarios.append(
                TestScenario(
                    agent_id=meta["agent_id"],
                    category="error_condition",
                    scenario_name="empty_agent_output",
                    description="Agent produces empty output - should be detected and handled",
                    test_type="unit",
                    relevant_code=["src/services/agent_service.py"],
                    tags=["empty_output", "validation"],
                )
            )

        if meta["has_sql"] and meta["has_permission_block"]:
            scenarios.append(
                TestScenario(
                    agent_id=meta["agent_id"],
                    category="edge_case",
                    scenario_name="memory_query_failure_graceful",
                    description="BigQuery memory queries fail gracefully without blocking moderation",
                    test_type="unit",
                    relevant_code=["src/data/memory.py"],
                    tags=["bigquery", "graceful_degradation"],
                )
            )

    # Deduplicate by scenario_name
    seen = set()
    unique_scenarios = []
    for s in scenarios:
        if s.scenario_name not in seen:
            seen.add(s.scenario_name)
            unique_scenarios.append(s)

    print(f"Log stats: {json.dumps(stats, indent=2)}", file=sys.stderr)
    return unique_scenarios


def main():
    parser = argparse.ArgumentParser(description="Extract test scenarios from agent output logs")
    parser.add_argument(
        "--log-dir",
        default="/Users/fonsecabc/.openclaw/tasks/agent-logs",
        help="Directory containing agent output logs",
    )
    parser.add_argument(
        "--output",
        choices=["json", "text"],
        default="text",
        help="Output format",
    )
    args = parser.parse_args()

    log_dir = Path(args.log_dir)
    if not log_dir.exists():
        print(f"Error: log directory {log_dir} does not exist", file=sys.stderr)
        sys.exit(1)

    scenarios = extract_scenarios(log_dir)

    if args.output == "json":
        print(json.dumps([asdict(s) for s in scenarios], indent=2))
    else:
        print(f"\n{'='*60}")
        print(f"Extracted {len(scenarios)} unique test scenarios")
        print(f"{'='*60}\n")
        for i, s in enumerate(scenarios, 1):
            print(f"{i}. [{s.category}] {s.scenario_name}")
            print(f"   Description: {s.description}")
            print(f"   Test type: {s.test_type}")
            print(f"   Files: {', '.join(s.relevant_code)}")
            print(f"   Tags: {', '.join(s.tags)}")
            print()


if __name__ == "__main__":
    main()
