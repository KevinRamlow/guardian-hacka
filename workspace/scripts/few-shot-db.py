#!/usr/bin/env python3
"""Few-Shot Database for Guardian Eval Cases.

Uses sqlite-vec for vector similarity search on eval cases.
Stores guideline text, answers, agreement status, and embeddings.
"""

import argparse
import json
import os
import sqlite3
import sys
from pathlib import Path

DB_PATH = os.environ.get("FEW_SHOT_DB", os.path.expanduser("~/.openclaw/tasks/few-shot.db"))


def get_db():
    """Get database connection with sqlite-vec loaded."""
    db = sqlite3.connect(DB_PATH)
    db.row_factory = sqlite3.Row
    try:
        import sqlite_vec
        db.enable_load_extension(True)
        sqlite_vec.load(db)
        db.enable_load_extension(False)
    except ImportError:
        print("WARNING: sqlite-vec not installed. Vector search disabled.", file=sys.stderr)
    return db


def init_db():
    """Initialize the database schema."""
    db = get_db()
    db.executescript("""
        CREATE TABLE IF NOT EXISTS eval_cases (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id TEXT NOT NULL,
            test_idx INTEGER,
            classification TEXT NOT NULL,
            guideline_text TEXT NOT NULL,
            media_description TEXT DEFAULT '',
            guardian_answer TEXT,
            human_answer TEXT,
            agreed INTEGER NOT NULL,
            error_type TEXT,
            reasoning TEXT DEFAULT '',
            justification TEXT DEFAULT '',
            created_at TEXT DEFAULT (datetime('now')),
            UNIQUE(run_id, test_idx)
        );

        CREATE INDEX IF NOT EXISTS idx_classification ON eval_cases(classification);
        CREATE INDEX IF NOT EXISTS idx_agreed ON eval_cases(agreed);
        CREATE INDEX IF NOT EXISTS idx_error_type ON eval_cases(error_type);
    """)

    try:
        db.execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS eval_case_embeddings USING vec0(
                case_id INTEGER PRIMARY KEY,
                embedding float[768]
            )
        """)
    except Exception as e:
        print(f"WARNING: Could not create vector table: {e}", file=sys.stderr)

    db.commit()
    db.close()
    print(json.dumps({"status": "ok", "db_path": DB_PATH}))


def generate_embeddings(texts):
    """Generate embeddings using Gemini API."""
    try:
        import google.generativeai as genai
        api_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
        if not api_key:
            print("WARNING: No GEMINI_API_KEY set. Skipping embeddings.", file=sys.stderr)
            return None
        genai.configure(api_key=api_key)
        result = genai.embed_content(
            model="models/gemini-embedding-001",
            content=texts,
            task_type="RETRIEVAL_DOCUMENT"
        )
        return result['embedding'] if isinstance(texts, str) else result['embedding']
    except Exception as e:
        print(f"WARNING: Embedding generation failed: {e}", file=sys.stderr)
        return None


def generate_query_embedding(text):
    """Generate embedding for a query."""
    try:
        import google.generativeai as genai
        api_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
        if not api_key:
            return None
        genai.configure(api_key=api_key)
        result = genai.embed_content(
            model="models/gemini-embedding-001",
            content=text,
            task_type="RETRIEVAL_QUERY"
        )
        return result['embedding']
    except Exception:
        return None


def ingest_run(run_dir):
    """Ingest eval results from a run directory into the database."""
    run_dir = Path(run_dir)
    progress_file = run_dir / "progress.jsonl"

    if not progress_file.exists():
        print(json.dumps({"error": f"progress.jsonl not found in {run_dir}"}))
        sys.exit(1)

    run_id = run_dir.name

    db = get_db()
    cases = []
    texts_for_embedding = []

    with open(progress_file) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                case = json.loads(line)
            except json.JSONDecodeError:
                continue

            test_idx = case.get("test_idx", 0)
            test_case = case.get("test_case", {})
            inputs = test_case.get("inputs", {})
            expected = test_case.get("expected", {})
            actual = case.get("actual", {})
            aggregate_score = case.get("aggregate_score", 1.0)

            guidelines = inputs.get("guidelines", [])
            guideline_text = guidelines[0].get("guideline", "") if guidelines else ""
            classification = guidelines[0].get("classification", "unknown") if guidelines else "unknown"

            media_desc = inputs.get("content", {}).get("media_descriptions", "")
            if isinstance(media_desc, list):
                media_desc = " | ".join(str(d) for d in media_desc)

            guardian_answer = str(actual.get("answer", ""))
            human_answer = str(expected.get("answer", ""))
            agreed = 1 if aggregate_score >= 1.0 else 0
            reasoning = actual.get("reasoning", "")
            justification = actual.get("justification", "")

            error_type = None
            if not agreed:
                g_bool = guardian_answer.lower() in ("true", "yes", "1", "approved")
                h_bool = human_answer.lower() in ("true", "yes", "1", "approved")
                if g_bool and not h_bool:
                    error_type = "false_negative"
                elif not g_bool and h_bool:
                    error_type = "false_positive"
                else:
                    error_type = "interpretation_error"

            cases.append({
                "run_id": run_id,
                "test_idx": test_idx,
                "classification": classification,
                "guideline_text": guideline_text,
                "media_description": str(media_desc)[:1000],
                "guardian_answer": guardian_answer,
                "human_answer": human_answer,
                "agreed": agreed,
                "error_type": error_type,
                "reasoning": str(reasoning)[:2000],
                "justification": str(justification)[:2000],
            })

            embed_text = f"{guideline_text} | {str(media_desc)[:500]}"
            texts_for_embedding.append(embed_text)

    inserted = 0
    for case in cases:
        try:
            db.execute("""
                INSERT OR IGNORE INTO eval_cases
                (run_id, test_idx, classification, guideline_text, media_description,
                 guardian_answer, human_answer, agreed, error_type, reasoning, justification)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                case["run_id"], case["test_idx"], case["classification"],
                case["guideline_text"], case["media_description"],
                case["guardian_answer"], case["human_answer"],
                case["agreed"], case["error_type"],
                case["reasoning"], case["justification"]
            ))
            inserted += 1
        except sqlite3.IntegrityError:
            pass

    db.commit()

    embeddings_stored = 0
    if texts_for_embedding:
        BATCH_SIZE = 50
        for i in range(0, len(texts_for_embedding), BATCH_SIZE):
            batch_texts = texts_for_embedding[i:i + BATCH_SIZE]
            batch_embeddings = generate_embeddings(batch_texts)
            if batch_embeddings:
                for j, emb in enumerate(batch_embeddings):
                    case_idx = i + j
                    if case_idx < len(cases):
                        row = db.execute(
                            "SELECT id FROM eval_cases WHERE run_id = ? AND test_idx = ?",
                            (cases[case_idx]["run_id"], cases[case_idx]["test_idx"])
                        ).fetchone()
                        if row:
                            try:
                                import struct
                                emb_bytes = struct.pack(f'{len(emb)}f', *emb)
                                db.execute(
                                    "INSERT OR REPLACE INTO eval_case_embeddings (case_id, embedding) VALUES (?, ?)",
                                    (row["id"], emb_bytes)
                                )
                                embeddings_stored += 1
                            except Exception:
                                pass
            db.commit()

    db.close()
    print(json.dumps({
        "status": "ok",
        "run_id": run_id,
        "total_cases": len(cases),
        "inserted": inserted,
        "embeddings_stored": embeddings_stored
    }))


def query_cases(classification=None, error_type=None, case_type=None, text=None, limit=10):
    """Query the few-shot database."""
    db = get_db()
    results = []

    if text:
        query_emb = generate_query_embedding(text)
        if query_emb:
            import struct
            emb_bytes = struct.pack(f'{len(query_emb)}f', *query_emb)
            rows = db.execute("""
                SELECT ec.*, e.distance
                FROM eval_case_embeddings e
                JOIN eval_cases ec ON ec.id = e.case_id
                WHERE e.embedding MATCH ?
                AND k = ?
                ORDER BY e.distance
            """, (emb_bytes, limit)).fetchall()
            results = [dict(r) for r in rows]
        else:
            rows = db.execute("""
                SELECT * FROM eval_cases
                WHERE guideline_text LIKE ?
                ORDER BY created_at DESC LIMIT ?
            """, (f"%{text}%", limit)).fetchall()
            results = [dict(r) for r in rows]
    else:
        conditions = []
        params = []

        if classification:
            conditions.append("classification = ?")
            params.append(classification)
        if case_type == "success":
            conditions.append("agreed = 1")
        elif case_type == "failure":
            conditions.append("agreed = 0")
        if error_type:
            conditions.append("error_type = ?")
            params.append(error_type)

        where = f"WHERE {' AND '.join(conditions)}" if conditions else ""
        params.append(limit)

        rows = db.execute(f"""
            SELECT * FROM eval_cases
            {where}
            ORDER BY created_at DESC LIMIT ?
        """, params).fetchall()
        results = [dict(r) for r in rows]

    db.close()
    print(json.dumps(results, indent=2, default=str))


def stats():
    """Show database statistics."""
    db = get_db()

    total = db.execute("SELECT COUNT(*) as cnt FROM eval_cases").fetchone()["cnt"]
    if total == 0:
        db.close()
        print(json.dumps({"total_cases": 0, "message": "Database is empty. Run 'ingest' first."}))
        return

    agreed = db.execute("SELECT COUNT(*) as cnt FROM eval_cases WHERE agreed = 1").fetchone()["cnt"]
    disagreed = total - agreed

    by_classification = db.execute("""
        SELECT classification,
               COUNT(*) as total,
               SUM(agreed) as agreed,
               COUNT(*) - SUM(agreed) as disagreed,
               ROUND(100.0 * SUM(agreed) / COUNT(*), 1) as agreement_rate
        FROM eval_cases
        GROUP BY classification
        ORDER BY agreement_rate ASC
    """).fetchall()

    by_error_type = db.execute("""
        SELECT error_type, COUNT(*) as cnt
        FROM eval_cases
        WHERE error_type IS NOT NULL
        GROUP BY error_type
        ORDER BY cnt DESC
    """).fetchall()

    runs = db.execute("""
        SELECT run_id, COUNT(*) as cases, MIN(created_at) as date
        FROM eval_cases
        GROUP BY run_id
        ORDER BY date DESC
        LIMIT 10
    """).fetchall()

    try:
        embeddings_count = db.execute("SELECT COUNT(*) as cnt FROM eval_case_embeddings").fetchone()["cnt"]
    except Exception:
        embeddings_count = 0

    db.close()

    print(json.dumps({
        "total_cases": total,
        "agreed": agreed,
        "disagreed": disagreed,
        "overall_agreement_rate": round(100.0 * agreed / total, 1),
        "embeddings": embeddings_count,
        "by_classification": [dict(r) for r in by_classification],
        "by_error_type": [dict(r) for r in by_error_type],
        "recent_runs": [dict(r) for r in runs]
    }, indent=2, default=str))


def main():
    parser = argparse.ArgumentParser(description="Few-Shot Database for Guardian Eval Cases")
    sub = parser.add_subparsers(dest="command")

    sub.add_parser("init", help="Initialize the database")

    ingest_p = sub.add_parser("ingest", help="Ingest eval results")
    ingest_p.add_argument("--run-dir", required=True, help="Path to eval run directory")

    query_p = sub.add_parser("query", help="Query the database")
    query_p.add_argument("--classification", help="Filter by classification")
    query_p.add_argument("--error-type", help="Filter by error type")
    query_p.add_argument("--type", choices=["success", "failure"], help="Filter by agreement")
    query_p.add_argument("--text", help="Semantic search query")
    query_p.add_argument("--limit", type=int, default=10, help="Max results")

    sub.add_parser("stats", help="Show database statistics")

    args = parser.parse_args()

    if args.command == "init":
        init_db()
    elif args.command == "ingest":
        ingest_run(args.run_dir)
    elif args.command == "query":
        query_cases(
            classification=args.classification,
            error_type=args.error_type,
            case_type=args.type,
            text=args.text,
            limit=args.limit
        )
    elif args.command == "stats":
        stats()
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
