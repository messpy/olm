#!/usr/bin/env bash
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
DB="${RAG_DB:-./rag.db}"

die(){ echo "ERROR: $*" >&2; exit 1; }
command -v sqlite3 >/dev/null 2>&1 || die "sqlite3 not found"
test -f "$DB" || die "DB not found: $DB"

q="${*:-}"
[ -n "$q" ] || die "usage: $0 <query...>"

# FTS5 有無判定（cases_fts が存在するかで判定）
HAS_FTS=0
sqlite3 -noheader -readonly "$DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='cases_fts' LIMIT 1;" | grep -qx 'cases_fts' && HAS_FTS=1
echo "DB=[$DB]"
echo "HAS_FTS=$HAS_FTS"
echo "QUERY_RAW=[$q]"
echo

if [ "$HAS_FTS" = "1" ]; then
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
  c.id,
  c.status,
  COALESCE(c.title,''),
  COALESCE(c.tags,'')
FROM cases_fts
JOIN cases c ON c.id = cases_fts.rowid
WHERE cases_fts MATCH '$fts_q'
ORDER BY bm25(cases_fts)
LIMIT 10;
SQL
else
  # FTS5 無し fallback: LIKE（簡易）
  # 記号は荒れるので空白で分割して AND 条件にする
  tok="$(printf "%s" "$q" | tr '\n' ' ' | sed -E 's/[^[:alnum:]_.-]+/ /g; s/[[:space:]]+/ /g; s/^ //; s/ $//')"
  echo "TOKENS=[$tok]"
  echo
  # 先頭3トークンだけ使う（SQLが長くなりすぎるのを防ぐ）
  t1="$(printf "%s" "$tok" | awk '{print $1}')"
  t2="$(printf "%s" "$tok" | awk '{print $2}')"
  t3="$(printf "%s" "$tok" | awk '{print $3}')"
  sqlite3 -noheader -readonly "$DB" <<SQL
.mode list
.separator " | "
SELECT
  c.id,
  c.status,
  COALESCE(c.title,''),
  COALESCE(c.tags,'')
FROM cases c
WHERE
  (c.title LIKE '%'||'$t1'||'%' OR c.body LIKE '%'||'$t1'||'%')
  AND (CASE WHEN '$t2'='' THEN 1 ELSE (c.title LIKE '%'||'$t2'||'%' OR c.body LIKE '%'||'$t2'||'%') END)
  AND (CASE WHEN '$t3'='' THEN 1 ELSE (c.title LIKE '%'||'$t3'||'%' OR c.body LIKE '%'||'$t3'||'%') END)
ORDER BY c.updated_at DESC
LIMIT 10;
SQL
fi
