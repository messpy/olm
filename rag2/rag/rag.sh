#!/usr/bin/env bash
# rag.sh - RAG unified CLI
# Usage:
#   rag.sh init
#   rag.sh add [--stdin] <title> <tags> [body...]
#   rag.sh search <query...>
#   rag.sh save-failed --cmd <cmd> --rc <rc> --dur <dur> --cwd <cwd> --stderr <file> --stdout <file> [--tags <tags>]
#   rag.sh save-ok    --cmd <cmd> --dur <dur> --cwd <cwd> --stdout <file> [--tags <tags>]
#   rag.sh suggest-ok <cmd...>
#   rag.sh rule-suggest <cmd...>   < stderr.txt

set -u
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

DB="${RAG_DB:-./rag.db}"

die()  { echo "ERROR: $*" >&2; exit 1; }
need_sqlite3() { command -v sqlite3 >/dev/null 2>&1 || die "sqlite3 not found"; }
need_db()      { test -f "$DB" || die "DB not found: $DB  (run: rag.sh init)"; }
esc()          { sed "s/'/''/g"; }

mk_cmd_sig() {
  printf "%s" "$1" \
  | sed -E 's/[[:space:]]+/ /g' \
  | sed -E 's#/(home|Users)/[^ ]+#<PATH>#g' \
  | sed -E 's/[0-9]+/<N>/g' \
  | cut -c1-160
}

# ============================================================
# サブコマンド
# ============================================================

cmd_init() {
  need_sqlite3

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

  if [ "$HAS_FTS5" = "1" ]; then
    sqlite3 "$DB" <<'SQL'
CREATE VIRTUAL TABLE IF NOT EXISTS cases_fts USING fts5(
  title, tags, err_sig, cmd_sig, body, explanation,
  content='cases', content_rowid='id', tokenize='unicode61'
);
SQL
  fi

  echo "OK: initialized DB=$DB"
}

# ------------------------------------------------------------

cmd_add() {
  need_sqlite3; need_db

  local mode="args"
  if [ "${1:-}" = "--stdin" ]; then mode="stdin"; shift; fi

  local title="${1:-}" tags="${2:-}"
  shift 2 2>/dev/null || true
  [ -n "$title" ] || die "usage: rag.sh add [--stdin] <title> <tags> [body...]"

  local body
  if [ "$mode" = "stdin" ]; then
    body="$(cat)"
  else
    body="${*:-}"
  fi
  [ -n "$body" ] || die "body is empty"

  local t g b
  t="$(printf "%s" "$title" | esc)"
  g="$(printf "%s" "$tags"  | esc)"
  b="$(printf "%s" "$body"  | esc)"

  local id
  id="$(sqlite3 -noheader "$DB" <<SQL
INSERT INTO cases(status,parent_id,title,tags,fingerprint,body,err_sig,cmd_sig,updated_at)
VALUES('note',NULL,'$t','$g',NULL,'$b','$t','',datetime('now'));
SELECT last_insert_rowid();
SQL
)" || die "insert failed"

  echo "OK: added id=$id"
}

# ------------------------------------------------------------

cmd_search() {
  need_sqlite3; need_db

  local q="${*:-}"
  [ -n "$q" ] || die "usage: rag.sh search <query...>"

  local HAS_FTS=0
  sqlite3 -noheader -readonly "$DB" \
    "SELECT name FROM sqlite_master WHERE type='table' AND name='cases_fts' LIMIT 1;" \
    | grep -qx 'cases_fts' && HAS_FTS=1

  echo "DB=[$DB]"
  echo "HAS_FTS=$HAS_FTS"
  echo "QUERY_RAW=[$q]"
  echo

  if [ "$HAS_FTS" = "1" ]; then
    local tok fts_q
    tok="$(printf "%s" "$q" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
    tok="$(printf "%s" "$tok" | sed -E 's/[^[:alnum:]_.-]+/ /g; s/[[:space:]]+/ /g; s/^ //; s/ $//')"
    fts_q="$(printf "%s" "$tok" | awk '{for(i=1;i<=NF;i++){printf "%s%s",$i,(i<NF?" AND ":"")}}')"
    echo "QUERY_FTS=[$fts_q]"
    echo
    sqlite3 -noheader -readonly "$DB" <<SQL
.mode list
.separator " | "
SELECT
  printf('%.2f', bm25(cases_fts)) AS score,
  c.id, c.status,
  COALESCE(c.title,''),
  COALESCE(c.tags,'')
FROM cases_fts
JOIN cases c ON c.id = cases_fts.rowid
WHERE cases_fts MATCH '$fts_q'
ORDER BY bm25(cases_fts)
LIMIT 10;
SQL
  else
    local tok t1 t2 t3
    tok="$(printf "%s" "$q" | tr '\n' ' ' | sed -E 's/[^[:alnum:]_.-]+/ /g; s/[[:space:]]+/ /g; s/^ //; s/ $//')"
    echo "TOKENS=[$tok]"
    echo
    t1="$(printf "%s" "$tok" | awk '{print $1}')"
    t2="$(printf "%s" "$tok" | awk '{print $2}')"
    t3="$(printf "%s" "$tok" | awk '{print $3}')"
    sqlite3 -noheader -readonly "$DB" <<SQL
.mode list
.separator " | "
SELECT c.id, c.status, COALESCE(c.title,''), COALESCE(c.tags,'')
FROM cases c
WHERE
  (c.title LIKE '%'||'$t1'||'%' OR c.body LIKE '%'||'$t1'||'%')
  AND (CASE WHEN '$t2'='' THEN 1 ELSE (c.title LIKE '%'||'$t2'||'%' OR c.body LIKE '%'||'$t2'||'%') END)
  AND (CASE WHEN '$t3'='' THEN 1 ELSE (c.title LIKE '%'||'$t3'||'%' OR c.body LIKE '%'||'$t3'||'%') END)
ORDER BY c.updated_at DESC
LIMIT 10;
SQL
  fi
}

# ------------------------------------------------------------

cmd_save_failed() {
  need_sqlite3; need_db

  local cmd="" rc="" dur="0" cwd; cwd="$(pwd)"
  local stderr_f="" stdout_f="" tags_extra=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --cmd)    cmd="$2";      shift 2 ;;
      --rc)     rc="$2";       shift 2 ;;
      --dur)    dur="$2";      shift 2 ;;
      --cwd)    cwd="$2";      shift 2 ;;
      --stderr) stderr_f="$2"; shift 2 ;;
      --stdout) stdout_f="$2"; shift 2 ;;
      --tags)   tags_extra="$2"; shift 2 ;;
      *) die "unknown arg: $1" ;;
    esac
  done

  [ -n "$cmd" ]      || die "--cmd required"
  [ -n "$rc" ]       || die "--rc required"
  [ -f "$stderr_f" ] || die "--stderr not found: $stderr_f"
  [ -f "$stdout_f" ] || die "--stdout not found: $stdout_f"

  local err_tail out_tail err_sig cmd_sig title tags fingerprint body
  err_tail="$(tail -n 80 "$stderr_f" 2>/dev/null || true)"
  out_tail="$(tail -n 80 "$stdout_f" 2>/dev/null || true)"

  err_sig="$(printf "%s" "$err_tail" \
    | tr '\n' ' ' \
    | sed -E 's/[[:space:]]+/ /g' \
    | sed -E 's#/(home|Users)/[^ ]+#<PATH>#g' \
    | sed -E 's/[0-9]+/<N>/g' \
    | cut -c1-220)"

  cmd_sig="$(mk_cmd_sig "$cmd")"
  title="$err_sig"; [ -z "$title" ] && title="rc=$rc $cmd_sig"
  tags="failed"; [ -n "$tags_extra" ] && tags="$tags,$tags_extra"
  fingerprint="$(printf "%s|%s" "$cmd_sig" "$err_sig" | sha1sum | awk '{print $1}')"

  body="CMD: $cmd
EXIT: $rc
DUR_SEC: $dur
CWD: $cwd

STDERR (tail 80):
$err_tail

STDOUT (tail 80):
$out_tail
"

  local t g b es cs cw
  t="$(printf "%s" "$title"   | esc)"
  g="$(printf "%s" "$tags"    | esc)"
  b="$(printf "%s" "$body"    | esc)"
  es="$(printf "%s" "$err_sig"  | esc)"
  cs="$(printf "%s" "$cmd_sig"  | esc)"
  cw="$(printf "%s" "$cwd"      | esc)"

  sqlite3 "$DB" <<SQL
INSERT INTO cases(status,parent_id,title,tags,fingerprint,body,cmd,rc,dur_sec,cwd,project_root,err_sig,cmd_sig,updated_at)
VALUES('failed',NULL,'$t','$g','$fingerprint','$b','$(printf "%s" "$cmd" | esc)',$rc,$dur,'$cw','','$es','$cs',datetime('now'))
ON CONFLICT(fingerprint) DO UPDATE SET
  updated_at=datetime('now'), tags=excluded.tags, body=excluded.body,
  cmd=excluded.cmd, rc=excluded.rc, dur_sec=excluded.dur_sec,
  cwd=excluded.cwd, err_sig=excluded.err_sig, cmd_sig=excluded.cmd_sig;
SQL

  local id
  id="$(sqlite3 -noheader "$DB" "SELECT id FROM cases WHERE fingerprint='$fingerprint' LIMIT 1;")"
  echo "OK: saved failed id=$id"
}

# ------------------------------------------------------------

cmd_save_ok() {
  need_sqlite3; need_db

  local cmd="" dur="0" cwd; cwd="$(pwd)"
  local stdout_f="" tags_extra=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --cmd)    cmd="$2";      shift 2 ;;
      --dur)    dur="$2";      shift 2 ;;
      --cwd)    cwd="$2";      shift 2 ;;
      --stdout) stdout_f="$2"; shift 2 ;;
      --tags)   tags_extra="$2"; shift 2 ;;
      *) die "unknown arg: $1" ;;
    esac
  done

  [ -n "$cmd" ]      || die "--cmd required"
  [ -f "$stdout_f" ] || die "--stdout not found: $stdout_f"

  local out_tail cmd_sig title tags fingerprint body
  out_tail="$(tail -n 80 "$stdout_f" 2>/dev/null || true)"
  cmd_sig="$(mk_cmd_sig "$cmd")"
  title="OK: $cmd_sig"
  tags="ok"; [ -n "$tags_extra" ] && tags="$tags,$tags_extra"
  fingerprint="$(printf "ok|%s" "$cmd_sig" | sha1sum | awk '{print $1}')"

  body="CMD: $cmd
EXIT: 0
DUR_SEC: $dur
CWD: $cwd

STDOUT (tail 80):
$out_tail
"

  local t g b cs cw
  t="$(printf "%s" "$title"  | esc)"
  g="$(printf "%s" "$tags"   | esc)"
  b="$(printf "%s" "$body"   | esc)"
  cs="$(printf "%s" "$cmd_sig" | esc)"
  cw="$(printf "%s" "$cwd"    | esc)"

  sqlite3 "$DB" <<SQL
INSERT INTO cases(status,parent_id,title,tags,fingerprint,body,cmd,rc,dur_sec,cwd,project_root,err_sig,cmd_sig,updated_at)
VALUES('ok',NULL,'$t','$g','$fingerprint','$b','$(printf "%s" "$cmd" | esc)',0,$dur,'$cw','','','$cs',datetime('now'))
ON CONFLICT(fingerprint) DO UPDATE SET
  updated_at=datetime('now'), tags=excluded.tags, body=excluded.body,
  cmd=excluded.cmd, dur_sec=excluded.dur_sec,
  cwd=excluded.cwd, cmd_sig=excluded.cmd_sig;
SQL

  local id
  id="$(sqlite3 -noheader "$DB" "SELECT id FROM cases WHERE fingerprint='$fingerprint' LIMIT 1;")"
  echo "OK: saved ok id=$id"
}

# ------------------------------------------------------------

cmd_suggest_ok() {
  need_sqlite3; need_db

  local cmd="${*:-}"
  [ -n "$cmd" ] || die "usage: rag.sh suggest-ok <cmd...>"

  local cmd_sig
  cmd_sig="$(mk_cmd_sig "$cmd")"

  echo "---- OK SUGGEST (same cmd) ----"
  echo "CMD_SIG=[$cmd_sig]"
  echo

  sqlite3 -noheader -readonly "$DB" <<SQL
.mode list
.separator " | "
SELECT id, updated_at, title
FROM cases
WHERE status='ok' AND cmd_sig='$cmd_sig'
ORDER BY updated_at DESC
LIMIT 3;
SQL

  echo
  echo "---- OK CONTEXT (top 1) ----"
  local id
  id="$(sqlite3 -noheader -readonly "$DB" \
    "SELECT id FROM cases WHERE status='ok' AND cmd_sig='$cmd_sig' ORDER BY updated_at DESC LIMIT 1;")"
  if [ -n "$id" ]; then
    sqlite3 -noheader -readonly "$DB" "SELECT body FROM cases WHERE id=$id;" | sed -n '1,80p'
  else
    echo "(no ok record for same cmd_sig)"
  fi
}

# ------------------------------------------------------------

cmd_rule_suggest() {
  local cmd="${*:-}"
  [ -n "$cmd" ] || cmd="(unknown)"

  local stderr
  stderr="$(cat 2>/dev/null || true)"

  local is_missing=0
  printf "%s" "$stderr" \
    | grep -qiE 'No such file or directory|Failed to spawn|cannot open|not found' \
    && is_missing=1

  [ "$is_missing" -eq 1 ] || exit 0

  pick_path() {
    local s="$1" p=""
    p="$(printf "%s" "$s" | tr '\n' ' ' | sed -nE 's/.*`([^`]+)`.*/\1/p' | head -n 1)"
    [ -n "$p" ] && { printf "%s" "$p"; return 0; }
    p="$(printf "%s" "$s" | tr '\n' ' ' | sed -nE 's/.*"([^"]+)".*/\1/p' | head -n 1)"
    [ -n "$p" ] && { printf "%s" "$p"; return 0; }
    p="$(printf "%s" "$s" | tr '\n' ' ' | sed -nE "s/.*'([^']+)'.*/\\1/p" | head -n 1)"
    [ -n "$p" ] && { printf "%s" "$p"; return 0; }
    p="$(printf "%s" "$s" | tr '\n' ' ' | grep -oE '[[:alnum:]_./-]+\.py' | head -n 1)"
    [ -n "$p" ] && { printf "%s" "$p"; return 0; }
    printf "%s" ""
  }

  local p
  p="$(pick_path "$stderr")"

  echo "[原因]"
  echo "- 実行対象のファイル/パスが存在しない可能性が高い（No such file / Failed to spawn 系）"
  echo
  echo "[結論]"
  echo "- まず「どのディレクトリで」「どのパスを」参照しているかを確認する"
  echo
  echo "[確認コマンド]"
  echo "- pwd"
  if [ -n "$p" ]; then
    echo "- ls -la '$p'"
    echo "- ls -la '$(dirname "$p" 2>/dev/null || echo .)'"
  else
    echo "- ls -la"
    echo "- ls -la ./bin ./"
  fi
  echo
  echo "[対処]"
  echo "1. 上の確認で対象パスが無いなら、作業ディレクトリ（プロジェクトルート）を正しい場所に合わせる"
  echo "2. 対象パスが無いなら、ファイル名/配置（bin/run.py など）が期待どおりか見直す"
  echo "3. 参照パスが相対なら、実行前に cd する/絶対パス化する（どちらかに統一）"
}

# ============================================================
# ヘルプ
# ============================================================

cmd_help() {
  cat <<'HELP'
Usage: rag.sh <subcommand> [options]

Subcommands:
  init                                    DBを初期化（初回のみ）
  add [--stdin] <title> <tags> [body...]  メモを手動登録
  search <query...>                       キーワード検索
  save-failed --cmd .. --rc .. --dur ..   失敗を記録
               --cwd .. --stderr <file> --stdout <file> [--tags ..]
  save-ok     --cmd .. --dur .. --cwd ..  成功を記録
               --stdout <file> [--tags ..]
  suggest-ok  <cmd...>                    同コマンドの成功履歴を表示
  rule-suggest <cmd...>  < stderr.txt     ルールベースで原因と対処を表示

Environment:
  RAG_DB   DB path (default: ./rag.db)
HELP
}

# ============================================================
# エントリポイント
# ============================================================

subcmd="${1:-help}"
[ $# -gt 0 ] && shift

case "$subcmd" in
  init)           cmd_init "$@" ;;
  add)            cmd_add "$@" ;;
  search)         cmd_search "$@" ;;
  save-failed)    cmd_save_failed "$@" ;;
  save-ok)        cmd_save_ok "$@" ;;
  suggest-ok)     cmd_suggest_ok "$@" ;;
  rule-suggest)   cmd_rule_suggest "$@" ;;
  help|--help|-h) cmd_help ;;
  *) echo "ERROR: unknown subcommand: $subcmd" >&2; cmd_help; exit 1 ;;
esac
