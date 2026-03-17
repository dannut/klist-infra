#!/usr/bin/env python3
"""
kli.st — generate_embeddings.py
Generates nomic-embed-text embeddings for all commands via Ollama
and stores them in PostgreSQL (pgvector).

Usage (run from kubectl or locally with port-forward):
  python3 generate_embeddings.py

Environment variables (all optional, have defaults for Kubernetes):
  DB_HOST      PostgreSQL host    (default: postgres.kli.svc.cluster.local)
  DB_PORT      PostgreSQL port    (default: 5432)
  DB_USER      PostgreSQL user    (default: kli_user)
  DB_PASSWORD  PostgreSQL pass    (required)
  DB_NAME      PostgreSQL db      (default: kli_db)
  OLLAMA_URL   Ollama base URL    (default: http://ollama.kli.svc.cluster.local:11434)
  BATCH_SIZE   Commands per batch (default: 10)
"""

import os
import json
import time
import gc
import sys

import psycopg2
import requests

# ── Config ────────────────────────────────────────────────────────────────────

DB_CONFIG = {
    "host":     os.getenv("DB_HOST",     "postgres.kli.svc.cluster.local"),
    "port":     int(os.getenv("DB_PORT", "5432")),
    "user":     os.getenv("DB_USER",     "kli_user"),
    "password": os.getenv("DB_PASSWORD", ""),
    "dbname":   os.getenv("DB_NAME",     "kli_db"),
}

OLLAMA_URL  = os.getenv("OLLAMA_URL", "http://ollama.kli.svc.cluster.local:11434")
MODEL       = "nomic-embed-text"
BATCH_SIZE  = int(os.getenv("BATCH_SIZE", "10"))

# ── Embedding ─────────────────────────────────────────────────────────────────

def get_embedding(text: str) -> list:
    resp = requests.post(
        f"{OLLAMA_URL}/api/embeddings",
        json={"model": MODEL, "prompt": text},
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json()["embedding"]

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    print(f"Connecting to PostgreSQL at {DB_CONFIG['host']}:{DB_CONFIG['port']}...")
    try:
        conn = psycopg2.connect(**DB_CONFIG)
    except Exception as e:
        print(f"ERROR: Cannot connect to PostgreSQL: {e}")
        sys.exit(1)

    cur = conn.cursor()

    cur.execute("SELECT COUNT(*) FROM commands WHERE embedding IS NULL")
    total = cur.fetchone()[0]
    print(f"Connected OK. Commands without embeddings: {total}")

    if total == 0:
        print("All embeddings already generated. Nothing to do.")
        cur.close()
        conn.close()
        return

    # Verify Ollama is reachable
    try:
        r = requests.get(f"{OLLAMA_URL}/api/tags", timeout=5)
        r.raise_for_status()
        print(f"Ollama reachable at {OLLAMA_URL}")
    except Exception as e:
        print(f"ERROR: Cannot reach Ollama at {OLLAMA_URL}: {e}")
        sys.exit(1)

    processed = 0
    errors    = 0

    while True:
        cur.execute(
            "SELECT id, syntax, description FROM commands WHERE embedding IS NULL LIMIT %s",
            (BATCH_SIZE,)
        )
        rows = cur.fetchall()
        if not rows:
            break

        for cmd_id, syntax, description in rows:
            text = f"{syntax} {description}"
            try:
                embedding = get_embedding(text)
                cur.execute(
                    "UPDATE commands SET embedding = %s::vector WHERE id = %s",
                    (json.dumps(embedding), cmd_id)
                )
                processed += 1
            except Exception as e:
                print(f"  WARNING: Failed embedding for id={cmd_id}: {e}")
                errors += 1

        conn.commit()
        gc.collect()
        pct = round((processed / total) * 100) if total > 0 else 0
        print(f"  {processed}/{total} ({pct}%) done...")
        time.sleep(0.2)

    cur.close()
    conn.close()
    print(f"\nDone! {processed} embeddings generated, {errors} errors.")
    if errors > 0:
        print(f"Re-run the script to retry failed embeddings.")

if __name__ == "__main__":
    main()
