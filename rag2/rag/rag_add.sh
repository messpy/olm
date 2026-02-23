#!/usr/bin/env bash
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
DB="${RAG_DB:-./rag.db}"

die(){ echo "ERROR: $*" >&2; exit 1; }
command -v sqlite3 >/dev/null 2>&1 || die "sqlite3 not found"
test -f "$DB" || die "DB not found: $DB"

mode="args"
if [ "${1:-}" = "--stdin" ]; then
  mode="stdin"
  shift
fi

title="${1:-}"; tags="${2:-}"
shift 2 2>/dev/null || true
[ -n "$title" ] || die "usage: $0 [--stdin] <title> <tags> [body...]"
[ -n "$tags" ] || tags=""

if [ "$mode" = "stdin" ]; then
  body="$(cat)"
else
  body="${*:-}"
fi
[ -n "$body" ] || die "body is empty"

# SQLエスケープ（' を '' に）
esc(){ sed "s/'/''/g"; }

t="$(printf "%s" "$title" | esc)"
g="$(printf "%s" "$tags"  | esc)"
b="$(printf "%s" "$body"  | esc)"

# 1プロセスの sqlite3 内で rowid を取る（ズレない）
id="$(
sqlite3 -noheader "$DB" <<SQL
INSERT INTO cases(status,parent_id,title,tags,fingerprint,body,err_sig,cmd_sig,updated_at)
VALUES('note',NULL,'$t','$g',NULL,'$b','$t','',datetime('now'));
SELECT last_insert_rowid();
SQL
)" || die "insert failed"

echo "OK: added id=$id"
