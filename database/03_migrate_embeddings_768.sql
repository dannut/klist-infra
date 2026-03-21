-- Migration: update embedding column from 384 dimensions (snowflake-arctic-embed)
--            to 768 dimensions (Gemini text-embedding-004)
--
-- Run this BEFORE running generate_embeddings.py
-- Safe to run on an empty embeddings column or a populated one
-- (it will NULL out all existing embeddings, which is expected)

BEGIN;

-- Drop the existing IVFFlat index (incompatible with dimension change)
DROP INDEX IF EXISTS commands_embedding_idx;

-- Change the vector dimension; existing values are NULLed automatically
ALTER TABLE commands ALTER COLUMN embedding TYPE vector(768);

-- Re-create the index after generate_embeddings.py has populated all rows
-- (run separately after embeddings are generated)
-- CREATE INDEX commands_embedding_idx ON commands USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- NULL out any stale embeddings from the old model
UPDATE commands SET embedding = NULL;

COMMIT;

-- After running generate_embeddings.py, create the index:
-- CREATE INDEX commands_embedding_idx
--   ON commands USING ivfflat (embedding vector_cosine_ops)
--   WITH (lists = 100);
