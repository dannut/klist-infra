-- kli.st database schema
-- Run this file first, then 02_seed.sql

-- Extensions
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS vector;

-- Tables
CREATE TABLE IF NOT EXISTS tools (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(100) UNIQUE NOT NULL,
    slug        VARCHAR(50)  UNIQUE NOT NULL,
    description TEXT
);

CREATE TABLE IF NOT EXISTS commands (
    id          SERIAL PRIMARY KEY,
    tool_id     INTEGER REFERENCES tools(id) ON DELETE CASCADE,
    syntax      TEXT NOT NULL,
    description TEXT NOT NULL,
    embedding   vector(768),
    UNIQUE (tool_id, syntax)
);

-- Indexes for full-text search
CREATE INDEX IF NOT EXISTS idx_fts ON commands
    USING GIN (to_tsvector('english', syntax || ' ' || description));

-- Indexes for fuzzy search (pg_trgm)
CREATE INDEX IF NOT EXISTS idx_trgm_syntax ON commands
    USING GIN (syntax gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_trgm_description ON commands
    USING GIN (description gin_trgm_ops);

-- Index for tool lookups
CREATE INDEX IF NOT EXISTS idx_tool_id ON commands(tool_id);

-- Index for vector similarity search
-- Used after embeddings are generated via generate_embeddings.py
CREATE INDEX IF NOT EXISTS idx_embedding ON commands
    USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
