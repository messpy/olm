#!/usr/bin/env bash
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
DB="${RAG_DB:-./rag.db}"

die(){ echo "ERROR: $*" >&2; exit 1; }

command -v sqlite3 >/dev/null 2>&1 || die "sqlite3 not found"

# FTS5 判定（無効でも落とさない）
HAS_FTS5=0
sqlite3 -cmd '.compile_options' :memory: '' 2>/dev/null | grep -qi 'ENABLE_FTS5' && HAS_FTS5=1
echo "HAS_FTS5=$HAS_FTS5"

sqlite3 "$DB" <<'SQL'
PRAGMA journal_mode=WAL;

CREATE TABLE IF NOT EXISTS cases (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  status       TEXT NOT NULL DEFAULT 'failed',
  parent_id    INTEGER,
  title        TEXT NOT NULL,
  tags         TEXT DEFAULT '',
  fingerprint  TEXT UNIQUE,
  body         TEXT NOT NULL,
  explanation  TEXT,
  cmd          TEXT,
  rc           INTEGER,
  dur_sec      INTEGER,
  cwd          TEXT,
  project_root TEXT,
  err_sig      TEXT,
  cmd_sig      TEXT,
  created_at   TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at   TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY(parent_id) REFERENCES cases(id)
);

CREATE INDEX IF NOT EXISTS idx_cases_parent_id ON cases(parent_id);
CREATE INDEX IF NOT EXISTS idx_cases_status    ON cases(status);
CREATE INDEX IF NOT EXISTS idx_cases_title     ON cases(title);
CREATE INDEX IF NOT EXISTS idx_cases_tags      ON cases(tags);
SQL

# FTS5 がある環境だけ cases_fts を作る
if [ "$HAS_FTS5" = "1" ]; then
sqlite3 "$DB" <<'SQL'
CREATE VIRTUAL TABLE IF NOT EXISTS cases_fts USING fts5(
  title,
  tags,
  err_sig,
  cmd_sig,
  body,
  explanation,
  content='cases',
  content_rowid='id',
  tokenize='unicode61'
);
SQL
fi

echo "OK: initialized DB=$DB"
