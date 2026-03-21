#!/usr/bin/env python3
"""
kli.st — generate_embeddings.py
Generates Gemini text-embedding-004 embeddings (768 dimensions) for all
commands and stores them in PostgreSQL (pgvector).

Usage (run locally with kubectl port-forward or from a pod):
  python3 generate_embeddings.py

Environment variables:
  DB_HOST        PostgreSQL host    (default: postgres.kli.svc.cluster.local)
  DB_PORT        PostgreSQL port    (default: 5432)
  DB_USER        PostgreSQL user    (default: kli_user)
  DB_PASSWORD    PostgreSQL pass    (required)
  DB_NAME        PostgreSQL db      (default: kli_db)
  GEMINI_API_KEY Google AI API key  (required)
  BATCH_SIZE     Commands per batch (default: 20)

NOTE: text-embedding-004 produces 768-dimensional vectors.
      If your pgvector column was created with a different dimension,
      run the migration first:
        ALTER TABLE commands ALTER COLUMN embedding TYPE vector(768);
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

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
GEMINI_EMBED_URL = (
    "https://generativelanguage.googleapis.com/v1beta/models/"
    "text-embedding-004:embedContent?key={key}"
)
BATCH_SIZE = int(os.getenv("BATCH_SIZE", "20"))

# ── Embedding ─────────────────────────────────────────────────────────────────

def get_embedding(text: str) -> list:
    url = GEMINI_EMBED_URL.format(key=GEMINI_API_KEY)
    payload = {
        "model": "models/text-embedding-004",
        "content": {"parts": [{"text": text}]},
    }
    resp = requests.post(url, json=payload, timeout=15)
    resp.raise_for_status()
    return resp.json()["embedding"]["values"]

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    if not GEMINI_API_KEY:
        print("ERROR: GEMINI_API_KEY environment variable is not set.")
        sys.exit(1)

    print(f"Connecting to PostgreSQL at {DB_CONFIG['host']}:{DB_CONFIG['port']}...")
    try:
        conn = psycopg2.connect(**DB_CONFIG)
    except Exception as e:
        print(f"ERROR: Cannot connect to PostgreSQL: {e}")
        sys.exit(1)

    cur = conn.cursor()

    # Verify vector column dimension is 768
    cur.execute("""
        SELECT atttypmod FROM pg_attribute
        WHERE attrelid = 'commands'::regclass AND attname = 'embedding'
    """)
    row = cur.fetchone()
    if row and row[0] != -1:
        dim = row[0]
        if dim != 768:
            print(f"WARNING: embedding column has dimension {dim}, expected 768.")
            print("Run: ALTER TABLE commands ALTER COLUMN embedding TYPE vector(768);")
            print("Then re-run this script.")
            cur.close()
            conn.close()
            sys.exit(1)

    cur.execute("SELECT COUNT(*) FROM commands WHERE embedding IS NULL")
    total = cur.fetchone()[0]
    print(f"Connected OK. Commands without embeddings: {total}")

    if total == 0:
        print("All embeddings already generated. Nothing to do.")
        cur.close()
        conn.close()
        return

    # Quick connectivity test
    try:
        test_embedding = get_embedding("test")
        print(f"Gemini API reachable. Embedding dimension: {len(test_embedding)}")
    except Exception as e:
        print(f"ERROR: Cannot reach Gemini API: {e}")
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
            # Gemini free tier: 1500 req/min -> ~50ms between requests
            time.sleep(0.05)

        conn.commit()
        gc.collect()
        pct = round((processed / total) * 100) if total > 0 else 0
        print(f"  {processed}/{total} ({pct}%) done...")

    cur.close()
    conn.close()
    print(f"\nDone! {processed} embeddings generated, {errors} errors.")
    if errors > 0:
        print("Re-run the script to retry failed embeddings.")

if __name__ == "__main__":
    main()
