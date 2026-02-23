#!/usr/bin/env bash
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
DB="${RAG_DB:-./rag.db}"

die(){ echo "ERROR: $*" >&2; exit 1; }
command -v sqlite3 >/dev/null 2>&1 || die "sqlite3 not found"
test -f "$DB" || die "DB not found: $DB"

cmd="${*:-}"
[ -n "$cmd" ] || die "usage: $0 <cmd...>"

# cmd_sig を rag_save_ok.sh と同じ規則で作る
cmd_sig="$(
  printf "%s" "$cmd" \
  | sed -E 's/[[:space:]]+/ /g' \
  | sed -E 's#/(home|Users)/[^ ]+#<PATH>#g' \
  | sed -E 's/[0-9]+/<N>/g' \
  | cut -c1-160
)"

echo "---- OK SUGGEST (same cmd) ----"
echo "CMD_SIG=[$cmd_sig]"
echo

# 同じcmd_sigの直近okを最大3件
sqlite3 -noheader -readonly "$DB" <<SQL
.mode list
.separator " | "
SELECT
  id,
  updated_at,
  title
FROM cases
WHERE status='ok'
  AND cmd_sig='$cmd_sig'
ORDER BY updated_at DESC
LIMIT 3;
SQL

echo
echo "---- OK CONTEXT (top 1) ----"
id="$(sqlite3 -noheader -readonly "$DB" "SELECT id FROM cases WHERE status='ok' AND cmd_sig='$cmd_sig' ORDER BY updated_at DESC LIMIT 1;")"
if [ -n "$id" ]; then
  sqlite3 -noheader -readonly "$DB" "SELECT body FROM cases WHERE id=$id;" | sed -n '1,80p'
else
  echo "(no ok record for same cmd_sig)"
fi
