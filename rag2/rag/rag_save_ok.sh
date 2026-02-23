#!/usr/bin/env bash
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
DB="${RAG_DB:-./rag.db}"

die(){ echo "ERROR: $*" >&2; exit 1; }
command -v sqlite3 >/dev/null 2>&1 || die "sqlite3 not found"
test -f "$DB" || die "DB not found: $DB"

cmd=""; dur="0"; cwd="$(pwd)"; stdout_f=""; tags_extra=""

while [ $# -gt 0 ]; do
  case "$1" in
    --cmd) cmd="$2"; shift 2;;
    --dur) dur="$2"; shift 2;;
    --cwd) cwd="$2"; shift 2;;
    --stdout) stdout_f="$2"; shift 2;;
    --tags) tags_extra="$2"; shift 2;;
    *) die "unknown arg: $1";;
  esac
done

[ -n "$cmd" ] || die "--cmd required"
[ -f "$stdout_f" ] || die "--stdout not found"

esc(){ sed "s/'/''/g"; }

out_tail="$(tail -n 80 "$stdout_f" 2>/dev/null || true)"

cmd_sig="$(
  printf "%s" "$cmd" \
  | sed -E 's/[[:space:]]+/ /g' \
  | sed -E 's#/(home|Users)/[^ ]+#<PATH>#g' \
  | sed -E 's/[0-9]+/<N>/g' \
  | cut -c1-160
)"

title="OK: $cmd_sig"
tags="ok"
[ -n "$tags_extra" ] && tags="$tags,$tags_extra"

# 成功は cmd_sig のみで同一判定（同じコマンド成功は更新）
fingerprint="$(printf "ok|%s" "$cmd_sig" | sha1sum | awk '{print $1}')"

body="CMD: $cmd
EXIT: 0
DUR_SEC: $dur
CWD: $cwd

STDOUT (tail 80):
$out_tail
"

t="$(printf "%s" "$title" | esc)"
g="$(printf "%s" "$tags"  | esc)"
b="$(printf "%s" "$body"  | esc)"
cs="$(printf "%s" "$cmd_sig" | esc)"
cw="$(printf "%s" "$cwd" | esc)"

sqlite3 "$DB" <<SQL
INSERT INTO cases(status,parent_id,title,tags,fingerprint,body,cmd,rc,dur_sec,cwd,project_root,err_sig,cmd_sig,updated_at)
VALUES('ok',NULL,'$t','$g','$fingerprint','$b','$(printf "%s" "$cmd" | esc)',0,$dur,'$cw','', '', '$cs', datetime('now'))
ON CONFLICT(fingerprint) DO UPDATE SET
  updated_at=datetime('now'),
  tags=excluded.tags,
  body=excluded.body,
  cmd=excluded.cmd,
  dur_sec=excluded.dur_sec,
  cwd=excluded.cwd,
  cmd_sig=excluded.cmd_sig;
SQL

id="$(sqlite3 -noheader "$DB" "SELECT id FROM cases WHERE fingerprint='$fingerprint' LIMIT 1;")"
echo "OK: saved ok id=$id"
