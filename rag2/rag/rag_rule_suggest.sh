#!/usr/bin/env bash
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

die(){ echo "ERROR: $*" >&2; exit 1; }

# usage: rag_rule_suggest.sh <cmd...>  < stderr.txt
cmd="${*:-}"
[ -n "$cmd" ] || cmd="(unknown)"

stderr="$(cat 2>/dev/null || true)"

# 対象パターン
is_missing=0
printf "%s" "$stderr" | grep -qiE 'No such file or directory|Failed to spawn|cannot open|not found' && is_missing=1

[ "$is_missing" -eq 1 ] || exit 0

# stderr から「それっぽいパス」を拾う（優先: `...` 内 / 次: "..."/ '...' / 次: *.py）
pick_path() {
  local s="$1" p=""

  # `bin/run.py` みたいなやつ
  p="$(printf "%s" "$s" | tr '\n' ' ' | sed -nE 's/.*`([^`]+)`.*/\1/p' | head -n 1)"
  [ -n "$p" ] && { printf "%s" "$p"; return 0; }

  # "bin/run.py" / 'bin/run.py'
  p="$(printf "%s" "$s" | tr '\n' ' ' | sed -nE 's/.*"([^"]+)".*/\1/p' | head -n 1)"
  [ -n "$p" ] && { printf "%s" "$p"; return 0; }
  p="$(printf "%s" "$s" | tr '\n' ' ' | sed -nE "s/.*'([^']+)'.*/\\1/p" | head -n 1)"
  [ -n "$p" ] && { printf "%s" "$p"; return 0; }

  # *.py を拾う
  p="$(printf "%s" "$s" | tr '\n' ' ' | grep -oE '[[:alnum:]_./-]+\.py' | head -n 1)"
  [ -n "$p" ] && { printf "%s" "$p"; return 0; }

  printf "%s" ""
}

p="$(pick_path "$stderr")"

echo "[原因]"
echo "- 実行対象のファイル/パスが存在しない可能性が高い（No such file / Failed to spawn 系）"
echo
echo "[結論]"
echo "- まず「どのディレクトリで」「どのパスを」参照しているかを確認する"
echo
echo "[確認コマンド]"
# read-only 最大3つ
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
