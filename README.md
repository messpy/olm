# olm
- shell command helper
- run command and explain output
- analyze text from stdin
- keep history as tsv
- config via ~/.config/olm/config.env

# install
- ./setup.sh
- source ~/.profile
- olm --help

# config
- if ~/.config/olm/config.env does not exist it will be created from config/config.env.example
- key examples
- OLM_MODEL_STD
- OLM_MODEL_LGT
- OLM_MODEL_HVY
- OLM_MODEL_FA
- OLM_MODEL_FB
- OLM_LANG
- OLM_ALWAYS_PROMPT

# usage
- olm "ls -la"
- olm -e "ls /nope"
- echo "some log text" | olm --analyze
- printf "%s\n" "pwd" "ls -la" | olm --exec-stdin --yes
- olm config list
- olm config set OLM_LANG jp
- olm history --last 50


olm_rag_run.sh 使い方
概要

任意のコマンドを実行するラッパースクリプト

実行結果を表示

失敗時にRAG検索

設定によりログ保存

設定によりLLM提案表示

基本構文

./olm_rag_run.sh -- コマンド 引数

例

./olm_rag_run.sh -- ssh gen

./olm_rag_run.sh -- ls -la

./olm_rag_run.sh -- git status

動作フロー

コマンド実行

終了コード取得

stdout / stderr 表示

失敗時のみ以下実行

rag_save_failed.sh 実行（設定有効時）

rag_search.sh 実行

LLM提案（設定有効時）

環境変数設定

CMD_HINT_ENABLE

1: コマンドヒント有効

0: 無効

HINT_INTERACTIVE

1: ヒント選択UI表示

0: 非表示

AUTO_APPLY_HINT

1: ヒント自動適用

0: 自動適用しない

DO_RAG_SEARCH

1: 失敗時にRAG検索

0: 検索しない

AUTO_SAVE_FAILED

1: 失敗ログ保存

0: 保存しない

LLM_ENABLE

1: RAGヒット無し時にLLM提案

0: LLM使わない

入力待ち無しテスト実行

CMD_HINT_ENABLE=0 HINT_INTERACTIVE=0 AUTO_APPLY_HINT=0 LLM_ENABLE=0 ./olm_rag_run.sh -- ssh gen || true

出力例

CMD=ssh gen

EXIT=255

DUR_SEC=0

---- STDERR ----

ssh: Could not resolve hostname gen: Name or service not known

---- RAG SEARCH ----

QUERY_RAW=[ssh: Could not resolve hostname gen: Name or service not known]

TOKENS=[ssh Could not resolve hostname gen Name or service not known]

ディレクトリ構成

olm_rag_run.sh

rag_search.sh

rag_save_failed.sh

rag_save_ok.sh

rag_init.sh

rag.db

rag_search.sh

SQLite rag.db 使用

FTS有無自動判定

エラーメッセージからトークン生成

類似エラー検索

初期化

rag.db が無い場合

./rag_init.sh

実行権限

chmod +x olm_rag_run.sh

chmod +x rag_search.sh

安全設計

LLMは自動実行しない

コマンドは直接実行

root操作は行わない

破壊操作は提案のみ

トラブルシュート

Permission denied

chmod +x 実行

rag.db not found

rag_init.sh 実行

QUERY_RAW 表示崩れ

CR除去処理実装済み

拡張候補

ベクトル検索追加

LLMスコアリング

自動修復モード

必要なら

上級者向け版

安全設計仕様書

アーキテクチャ設計書

シーケンス図テキスト版