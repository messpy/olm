#!/usr/bin/env bash
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

raw="$*"
[ -n "$raw" ] || exit 1

raw_lc="$(printf "%s" "$raw" | tr 'A-Z' 'a-z' | tr -s ' ')"

emit() {
  # KEY<TAB>VALUE
  # VALUE に空白があっても壊れない
  printf "%s\t%s\n" "$1" "$2"
}

case "$raw_lc" in
  ssh\ gen*|ssh\ keygen*|ssh\ key-gen*|ssh\ key\ gen*|ssh\ keys*|ssh\ 鍵*|ssh\ make\ key*|ssh\ create\ key*)
    emit "SUGGEST_KIND"  "ssh-keygen-ed25519-default"
    emit "SUGGEST_QUERY" "ssh-keygen ed25519"
    emit "REASON"        "ssh は接続コマンド。鍵生成は ssh-keygen（別コマンド）"
    emit "TAGS"          "ssh,keygen,auth"
    exit 0
    ;;
esac

exit 1
