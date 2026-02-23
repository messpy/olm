#!/usr/bin/env bash
set -u

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

DB="${RAG_DB:-./rag.db}"
AUTO_SAVE_FAILED="${AUTO_SAVE_FAILED:-1}"
DO_RAG_SEARCH="${DO_RAG_SEARCH:-1}"

die(){ echo "ERROR: $*" >&2; exit 1; }

command -v sqlite3 >/dev/null 2>&1 || die "sqlite3 not found"
test -f "$DB" || die "DB not found: $DB"

[ "${1:-}" = "--" ] || die "usage: $0 -- <command...>"
shift
[ $# -gt 0 ] || die "command required"

# temp
cwd="$(pwd)"
tmp_dir="${TMPDIR:-/tmp}/olm_rag.$$"
mkdir -p "$tmp_dir" || die "cannot create temp dir"
OUT="$tmp_dir/out.txt"
ERR="$tmp_dir/err.txt"

start="$(date +%s)"
"$@" 1>"$OUT" 2>"$ERR"
rc=$?
end="$(date +%s)"
dur=$((end-start))

echo "CMD=$*"
echo "EXIT=$rc"
echo "DUR_SEC=$dur"
echo
echo "---- STDERR (tail 80) ----"
tail -n 80 "$ERR" 2>/dev/null || true
echo
echo "---- STDOUT (tail 80) ----"
tail -n 80 "$OUT" 2>/dev/null || true
echo

if [ "$rc" -ne 0 ]; then
  if [ "$AUTO_SAVE_FAILED" = "1" ] && [ -x ../rag/rag_save_failed.sh ]; then
    ../rag/rag_save_failed.sh --cmd "$*" --rc "$rc" --dur "$dur" --cwd "$cwd" --stderr "$ERR" --stdout "$OUT" >/dev/null 2>&1 || true
  fi

  if [ "$DO_RAG_SEARCH" = "1" ] && [ -x ../rag/rag_search.sh ]; then
    echo "---- RAG SEARCH ----"
      RAG_SEARCH_REALPATH="$(readlink -f ../rag/rag_search.sh 2>/dev/null || realpath ../rag/rag_search.sh 2>/dev/null || echo ../rag/rag_search.sh)"
      echo "RAG_SEARCH_REALPATH=$RAG_SEARCH_REALPATH"
    q="$(tail -n 40 "$ERR" 2>/dev/null || true)"
    if [ -n "$q" ]; then
        rag_out="$(bash "$RAG_SEARCH_REALPATH" "$q" 2>&1 || true)"
        rag_out="$(printf "%s" "$rag_out" | tr -d '\r')"
        rag_out="$(printf '%s\n' "$rag_out" | sed -E 's/^\]UERY_RAW=/QUERY_RAW=/; s/^\]QUERY_RAW=/QUERY_RAW=/')"
        printf "%s\n" "$rag_out"
    else
      echo "SKIP: empty stderr"
    fi
  fi
fi

rm -rf "$tmp_dir" 2>/dev/null || true
exit "$rc"
