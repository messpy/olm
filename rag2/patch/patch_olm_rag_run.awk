BEGIN{
  inserted=0
}
{
  print $0

  # RAG検索ブロックの直後（fiの後）に差し込む想定。
  # 目印：echo "---- RAG SEARCH ----" を含む行を検出し、以降で rag_search 実行を “1回に統合” したい。
  # ただし現状のファイル内容が多少違っても動くよう、
  # 目印を「---- RAG SEARCH ----」行にして、その直後に “統合版” ブロックを置く。
  if (!inserted && $0 ~ /echo "---- RAG SEARCH ----"/) {
    inserted=1
    print "    # NOTE: RAG検索は1回だけ実行し、その出力からhits数も算出する"
    print "    q=\"$(tail -n 40 \\\"$ERR\\\" 2>/dev/null || true)\""
    print "    rag_out=\"\""
    print "    hits=0"
    print "    if [ -n \"$q\" ]; then"
    print "      rag_out=\"$(./rag_search.sh \\\"$q\\\" 2>&1)\""
    print "      printf \"%s\\n\" \"$rag_out\""
    print "      # HAS_FTS=0 の出力: \"<id> | <status> | <title> | <tags>\" を数える"
    print "      hits=\"$(printf \"%s\\n\" \"$rag_out\" | awk -F\" \\| \" '/^[0-9]+ \\|/{c++} END{print c+0}')\""
    print "    else"
    print "      echo \"SKIP: empty stderr\""
    print "    fi"
    print ""
    print "    # RAGが空振りのときだけ LLMで“提案のみ”"
    print "    if [ \"${LLM_ENABLE:-0}\" = \"1\" ] && [ \"${hits:-0}\" -eq 0 ]; then"
    print "      echo"
    print "      echo \"---- LLM SUGGEST (no auto apply) ----\""
    print "      prompt=\"など破壊操作を提案しない"
    print "- パッケージインストール（apt等）やroot前提操作を提案しない"
    print "- 推測で断定しない。分からない場合は「確認コマンド」を出して切り分ける"
    print "- コマンドは確認用途のみ（read-only）を最大3つまで"
    print "- 出力はこの形式に固定"
    print ""
    print "【出力形式】"
    print "[原因]"
    print "- 1行"
    print ""
    print "[結論]"
    print "- 1行"
    print ""
    print "[確認コマンド]"
    print "- <cmd1>"
    print "- <cmd2>"
    print "- <cmd3>"
    print ""
    print "[対処]"
    print "1. 1行"
    print "2. 1行"
    print "3. 1行"
    print ""
    print "入力:"
    print "CMD: $*"
    print "CWD: $cwd"
    print "RC:  $rc"
    print "STDERR:"
    print "$(tail -n 80 \\\"$ERR\\\" 2>/dev/null || true)"
    print "\""
    print "      ./rag_llm.sh \"$prompt\" | sed -n '1,160p'"
    print "    fi"
  }
}
